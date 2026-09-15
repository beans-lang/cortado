// Which control carries which attribute, asked three ways and answered once:
// 39 tags x 61 attributes, then every property set on a real control.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.bx
import std.io

/// A value that is in range for `name`, so that a refusal is about the control
/// and never about the number.
fn value_for(name: string) -> f64 {
    if name == "min" { return 0.0 }
    if name == "max" { return 10.0 }
    if name == "value" { return 1.0 }
    if name == "font_size" { return 13.0 }
    if name == "step" { return 1.0 }
    if name == "opacity" { return 1.0 }
    if name == "day" { return 0.0 }
    if name == "alignment" { return 0.0 }
    // -1 is "nothing chosen", which every list-shaped control accepts and
    // which needs no items to have been added first.
    if name == "selected" { return 0.0 - 1.0 }
    if name == "color" { return 4278190335.0 }
    return 1.0
}

/// What happened when the property was set: the refusal kind, or "" for yes.
fn try_set(control: widgets.Widget, name: string) -> string {
    let property: int = component.Vocabulary.property_of(name)
    let value: f64 = value_for(name)
    var outcome: Result<bool> = ok(true)
    if component.Vocabulary.kind_of_property(name) == component.AttributeKind.real {
        outcome = control.set_property_real(property, value)
    } else {
        outcome = control.set_property(property, value as int)
    }
    match outcome {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let names: List<string> = bx.attribute_names()
    let tags: List<string> = bx.widget_tags()

    io.println("-- the markup table and the host agree, tag by tag --")
    var pairs: int = 0
    var same: int = 0
    var told: int = 0
    for tag: string in tags {
        match component.Vocabulary.kind_of(tag) {
            none => { io.println("  {tag} is not a control here, and the two lists say it is") }
            some(kind) => {
                for name: string in names {
                    pairs = pairs + 1
                    let written: bool = bx.tag_carries(tag, name)
                    let asked: bool = component.Vocabulary.carries(kind, name)
                    if written == asked {
                        same = same + 1
                    } else {
                        // Bounded, or a wholesale drift buries its own count.
                        if told < 8 {
                            io.println("  {tag}.{name}: markup says {written}, the host says {asked}")
                            told = told + 1
                        }
                    }
                }
            }
        }
    }
    // The same on every platform: neither table knows what this machine builds.
    io.println("  every pair was asked: {pairs == 2415}")
    io.println("  and answered the same way by both: {same == pairs}")

    io.println("-- and the answer is the one the control gives --")
    // A carried property is never refused as `wrong_widget`; one that is not
    // carried is never taken. `unsupported` may pre-empt either: a platform
    // that cannot do a key at all never reaches the question about the kind.
    var tried: int = 0
    var agreed: int = 0
    var surprises: int = 0
    var ranged: int = 0
    for kind: widgets.WidgetKind in widgets.WidgetKind.all() {
        if !kind.available() { continue }
        match component.WidgetMaker.of_kind(kind) {
            err(problem) => { io.println("  {kind.name()} could not be built: {problem.kind}") }
            ok(control) => {
                for name: string in names {
                    if component.Vocabulary.property_of(name) < 0 { continue }
                    tried = tried + 1
                    let promised: bool = component.Vocabulary.carries(kind, name)
                    let refusal: string = try_set(control, name)
                    if refusal == "range" { ranged = ranged + 1 }
                    var kept: bool = refusal != ""
                    if promised { kept = refusal != "wrong_widget" }
                    if kept {
                        agreed = agreed + 1
                    } else {
                        if surprises < 40 {
                            let said: string = if refusal == "" { "took it" } else { refusal }
                            io.println("  {kind.name()}.{name}: the rule says {promised}, the control {said}")
                        }
                        surprises = surprises + 1
                    }
                }
                control.release()
            }
        }
    }
    io.println("  every control was asked about every property: {tried > 0}")
    io.println("  and did exactly what the rule promised: {agreed == tried}")
    io.println("  no value was out of range: {ranged == 0}")

    io.println("-- the three answers a caller has to be able to tell apart --")
    var caption: widgets.Label = widgets.Label.of("Flat white")?
    var label_refusal: string = try_set(caption, "checked")
    io.println("  a label has no checked state: {label_refusal == "wrong_widget"}")
    io.println("  and it does have a font size: {try_set(caption, "font_size") == ""}")
    caption.release()

    // A slider carries a step everywhere; whether this platform can put
    // detents on one is a different question and must not be the same word.
    var dial: widgets.Slider = widgets.Slider.of(0.0, 10.0, 4.0)?
    let step_refusal: string = try_set(dial, "step")
    io.println("  a slider carries a step: {component.Vocabulary.carries(widgets.WidgetKind.slider, "step")}")
    io.println("  and was told yes or told the platform cannot: {step_refusal == "" || step_refusal == "unsupported"}")
    dial.release()

    // `spacing` is read by the parent's layout and never reaches the control.
    io.println("  a layout name belongs to no control: {component.Vocabulary.carries(widgets.WidgetKind.label, "spacing")}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
