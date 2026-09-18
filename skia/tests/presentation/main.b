package main

import cortado_skia
import cortado.geometry
import cortado.paint
import cortado.widgets
import cortado.platform
import cortado.surface
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn pixels(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32,
          width: int, height: int, red: int) -> i32 {
    let count: int = width * height * 4
    unsafe {
        size.write(width as f64); size.offset(1).write(height as f64)
        if out.is_null() { return count as i32 }
        if capacity < count as i32 { return -1 }
        for pixel: int in 0..width * height {
            out.offset(pixel * 4).write(red as i8)
            out.offset(pixel * 4 + 1).write(0)
            out.offset(pixel * 4 + 2).write(0)
            out.offset(pixel * 4 + 3).write(-1)
        }
    }
    return count as i32
}
fn red(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32) -> i32 {
    return pixels(size, out, capacity, 2, 2, 40)
}
fn blue(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32) -> i32 {
    return pixels(size, out, capacity, 2, 2, 90)
}
fn wide(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32) -> i32 {
    return pixels(size, out, capacity, 3, 1, 120)
}
fn bad_count(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32) -> i32 {
    unsafe { size.write(2.0); size.offset(1).write(2.0) }
    return 15
}
fn raced_size(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32) -> i32 {
    unsafe {
        if out.is_null() { size.write(2.0); size.offset(1).write(2.0) }
        else { size.write(4.0); size.offset(1).write(1.0) }
    }
    return 16
}
fn short_write(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32) -> i32 {
    unsafe { size.write(2.0); size.offset(1).write(2.0) }
    if out.is_null() { return 16 }
    return 12
}

fn draw(renderer: cortado_skia.SkiaRenderer, size: geometry.Size, color: int) -> Result<bool> {
    let canvas: paint.Canvas = renderer.begin(size, 1.0, color)?
    renderer.end()?
    return ok(true)
}

fn verify() -> Result<bool> {
    let frame: widgets.Snapshot = widgets.Snapshot.read("first", red)?
    require(frame.width == 2 && frame.height == 2 && frame.pixel(1, 1)?.red == 40,
            "initial capture was wrong")
    frame.recapture("same size", blue)?
    require(frame.byte_count() == 16 && frame.pixel(1, 1)?.red == 90,
            "same-size recapture did not update pixels")
    frame.recapture("resized", wide)?
    require(frame.width == 3 && frame.height == 1 && frame.byte_count() == 12 &&
            frame.pixel(2, 0)?.red == 120, "resize did not replace the buffer safely")
    match frame.recapture("bad count", bad_count) {
        ok(_) => { panic("invalid dimensions and count were accepted") }
        err(_) => { require(frame.width == 3 && frame.height == 1,
                           "failed probe changed a valid frame") }
    }
    frame.recapture("restored", red)?
    match frame.recapture("raced", raced_size) {
        ok(_) => { panic("changed dimensions during read were accepted") }
        err(problem) => { require(problem.kind == "host_raced" && frame.width == 0,
                                  "failed reused read was not invalidated") }
    }
    frame.recapture("recovered", blue)?
    require(frame.width == 2 && frame.height == 2 && frame.pixel(0, 0)?.red == 90,
            "recapture did not recover after a failed write")
    match frame.recapture("short write", short_write) {
        ok(_) => { panic("short second read was accepted") }
        err(problem) => { require(problem.kind == "host_raced" && frame.width == 0,
                                  "short reused read was not invalidated") }
    }

    let app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    let window: surface.Window = app.window(8.0, 8.0, "renderer presentation")?
    let target: widgets.Canvas = new widgets.Canvas()
    window.set_root(target)?
    let renderer: cortado_skia.SkiaRenderer = new cortado_skia.SkiaRenderer()
    draw(renderer, geometry.Size.of(8.0, 8.0), 0x401020ff)?
    let public_first: widgets.Snapshot = renderer.snapshot()?
    renderer.present_to(target)?
    draw(renderer, geometry.Size.of(8.0, 8.0), 0x902030ff)?
    renderer.present_to(target)?
    let public_second: widgets.Snapshot = renderer.snapshot()?
    require(public_first.pixel(0, 0)?.red == 64 && public_second.pixel(0, 0)?.red == 144,
            "public snapshots changed with later presentation")
    draw(renderer, geometry.Size.of(12.0, 6.0), 0x20a040ff)?
    renderer.present_to(target)?
    require(public_first.width == 8 && public_first.height == 8 &&
            public_first.pixel(0, 0)?.red == 64,
            "resized presentation changed a retained public snapshot")
    renderer.close()
    window.close()?
    app.shutdown()
    io.println("ok snapshot recapture, presentation, resize, errors, and owned snapshots")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
