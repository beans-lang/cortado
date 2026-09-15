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
pub fn report_dismiss() {
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
