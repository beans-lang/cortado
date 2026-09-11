// Builds a widget tree out of real native controls and prints what the
// platform actually made of it.
//
// Nothing appears on screen: the application runs headless, so the window is
// built, sized and measured but never ordered front. Every line below is read
// back off the live platform objects — the class name is what the platform
// calls its own control, not a name cortado chose.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.geometry
import std.io

fn geometry_rect(x: f64, y: f64, width: f64, height: f64) -> geometry.Rect {
    return geometry.Rect.of(x, y, width, height)
}

fn build() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(480.0, 320.0, "Cortado")?

    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Order a coffee")?
    heading.set_frame(geometry_rect(20.0, 20.0, 240.0, 20.0))?
    root.add(heading)?

    var name: widgets.TextField = widgets.TextField.of("flat white")?
    name.set_frame(geometry_rect(20.0, 52.0, 200.0, 24.0))?
    root.add(name)?

    var extra_shot: widgets.CheckBox = widgets.CheckBox.of("Extra shot")?
    extra_shot.set_frame(geometry_rect(20.0, 88.0, 200.0, 20.0))?
    extra_shot.set_state(widgets.CheckState.mixed)?
    root.add(extra_shot)?

    var picture: widgets.ImageView = new widgets.ImageView()
    picture.set_frame(geometry_rect(300.0, 20.0, 64.0, 64.0))?
    root.add(picture)?

    var buttons: widgets.Container = new widgets.Container()
    buttons.set_frame(geometry_rect(20.0, 130.0, 300.0, 40.0))?
    root.add(buttons)?

    var order: widgets.Button = widgets.Button.of("Order")?
    order.set_frame(geometry_rect(0.0, 0.0, 100.0, 32.0))?
    buttons.add(order)?

    var cancel: widgets.Button = widgets.Button.of("Cancel")?
    cancel.set_frame(geometry_rect(110.0, 0.0, 100.0, 32.0))?
    cancel.set_enabled(false)?
    buttons.add(cancel)?

    io.print(widgets.WidgetDump.of(root)?)

    // Reordering is one call, and the tree follows it. A list that reorders
    // while the user is typing must not lose the row or the caret.
    buttons.move_child(0, 1)?
    io.println("-- after reordering the buttons --")
    io.print(widgets.WidgetDump.of(buttons)?)

    // A released widget's handle stays valid as a value and invalid as a
    // reference. Every copy of it answers the same way.
    let handle_before: bool = cancel.is_alive()
    cancel.release()
    io.println("cancel alive before={handle_before} after={cancel.is_alive()}")

    window.close()?
    app.shutdown()
    return ok(true)
}

fn main() {
    match build() {
        ok(done) => { io.println("built={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
