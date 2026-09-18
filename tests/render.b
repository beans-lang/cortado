package main

import cortado.paint
import cortado.render
import cortado.geometry
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn verify() -> Result<bool> {
    let dirty: render.Invalidation = new render.Invalidation()
    let first: int = dirty.paint_version()
    dirty.paint()
    dirty.painted(first)
    require(dirty.needs_paint(), "invalidation raised during paint was lost")
    dirty.painted(dirty.paint_version())
    let layout: int = dirty.layout_version()
    dirty.semantics()
    require(!dirty.needs_paint() && dirty.layout_version() == layout, "semantics invalidated layout or paint")
    dirty.layout()
    require(dirty.needs_paint(), "layout did not request paint")
    let theme: render.Theme = new render.Theme()
    match theme.set_font_size(-1.0) { ok(_) => { panic("invalid font accepted") } err(_) => {} }
    require(theme.font_size() == 14.0 && theme.version() == 0, "failed mutation changed theme")
    let commands: paint.DisplayList = new paint.DisplayList()
    match commands.restore() { ok(_) => { panic("unbalanced restore accepted") } err(_) => {} }
    commands.save()?
    let target: paint.DisplayList = new paint.DisplayList()
    match commands.replay(target) { ok(_) => { panic("unclosed save submitted") } err(_) => {} }
    require(target.count() == 0, "invalid display list partly submitted")
    commands.translate(12.0, 24.0)?
    commands.rectangle(geometry.Rect.of(0.0, 0.0, 40.0, 20.0), 4.0, 0x112233ff, 0.0)?
    commands.restore()?
    commands.replay(target)?
    require(target.count() == 4, "valid display list lost commands")
    io.println("ok rendering: invalidation, validated theme, balanced display lists")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
