// The display's own beat, on the one host that has a display.
//
// `tests/clock.b` checks the clock's arithmetic with synthesized frames, which
// is what every host can do. This checks the half that only a real display can
// answer: that CVDisplayLink starts, that its callback reaches Beans on the UI
// thread, that the numbering it produces is the numbering the synthesized path
// produces, and that a stopped clock really does go quiet — frames the link
// had already queued must not arrive after the program asked for silence.
//
// Nothing here is a golden of *when* anything happened. Two runs of the same
// program never agree on that. What is pinned is how many frames arrived, in
// what order, and every invariant the header promises about them.
//
// It runs the event loop, which no other case does, and it runs it with a
// deadline. A gate that waited for a display on a machine that has none would
// not fail there — it would hang for ever.
package main

import cortado.platform
import cortado.surface
import cortado.motion
import std.io

class Watch {
    pub frames: int = 0
    pub numbered_in_order: bool = true
    pub token_echoed: bool = true
    pub deltas_positive: bool = true
    pub elapsed_rising: bool = true
    pub elapsed: f64 = 0.0
    pub deltas: f64 = 0.0
    pub stopped_from_a_frame: bool = false

    pub fn init() {}
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(320.0, 200.0, "Frames")?
    var clock: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)

    let watch: Watch = new Watch()
    let wanted: int = 5

    clock.start(42, fn(frame: motion.Frame) {
        watch.frames = watch.frames + 1
        if frame.number != watch.frames { watch.numbered_in_order = false }
        if frame.token != 42 { watch.token_echoed = false }
        if frame.delta <= 0.0 { watch.deltas_positive = false }
        if frame.elapsed <= watch.elapsed { watch.elapsed_rising = false }
        watch.elapsed = frame.elapsed
        watch.deltas = watch.deltas + frame.delta
        if watch.frames == wanted {
            // Stopped from inside a frame, which is what anything that
            // finishes actually does — and the only way this case can pin a
            // number. The link's thread hands each frame to the UI thread, so
            // by the time the first one is looked at there is a whole batch of
            // them already waiting. Asking the clock to stop is what makes the
            // rest of that batch be refused instead of delivered.
            match clock.stop() {
                ok(done) => { watch.stopped_from_a_frame = true }
                err(problem) => { watch.stopped_from_a_frame = false }
            }
            app.stop()
        }
    })?

    // Two seconds for five frames. A display that refreshes at all delivers
    // them in under a tenth of that, so the deadline is only ever reached when
    // there is nothing driving the clock — and then this case fails, loudly,
    // instead of waiting.
    app.run_for(2.0)?

    let ran: motion.ClockState = clock.state()?
    io.println("asked for {wanted} frames, beans saw {watch.frames}, the host counted {ran.frames}")
    io.println("stopped from inside a frame: {watch.stopped_from_a_frame}")
    io.println("numbered 1.. in order: {watch.numbered_in_order}")
    io.println("token echoed on every frame: {watch.token_echoed}")
    io.println("every delta positive: {watch.deltas_positive}")
    io.println("elapsed rose every frame: {watch.elapsed_rising}")
    // The header's promise that no tick is dropped or merged, as arithmetic:
    // if a frame had gone missing its delta would be missing from this sum.
    let drift: f64 = watch.deltas - watch.elapsed
    io.println("the deltas add up to the elapsed: {drift < 0.000000001 && drift > -0.000000001}")

    // Already stopped, from inside the frame. Doing it again is allowed, and
    // a teardown path that did not know is the reason it is allowed.
    clock.stop()?
    let at_stop: motion.ClockState = clock.state()?
    // The link's callback runs on its own thread and hands each frame to the
    // UI thread, so at the moment a clock stops there may be frames already in
    // flight. Pumping the loop again is what makes them arrive if they are
    // going to, and the host's own count is what sees them — the handler came
    // off with the clock, so Beans could not.
    app.run_for(0.2)?
    let settled: motion.ClockState = clock.state()?
    io.println("frames delivered after the clock stopped: {settled.frames - at_stop.frames}")

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
