// Dressing a control: a background, rounded corners, a border.
//
// **This case's list came off a screen.** `examples/styled.b` puts every
// control on a window twice, plain and dressed, and the four that came back
// looking exactly as they started are the bezelled text-entry ones. An
// offscreen snapshot could not settle it — rendered alone a bezelled button
// reports one thing and rendered in a window another — so the rule was read
// rather than reasoned about, and this holds the code to what was read.
//
// The one everybody expects to fail is the one that works: **a push button
// takes a background**, keeps its bezel's shape and draws its title on top.
// Only the text-entry controls refuse, and they refuse for a reason that is
// about the bezel rather than the class — a label is an `NSTextField` too, has
// no bezel, and takes a background fine.
//
// Every line asks whether what happened agrees with what the platform and the
// kind promised, so the same bytes come out of a host that does all of this
// and a host that does none of it.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import std.io

/// The widget kinds that must refuse a background, and why they are alike.
fn refuses_background(kind: widgets.WidgetKind) -> bool {
    return kind == widgets.WidgetKind.text_field ||
           kind == widgets.WidgetKind.secure_field ||
           kind == widgets.WidgetKind.search_field ||
           kind == widgets.WidgetKind.text_area
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    // Never printed, only compared against. A platform that dresses controls
    // and one that does not must produce the same bytes here, which is what
    // lets one golden hold all four hosts — the shape `tests/gpu.b` uses.
    let dressed: bool = platform.Capability.layer_style.available()

    let red: widgets.Rgba = widgets.Rgba { red: 220, green: 60, blue: 60, alpha: 255 }
    let blue: widgets.Rgba = widgets.Rgba { red: 40, green: 80, blue: 220, alpha: 255 }

    var offered: int = 0
    var took_background: int = 0
    var refused_background: int = 0
    var owed_background: int = 0
    var owed_refusal: int = 0
    var took_radius: int = 0
    var took_border: int = 0
    var agreed: int = 0

    for kind: widgets.WidgetKind in widgets.WidgetKind.all() {
        if !kind.available() { continue }
        offered = offered + 1
        match component.WidgetMaker.of_kind(kind) {
            err(problem) => { io.println("  {kind.name()} could not be built: {problem.kind}") }
            ok(control) => {
                // A background is promised exactly where the platform can
                // dress a control *and* the kind is not one whose own chrome
                // would cover it.
                let want_background: bool = dressed && !refuses_background(kind)
                // Counted from the kinds actually walked rather than from
                // `offered - 4`: a host that does not offer one of the four
                // text controls would make that arithmetic quietly wrong.
                if want_background { owed_background = owed_background + 1 }
                if dressed && refuses_background(kind) { owed_refusal = owed_refusal + 1 }
                var got_background: bool = false
                match control.set_background(red) {
                    ok(done) => { got_background = true }
                    err(problem) => { got_background = false }
                }
                if got_background { took_background = took_background + 1 }
                if !got_background && dressed && refuses_background(kind) {
                    refused_background = refused_background + 1
                }

                // Corners and borders have no such rule: every control took
                // both, the four text ones included, so there is nothing for a
                // per-kind rule to say.
                var got_radius: bool = false
                match control.set_corner_radius(6.0) {
                    ok(done) => { got_radius = true }
                    err(problem) => { got_radius = false }
                }
                if got_radius { took_radius = took_radius + 1 }

                var got_border: bool = false
                match control.set_border(2.0, blue) {
                    ok(done) => { got_border = true }
                    err(problem) => { got_border = false }
                }
                if got_border { took_border = took_border + 1 }

                if got_background == want_background &&
                   got_radius == dressed && got_border == dressed {
                    agreed = agreed + 1
                }
                control.release()
            }
        }
    }

    io.println("-- every control this platform offers --")
    io.println("  each one did exactly what was promised: {agreed == offered}")
    io.println("  corners were taken by all of them or none: {took_radius == (if dressed { offered } else { 0 })}")
    io.println("  and so were borders: {took_border == (if dressed { offered } else { 0 })}")

    io.println("-- the four that draw their own background --")
    // Four, and the count matters: a rule that refused three of them, or every
    // control, would still pass a test that only asked whether *some* control
    // refused.
    io.println("  every one of them refused: {refused_background == owed_refusal}")
    io.println("  and everything else took one: {took_background == owed_background}")
    // The count itself, because a rule that refused *every* control would
    // satisfy the two lines above and be badly wrong.
    io.println("  there are four of them wherever a platform dresses: {owed_refusal == (if dressed { 4 } else { 0 })}")

    io.println("-- the one everybody expects to fail --")
    // A bezelled push button showing a layer colour is the finding this whole
    // lane turned on, so it is asserted by name rather than left to a count.
    var order: widgets.Button = widgets.Button.of("Order")?
    var button_took: bool = false
    match order.set_background(red) {
        ok(done) => { button_took = true }
        err(problem) => { button_took = false }
    }
    io.println("  a push button takes a background: {button_took == dressed}")
    order.release()

    io.println("-- and the refusal names the control --")
    var field: widgets.TextField = widgets.TextField.of("beans")?
    var field_named: bool = false
    var field_refused: bool = false
    match field.set_background(red) {
        ok(done) => {}
        err(problem) => {
            field_refused = true
            // `wrong_widget` where the platform dresses controls — this
            // control cannot. `unsupported` where it dresses none of them, and
            // that is a different fact about a different thing.
            field_named = problem.msg.contains("TextField") &&
                          problem.kind == (if dressed { "wrong_widget" } else { "unsupported" })
        }
    }
    io.println("  a text field is always refused one: {field_refused}")
    io.println("  and told which control and why: {field_named}")
    field.release()

    // Out of range is a refusal rather than a clamp, for the reason opacity
    // gives: a caller who computed it has a bug.
    var box: widgets.Container = new widgets.Container()
    var negative_refused: bool = false
    match box.set_corner_radius(0.0 - 4.0) {
        ok(done) => {}
        err(problem) => { negative_refused = true }
    }
    io.println("  a negative radius is refused everywhere: {negative_refused}")
    box.release()

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
