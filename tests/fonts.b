// A size named by the job it does, so it follows the reader's own setting.
//
// Not one number is printed below. A role's points are the platform's and the
// reader's — 13 on a Mac, whatever Dynamic Type says on a phone — so a golden
// holding one would be a golden for one machine. What is asserted instead is
// the rule: which role is larger, and that a role lays a control out exactly
// as its own number does.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import {view} from cortado.annotations
import std.io

/// A screen that renders whatever it is handed, so one helper can show many.
@view
pub class Sheet extends component.Component {
    pub draw: fn(component.Builder) = fn(b: component.Builder) {}
    pub fn init() { super.init() }
    /// The run matters: a lone root fills the window and every font lays out
    /// to the same frame, which is a comparison that cannot fail.
    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.word("align", "start")
        self.draw(into)
        into.close()
    }
}

/// The tree a render produces, as text, laid out in a real window.
fn shown(app: surface.Application, draw: fn(component.Builder)) -> Result<string> {
    var window: surface.Window = app.window(400.0, 200.0, "Fonts")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    var sheet: Sheet = new Sheet()
    sheet.draw = draw
    mount.show(sheet)?
    let text: string = widgets.WidgetDump.of(root)?
    mount.close()?
    return ok(text)
}

/// What a render was refused for, or that it was not.
fn refusal(draw: fn(component.Builder)) -> string {
    var into: component.Builder = new component.Builder()
    draw(into)
    match into.finish() {
        ok(tree) => { return "(accepted)" }
        err(problem) => { return problem.msg }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let body: f64 = platform.SystemFont.body.size()?
    let heading: f64 = platform.SystemFont.heading.size()?
    let caption: f64 = platform.SystemFont.caption.size()?
    let mono: f64 = platform.SystemFont.mono.size()?

    io.println("== what the four roles answer ==")
    // Headline and Body are both 17 points on a phone, so this is the bound
    // that holds on every host rather than the one macOS alone would allow.
    io.println("  heading is at least body: {heading >= body}")
    io.println("  caption is smaller than body: {caption < body}")
    io.println("  mono is body's size, and only its family differs: {mono == body}")

    io.println("== a role lays out as its own number ==")
    let by_role: string = shown(app, fn(b: component.Builder) {
        b.open("Label")
        b.word("font_role", "heading")
        b.text("Petrichor")
        b.close()
    })?
    let by_number: string = shown(app, fn(b: component.Builder) {
        b.open("Label")
        b.number("font_size", heading)
        b.text("Petrichor")
        b.close()
    })?
    // Against caption and not against heading: Headline and Body are the same
    // point size on a phone and differ by weight, which a frame cannot show.
    let caption_by_role: string = shown(app, fn(b: component.Builder) {
        b.open("Label")
        b.word("font_role", "caption")
        b.text("Petrichor")
        b.close()
    })?
    let by_body: string = shown(app, fn(b: component.Builder) {
        b.open("Label")
        b.word("font_role", "body")
        b.text("Petrichor")
        b.close()
    })?
    io.println("  heading by role is heading by number: {by_role == by_number}")
    io.println("  and a body role is not a caption one: {by_body != caption_by_role}")

    io.println("== two names on one property, so the last one wins ==")
    let role_then_number: string = shown(app, fn(b: component.Builder) {
        b.open("Label")
        b.word("font_role", "heading")
        b.number("font_size", caption)
        b.text("Petrichor")
        b.close()
    })?
    let number_then_role: string = shown(app, fn(b: component.Builder) {
        b.open("Label")
        b.number("font_size", caption)
        b.word("font_role", "heading")
        b.text("Petrichor")
        b.close()
    })?
    let by_caption: string = shown(app, fn(b: component.Builder) {
        b.open("Label")
        b.number("font_size", caption)
        b.text("Petrichor")
        b.close()
    })?
    io.println("  font_role then font_size is the number: {role_then_number == by_caption}")
    io.println("  font_size then font_role is the role: {number_then_role == by_role}")

    io.println("== what is refused ==")
    let not_a_size: string = refusal(fn(b: component.Builder) {
        b.open("Label")
        b.word("font_role", "mono")
        b.text("x")
        b.close()
    })
    let not_a_role: string = refusal(fn(b: component.Builder) {
        b.open("Label")
        b.word("font_role", "huge")
        b.text("x")
        b.close()
    })
    let not_a_carrier: string = refusal(fn(b: component.Builder) {
        b.open("Slider")
        b.word("font_role", "body")
        b.close()
    })
    io.println("  {not_a_size}")
    io.println("  {not_a_role}")
    io.println("  {not_a_carrier}")
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
