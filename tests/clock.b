// The frame clock, without a display.
//
// A frame is the one event no test can provoke by clicking something, and on
// three hosts out of four it cannot be provoked at all in a gate: a window
// that is never shown is on no screen, and a frame clock with no screen has
// nothing to follow. So the host has `step`, the same family as
// `Button.activate` — it raises a frame down the exact path the display link
// uses, rather than around it, and the numbering, the token, the elapsed
// arithmetic and every refusal become the same bytes on every platform.
//
// What the times are is deliberately not the news here. The steps are quarter
// seconds because a quarter is exact in binary on every machine, so this
// golden pins the clock's arithmetic and never floating point.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.motion
import std.io

// Handlers capture this rather than a list, for the reason `tests/events.b`
// gives: a handler that captured the thing it is attached to would be a cycle
// the collector cannot see through.
class Tally {
    pub log: List<string> = []

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
    var window: surface.Window = app.window(320.0, 200.0, "Clock")?

    var clock: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)

    let before: motion.ClockState = clock.state()?
    io.println("before start: {before.show()}")
    io.println(refusal("a step before the clock started", clock.step(0.25)))
    // Stopping one that never started is not an error: a teardown path should
    // not have to ask first, and there is nothing a caller would do
    // differently about a clock that had already stopped.
    match clock.stop() {
        ok(done) => { io.println("stopping a clock that never started: allowed") }
        err(problem) => { io.println("stopping a clock that never started refused: {problem.kind}") }
    }

    let tally: Tally = new Tally()
    clock.start(77, fn(frame: motion.Frame) {
        tally.log.push("{frame.show()} elapsed={frame.elapsed} delta={frame.delta}")
    })?

    clock.step(0.25)?
    clock.step(0.25)?
    clock.step(0.25)?
    for line: string in tally.log {
        io.println(line)
    }

    io.println(refusal("a second start while running", clock.start(99, fn(frame: motion.Frame) {})))

    let running: motion.ClockState = clock.state()?
    io.println("while running: {running.show()} elapsed={running.elapsed}")
    // The count the host kept against the count Beans made. They are two
    // independent tallies of the same frames, and a delivery path that lost
    // one shows up here rather than as an animation that ends early.
    io.println("beans counted {tally.log.len()}, the host counted {running.frames}")

    io.println(refusal("a step of no time at all", clock.step(0.0)))
    io.println(refusal("a step backwards", clock.step(-0.25)))

    io.println("-- the rate a surface asks its display for --")
    // Zero is "the screen's own maximum", which is what a clock asks for
    // until it is told otherwise, so it is a real request and not a no-op.
    match clock.prefer(0.0, 0.0, 0.0) {
        ok(done) => { io.println("asking for the screen's maximum: allowed") }
        err(problem) => { io.println("asking for the screen's maximum refused: {problem.kind}") }
    }
    match clock.prefer(60.0, 60.0, 60.0) {
        ok(done) => { io.println("asking for one rate, held: allowed") }
        err(problem) => { io.println("asking for one rate refused: {problem.kind}") }
    }
    io.println(refusal("a rate below zero", clock.prefer(0.0, 0.0, 0.0 - 1.0)))
    io.println(refusal("a floor above the ceiling", clock.prefer(120.0, 60.0, 60.0)))
    // With no rate wished for, the crossed ends are the only thing wrong —
    // which is what makes this case the one that tests that rule alone.
    io.println(refusal("crossed ends and no wish", clock.prefer(120.0, 60.0, 0.0)))
    io.println(refusal("a wish above the ceiling", clock.prefer(0.0, 60.0, 120.0)))
    io.println(refusal("a wish below the floor", clock.prefer(60.0, 0.0, 30.0)))

    clock.stop()?
    let stopped: motion.ClockState = clock.state()?
    io.println("after stop: {stopped.show()}")
    io.println(refusal("a step after the clock stopped", clock.step(0.25)))
    // The handler went with the clock, so nothing is left pointing at it.
    io.println("handlers left registered: {app.router.registered()}")

    // Starting again is a new clock, not a continuation: the numbering goes
    // back to 1 and so does the elapsed. Somebody who restarts a clock is
    // starting whatever it drives over again, and a first frame numbered 4
    // would be a strange way to say that.
    let again: Tally = new Tally()
    clock.start(88, fn(frame: motion.Frame) {
        again.log.push("{frame.show()} elapsed={frame.elapsed} delta={frame.delta}")
    })?
    clock.step(0.5)?
    for line: string in again.log {
        io.println(line)
    }
    let restarted: motion.ClockState = clock.state()?
    io.println("after restarting: {restarted.show()} elapsed={restarted.elapsed}")
    clock.stop()?

    // A clock belongs to a surface. Asking a button for one is a mistake worth
    // being told about, not a clock that quietly never ticks.
    var button: widgets.Button = widgets.Button.of("Not a surface")?
    var wrong: motion.FrameClock = new motion.FrameClock(button.handle(), app.router)
    io.println(refusal("a clock on a button", wrong.start(1, fn(frame: motion.Frame) {})))

    button.release()
    io.println(refusal("a clock on a released widget", wrong.stop()))

    window.close()?
    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
