// A sign-in window — and a control that is not on every platform.
//
//     beansc build examples/signin.b -o build/signin && ./build/signin
//
// The password box is a real `NSSecureTextField`, a real `GtkEntry` with
// visibility off, a real `EDIT` with `ES_PASSWORD`. That matters more than it
// sounds: a text field with a bullet glyph drawn into it looks identical and
// does none of the work — the real one keeps what is typed out of the
// pasteboard, out of autocorrect's dictionary, and off a screen recording.
//
// The interesting line is `WidgetKind.switch.available()`. A toggle switch is
// a real control on macOS, iOS and Linux and **does not exist in the Win32
// common controls** — Windows has them, in WinUI, which an `HWND` cannot be.
// cortado will not draw an imitation and will not quietly hand back a check
// box, so it says so and this program decides: a switch where there is one, a
// check box where there is not. Six lines, and the program is right on four
// platforms instead of wrong on one.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

/// The "remember me" control, whichever one this platform has.
///
/// Returned as a `Widget` because that is all the layout and the event router
/// need. Whether it is on is asked through `is_remembering` below, which is
/// the one place that has to know which control it got.
fn remember_control() -> Result<widgets.Widget> {
    if widgets.WidgetKind.switch.available() {
        return ok(widgets.Switch.of(false)?)
    }
    return ok(widgets.CheckBox.of("Remember me")?)
}

/// Whether the control above is on, whichever one it is.
fn is_remembering(control: widgets.Widget) -> bool {
    match control as? widgets.Switch {
        some(toggle) => { return toggle.is_on().or(false) }
        none => {}
    }
    match control as? widgets.CheckBox {
        some(box) => { return box.state().or(widgets.CheckState.off) == widgets.CheckState.on }
        none => {}
    }
    return false
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(360.0, 260.0, "Sign in")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Sign in to cortado")?
    var who: widgets.TextField = widgets.TextField.of("")?
    var secret: widgets.SecureField = widgets.SecureField.of("")?
    var remember: widgets.Widget = remember_control()?
    var label: widgets.Label = widgets.Label.of("Remember me")?
    var status: widgets.Label = widgets.Label.of("")?
    var sign_in: widgets.Button = widgets.Button.of("Sign in")?
    var quit_button: widgets.Button = widgets.Button.of("Quit")?

    root.add(heading)?
    root.add(who)?
    root.add(secret)?
    root.add(remember)?
    root.add(label)?
    root.add(status)?
    root.add(sign_in)?
    root.add(quit_button)?

    // A switch has no title of its own — it is the control, and the words go
    // beside it. A check box carries its own, so the label beside it would be
    // the same words twice.
    if !widgets.WidgetKind.switch.available() { label.set_hidden(true)? }

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(10.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?

    page.add(sheet.leaf("heading", heading))
    page.add(sheet.leaf("who", who))
    page.add(sheet.leaf("secret", secret))

    var line: layout.StackLayout = layout.StackLayout.row(8.0)
    var row: layout.LayoutNode = sheet.spacer("remember", line)
    row.add(sheet.leaf("toggle", remember))
    row.add(sheet.leaf("label", label))
    page.add(row)

    page.add(sheet.leaf("status", status))

    var bar: layout.StackLayout = layout.StackLayout.row(10.0)
    bar.set_justify(layout.Justify.end)
    var buttons: layout.LayoutNode = sheet.spacer("buttons", bar)
    buttons.add(sheet.leaf("sign_in", sign_in))
    buttons.add(sheet.leaf("quit", quit_button))
    page.add(buttons)

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    io.println("remember me is a {remember.kind().name()} on this platform")

    app.router.on(sign_in.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            let name: string = who.value().or("")
            // The password is read here and nowhere else. `display_text` on a
            // secure field answers "" on purpose, so a control tree printed to
            // a log carries the field but not what was typed into it.
            let typed: string = secret.value().or("")
            if name.len() == 0 || typed.len() == 0 {
                status.set_text("Fill in both boxes")
                return
            }
            let kept: string = if is_remembering(remember) { ", and remembered" } else { "" }
            status.set_text("Signed in as {name}{kept}")
            io.println("signed in as {name} with {typed.len()} characters{kept}")
        })

    app.router.on(quit_button.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { app.stop() })

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
