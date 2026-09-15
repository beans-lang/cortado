// A mount snaps its first solve to the display it is on.
//
// The first two lines are non-vacuous only on a display whose scale is not
// 1: on a 1x runner the mount's default and the display agree by accident.
// The arithmetic half below is the same on any machine, and is what guards
// the snapping path itself.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import {view} from cortado.annotations
import std.io

/// Three equal shares of a row: thirds, which no whole grid holds exactly.
@view
pub class Thirds extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        into.open("HStack")
        for index: int in 0..3 {
            into.open("Container")
            into.number("flex", 1.0)
            into.close()
        }
        into.close()
    }
}

/// Whether `value` lands on a grid of `1/scale` points.
fn on_grid(value: f64, scale: f64) -> bool {
    let scaled: f64 = value * scale
    let whole: f64 = (scaled + 0.5).floor()
    let off: f64 = scaled - whole
    return off > -0.000001 && off < 0.000001
}

/// The x of every child of the row, as text.
fn lefts(root: widgets.Container) -> Result<string> {
    var out: string = ""
    for row: widgets.Widget in root.children() {
        for child: widgets.Widget in row.children() {
            let frame: geometry.Rect = child.frame()?
            if out != "" { out = "{out}, " }
            out = "{out}{frame.x}"
        }
    }
    return ok(out)
}

/// Whether every edge of every child lands on the grid at `scale`.
fn all_on_grid(root: widgets.Container, scale: f64) -> Result<bool> {
    for row: widgets.Widget in root.children() {
        for child: widgets.Widget in row.children() {
            let frame: geometry.Rect = child.frame()?
            if !on_grid(frame.x, scale) || !on_grid(frame.x + frame.width, scale) { return ok(false) }
        }
    }
    return ok(true)
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(100.0, 40.0, "Thirds")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    mount.show(new Thirds())?

    let scale: f64 = window.scale()?
    io.println("== the first solve is on the display's grid ==")
    io.println("  the mount took the surface's scale: {mount.scale_in_use() == scale}")
    io.println("  every edge is on that grid: {all_on_grid(root, scale)?}")
    io.println("  the same scale again is not a pass: {!mount.rescaled(scale)?}")

    io.println("== thirds of 100, at 2x and at 1x ==")
    mount.rescaled(2.0)?
    io.println("  at 2x: {lefts(root)?}")
    io.println("  every edge on half points: {all_on_grid(root, 2.0)?}")
    mount.rescaled(1.0)?
    io.println("  at 1x: {lefts(root)?}")
    io.println("  every edge on whole points: {all_on_grid(root, 1.0)?}")

    mount.close()?
    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("FAILED {problem.kind}: {problem.msg}") }
    }
}
