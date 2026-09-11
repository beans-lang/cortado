// Does a torn-down screen actually let go?
//
// This is the gate for the one hazard the design flagged and could not
// design away: **a stored callback is invisible to the cycle collector**
// (`beans_rt.c` — a handler the runtime is holding is not traced), so a
// per-widget closure that captured its own widget would keep that widget, its
// component and everything the component referenced alive forever, with
// nothing able to reclaim it and nothing on screen to show for it.
//
// cortado's answer is that handlers are not stored per widget at all: there is
// one platform callback for the whole process, and handlers live in
// `EventRouter` as ordinary functions in a table keyed by handle. That is a
// claim about lifetime, and a claim about lifetime is only worth what the test
// behind it is worth.
//
// So: **a thousand handler-bearing controls, torn down ten times.**
//
// Ten thousand is not an arbitrary number. The host's handle table is 8192
// slots, so a run this size can only finish if released slots are handed back
// and reused — which they were not until this file was written, and which the
// generation in every handle exists to make safe. Drop the rounds below eight
// and that half of the gate stops testing anything.
//
// The number matters. `tests/mount.b` already checks that the router is empty
// after a close, with about five controls — and a table that leaked one entry
// per widget, or freed all but the last, would pass that and fail this. A case
// built from one element proves nothing about a table.
//
// Three things are asserted, and they fail independently:
//
//   * the router really did hold a thousand handlers, so the mount is not
//     quietly doing nothing;
//   * after `close`, the router holds none and every one of those thousand
//     controls is dead at the platform — `is_alive` asks the host, not
//     cortado's own bookkeeping;
//   * the **component** was reclaimed, counted by its own `deinit`. That is
//     the one that catches the hazard: the router could empty and the controls
//     could die while a stored closure still pinned the object graph behind
//     them, and only a destructor running says otherwise.
//
// Run under `./test.sh --sanitize` this is also where LeakSanitizer gets a
// workload big enough to say something: ten thousand controls made and
// released.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import {view} from cortado.annotations
import cortado.events
import cortado.host
import std.io

/// How many screens are alive. A counter object rather than a module
/// variable, because Beans has no mutable state at module scope — and passing
/// it in is what makes the screen reference something, which is the shape a
/// leak would preserve.
class Tally {
    pub live: int = 0
    pub made: int = 0

    pub fn init() {}
}

const ROWS: int = 1000

@view
pub class Sheet extends component.Component {
    tally: Tally
    pub clicks: int = 0

    pub fn init(tally: Tally) {
        // The field first, then `super.init()`: a base initializer may call an
        // overridden method, and the compiler refuses the other order rather
        // than letting it see a half-built object.
        self.tally = tally
        super.init()
        self.tally.live = self.tally.live + 1
        self.tally.made = self.tally.made + 1
    }

    /// The destructor is the whole point of this file. If a handler the
    /// platform is holding keeps this object alive, this never runs.
    pub fn deinit() {
        self.tally.live = self.tally.live - 1
    }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        for row: int in 0..ROWS {
            into.open("Button")
            into.key("row{row}")
            into.text("row {row}")
            // A closure over `self`, which is exactly the shape that would
            // pin the component if handlers were stored per widget.
            into.on_kind(events.EventKind.activate, fn(event: events.UiEvent) {
                self.clicks = self.clicks + 1
            })
            into.close()
        }
        into.close()
    }
}

/// One mount-and-close. Answers how many handlers the router held while the
/// screen was up, and how many of its controls were still alive after.
fn cycle(app: surface.Application, window: surface.Window,
         tally: Tally) -> Result<List<int>> {
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)

    var screen: Sheet = new Sheet(tally)
    mount.show(screen)?

    // Every control the *mount* made, remembered by handle so liveness can be
    // asked of the platform after the Beans objects are gone.
    //
    // The root container is not in the list: it was made here and handed to
    // the window, which holds it until the next `set_root` replaces it, so it
    // is alive after a close on purpose. Counting the caller's own object as a
    // leak would make this test fail for being right.
    var handles: List<u64> = []
    for child: widgets.Widget in root.children() {
        collect(child, handles)
    }
    let held: int = app.router.registered()

    // One control kept the way an application would keep one — a reference of
    // its own, held across the teardown. Clearing the mount's internal
    // references would let ARC reclaim everything *it* holds and leave this
    // one alive, so this is what says `close` releases what it made rather
    // than merely letting go of it.
    var kept: widgets.Widget = root.child_at(0).expect("the mount rendered a root")
    mount.close()?
    var kept_alive: int = 0
    if kept.is_alive() { kept_alive = 1 }
    var alive: int = 0
    for handle: u64 in handles {
        unsafe {
            if host.ctd_widget_alive(handle) == 1 { alive = alive + 1 }
        }
    }
    return ok([held, app.router.registered(), handles.len(), alive, kept_alive])
}

fn collect(widget: widgets.Widget, into: List<u64>) {
    into.push(widget.handle().raw)
    for child: widgets.Widget in widget.children() {
        collect(child, into)
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(400.0, 400.0, "Leaks")?
    var tally: Tally = new Tally()

    let rounds: int = 10
    var worst_held: int = 999999
    var left_registered: int = 0
    var left_alive: int = 0
    var still_held: int = 0
    var fewest_controls: int = 999999

    for round: int in 0..rounds {
        let answer: List<int> = cycle(app, window, tally)?
        if answer[0] < worst_held { worst_held = answer[0] }
        left_registered = left_registered + answer[1]
        if answer[2] < fewest_controls { fewest_controls = answer[2] }
        left_alive = left_alive + answer[3]
        still_held = still_held + answer[4]
    }

    io.println("rounds: {rounds}, screens made: {tally.made}")
    io.println("controls per round: {fewest_controls >= ROWS}")
    io.println("handlers held while up: {worst_held >= ROWS}")
    io.println("handlers left after close: {left_registered}")
    io.println("controls left alive after close: {left_alive}")
    io.println("a reference held across the close: {still_held}")
    io.println("screens still live: {tally.live}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
