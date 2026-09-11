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
import std.io

const SAY_HELLO: int = 201
const PICK_FILE: int = 202

class Answers {
    pub lines: List<string> = []
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
