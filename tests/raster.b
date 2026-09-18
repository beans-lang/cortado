package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.geometry
import cortado.host
import std.io

fn verify() -> Result<bool> {
    let app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    let window: surface.Window = app.window(40.0, 40.0, "raster bridge")?
    let canvas: widgets.Canvas = new widgets.Canvas()
    window.set_root(canvas)?
    let frame: widgets.Snapshot = widgets.Snapshot.read("test pixels",
        fn(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32) -> i32 {
            unsafe {
                size.write(32.0); size.offset(1).write(32.0)
                if out.is_null() { return 4096 }
                if capacity < 4096 { return host.ERR_RANGE as i32 }
                for pixel: int in 0..1024 {
                    out.offset(pixel * 4).write(76)
                    out.offset(pixel * 4 + 1).write(-104)
                    out.offset(pixel * 4 + 2).write(-32)
                    out.offset(pixel * 4 + 3).write(-1)
                }
            }
            return 4096
        })?
    canvas.present(frame)?
    canvas.present(frame)?
    let invalid: widgets.Snapshot = new widgets.Snapshot(32, 32, 1)
    match canvas.present(invalid) { ok(_) => { panic("short pixel buffer accepted") } err(_) => {} }
    let label: widgets.Label = new widgets.Label()
    unsafe {
        let code: int = host.ctd_canvas_set_pixels(label.handle().raw, 1, 1, RawPtr.null(), 0) as int
        if code != host.ERR_KIND { return err("raster accepted a non-canvas", "test") }
    }
    canvas.release()
    match canvas.present(frame) { ok(_) => { panic("stale canvas accepted pixels") } err(_) => {} }
    window.close()?
    label.release()
    app.shutdown()
    io.println("ok raster bridge: copied frames, buffer validation, kind checks, stale handles")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
