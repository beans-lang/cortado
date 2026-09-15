// Whether the toast's buttons actually do anything — which a tree dump of the
// screen as it opens cannot see, because the toast is there either way.
//
//     beansc build examples/gradients/main.b -o gradients && ./gradients --dismiss
//
// This exists because they did not. The handlers ran and set the field, and the
// screen kept showing the toast: a mount asks whether a component is dirty, so
// a handler that changes a field and stops is a button that does nothing.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import std.io
import {Petrichor} from gradients.generated.site

/// The first button anywhere under `node` whose title is `label`.
fn button_titled(node: widgets.Widget, label: string) -> Option<widgets.Widget> {
    for child: widgets.Widget in node.children() {
        match child as? widgets.Button {
            some(button) => {
                match button.title() {
                    ok(text) => { if text == label { return some(child) } }
                    err(problem) => {}
                }
            }
            none => {}
        }
        match button_titled(child, label) {
            some(found) => { return some(found) }
            none => {}
        }
    }
    return none
}

/// Opens the screen, presses a button on the toast the way a mouse would, and
/// answers the three things worth knowing about what happened.
fn press(label: string) -> Result<List<bool>> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(900.0, 640.0, "Petrichor")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(900.0, 640.0))
    var screen: Petrichor = new Petrichor()
    mount.show(screen)?

    var found: bool = false
    match button_titled(root, label) {
        some(button) => {
            found = true
            // The platform's own dispatch, which is the path a click takes.
            button.activate()?
        }
        none => {}
    }
    let handled: bool = screen.dismissed
    let refreshed: bool = mount.refresh_if_needed()?
    var gone: bool = true
    match button_titled(root, "Restore draft") {
        some(still) => { gone = false }
        none => {}
    }
    mount.close()?
    app.shutdown()

    var answers: List<bool> = []
    answers.push(found)
    answers.push(handled)
    answers.push(refreshed && gone)
    return ok(move answers)
}

/// The `--dismiss` report. One line per button, the same on any host.
/// Runs the screen for long enough to take a frame-rate reading, and answers
/// whether the number on it was counted rather than guessed.
///
/// Headless, and that is not a dodge: a headless app on this platform still
/// gets real display-link ticks (`tests/frames.b` is built on it), so the
/// canvas really draws and the reading really counts what it drew.
pub fn report_rate() {
    match take_reading() {
        ok(answers) => {
            io.println("a reading was taken: {answers[0]}")
            io.println("it counts frames that reached the screen: {answers[1]}")
            io.println("and the label says so: {answers[2]}")
            io.println("at a rate a display could produce: {answers[3]}")
        }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
    io.println("-- a window the window server is not showing --")
    match unshown() {
        ok(answers) => {
            io.println("nothing was drawn into it: {answers[0]}")
            io.println("so no reading was taken: {answers[1]}")
        }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}

/// The same screen in a real application whose window is never shown.
///
/// A frame drives drawing, and drawing into a surface nobody is being shown
/// costs a full GPU pass for nothing — six of them here. The display link is
/// the *display's*, so it fires for a window that is hidden, minimised or
/// buried, and before the clock was gated on what the window server is
/// actually showing this drew flat out behind whatever you were working in.
fn unshown() -> Result<List<bool>> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?
    var window: surface.Window = app.window(900.0, 640.0, "Petrichor")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(900.0, 640.0))
    var screen: Petrichor = new Petrichor()
    // No `window.show()`. Everything else is what the shown case does.
    mount.show(screen)?
    app.run_for(1.4)?
    mount.refresh_if_needed()?
    let quiet: bool = screen.rate == "measuring"
    let unread: bool = screen.measured < 0.0
    mount.close()?
    app.shutdown()
    var answers: List<bool> = []
    answers.push(quiet)
    answers.push(unread)
    return ok(move answers)
}

fn take_reading() -> Result<List<bool>> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(900.0, 640.0, "Petrichor")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(900.0, 640.0))
    var screen: Petrichor = new Petrichor()
    mount.show(screen)?
    // Longer than the one-second window the reading is taken over.
    app.run_for(1.4)?
    mount.refresh_if_needed()?
    let took: bool = screen.measured >= 0.0
    let counted: bool = screen.measured > 0.0
    let said: bool = screen.rate.contains("fps")
    // A number rather than a range would be a golden that fails on a busy
    // machine; nought and ten thousand are the two answers that are bugs.
    let sane: bool = screen.measured > 0.5 && screen.measured < 400.0
    mount.close()?
    app.shutdown()
    var answers: List<bool> = []
    answers.push(took)
    answers.push(counted)
    answers.push(said)
    answers.push(sane)
    return ok(move answers)
}

fn report_dismiss() {
    io.println("-- the toast does what its buttons say --")
    say("the ✕", "✕")
    say("restore draft", "Restore draft")
}

fn say(name: string, label: string) {
    match press(label) {
        ok(answers) => {
            io.println("  {name} is on the screen: {answers[0]}, runs its handler: {answers[1]}, and the toast goes: {answers[2]}")
        }
        err(problem) => { io.println("  {name}: {problem.kind}: {problem.msg}") }
    }
}
