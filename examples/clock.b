// Motion, both kinds: one you drive, and one the platform drives.
//
//     beansc build examples/clock.b -o build/clock && ./build/clock
//
// The bar is driven here. A frame clock delivers one event per frame the
// display is about to show, carrying how long since the last one, and that
// number — `frame.delta` — is what the bar advances by. The difference shows
// up the moment the screen is not 60 Hz: a fixed step per tick finishes in
// half the time on a 120 Hz display, and this finishes in three seconds on
// both. The measured rate is printed as it goes, which is the other half of
// the point: nothing here had to be told what the refresh rate is.
//
// The fade is not driven here. It is described — from, to, how long, what
// shape — and handed to the platform, which runs it on the render server at
// the display's rate with no Beans code involved in any frame of it. Clicking
// Fade twice before it finishes is the interesting case: the second animation
// replaces the first, which reports itself cancelled.
//
// Which to use is the whole lesson of this file. A frame clock is for
// something whose next value you have to work out — a simulation, a plot, a
// game. An animation is for a value you already know the end of, which is
// almost everything an interface does.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.motion
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

// Handlers capture this rather than the controls they belong to. A closure
// that captured its own widget would be a cycle the collector cannot see
// through, because the platform's stored callback holds a reference the tracer
// never walks.
class Progress {
    pub filled: f64 = 0.0
    pub frames: int = 0
    pub done: bool = false
    pub faded_to: f64 = 1.0

    pub fn init() {}
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(420.0, 180.0, "Cortado — motion")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Three seconds, one frame at a time")?
    var bar: widgets.ProgressBar = new widgets.ProgressBar()
    var status: widgets.Label = widgets.Label.of("waiting for the first frame")?
    var fade_button: widgets.Button = widgets.Button.of("Fade")?
    var quit_button: widgets.Button = widgets.Button.of("Quit")?

    root.add(heading)?
    root.add(bar)?
    root.add(status)?
    root.add(fade_button)?
    root.add(quit_button)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(24.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?
    page.add(sheet.leaf("heading", heading))
    page.add(sheet.leaf("bar", bar))
    page.add(sheet.leaf("status", status))

    var row: layout.StackLayout = layout.StackLayout.row(12.0)
    row.set_justify(layout.Justify.end)
    var buttons: layout.LayoutNode = sheet.spacer("buttons", row)
    buttons.add(sheet.leaf("fade", fade_button))
    buttons.add(sheet.leaf("quit", quit_button))
    page.add(buttons)

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    bar.set_range(0.0, 1.0)?
    bar.set_value(0.0)?

    let progress: Progress = new Progress()
    var clock: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)

    clock.start(1, fn(frame: motion.Frame) {
        progress.frames = frame.number
        // Advanced by the time that passed, never by a fixed step per tick.
        // This is the whole difference between motion that takes three seconds
        // and motion that takes however long the display feels like.
        progress.filled = progress.filled + frame.delta / 3.0
        if progress.filled >= 1.0 {
            progress.filled = 1.0
            progress.done = true
        }
        bar.set_value(progress.filled)
        let rate: f64 = if frame.elapsed > 0.0 { frame.number as f64 / frame.elapsed } else { 0.0 }
        status.set_text("frame {frame.number} · {rate as int} per second · {(progress.filled * 100.0) as int}%")
        if progress.done {
            // Stopped from inside the frame that finished it, which is what
            // anything with an end does. A clock nobody stops keeps waking the
            // process sixty times a second for the rest of its life.
            match clock.stop() {
                ok(stopped) => { status.set_text("done in {frame.number} frames") }
                err(problem) => { status.set_text("could not stop: {problem.msg}") }
            }
        }
    })?

    // The platform's own animation: described, handed over, and then nothing
    // here runs until it reports back.
    app.router.on(fade_button.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            progress.faded_to = if progress.faded_to > 0.5 { 0.2 } else { 1.0 }
            match motion.Animation.on(heading.handle(), motion.Animatable.opacity) {
                ok(fade) => {
                    fade.to(progress.faded_to)
                    fade.duration(0.4)
                    fade.curve(motion.Curve.ease_in_out)
                    fade.start(2)
                    io.println("fading to {progress.faded_to}")
                }
                err(problem) => { io.println("no fade: {problem.msg}") }
            }
        })

    // Where an animation reports back: an ordinary event on the widget it
    // moved, so it is registered like any other handler and carries the token
    // that says which animation it was.
    app.router.on(heading.handle(), events.EventKind.anim_done,
        fn(event: events.UiEvent) {
            let end: motion.AnimationEnd = motion.AnimationEnd.of(event)
            if end.finished {
                io.println("faded to {end.value}")
            } else {
                io.println("that fade was cut short at {end.value}")
            }
        })

    app.router.on(quit_button.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            io.println("closing after {progress.frames} frames")
            app.stop()
        })

    window.show()?
    app.run()
    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => { io.println("done={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
