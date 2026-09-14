// Several things moving in one window. Three, not two: an off-by-one fan-out
// still serves two, and removing the middle one catches a list keyed by index.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.motion
import std.io

// Handlers capture this rather than the thing they are attached to: the other
// way is a cycle the collector cannot see through.
class Counter {
    pub seen: int = 0
    pub tokens: List<int> = []

    pub fn init() {}
}

fn refusal(what: string, outcome: Result<bool>) -> string {
    match outcome {
        ok(done) => { return "{what} was allowed, and should not have been" }
        err(problem) => { return "{what} refused: {problem.kind}" }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(320.0, 200.0, "Clocks")?

    // Counters say everybody was told; the order log says in what order. Two
    // different claims.
    let first: Counter = new Counter()
    let second: Counter = new Counter()
    let third: Counter = new Counter()
    let order: Counter = new Counter()

    var one: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)
    var two: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)
    var three: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)

    one.start(11, fn(frame: motion.Frame) {
        first.seen = first.seen + 1
        first.tokens.push(frame.token)
        order.tokens.push(11)
    })?
    two.start(22, fn(frame: motion.Frame) {
        second.seen = second.seen + 1
        second.tokens.push(frame.token)
        order.tokens.push(22)
    })?
    three.start(33, fn(frame: motion.Frame) {
        third.seen = third.seen + 1
        third.tokens.push(frame.token)
        order.tokens.push(33)
    })?

    io.println("-- three clocks on one window --")
    io.println("  all three joined: {motion.ClockDesk.instance.listeners_on(window.handle()) == 3}")
    let running: motion.ClockState = one.state()?
    io.println("  the host started exactly one clock: {running.running}")

    one.step(0.25)?
    one.step(0.25)?
    one.step(0.25)?

    io.println("  every listener saw every frame: {first.seen == 3 && second.seen == 3 && third.seen == 3}")
    // The host counts frames once; each listener was handed all of them. A
    // fan-out that started its own clock per listener would make these differ.
    let counted: motion.ClockState = one.state()?
    io.println("  the host counted them once: {counted.frames == 3}")

    // Each listener is told its own token: one frame now reaches three handlers
    // and each needs to know which it is.
    io.println("  each was told its own token: {first.tokens[0] == 11 && second.tokens[0] == 22 && third.tokens[0] == 33}")
    io.println("  and told in the order they joined: {order.tokens[0] == 11 && order.tokens[1] == 22 && order.tokens[2] == 33}")

    io.println("-- the middle one leaves --")
    two.stop()?
    io.println("  two are left: {motion.ClockDesk.instance.listeners_on(window.handle()) == 2}")
    let still: motion.ClockState = one.state()?
    io.println("  the host clock is still running: {still.running}")

    one.step(0.25)?
    one.step(0.25)?

    io.println("  the survivors kept getting frames: {first.seen == 5 && third.seen == 5}")
    io.println("  the one that left stopped getting them: {second.seen == 3}")
    // The survivors are the first and the last. A fan-out that rebuilt its
    // order list by index rather than by identity drops one of these.
    io.println("  and they are still the two that stayed: {first.tokens.len() == 5 && third.tokens.len() == 5}")

    io.println("-- the last two leave --")
    one.stop()?
    three.stop()?
    io.println("  nobody is left: {motion.ClockDesk.instance.listeners_on(window.handle()) == 0}")
    let stopped: motion.ClockState = one.state()?
    io.println("  and the host clock stopped with them: {!stopped.running}")

    io.println("-- refusals --")
    // Two listeners under one token would mean a frame arriving at a handler
    // whose owner cannot take it off again.
    var rejoin: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)
    rejoin.start(44, fn(frame: motion.Frame) {})?
    var clash: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)
    io.println(refusal("a second listener under a token already joined",
                       clash.start(44, fn(frame: motion.Frame) {})))
    // Starting one clock twice is still wrong: the object holds one token, so
    // the first listener would be stranded.
    io.println(refusal("one clock started twice",
                       rejoin.start(55, fn(frame: motion.Frame) {})))
    rejoin.stop()?
    io.println("  the surface is clear again: {motion.ClockDesk.instance.listeners_on(window.handle()) == 0}")

    // A clock on something that is not a surface is still that mistake, and a
    // desk in front of the host must not swallow it.
    var button: widgets.Button = widgets.Button.of("Not a surface")?
    var wrong: motion.FrameClock = new motion.FrameClock(button.handle(), app.router)
    io.println(refusal("a clock on a button", wrong.start(1, fn(frame: motion.Frame) {})))
    button.release()
    io.println(refusal("a clock on a released widget", wrong.stop()))

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
