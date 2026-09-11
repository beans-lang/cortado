// The negative control for the headless leg.
//
// Every other test claims that a widget tree can be built, sized and measured
// with nothing on screen. That claim is only worth something if its opposite
// is detectable — a probe that always answered "yes, headless" would look
// exactly like one that worked. So this shows a surface under
// `AppRole.headless` and requires it to report itself invisible, and shows one
// under `AppRole.accessory` and requires the opposite.
package main

import cortado.platform
import cortado.surface
import std.io

fn probe() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)

    var hidden: surface.Window = app.window(200.0, 120.0, "Headless")?
    hidden.show()?
    io.println("headless visible={hidden.is_visible()}")
    hidden.close()?

    app.set_role(platform.AppRole.accessory)?
    var shown: surface.Window = app.window(200.0, 120.0, "Accessory")?
    shown.show()?
    io.println("accessory visible={shown.is_visible()}")
    shown.close()?

    app.shutdown()
    return ok(true)
}

fn main() {
    match probe() {
        ok(done) => { io.println("probed={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
