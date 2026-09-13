// What the platform says about itself: appearance, scale, fonts and dialogs.
//
// Most of what is printed here is *not* a value — it is a verdict about a
// value. The system font family is "SF Pro" on one macOS release and something
// else on the next, and the display this runs on may or may not be Retina, so
// a golden holding either would fail for a reason that has nothing to do with
// cortado. What the golden holds is that each answer is present, plausible and
// the same under both backends.
package main

import cortado.platform
import cortado.surface
import cortado.events
import cortado.host
import cortado.widgets
import std.io

const SAY_HELLO: int = 201
const PICK_FILE: int = 202

class Answers {
    pub lines: List<string> = []
    pub fn init() {}
}

/// Events reaching a handler, and settles following them.
class Settles {
    pub events: int = 0
    pub settles: int = 0
    pub fn init() {}
}

fn build() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("-- appearance --")
    let look: platform.Appearance = platform.Appearance.current()
    io.println("  the system reports one of light or dark: {look.name() == "light" || look.name() == "dark"}")

    io.println("-- fonts --")
    // Each role must answer a real family and a sensible size, and the four
    // must not all be the same font: a caption that is body-sized, or a mono
    // that is the body family, means the host is not really asking the system.
    var families: List<string> = []
    var sizes: List<f64> = []
    for role: platform.SystemFont in [platform.SystemFont.body, platform.SystemFont.heading,
                                      platform.SystemFont.caption, platform.SystemFont.mono] {
        let family: string = role.family()?
        let size: f64 = role.size()?
        families.push(family)
        sizes.push(size)
        io.println("  {role.name()}: named={family.len() > 0} size in range={size > 6.0 && size < 48.0}")
    }
    io.println("  a heading is larger than a caption: {sizes[1] > sizes[2]}")
    io.println("  mono is a different family from body: {families[3] != families[0]}")

    io.println("-- scale --")
    var window: surface.Window = app.window(300.0, 200.0, "System")?
    let scale: f64 = window.scale()?
    io.println("  a surface answers a scale: {scale == 1.0 || scale == 2.0 || scale == 3.0}")

    io.println("-- dialogs --")
    // A dialog answers through an event carrying the token it was asked with,
    // never by returning. Under a headless run there is no surface to hang one
    // from, so a message answers its default button and a file dialog answers a
    // cancel — which is what makes a program that uses dialogs testable at all.
    let seen: Answers = new Answers()
    app.router.on(host.Handle.none(), events.EventKind.post,
        fn(event: events.UiEvent) {
            seen.lines.push("token={event.token} button={event.index} text=\"{event.text}\"")
        })

    surface.Dialog.ask_free(surface.DialogKind.message, "Hello", "Nothing is wrong", SAY_HELLO)?
    surface.Dialog.ask(window, surface.DialogKind.open_file, "Open", "Pick a file", PICK_FILE)?
    for line: string in seen.lines {
        io.println("  {line}")
    }
    io.println("  both dialogs answered: {seen.lines.len() == 2}")

    // **How often a program re-renders follows the screen, not the mouse.**
    //
    // What `after` runs is a render, and a slider being dragged reports on
    // every step. Running it per report does a screen's worth of work per
    // report, and the reports do not slow down to wait — so the queue grows
    // and the window stops answering. Events still reach their handlers one
    // for one and in order; only the work *after* a batch collapses.
    //
    // The window is set to a whole second here so the collapse is a fact
    // rather than a race: at the default of one frame, whether four
    // activations land inside one window depends on how fast the machine is,
    // and a case that proves nothing on a slow one is worse than no case.
    //
    // This is not in the cross-host list, and that is deliberate: the wake-up
    // is a `ctd_post`, its timing is the platform's, and a golden asserting
    // *how many* settles a host produced would be asserting the shape of that
    // host's run loop. What is checked here is the rule — fewer settles than
    // events, none lost, and the framework's own word never reaching a
    // program's handler.
    io.println("-- settling --")
    var page: widgets.Container = new widgets.Container()
    window.set_root(page)?
    var press: widgets.Button = widgets.Button.of("press")?
    page.add(press)?
    let tally: Settles = new Settles()
    app.router.on(press.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { tally.events = tally.events + 1 })
    app.router.after(fn() { tally.settles = tally.settles + 1 })
    let dialogs_seen: int = seen.lines.len()

    app.router.set_settle_window(1000000000)
    press.activate()?
    press.activate()?
    press.activate()?
    press.activate()?
    io.println("  four events all reached the handler: {tally.events == 4}")
    io.println("  and settled once, not four times: {tally.settles == 1}")
    io.println("  with one settle owed: {app.router.settle_waiting()}")

    // The one that matters most. The last event of a drag has nothing behind
    // it, so a deferral waiting to be triggered by the *next* event would
    // leave the screen showing the second-to-last frame for ever.
    //
    // Turns of the loop rather than one long wait, and bounded rather than
    // open: *when* a platform runs a queued block is the platform's business —
    // the two dialogs above delay this one past a single fiftieth of a second
    // on macOS — and a case that asserted a deadline would be asserting the
    // shape of a run loop. What is promised is that it arrives.
    var turns: int = 0
    for app.router.settle_waiting() && turns < 20 {
        app.run_for(0.05)?
        turns = turns + 1
    }
    io.println("  the wake-up collects it: {tally.settles == 2}")
    io.println("  and nothing is left owed: {app.router.settle_waiting() == false}")
    io.println("  the program's post handler never saw it: {seen.lines.len() == dialogs_seen}")
    app.router.set_settle_window(events.FRAME_NANOS)

    io.println("-- refusals --")
    match window.scale() {
        ok(value) => {}
        err(problem) => { io.println("  a live window refused its scale: {problem.kind}") }
    }

    app.shutdown()
    return ok(true)
}

fn main() {
    match build() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
