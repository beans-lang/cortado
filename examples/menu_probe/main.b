package main

import cortado_skia
import cortado.geometry
import cortado.render
import cortado.widgets
import cortado.events
import std.io
import std.os

/// Opens one popup button's menu and writes it, so the menu can be looked at
/// without a display. The showcase is the same control in a real window.
fn shoot(dark: bool, size: int, name: string) -> Result<bool> {
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(320.0, 220.0))
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    theme.set_dark(dark)
    theme.set_control_size(size)?
    let root: widgets.Container = scene.root()
    let combo: widgets.ComboBox = new widgets.ComboBox(some(context))
    combo.set_items(["Espresso", "Latte", "Cortado", "Flat white"])?
    combo.select(2)?
    combo.set_frame(geometry.Rect.of(40.0, 90.0, 150.0, theme.control_height()))?
    root.add(combo)?
    scene.resize(geometry.Size.of(320.0, 220.0), 2.0)?
    scene.refresh()?
    context.focus(combo.handle().raw)?
    context.dispatch(events.UiEvent.of(events.EventKind.activate, combo.handle()))?
    scene.refresh()?
    scene.renderer().write_png(name)?
    scene.close()
    io.println("wrote {name}")
    return ok(true)
}

fn main() {
    match shoot(false, 2, "build/menu-light.png") { ok(_) => {} err(p) => { io.println("light failed: {p.msg}"); os.exit(1) } }
    match shoot(true, 2, "build/menu-dark.png") { ok(_) => {} err(p) => { io.println("dark failed: {p.msg}"); os.exit(1) } }
    match shoot(false, 0, "build/menu-mini.png") { ok(_) => {} err(p) => { io.println("mini failed: {p.msg}"); os.exit(1) } }
    match shoot(false, 3, "build/menu-large.png") { ok(_) => {} err(p) => { io.println("large failed: {p.msg}"); os.exit(1) } }
}
