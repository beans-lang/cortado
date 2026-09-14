// A screen that decides by the window it is in, and follows it.
//
// The mount already laid a tree out again on every resize; what it could not
// do was render again, so a screen had no way to learn the width it was given.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import {view} from cortado.annotations
import std.io

/// Reads nothing about the window, and is memoised: rendered once, kept.
@view
pub class Fixed extends component.Component {
    pub renders: int = 0
    pub fn init() { super.init() }
    pub override fn should_render() -> bool { return false }
    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("Label")
        into.text("fixed")
        into.close()
    }
}

/// Decides by the width, and says so.
@view
pub class Folding extends component.Component {
    pub renders: int = 0
    pub fixed: Fixed = new Fixed()
    pub fn init() { super.init() }

    pub override fn follows_viewport() -> bool { return true }

    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        let room: geometry.Size = self.viewport()
        into.open("VStack")
        into.word("align", "stretch")
            into.open("Label")
            if room.width < 500.0 {
                into.text("narrow at {room.width as int}x{room.height as int}")
            } else {
                into.text("wide at {room.width as int}x{room.height as int}")
            }
            into.close()
            into.show("fixed", self.fixed)
        into.close()
    }
}

/// Reads the window but never said so — right until the first resize.
@view
pub class Deaf extends component.Component {
    pub renders: int = 0
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("Label")
        into.text("deaf at {self.viewport().width as int}")
        into.close()
    }
}

fn dump(root: widgets.Container) -> Result<bool> {
    io.print(widgets.WidgetDump.of(root)?)
    return ok(true)
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(400.0, 300.0, "Folding")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    var screen: Folding = new Folding()
    mount.show(screen)?

    io.println("== at 400 x 300 ==")
    dump(root)?
    io.println("  the first render saw the room: {screen.viewport().width as int}x{screen.viewport().height as int}")
    io.println("  and so did the child that never asked: {screen.fixed.viewport().width as int}")

    io.println("== dragged to 640 x 480 ==")
    let grew: bool = mount.resized(geometry.Size.of(640.0, 480.0))?
    io.println("  the room changed: {grew}")
    io.println("  a following screen asks to render: {mount.is_dirty()}")
    let rendered: bool = mount.refresh_if_needed()?
    io.println("  and is rendered on the next refresh: {rendered && screen.renders == 2}")
    dump(root)?
    io.println("  the memoised child kept its render: {screen.fixed.renders == 1}")
    io.println("  but was told the room anyway: {screen.fixed.viewport().width as int}")

    io.println("== the same size again ==")
    let same: bool = mount.resized(geometry.Size.of(640.0, 480.0))?
    io.println("  nothing changed: {!same && !mount.is_dirty()}")
    mount.close()?

    io.println("== a screen that reads the room and does not follow it ==")
    var other: surface.Window = app.window(400.0, 300.0, "Deaf")?
    var base: widgets.Container = new widgets.Container()
    other.set_root(base)?
    var still: component.Mount = new component.Mount(base, app.router)
    still.set_bounds(other.content_size()?)
    var deaf: Deaf = new Deaf()
    still.show(deaf)?
    still.resized(geometry.Size.of(640.0, 480.0))?
    io.println("  a resize does not wake it: {!still.is_dirty()}")
    io.println("  so its label is stale: {deaf.renders == 1}")
    dump(base)?
    still.close()?
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
