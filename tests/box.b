// A component told the box it was laid out in, rather than the window.
//
// `viewport()` is the room the whole mount got, and every component is handed
// the same one — so a screen sizing anything by it is sizing by a number that
// is not the box it will land in. This is that box: what `onLayout` hands a
// React Native view, one pass behind, and the mount lays out again when it
// moves. Numbers are compared rather than printed: what a label measures is
// the platform's business.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import {view} from cortado.annotations
import std.io

/// Sized from its own box, and says so by reading it.
@view
pub class Card extends component.Component {
    pub renders: int = 0
    pub layouts: int = 0
    pub last: f64 = 0.0
    pub fn init() { super.init() }

    pub override fn on_layout(frame: geometry.Rect) {
        self.layouts = self.layouts + 1
        self.last = frame.width
    }

    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("Label")
        into.number("font_size", self.cw(5.0, 10.0, 40.0))
        into.text("Petrichor")
        into.close()
    }
}

/// Never asks. A box that moves under it is not a reason to render.
@view
pub class Quiet extends component.Component {
    pub renders: int = 0
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("Label")
        into.text("quiet")
        into.close()
    }
}

/// Twenty points of padding either side, so a child's box is not the window.
@view
pub class Desk extends component.Component {
    pub card: Card = new Card()
    pub still: Quiet = new Quiet()
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.word("align", "stretch")
        into.number("padding", 20.0)
            into.show("card", self.card)
            into.show("still", self.still)
        into.close()
    }
}

/// Wide when its box is narrow and narrow when its box is wide, which is the
/// one shape a box read can never settle into.
@view
pub class Flip extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.word("align", "start")
        into.open("Label")
        if self.box().width > 200.0 {
            into.text("short")
        } else {
            into.text("a label a great deal longer than the short one is")
        }
        into.close()
        into.close()
    }
}

/// A run that sizes its child to what the child measures, so `Flip`'s own
/// content is what decides its box.
@view
pub class Spin extends component.Component {
    pub perch: Flip = new Flip()
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        into.open("HStack")
        into.word("align", "start")
            into.show("flip", self.perch)
        into.close()
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(600.0, 400.0, "Desk")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    var desk: Desk = new Desk()
    mount.show(desk)?

    io.println("== at 600 x 400, with 20 points of padding ==")
    io.println("  the screen's box is the window: {desk.box().width == desk.viewport().width}")
    io.println("  the card's box is the window less the padding: {desk.card.box().width == desk.viewport().width - 40.0}")
    io.println("  which is not what viewport() would have said: {desk.card.box().width != desk.card.viewport().width}")
    io.println("  cw(5) is a share of the box: {desk.card.cw(5.0, 10.0, 40.0) == 28.0}")
    io.println("  a share under the floor is the floor: {desk.card.cw(1.0, 10.0, 40.0) == 10.0}")
    io.println("  and one over the ceiling is the ceiling: {desk.card.cw(20.0, 10.0, 40.0) == 40.0}")
    io.println("  and the card heard its layout: {desk.card.layouts > 0}")
    io.println("  reading the box is the declaration: {desk.card.follows_box()}")
    io.println("  the one that never read it does not follow: {!desk.still.follows_box()}")

    io.println("== dragged to 400 x 300 ==")
    let heard: int = desk.card.layouts
    mount.resized(geometry.Size.of(400.0, 300.0))?
    io.println("  the card's box moved, so it asks to render: {desk.card.is_dirty()}")
    io.println("  and the quiet one does not: {!desk.still.is_dirty()}")
    io.println("  on_layout ran again: {desk.card.layouts > heard}")
    mount.refresh_if_needed()?
    io.println("  its box is the new window less the padding: {desk.card.box().width == 360.0}")
    io.println("  and cw(5) followed it down: {desk.card.cw(5.0, 10.0, 40.0) == 18.0}")
    mount.close()?

    io.println("== a box that decides itself ==")
    var other: surface.Window = app.window(600.0, 400.0, "Spin")?
    var base: widgets.Container = new widgets.Container()
    other.set_root(base)?
    var spinning: component.Mount = new component.Mount(base, app.router)
    spinning.set_bounds(other.content_size()?)
    var spin: Spin = new Spin()
    match spinning.show(spin) {
        ok(done) => { io.println("  it was allowed, and should not have been") }
        err(problem) => {
            io.println("  is refused rather than laid out for ever: {problem.kind == "unsettled_layout"}")
            io.println("  and the message says what is still moving: {problem.msg.contains("still moving")}")
        }
    }
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
