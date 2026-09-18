package main

import cortado_skia
import cortado.geometry
import cortado.surface
import cortado.platform
import cortado.host
import {DrawingPage} from rendered_demo.generated.site
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn verify() -> Result<bool> {
    let app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    let page: DrawingPage = new DrawingPage()
    let window: cortado_skia.Window = cortado_skia.Window.open(app, geometry.Size.of(700.0, 370.0),
                                                               "animation test", page)?
    require(!window.scene().has_active_animations(), "opening a still page started the frame clock")
    page.toggle()
    require(window.refresh()?, "drawing state change did not refresh the window")
    require(window.scene().has_active_animations(), "drawing transition did not start")
    unsafe { host.check(host.ctd_clock_step(window.native_window().handle().raw, 0.1) as int,
                        "advance shared window transition")? }
    require(window.scene().has_active_animations(), "transition stopped before its duration")
    unsafe { host.check(host.ctd_clock_step(window.native_window().handle().raw, 0.4) as int,
                        "finish shared window transition")? }
    require(!window.scene().has_active_animations(), "transition stayed active after its duration")
    var stopped: bool = false
    unsafe {
        stopped = host.ctd_clock_step(window.native_window().handle().raw, 0.1) as int != host.OK
    }
    require(stopped, "idle shared window kept its native frame clock")
    require(window.last_error() == "", "window reported a render or native service error: {window.last_error()}")
    window.close()
    require(app.router.watching() == 0, "closing the shared window left event callbacks")
    app.shutdown()
    io.println("ok window animation, native frame stop, and teardown")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
