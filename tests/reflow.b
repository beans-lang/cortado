// A label reflows to the width it is offered, on every host.
//
// Booleans only: how tall a line is belongs to the platform and its font. What
// is the same everywhere is the rule — narrower means taller for words that
// wrap, never wider than offered, a button does not wrap, and `lines` caps it.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.geometry
import cortado.host
import std.io

/// The height `control` answers when offered `width` and no height limit.
fn tall_at(control: widgets.Widget, width: f64) -> Result<f64> {
    let size: geometry.Size = control.measure(geometry.Size.of(width, 0.0 - 1.0))?
    return ok(size.height)
}

fn wide_at(control: widgets.Widget, width: f64) -> Result<f64> {
    let size: geometry.Size = control.measure(geometry.Size.of(width, 0.0 - 1.0))?
    return ok(size.width)
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    let words: string = "A sentence long enough to need several lines once the column it sits in narrows to the width of a phone."

    var long: widgets.Label = widgets.Label.of(words)?
    var short: widgets.Label = widgets.Label.of("hi")?
    var button: widgets.Button = new widgets.Button()
    button.set_display_text(words)?

    io.println("== words reflow to the width they are offered ==")
    let roomy: f64 = tall_at(long, 1000.0)?
    let narrow: f64 = tall_at(long, 120.0)?
    let one_line: f64 = tall_at(short, 1000.0)?
    io.println("  a long sentence is taller at 120 than at 1000: {narrow > roomy}")
    io.println("  and at 1000 it is one line tall: {roomy == one_line}")
    io.println("  a short one is the same height at both: {tall_at(short, 120.0)? == one_line}")
    io.println("  neither answers wider than offered: {wide_at(long, 120.0)? <= 120.0 && wide_at(short, 120.0)? <= 120.0}")
    io.println("  and both answer their whole width when there is room: {wide_at(long, 1000.0)? > 120.0}")
    io.println("  a button with the same words does not grow taller: {tall_at(button, 120.0)? == tall_at(button, 1000.0)?}")

    io.println("== lines caps it ==")
    long.set_property(host.P_LINES, 1)?
    io.println("  lines=1 brings the sentence back to one line: {tall_at(long, 120.0)? == one_line}")
    long.set_property(host.P_LINES, 2)?
    let two: f64 = tall_at(long, 120.0)?
    io.println("  lines=2 sits between one line and the whole: {two > one_line && two < narrow}")
    long.set_property(host.P_LINES, 0)?
    io.println("  lines=0 is no cap again: {tall_at(long, 120.0)? == narrow}")
    match long.set_property(host.P_LINES, 0 - 1) {
        ok(done) => { io.println("  a negative cap was taken, and should not have been") }
        err(problem) => { io.println("  a negative cap is refused: {problem.kind}") }
    }
    match button.set_property(host.P_LINES, 2) {
        ok(done) => { io.println("  lines on a button was taken, and should not have been") }
        err(problem) => { io.println("  lines on a button is refused: {problem.kind}") }
    }

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("FAILED {problem.kind}: {problem.msg}") }
    }
}
