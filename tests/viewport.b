// A screen that decides by the window it is in, and follows it.
//
// Reading the room during a render is what declares the dependency: there is
// no second place to keep in step, and a handler's read is not a render's.
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

/// Decides by the width and says so — and declares nothing to do it.
@view
pub class Folding extends component.Component {
    pub renders: int = 0
    pub fixed: Fixed = new Fixed()
    pub fn init() { super.init() }

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

/// Never reads the room in a render. A handler that asks is not a dependency,
/// or every screen with one button would render again on every drag.
@view
pub class Blind extends component.Component {
    pub renders: int = 0
    pub seen: f64 = 0.0
    pub fn init() { super.init() }

    /// What a click would do: read the room outside a render.
    pub fn peek() {
        self.seen = self.viewport().width
    }

    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("Label")
        into.text("blind")
        into.close()
    }
}

/// Reads nothing either, but says it follows the room. An override is still
/// the last word over what the render was seen to do.
@view
pub class Pinned extends component.Component {
    pub renders: int = 0
    pub fn init() { super.init() }
    pub override fn follows_viewport() -> bool { return true }
    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("Label")
        into.text("pinned")
        into.close()
    }
}

/// Reads the room down one branch only, which is the edge worth pinning: it
/// starts following on the render that first takes that branch.
@view
pub class Lazy extends component.Component {
    pub renders: int = 0
    pub shown: bool = false
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("Label")
        if self.shown {
            into.text("lazy at {self.viewport().width as int}")
        } else {
            into.text("lazy, folded")
        }
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
    io.println("  the read was the declaration: {screen.follows_viewport()}")
    io.println("  and the child that never read does not follow: {!screen.fixed.follows_viewport()}")

    io.println("== dragged to 640 x 480 ==")
    let grew: bool = mount.resized(geometry.Size.of(640.0, 480.0))?
    io.println("  the room changed: {grew}")
    io.println("  a screen that read it asks to render: {mount.is_dirty()}")
    let rendered: bool = mount.refresh_if_needed()?
    io.println("  and is rendered on the next refresh: {rendered && screen.renders == 2}")
    dump(root)?
    io.println("  the memoised child kept its render: {screen.fixed.renders == 1}")
    io.println("  but was told the room anyway: {screen.fixed.viewport().width as int}")

    io.println("== the same size again ==")
    let same: bool = mount.resized(geometry.Size.of(640.0, 480.0))?
    io.println("  nothing changed: {!same && !mount.is_dirty()}")
    mount.close()?

    io.println("== a screen that never reads the room in a render ==")
    var other: surface.Window = app.window(400.0, 300.0, "Blind")?
    var base: widgets.Container = new widgets.Container()
    other.set_root(base)?
    var still: component.Mount = new component.Mount(base, app.router)
    still.set_bounds(other.content_size()?)
    var blind: Blind = new Blind()
    still.show(blind)?
    blind.peek()
    io.println("  a handler read it: {blind.seen as int}")
    still.resized(geometry.Size.of(640.0, 480.0))?
    io.println("  which is not a dependency: {!blind.follows_viewport()}")
    io.println("  so a resize does not wake it: {!still.is_dirty()}")
    io.println("  it rendered once: {blind.renders == 1}")
    io.println("  and was told the room anyway: {blind.viewport().width as int}")
    dump(base)?
    still.close()?

    io.println("== a screen that says it follows and never reads ==")
    var third: surface.Window = app.window(400.0, 300.0, "Pinned")?
    var held: widgets.Container = new widgets.Container()
    third.set_root(held)?
    var kept: component.Mount = new component.Mount(held, app.router)
    kept.set_bounds(third.content_size()?)
    var pinned: Pinned = new Pinned()
    kept.show(pinned)?
    kept.resized(geometry.Size.of(640.0, 480.0))?
    io.println("  the override is the last word: {kept.is_dirty()}")
    kept.refresh_if_needed()?
    io.println("  and it rendered again: {pinned.renders == 2}")
    kept.close()?

    io.println("== a screen that reads the room down one branch ==")
    var fourth: surface.Window = app.window(400.0, 300.0, "Lazy")?
    var folded: widgets.Container = new widgets.Container()
    fourth.set_root(folded)?
    var slow: component.Mount = new component.Mount(folded, app.router)
    slow.set_bounds(fourth.content_size()?)
    var lazy: Lazy = new Lazy()
    slow.show(lazy)?
    slow.resized(geometry.Size.of(640.0, 480.0))?
    io.println("  folded, it does not follow: {!lazy.follows_viewport()}")
    lazy.shown = true
    lazy.request_render()
    slow.refresh_if_needed()?
    io.println("  the render that took the branch declares it: {lazy.follows_viewport()}")
    slow.resized(geometry.Size.of(900.0, 500.0))?
    io.println("  so the next resize wakes it: {slow.is_dirty()}")
    slow.refresh_if_needed()?
    dump(folded)?
    slow.close()?
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
