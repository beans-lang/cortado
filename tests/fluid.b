// A size that is a share of the room, held between two points.
//
// Three window sizes, because two prove a breakpoint and a clamp needs its
// floor, its band and its ceiling each shown once.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import {view} from cortado.annotations
import std.io

/// A title that is a tenth of the window, and a caption a twentieth of it.
/// Neither method is declared anywhere: reading the room is the declaration.
@view
pub class Fluid extends component.Component {
    pub renders: int = 0
    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("VStack")
        into.word("align", "stretch")
            into.open("Label")
            into.number("font_size", self.vw(10.0, 28.0, 64.0))
            into.text("Petrichor")
            into.close()
            into.open("Label")
            into.number("font_size", self.vh(5.0, 10.0, 20.0))
            into.text("four colours")
            into.close()
        into.close()
    }
}

fn at(app: surface.Application, wide: f64, tall: f64) -> Result<bool> {
    var window: surface.Window = app.window(wide, tall, "Fluid")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    var screen: Fluid = new Fluid()
    mount.show(screen)?

    io.println("== at {wide as int} x {tall as int} ==")
    io.println("  vw(10, 28, 64) = {screen.vw(10.0, 28.0, 64.0)}")
    io.println("  vh(5, 10, 20)  = {screen.vh(5.0, 10.0, 20.0)}")
    io.println("  and it follows the room without being told: {screen.follows_viewport()}")
    io.print(widgets.WidgetDump.of(root)?)
    mount.close()?
    return ok(true)
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    // 10% of 200 is under the floor, of 500 is inside the band, of 900 is over
    // the ceiling — and the heights land the same way on the other axis.
    at(app, 200.0, 150.0)?
    at(app, 500.0, 300.0)?
    at(app, 900.0, 600.0)?

    io.println("== the bounds the wrong way round ==")
    var window: surface.Window = app.window(500.0, 300.0, "Reversed")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    var screen: Fluid = new Fluid()
    mount.show(screen)?
    // CSS says the low bound wins, so 50 held between 64 and 28 is 64.
    io.println("  vw(10, 64, 28) = {screen.vw(10.0, 64.0, 28.0)}")
    mount.close()?

    io.println("== dragged, and the size follows ==")
    var other: surface.Window = app.window(200.0, 150.0, "Dragged")?
    var base: widgets.Container = new widgets.Container()
    other.set_root(base)?
    var still: component.Mount = new component.Mount(base, app.router)
    still.set_bounds(other.content_size()?)
    var growing: Fluid = new Fluid()
    still.show(growing)?
    io.println("  at 200 wide: {growing.vw(10.0, 28.0, 64.0)}")
    still.resized(geometry.Size.of(900.0, 600.0))?
    still.refresh_if_needed()?
    io.println("  at 900 wide: {growing.vw(10.0, 28.0, 64.0)}")
    io.println("  and it rendered again: {growing.renders == 2}")
    io.print(widgets.WidgetDump.of(base)?)
    still.close()?
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
