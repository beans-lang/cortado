// An animation, built here and run by the platform.
//
// What is pinned is everything that is a decision rather than a measurement:
// the refusals, the rule that the property reads as the destination the moment
// the animation starts, that the end arrives as an ordinary event carrying the
// token it was given, that cancelling keeps the value it was showing rather
// than jumping to the destination, and that starting a second animation of the
// same property ends the first as cancelled.
//
// What is not pinned is any time or any value in flight. Two runs never agree
// on those, so the one mid-flight reading this case looks at is checked for
// being inside a range rather than printed.
//
// This case is built for iOS and not run there, and the reason is a platform
// rule rather than a gap: a layer that is not in a visible window has no render
// context on iOS, and Core Animation removes an animation on one within a frame
// and reports that it did not finish. macOS has no such rule, which is the only
// reason the rest of this suite can be headless. `test.sh` says the same thing
// beside `ios_builds_only`.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.motion
import cortado.events
import std.io

class Tally {
    pub log: List<string> = []
    pub ended: int = 0

    pub fn init() {}
}

fn refusal(what: string, outcome: Result<bool>) -> string {
    match outcome {
        ok(done) => { return "{what} was allowed, and should not have been" }
        err(problem) => { return "{what} refused: {problem.kind}" }
    }
}

fn rounded(value: f64) -> string {
    let hundredths: int = ((value * 100.0) + 0.5) as int
    let whole: int = hundredths / 100
    let rest: int = hundredths % 100
    if rest < 10 { return "{whole}.0{rest}" }
    return "{whole}.{rest}"
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(320.0, 200.0, "Animation")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var badge: widgets.Button = widgets.Button.of("Badge")?
    root.add(badge)?

    let tally: Tally = new Tally()
    app.router.on(badge.handle(), events.EventKind.anim_done, fn(event: events.UiEvent) {
        let end: motion.AnimationEnd = motion.AnimationEnd.of(event)
        tally.ended = tally.ended + 1
        tally.log.push("ended {end.show()}")
    })

    // ---- what the builder refuses -------------------------------------------

    var checks: motion.Animation = motion.Animation.on(badge.handle(), motion.Animatable.opacity)?
    io.println(refusal("an animation of no time at all", checks.duration(0.0)))
    io.println(refusal("an animation of negative time", checks.duration(-1.0)))
    io.println(refusal("a delay before the start of time", checks.delay(-0.5)))
    io.println(refusal("starting one that was never told where to go", checks.start(1)))
    // Built and never started: cancelling is how it is thrown away, and it
    // raises nothing because nothing ever ran.
    checks.cancel()?
    io.println(refusal("cancelling it a second time", checks.cancel()))
    io.println("nothing ended yet: {tally.ended}")
    // A surface is not a widget. Three platforms out of four would have taken
    // one — a UIWindow is a UIView and a GtkWindow is a GtkWidget — so this is
    // cortado's answer rather than the object systems', and it is here because
    // a rule nobody checks is four rules.
    match motion.Animation.on(window.handle(), motion.Animatable.opacity) {
        ok(built) => { io.println("an animation of a surface was allowed, and should not have been") }
        err(problem) => { io.println("an animation of a surface refused: {problem.kind}") }
    }

    // ---- a movement that finishes -------------------------------------------

    badge.set_opacity(1.0)?
    var fade: motion.Animation = motion.Animation.on(badge.handle(), motion.Animatable.opacity)?
    fade.to(0.0)?
    fade.duration(0.1)?
    fade.curve(motion.Curve.linear)?
    fade.start(7)?
    // The rule the whole design rests on: the property says where the control
    // is *going*, from the moment it is asked to go there. What is on screen
    // for the next tenth of a second is a picture.
    io.println("opacity the instant it starts: {rounded(badge.opacity()?)}")
    // Every setter, not one of them. Each carries the same guard and a test
    // that tried one would leave four that could be deleted without a word.
    io.println(refusal("moving the start of one that is running", fade.from(0.5)))
    io.println(refusal("moving the end of one that is running", fade.to(0.5)))
    io.println(refusal("changing how long one that is running takes", fade.duration(0.5)))
    io.println(refusal("delaying one that is already running", fade.delay(0.5)))
    io.println(refusal("changing the curve of one that is running", fade.curve(motion.Curve.ease_in)))
    io.println(refusal("starting one that is already running", fade.start(8)))

    app.run_for(1.0)?
    io.println("after it finished: {tally.log[0]} opacity={rounded(badge.opacity()?)}")
    // The platform owned it and has let it go, so the handle names nothing.
    io.println(refusal("cancelling one that already ended", fade.cancel()))

    // ---- a movement that is cancelled ---------------------------------------

    badge.set_opacity(0.0)?
    var rise: motion.Animation = motion.Animation.on(badge.handle(), motion.Animatable.opacity)?
    rise.to(1.0)?
    rise.duration(4.0)?
    rise.curve(motion.Curve.linear)?
    rise.start(11)?
    app.run_for(0.4)?
    rise.cancel()?
    app.run_for(0.2)?
    let stopped: f64 = badge.opacity()?
    io.println("after cancelling: {tally.log[1]}")
    // Not the destination, which is the whole point of cancelling, and not
    // still at the start either — four seconds is long enough that four tenths
    // of it is plainly in the middle, on any machine that draws at all.
    io.println("it kept where it was showing: {stopped > 0.0 && stopped < 1.0}")

    // ---- a movement replaced by another -------------------------------------

    badge.set_opacity(0.0)?
    var slow: motion.Animation = motion.Animation.on(badge.handle(), motion.Animatable.opacity)?
    slow.to(1.0)?
    slow.duration(4.0)?
    slow.start(21)?
    var quick: motion.Animation = motion.Animation.on(badge.handle(), motion.Animatable.opacity)?
    quick.to(0.5)?
    quick.duration(0.1)?
    quick.start(22)?
    app.run_for(1.0)?
    io.println("the one replaced: {tally.log[2]}")
    io.println("the one that replaced it: {tally.log[3]}")
    io.println("opacity at the end: {rounded(badge.opacity()?)}")

    // ---- a widget that goes while something is moving it --------------------

    var doomed: widgets.Button = widgets.Button.of("Doomed")?
    root.add(doomed)?
    app.router.on(doomed.handle(), events.EventKind.anim_done, fn(event: events.UiEvent) {
        let end: motion.AnimationEnd = motion.AnimationEnd.of(event)
        tally.ended = tally.ended + 1
        tally.log.push("ended {end.show()}")
    })
    var vanish: motion.Animation = motion.Animation.on(doomed.handle(), motion.Animatable.opacity)?
    vanish.to(0.0)?
    vanish.duration(4.0)?
    vanish.start(31)?
    doomed.release()
    app.run_for(0.3)?
    // Whatever a platform does with the layer, the answer a program gets has
    // to be the same one: the movement did not finish, and it is not still
    // going. A host that quietly kept ticking against a released widget would
    // report it finished four seconds later.
    io.println("when the widget went: {tally.log[4]}")

    io.println("animations that ended: {tally.ended}")

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
