// Dressing a control. The list came off a screen, not off a guess: a push
// button takes a background, and only the four bezelled text controls refuse.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
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

    // Never printed, only compared against, so one golden holds all four hosts.
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
                // Promised where the platform dresses and the kind's own chrome
                // would not cover it.
                let want_background: bool = dressed && !refuses_background(kind)
                // Counted from the kinds walked, not `offered - 4`: a host
                // missing one text control would make that quietly wrong.
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

                // Corners and borders have no rule: every control took both,
                // the four text ones included.
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
    // The count matters: a rule refusing three of them, or all of them, would
    // pass a test that only asked whether some control refused.
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
            // `wrong_widget` where the platform dresses and this control
            // cannot; `unsupported` where it dresses none. Different facts.
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

    io.println("-- and what was set reads back --")
    // Nothing read these back, which is how the radius and border getters
    // shipped as copies of their setters: asking set the radius to zero.
    var card: widgets.Container = new widgets.Container()
    card.set_background(red)
    card.set_corner_radius(6.0)
    card.set_border(2.0, blue)
    var radius_back: bool = false
    match card.corner_radius() {
        ok(points) => { radius_back = points == (if dressed { 6.0 } else { 0.0 }) }
        err(problem) => { radius_back = !dressed }
    }
    io.println("  the corner radius that went in: {radius_back}")
    var border_back: bool = false
    match card.border_width() {
        ok(points) => { border_back = points == (if dressed { 2.0 } else { 0.0 }) }
        err(problem) => { border_back = !dressed }
    }
    io.println("  the border width that went in: {border_back}")
    var colour_back: bool = false
    match card.background() {
        ok(shade) => { colour_back = !dressed || (shade.red == 220 && shade.green == 60 &&
                                                  shade.blue == 60 && shade.alpha == 255) }
        err(problem) => { colour_back = !dressed }
    }
    io.println("  and the colour, byte for byte: {colour_back}")
    // A control nobody dressed has no layer, and reads zero rather than
    // growing one to answer.
    var plain_box: widgets.Container = new widgets.Container()
    var undressed: bool = false
    match plain_box.corner_radius() {
        ok(points) => { undressed = points == 0.0 }
        err(problem) => { undressed = !dressed }
    }
    io.println("  one nobody dressed reads zero: {undressed}")
    card.release()
    plain_box.release()

    io.println("-- and markup dresses a control the same way --")
    // The other half of the same property: `<Button background="#dc3c3c" .../>`
    // through a real Builder, so the markup path is held to the control's state.
    var screen: widgets.Container = new widgets.Container()
    var mount: component.Mount = new component.Mount(screen, app.router)
    let screen_component: Dressed = new Dressed()
    let seen: Seen = screen_component.watch
    mount.show(screen_component)?
    mount.set_bounds(geometry.Size.of(200.0, 60.0))
    mount.refresh()?
    io.println("  the colour written in markup is the control's: {seen.dressed_right(dressed)}")

    // A value of the wrong shape is the Builder's to refuse, uniformly — the
    // markup compiler parses no colours, so there is one parser and not two.
    var bad: widgets.Container = new widgets.Container()
    var second: component.Mount = new component.Mount(bad, app.router)
    second.set_bounds(geometry.Size.of(200.0, 60.0))
    var said: string = ""
    match second.show(new Misspelt()) {
        ok(done) => {
            match second.refresh() {
                ok(again) => {}
                err(problem) => { said = problem.msg }
            }
        }
        err(problem) => { said = problem.msg }
    }
    io.println("  a colour that is not one is refused at render: {said.contains("gg0000")}")

    app.shutdown()
    return ok(true)
}

/// What the mounted button read back, so the assertion is outside the mount.
class Seen {
    pub built: bool = false
    pub red: int = 0
    pub green: int = 0
    pub blue: int = 0
    pub alpha: int = 0
    pub refused: bool = false

    pub fn init() {}

    pub fn dressed_right(dressed: bool) -> bool {
        if !self.built { return false }
        if !dressed { return self.refused }
        return self.red == 220 && self.green == 60 && self.blue == 60 && self.alpha == 255
    }
}

/// A button dressed the way markup dresses one.
class Dressed extends component.Component {
    pub watch: Seen = new Seen()

    pub fn init() { super.init() }

    pub override fn on_mount(stage: component.Stage) {
        match stage.widget("order") {
            none => {}
            some(order) => {
                self.watch.built = true
                match order.background() {
                    err(problem) => { self.watch.refused = true }
                    ok(shade) => {
                        self.watch.red = shade.red
                        self.watch.green = shade.green
                        self.watch.blue = shade.blue
                        self.watch.alpha = shade.alpha
                    }
                }
            }
        }
    }

    pub override fn render(into: component.Builder) {
        into.open("Button")
        into.key("order")
        into.text("Order")
        into.word("background", "#dc3c3c")
        into.number("corner_radius", 6.0)
        into.number("border_width", 2.0)
        into.word("border_color", "#2850dc")
        into.close()
    }
}

/// The same, with a colour that is not one.
class Misspelt extends component.Component {
    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("Button")
        into.text("Order")
        into.word("background", "#gg0000")
        into.close()
    }
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
