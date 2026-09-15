// A control the room hides. No Beans code decides it, and no render runs when
// a resize shows or hides it: the layout culls it and the sheet hides it.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import {view} from cortado.annotations
import std.io

/// A row whose middle label is for boxes 500 wide and up, and whose last
/// label is hidden outright.
@view
pub class Strip extends component.Component {
    pub renders: int = 0
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("HStack")
        into.number("spacing", 8.0)
            into.open("Label")
            into.text("left")
            into.close()
            into.open("Label")
            into.text("side")
            into.number("hide_below", 500.0)
            into.close()
            into.open("Label")
            into.text("right")
            into.close()
            into.open("Label")
            into.text("never")
            into.flag("hidden", true)
            into.close()
        into.close()
    }
}

/// A screen whose root asks to be hidden, which nothing contains to judge.
@view
pub class Rootless extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        into.open("Label")
        into.text("root")
        into.number("hide_below", 100.0)
        into.close()
    }
}

/// Bounds that leave no width to show at.
@view
pub class Never extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        into.open("VStack")
            into.open("Label")
            into.text("nowhere")
            into.number("hide_above", 400.0)
            into.number("hide_below", 600.0)
            into.close()
        into.close()
    }
}

fn dump(root: widgets.Container) -> Result<bool> {
    io.print(widgets.WidgetDump.of(root)?)
    return ok(true)
}

/// Shows `screen` in a fresh window and answers what the mount said.
fn refusal(app: surface.Application, screen: component.Component, title: string) -> Result<bool> {
    var window: surface.Window = app.window(300.0, 100.0, title)?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    match mount.show(screen) {
        ok(shown) => { io.println("  accepted, and should not have been") }
        err(problem) => { io.println("  refused ({problem.kind}): {problem.msg}") }
    }
    mount.close()?
    return ok(true)
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(640.0, 200.0, "Strip")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    var screen: Strip = new Strip()
    mount.show(screen)?

    io.println("== at 640: the side is in, the never is not ==")
    dump(root)?
    let renders: int = screen.renders

    // A hidden control keeps the frame it last had; only the sheet's word on
    // whether it is hidden changes, and the run closes up around it.
    io.println("== dragged to 400: the side goes, and nothing renders ==")
    let narrowed: bool = mount.resized(geometry.Size.of(400.0, 200.0))?
    io.println("  the room changed: {narrowed}")
    io.println("  nothing asked to render: {!mount.is_dirty()}")
    dump(root)?
    io.println("  and no render ran: {screen.renders == renders}")

    io.println("== back to 640: the side is back, and still nothing renders ==")
    let widened: bool = mount.resized(geometry.Size.of(640.0, 200.0))?
    io.println("  the room changed: {widened}")
    dump(root)?
    io.println("  and no render ran: {screen.renders == renders}")
    mount.close()?

    io.println("== a root that asks to hide ==")
    refusal(app, new Rootless(), "Rootless")?
    io.println("== bounds with no width between them ==")
    refusal(app, new Never(), "Never")?

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("FAILED {problem.kind}: {problem.msg}") }
    }
}
