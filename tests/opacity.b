// Opacity: one property, four hosts, the same answer.
//
// This is the first of the visual properties, and it is deliberately the
// simplest one: a single real that every platform already has a name for —
// `alphaValue` on AppKit, `alpha` on UIKit, `gtk_widget_set_opacity` on GTK4,
// and a layered window on Win32. Nothing here needs a new ABI entry point,
// which is the property bag doing the job the header says it is for.
//
// What the golden pins is the part that is a decision rather than a lookup:
// **every kind has an opacity, containers included** — unlike `enabled`, which
// six kinds do not have — and **out of range is refused rather than clamped**,
// because a caller who computed 1.5 has a bug and showing them 1.0 hides it.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import std.io

fn every_kind() -> List<widgets.Widget> {
    return [
        new widgets.Container(),
        new widgets.Label(),
        new widgets.Button(),
        new widgets.TextField(),
        new widgets.CheckBox(),
        new widgets.ImageView(),
        new widgets.Slider(),
        new widgets.ProgressBar(),
        new widgets.Separator(),
        new widgets.TextArea(),
        new widgets.ComboBox(),
        new widgets.ScrollView(),
        new widgets.RadioButton(),
    ]
}

/// Reads back at two decimal places. A platform stores opacity as a float and
/// Win32 as one byte in 255, so the last bits are not a portable fact and
/// pinning them would make this golden a report on floating point.
fn rounded(value: f64) -> string {
    let hundredths: int = ((value * 100.0) + 0.5) as int
    let whole: int = hundredths / 100
    let rest: int = hundredths % 100
    if rest < 10 { return "{whole}.0{rest}" }
    return "{whole}.{rest}"
}

fn report(widget: widgets.Widget) -> string {
    let name: string = widget.kind().name()
    match widget.set_opacity(0.5) {
        ok(done) => {}
        err(refusal) => { return "{name} refused {refusal.kind}" }
    }
    match widget.opacity() {
        ok(value) => {
            if rounded(value) != "0.50" {
                return "{name} wrote 0.5 and read back {rounded(value)}"
            }
        }
        err(refusal) => { return "{name} took a write and refused the read: {refusal.kind}" }
    }
    // Back to opaque, which on Win32 is the path that takes the layer off again.
    match widget.set_opacity(1.0) {
        ok(done) => {}
        err(refusal) => { return "{name} could not return to opaque: {refusal.kind}" }
    }
    match widget.opacity() {
        ok(value) => {
            if rounded(value) != "1.00" { return "{name} did not return to opaque: {rounded(value)}" }
        }
        err(refusal) => { return "{name} took a write and refused the read: {refusal.kind}" }
    }
    return "{name} opacity round-trips"
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    for widget: widgets.Widget in every_kind() {
        io.println(report(widget))
    }

    // Out of range, both ends, on a kind every platform agrees about.
    var button: widgets.Button = new widgets.Button()
    match button.set_opacity(1.5) {
        ok(done) => { io.println("above one was accepted, and should not have been") }
        err(refusal) => { io.println("above one refused: {refusal.kind}") }
    }
    match button.set_opacity(-0.1) {
        ok(done) => { io.println("below zero was accepted, and should not have been") }
        err(refusal) => { io.println("below zero refused: {refusal.kind}") }
    }

    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
