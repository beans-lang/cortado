// Which controls actually take a background, a corner radius and a border.
//
// This is a probe you look at, not a test that asserts. cortado is about to
// decide which kinds may be dressed and which must refuse by name, and that
// decision belongs in `src/cortado_rules.h` for all four hosts — so it had
// better be made from what a screen shows rather than from what anybody
// expects. An offscreen snapshot could not settle it: rendered on its own a
// bezeled button reports one thing and rendered in a window another, and the
// two disagree.
//
// Every row is the same control twice: plain on the left, dressed on the
// right. A control whose own chrome covers what cortado set looks identical on
// both sides, and that is the answer this program exists to give.
//
//     beansc build examples/styled.b -o build/styled && ./build/styled
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.geometry
import cortado.events
import std.io

const ROW: f64 = 42.0
const LEFT: f64 = 130.0
const MIDDLE: f64 = 270.0
const WIDE: f64 = 120.0

/// Red, rounded and outlined in blue — three things at once, so one look
/// answers three questions.
fn dress(control: widgets.Widget) {
    let red: widgets.Rgba = widgets.Rgba { red: 220, green: 60, blue: 60, alpha: 255 }
    let blue: widgets.Rgba = widgets.Rgba { red: 40, green: 80, blue: 220, alpha: 255 }
    match control.set_background(red) {
        ok(done) => {}
        err(problem) => { io.println("background refused: {problem.kind}") }
    }
    match control.set_corner_radius(10.0) {
        ok(done) => {}
        err(problem) => { io.println("radius refused: {problem.kind}") }
    }
    match control.set_border(2.0, blue) {
        ok(done) => {}
        err(problem) => { io.println("border refused: {problem.kind}") }
    }
}

fn row(root: widgets.Container, at: f64, name: string,
       plain: widgets.Widget, fancy: widgets.Widget) -> Result<bool> {
    var caption: widgets.Label = widgets.Label.of(name)?
    caption.set_frame(geometry.Rect.of(16.0, at + 6.0, 108.0, 20.0))?
    root.add(caption)?

    plain.set_frame(geometry.Rect.of(LEFT, at, WIDE, 28.0))?
    root.add(plain)?

    fancy.set_frame(geometry.Rect.of(MIDDLE, at, WIDE, 28.0))?
    dress(fancy)
    root.add(fancy)?
    return ok(true)
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    var window: surface.Window = app.window(440.0, 820.0, "plain / dressed")?

    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("left: as the platform draws it.  right: + background, radius, border")?
    heading.set_frame(geometry.Rect.of(16.0, 10.0, 410.0, 20.0))?
    root.add(heading)?

    var at: f64 = 40.0
    row(root, at, "Button", widgets.Button.of("Order")?, widgets.Button.of("Order")?)?
    at = at + ROW
    row(root, at, "Label", widgets.Label.of("Flat white")?, widgets.Label.of("Flat white")?)?
    at = at + ROW
    row(root, at, "TextField", widgets.TextField.of("beans")?, widgets.TextField.of("beans")?)?
    at = at + ROW
    row(root, at, "CheckBox", widgets.CheckBox.of("Grind")?, widgets.CheckBox.of("Grind")?)?
    at = at + ROW
    row(root, at, "Slider", widgets.Slider.of(0.0, 10.0, 4.0)?, widgets.Slider.of(0.0, 10.0, 4.0)?)?
    at = at + ROW
    row(root, at, "ProgressBar", widgets.ProgressBar.of(0.0, 10.0)?, widgets.ProgressBar.of(0.0, 10.0)?)?
    at = at + ROW
    row(root, at, "Switch", widgets.Switch.of(true)?, widgets.Switch.of(true)?)?
    at = at + ROW
    row(root, at, "SearchField", widgets.SearchField.of("find")?, widgets.SearchField.of("find")?)?
    at = at + ROW
    row(root, at, "Stepper", widgets.Stepper.of(0.0, 10.0, 1.0, 3.0)?, widgets.Stepper.of(0.0, 10.0, 1.0, 3.0)?)?
    at = at + ROW
    row(root, at, "Separator", new widgets.Separator(), new widgets.Separator())?
    at = at + ROW
    row(root, at, "Container", new widgets.Container(), new widgets.Container())?
    at = at + ROW
    row(root, at, "Canvas", new widgets.Canvas(), new widgets.Canvas())?
    at = at + ROW
    row(root, at, "SecureField", widgets.SecureField.of("")?, widgets.SecureField.of("")?)?
    at = at + ROW
    row(root, at, "ComboBox", new widgets.ComboBox(), new widgets.ComboBox())?
    at = at + ROW
    row(root, at, "TextArea", widgets.TextArea.of("notes")?, widgets.TextArea.of("notes")?)?
    at = at + ROW
    row(root, at, "GroupBox", widgets.GroupBox.of("Brew")?, widgets.GroupBox.of("Brew")?)?
    at = at + ROW

    var quit: widgets.Button = widgets.Button.of("Done")?
    quit.set_frame(geometry.Rect.of(MIDDLE, at + 10.0, WIDE, 28.0))?
    root.add(quit)?
    app.router.on(quit.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { app.stop() })

    window.show()?
    app.run()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
