package main

import cortado_skia
import cortado.paint
import cortado.geometry
import cortado.widgets
import std.io

fn verify() -> Result<bool> {
    let renderer: cortado_skia.SkiaRenderer = new cortado_skia.SkiaRenderer()
    let paragraph: paint.Paragraph = renderer.paragraph("Cortado · مرحبا · 日本語", 20.0, 360.0, 0x202128ff)?
    if paragraph.size().height <= 0.0 { return err("paragraph was not measured", "test") }
    let selected: List<geometry.Rect> = paragraph.selection(0, 7)?
    if selected.len() == 0 || selected[0].width <= 0.0 { return err("selection had no shaped bounds", "test") }
    let canvas: paint.Canvas = renderer.begin(geometry.Size.of(400.0, 160.0), 1.0, 0xffffffff)?
    canvas.rectangle(geometry.Rect.of(20.0, 20.0, 360.0, 120.0), 12.0, 0xe8eaf0ff, 0.0)?
    canvas.paragraph(paragraph, 32.0, 48.0)?
    renderer.end()?
    let pixels: widgets.Snapshot = renderer.snapshot()?
    let outside: widgets.Rgba = pixels.pixel(0, 0)?
    let inside: widgets.Rgba = pixels.pixel(25, 70)?
    if outside.same_as(inside) { return err("renderer painted no rectangle", "test") }
    let boundaries: List<int> = renderer.graphemes("a\u{301}👩‍💻z")?
    if boundaries.len() != 4 { return err("grapheme boundaries split a cluster", "test") }
    renderer.write_png("build/skia-proof.png")?
    io.println("ok Skia pixels, shaped text, Unicode graphemes")
    return ok(true)
}

fn main() {
    match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } }
}
