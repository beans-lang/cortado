package main

import cortado_skia
import cortado.geometry
import cortado.paint
import cortado.widgets
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn draw(renderer: cortado_skia.SkiaRenderer) -> Result<bool> {
    let canvas: paint.Canvas = renderer.begin(geometry.Size.of(64.0, 48.0), 1.0, 0xffffffff)?
    canvas.rectangle(geometry.Rect.of(4.0, 4.0, 24.0, 24.0), 3.0, 0xd03020ff, 0.0)?
    renderer.end()?
    let shot: widgets.Snapshot = renderer.snapshot()?
    require(shot.width == 64 && shot.height == 48, "bad frame size")
    require(!shot.pixel(0, 0)?.same_as(shot.pixel(12, 12)?), "draw did not change pixel")
    return ok(true)
}

fn verify() -> Result<bool> {
    let renderer: cortado_skia.SkiaRenderer = new cortado_skia.SkiaRenderer()
    require(renderer.backend() == cortado_skia.Backend.software, "default backend must be software")
    draw(renderer)?
    renderer.select_backend(cortado_skia.Backend.automatic)?
    let selected: cortado_skia.Backend = renderer.backend()
    require(selected != cortado_skia.Backend.automatic, "automatic is not an active backend")
    draw(renderer)?
    if selected == cortado_skia.Backend.metal {
        renderer.write_png("build/skia-gpu-proof.png")?
    }
    renderer.recover_software()?
    require(renderer.backend() == cortado_skia.Backend.software, "software recovery failed")
    draw(renderer)?
    renderer.close()
    io.println("ok Skia backend selection, GPU pixels, software recovery")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
