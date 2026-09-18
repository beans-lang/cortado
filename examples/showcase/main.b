package main

import cortado_skia
import cortado.geometry
import cortado.platform
import cortado.surface
import {Showcase} from cortado_showcase.generated.site
import std.io
import std.os

fn window(headless: bool) -> Result<bool> {
    let app: surface.Application = new surface.Application(
        if headless { platform.AppRole.headless } else { platform.AppRole.gui })
    let view: Showcase = new Showcase()
    let opened: cortado_skia.Window = cortado_skia.Window.open(app, geometry.Size.of(980.0, 640.0),
        "Cortado showcase", view)?
    view.use_theme(opened.scene().context().theme())
    opened.refresh()?
    if headless {
        let problem: string = opened.last_error()
        opened.close(); app.shutdown()
        if problem != "" { return err(problem, "renderer_error") }
        io.println("ok showcase: the window opened, laid out and painted once")
        return ok(true)
    }
    app.run()
    let problem: string = opened.last_error()
    opened.close(); app.shutdown()
    if problem != "" { return err(problem, "renderer_error") }
    return ok(true)
}

/// Writes both appearances at every control size to build/, so the look can be
/// checked without a display — and so a size that overflows is visible.
fn shots() -> Result<bool> {
    let names: List<string> = ["mini", "small", "regular", "large"]
    for size: int in 0..4 {
        for dark: bool in [false, true] {
            let view: Showcase = new Showcase()
            let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(980.0, 640.0))
            scene.show(view)?
            view.use_theme(scene.context().theme())
            view.set_mode(if dark { 1 } else { 0 })
            view.set_control_size(size)
            scene.refresh()?
            let name: string = "build/showcase-{names[size]}-{if dark { "dark" } else { "light" }}.png"
            scene.renderer().write_png(name)?
            scene.close()
            io.println("wrote {name}")
        }
    }
    return ok(true)
}

fn main() {
    var mode: string = "window"
    for argument: string in os.args() {
        if argument == "--shots" { mode = "shots" }
        if argument == "--smoke" { mode = "smoke" }
    }
    let outcome: Result<bool> = if mode == "shots" { shots() }
                                else if mode == "smoke" { window(true) }
                                else { window(false) }
    match outcome { ok(value) => {} err(problem) => { io.println("showcase failed"); os.exit(1) } }
}
