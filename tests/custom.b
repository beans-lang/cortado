// A control a program draws itself, that a person can actually use.
//
// **What was already true, and had to be tested rather than assumed:** a
// canvas already receives a pointer. The hit test finds it like any other
// view, and the position arrives in the control's own points, top-left and y
// down. So `<Canvas on:pointer_down={...}>` worked before any of this, and the
// three things below are what was genuinely missing.
//
//   * a canvas cannot take the keyboard — a plain view answers no to
//     `acceptsFirstResponder`, so `focus` was refused as `unsupported`
//   * a canvas cannot say what it is — `ctd_a11y_role` hardcoded `group`
//   * nothing named the conversion from a pointer's position to the `uv` its
//     shader was given, so every program would have re-derived it and one of
//     them would have got the flip wrong
//
// Every line asks whether what happened agrees with what the platform and the
// kind promised, so a host that does all of this and a host that does none of
// it print the same bytes.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import cortado.events
import cortado.gpu
import std.io

/// Handlers capture this rather than the control they are attached to, for the
/// reason `tests/events.b` gives.
class Seen {
    pub hits: int = 0
    pub at: geometry.Point = geometry.Point.zero()

    pub fn init() {}
}

/// What a screen reader would say, or "" where this host has no such idea.
///
/// A reader rather than `?` at every call site, because a host that has not
/// been taught this key answers `unsupported` and the case still has to print
/// the same bytes as one that has.
fn spoken(control: widgets.Widget) -> string {
    match control.a11y_label() {
        ok(said) => { return said }
        err(problem) => { return "" }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(240.0, 160.0, "Custom")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var plot: widgets.Canvas = new widgets.Canvas()
    plot.set_frame(geometry.Rect.of(10.0, 10.0, 100.0, 50.0))?
    root.add(plot)?

    io.println("-- a canvas already hears a pointer --")
    let seen: Seen = new Seen()
    app.router.on(plot.handle(), events.EventKind.pointer_down,
        fn(event: events.UiEvent) {
            seen.hits = seen.hits + 1
            seen.at = event.position
        })
    // Through the platform's own dispatch where it can be — a synthesised
    // NSEvent goes into the application's queue and comes out the far side,
    // so this tests how the event is *reached* and not only that the handler
    // runs.
    let driven: bool = plot.point_as_user(events.EventKind.pointer_down,
                                          geometry.Point.at(25.0, 15.0),
                                          events.PointerButton.left).is_ok()
    app.run_for(0.3)?
    io.println("  the press arrived: {seen.hits == 1}")
    // The control's own points, top-left and y down. A flip anywhere on the
    // way would put this at y = 35.
    io.println("  in the canvas's own points: {seen.at.x == 25.0 && seen.at.y == 15.0}")
    io.println("  and the platform carried it: {driven}")

    io.println("-- the same point, as the shader sees it --")
    match gpu.uv_of(plot.handle(), seen.at) {
        err(problem) => { io.println("  uv refused: {problem.kind}") }
        ok(uv) => {
            // 25 of 100 across, 15 of 50 down. Both exact in binary, so this
            // pins the arithmetic and never floating point.
            io.println("  a quarter across and three tenths down: {uv.x == 0.25 && uv.y == 0.3}")
        }
    }
    // A canvas with no size has no answer rather than a division by zero.
    var narrow: widgets.Canvas = new widgets.Canvas()
    root.add(narrow)?
    match gpu.uv_of(narrow.handle(), geometry.Point.at(1.0, 1.0)) {
        ok(uv) => { io.println("  a canvas with no size was allowed one, and should not have been") }
        err(problem) => { io.println("  a canvas with no size says so: {problem.kind == "no_size"}") }
    }

    // **Not a capability, and deliberately so.** This is not a platform
    // difference — a UIView and a GtkWidget both take focus, and both could
    // carry a role; the cases are simply not written for those hosts yet. A
    // Capability member would say "this platform cannot", which would be a
    // claim about UIKit that is not true. So the case asks once and holds
    // every later line to that answer, and the golden is the same bytes
    // wherever it runs.
    let drawn: bool = plot.set_focusable(true).is_ok()

    io.println("-- taking the keyboard is asked for, not assumed --")
    // Refused as `wrong_moment` and not `unsupported`: this platform *can*
    // point the keyboard at a canvas, and the program has not said it wants
    // that. Two different answers to two different questions.
    var quiet: widgets.Canvas = new widgets.Canvas()
    quiet.set_frame(geometry.Rect.of(0.0, 70.0, 40.0, 20.0))?
    root.add(quiet)?
    var before_kind: string = ""
    match quiet.focus() {
        ok(done) => {}
        err(problem) => { before_kind = problem.kind }
    }
    // `wrong_moment` where a canvas *can* be focused and has not been asked;
    // `unsupported` where no canvas can. Two answers to two questions.
    io.println("  one that has not asked is refused: {before_kind == (if drawn { "wrong_moment" } else { "unsupported" })}")

    var says_yes: bool = false
    match plot.is_focusable() {
        ok(on) => { says_yes = on }
        err(problem) => { says_yes = false }
    }
    io.println("  one that asked says so: {says_yes == drawn}")
    let took: bool = plot.focus().is_ok()
    io.println("  then it takes the keyboard: {took == drawn}")
    io.println("  and knows it has it: {plot.focused() == took}")

    // Off again, and out of the tab order again.
    let turned_off: bool = plot.set_focusable(false).is_ok()
    var still_yes: bool = false
    match plot.is_focusable() {
        ok(on) => { still_yes = on }
        err(problem) => { still_yes = false }
    }
    io.println("  turning it off puts it back: {turned_off == drawn && !still_yes}")

    io.println("-- and only a canvas may be told --")
    var order: widgets.Button = widgets.Button.of("Order")?
    root.add(order)?
    match order.set_focusable(true) {
        ok(done) => { io.println("  a button was allowed one, and should not have been") }
        // `wrong_widget` where the key is known and this is the wrong control
        // for it; `unsupported` where the host has never heard of the key.
        // Both are right, and they are answers to different questions.
        err(problem) => { io.println("  a button is refused: {problem.kind == (if drawn { "wrong_widget" } else { "unsupported" })}") }
    }

    io.println("-- what a canvas calls itself --")
    io.println("  by default, what its kind says: {plot.a11y_role()? == "group"}")
    let told_button: bool = plot.set_a11y_role(widgets.A11yRole.button).is_ok()
    io.println("  told it is a button, it says button: {told_button == drawn && plot.a11y_role()? == (if drawn { "button" } else { "group" })}")
    plot.set_a11y_role(widgets.A11yRole.image)
    io.println("  told it is an image, it says image: {plot.a11y_role()? == (if drawn { "image" } else { "group" })}")
    plot.set_a11y_role(widgets.A11yRole.automatic)
    io.println("  and put back, its kind answers again: {plot.a11y_role()? == "group"}")

    match order.set_a11y_role(widgets.A11yRole.image) {
        ok(done) => { io.println("  a button was allowed a role, and should not have been") }
        err(problem) => { io.println("  a button may not claim one: {problem.kind == (if drawn { "wrong_widget" } else { "unsupported" })}") }
    }

    io.println("-- and what it is called --")
    // Carried by every kind: a label on a button is how a toolbar of icons is
    // usable at all.
    let named: bool = plot.set_a11y_label("Sales, last twelve months").is_ok()
    io.println("  a canvas can be named: {spoken(plot) == (if named { "Sales, last twelve months" } else { "" })}")
    order.set_a11y_label("Place the order")
    io.println("  and so can a button: {spoken(order) == (if named { "Place the order" } else { "" })}")
    // What a screen reader will *say*, not what cortado was told: a button
    // nobody named is still announced by its own title, and a canvas nobody
    // named is announced by nothing at all. Both are the platform's answer and
    // both are the useful one.
    var plain: widgets.Button = widgets.Button.of("Cancel")?
    root.add(plain)?
    io.println("  an unnamed button is announced by its title: {spoken(plain) == (if named { "Cancel" } else { "" })}")
    var bare: widgets.Canvas = new widgets.Canvas()
    bare.set_frame(geometry.Rect.of(0.0, 0.0, 10.0, 10.0))?
    root.add(bare)?
    io.println("  an unnamed canvas is announced by nothing: {spoken(bare) == ""}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
