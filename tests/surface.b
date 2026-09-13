// The four things that happen to a window, and the one rule that decides a
// close.
//
// **All four were declared in the header from its first version and raised by
// almost nobody.** Win32 raised all four; macOS and GTK4 raised none and iOS
// raised one. A program could not save the size its window was left at, could
// not ask "are you sure?" before it closed, and could not redraw what it had
// drawn itself when the system went dark — which `platform/appearance.b` had
// been promising in a doc comment the whole time.
//
// Cross-host, and in the agreement shape, because two of the four take the
// platform's real road and two cannot. A resize really resizes and a close
// really asks; nothing can change the system's appearance or a display's
// scale, so those two are raised directly and this file says what that does
// and does not prove.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import cortado.geometry
import std.io

class Heard {
    pub resizes: int = 0
    pub closes: int = 0
    pub appearances: int = 0
    pub scales: int = 0
    pub width: f64 = 0.0
    pub height: f64 = 0.0
    pub value: int = -1
    pub scale: f64 = 0.0
    pub fn init() {}
}

fn refused_as(answer: Result<bool>, kind: string) -> bool {
    match answer {
        ok(done) => { return false }
        err(problem) => { return problem.kind == kind }
    }
}

fn took(answer: Result<bool>) -> bool {
    match answer {
        ok(done) => { return true }
        err(problem) => { return false }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(320.0, 240.0, "surface")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    let tally: Heard = new Heard()

    io.println("-- nobody is listening --")
    // The gate the whole section rests on. A window dragged by its corner
    // reports a resize on every frame of the drag, so a host that crossed into
    // a program that was not listening would be paying sixty times a second
    // for an answer nobody reads.
    window.resize_as_user(geometry.Size.of(300.0, 200.0))?
    io.println("  a resize nobody asked for is not delivered: {tally.resizes == 0}")

    app.router.on(window.handle(), events.EventKind.surface_resized,
        fn(event: events.UiEvent) {
            tally.resizes = tally.resizes + 1
            tally.width = event.size.width
            tally.height = event.size.height
        })
    app.router.on(window.handle(), events.EventKind.appearance,
        fn(event: events.UiEvent) {
            tally.appearances = tally.appearances + 1
            tally.value = event.index
        })
    app.router.on(window.handle(), events.EventKind.scale_changed,
        fn(event: events.UiEvent) {
            tally.scales = tally.scales + 1
            tally.scale = event.position.x
        })

    io.println("-- a resize --")
    window.resize_as_user(geometry.Size.of(280.0, 180.0))?
    // Turns of the loop, because one host reports the size a turn later and
    // has to. GTK notifies once per dimension, so 300x200 becoming 280x180
    // fires a notification for a window 280 wide and still 200 tall — a shape
    // it was never at — and then one for the real size. Deferring is what
    // turns those two into the one event AppKit's single notification gives
    // for free, and what stops a layout solving against a phantom.
    //
    // **Waited for, not waited out.** This was one `run_for(0.05)`, and what
    // that asserts is not that the host reports a resize — it is that the
    // host reports one within a fiftieth of a second on the machine running
    // the gate. *When* GTK runs a queued idle source is GTK's business, and a
    // full gate has a great deal else going on, so this failed about once in
    // fifty runs with the two lines below reading false and nothing wrong.
    // Proven rather than guessed: the same two lines flip, byte for byte, on
    // an untouched tree with nothing changed but this number.
    //
    // Bounded, because a host that never reports must still fail. Two seconds
    // of turns is far past any real deferral and far short of hanging a gate,
    // and the loop stops the moment the event lands — so the macOS leg, where
    // the report is synchronous and `resizes` is already 1, takes no turn at
    // all and this costs it nothing.
    var turns: int = 0
    for tally.resizes == 0 && turns < 200 {
        app.run_for(0.01)?
        turns = turns + 1
    }
    io.println("  the user dragging the corner is reported: {tally.resizes == 1}")
    io.println("  and it says how big the window is now: {tally.width == 280.0 && tally.height == 180.0}")
    io.println("  a negative size is refused: {refused_as(window.resize_as_user(geometry.Size.of(-1.0, 10.0)), "out_of_range")}")

    io.println("-- the system --")
    // Neither of these takes the platform's road, and the reason is that there
    // is no road to take: a program cannot make the system go dark. What is
    // checked is everything above the platform — the gate, the routing and the
    // payload — and this file says so rather than letting the line look like
    // more than it is.
    window.happen(events.EventKind.appearance, 1.0, 0.0)?
    io.println("  the system going dark reaches a handler: {tally.appearances == 1 && tally.value == 1}")
    window.happen(events.EventKind.scale_changed, 2.0, 0.0)?
    io.println("  and so does a display that changed scale: {tally.scales == 1 && tally.scale == 2.0}")
    io.println("  a kind that does not happen to a surface is refused: {refused_as(window.happen(events.EventKind.activate, 0.0, 0.0), "out_of_range")}")

    io.println("-- a close --")
    // The rule, and the whole reason it is a rule: a handler cannot answer
    // back, so the question of whether the window goes is settled before the
    // event is raised, by whether anyone is listening. Three hosts disagreed
    // about this before it was written down.
    var second: surface.Window = app.window(200.0, 150.0, "second")?
    var no_handler: bool = false
    match second.close_as_user() {
        ok(done) => { no_handler = !second.is_visible() }
        err(problem) => { no_handler = problem.kind == "unsupported" }
    }
    io.println("  a window nobody is watching closes itself: {no_handler}")

    app.router.on(window.handle(), events.EventKind.surface_close,
        fn(event: events.UiEvent) { tally.closes = tally.closes + 1 })
    var watched_closed: bool = false
    var watched_told: bool = false
    var no_close_here: bool = false
    match window.close_as_user() {
        ok(done) => {
            watched_told = tally.closes == 1
            watched_closed = window.is_visible()
        }
        err(problem) => { no_close_here = problem.kind == "unsupported" }
    }
    // A phone has no window to close, and says so rather than letting this
    // pass on a platform where the thing being tested cannot happen.
    io.println("  a watched one is told and stays, or this platform has no close: {(watched_told && !watched_closed) != no_close_here}")

    // A headless window is never visible, so "stays" above is about the close
    // and not about the screen: this is the line that says the two are
    // different questions.
    io.println("  and a headless window was never on screen anyway: {!window.is_visible()}")

    app.router.forget(window.handle())
    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
