package main

import cortado_skia
import cortado.surface
import cortado.platform
import cortado.motion
import std.io

class Counter {
    pub frames: int = 0
    pub elapsed: f64 = 0.0
    pub fn init() {}
}
fn require(value: bool, message: string) { if !value { panic(message) } }
fn verify() -> Result<bool> {
    let app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    let first: surface.Window = app.window(100.0, 100.0, "first clock")?
    let second: surface.Window = app.window(100.0, 100.0, "second clock")?
    let seen: Counter = new Counter()
    let other: Counter = new Counter()
    let clock: cortado_skia.FrameDriver = new cortado_skia.FrameDriver(first.handle(), app.router,
        fn(delta: f64) { seen.frames += 1; seen.elapsed += delta })
    let independent: cortado_skia.FrameDriver = new cortado_skia.FrameDriver(second.handle(), app.router,
        fn(delta: f64) { other.frames += 1 })
    require(!clock.request(false)? && !clock.is_running(), "idle frame driver started a clock")
    require(clock.request(true)? && !clock.request(true)?, "frame subscription was duplicated")
    independent.request(true)?
    clock.step(0.125)?
    clock.step(0.125)?
    require(seen.frames == 2 && seen.elapsed == 0.25, "native frame deltas did not reach Beans")
    require(other.frames == 0, "frame tick reached another window")
    require(motion.ClockDesk.instance.listeners_on(first.handle()) == 0, "shared driver used global listener registry")
    clock.request(false)?
    match clock.step(0.125) { ok(_) => { panic("idle frame clock kept ticking") } err(_) => {} }
    independent.step(0.125)?
    require(other.frames == 1, "stopping one clock stopped another window")
    clock.request(true)?
    clock.step(0.125)?
    require(seen.frames == 3, "frame driver could not restart")
    clock.close(); clock.close(); independent.close()
    require(app.router.watching() == 0, "frame teardown kept callbacks")
    match clock.request(true) { ok(_) => { panic("closed driver restarted") } err(_) => {} }
    first.close(); second.close(); app.shutdown()
    io.println("ok window-local frames, idle stop, restart, deltas, teardown")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
