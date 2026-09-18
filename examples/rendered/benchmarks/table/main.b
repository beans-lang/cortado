package main
import cortado_skia
import cortado.geometry
import cortado.surface
import cortado.platform
import cortado.widgets
import {TablePage} from rendered_demo.generated.site
import std.io
import std.time

fn run() -> Result<bool> {
    let page: TablePage = new TablePage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(840.0, 760.0))
    scene.show(page)?
    scene.resize(geometry.Size.of(840.0, 760.0), 2.0)?
    let point: geometry.Point = geometry.Point.at(300.0, 300.0)
    for index: int in 0..10 { scene.scroll(point, 0.0, 4.0)?; scene.snapshot()? }
    let before: int = page.rows.calls
    var draw: f64 = 0.0
    var copies: f64 = 0.0
    var slow: int = 0
    var maximum: f64 = 0.0
    for index: int in 0..120 {
        let start: int = time.monotonic_nanos()
        scene.scroll(point, 0.0, 4.0)?
        let painted: int = time.monotonic_nanos()
        scene.snapshot()?
        let ended: int = time.monotonic_nanos()
        let ms: f64 = (ended - start) as f64 / 1000000.0
        draw += (painted - start) as f64 / 1000000.0
        copies += (ended - painted) as f64 / 1000000.0
        if ms > maximum { maximum = ms }
        if ms > 16.67 { slow += 1 }
    }
    io.println("120 frames, 840x760 at 2x, software, 4px scroll/frame")
    io.println("mean render ms: {draw / 120.0}; mean snapshot ms: {copies / 120.0}; max total ms: {maximum}; over 16.67ms: {slow}; cell reads: {page.rows.calls - before}")
    let app: surface.Application = new surface.Application(platform.AppRole.headless)
    let canvas: widgets.Canvas = new widgets.Canvas()
    scene.present_to(canvas)?
    var presentation: f64 = 0.0
    for index: int in 0..120 {
        let start: int = time.monotonic_nanos()
        scene.present_to(canvas)?
        presentation += (time.monotonic_nanos() - start) as f64 / 1000000.0
    }
    io.println("mean readback+native present ms: {presentation / 120.0}")
    canvas.release(); app.shutdown()
    scene.close()
    return ok(true)
}
fn main() { match run() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
