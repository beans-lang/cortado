// A stepper and a gauge: two controls that carry a number.
//
//     beansc build examples/brew.b -o build/brew && ./build/brew
//
// The stepper is the platform's own — `NSStepper`, `UIStepper`, a
// `GtkSpinButton`, an up-down control — and it is one of the two controls a
// user *nudges* rather than aims at. Every press raises `value_changed`, and
// the handler reads the control rather than keeping a count of its own,
// because the platform owns the value and a second copy in Beans is a second
// thing that can be wrong.
//
// The gauge is `NSLevelIndicator` or `GtkLevelBar`, and **there is no such
// control on iOS or Windows**. A `UIProgressView` is not one: a progress bar
// is work with a beginning and an end, and a level is a reading that goes up
// and down and never finishes. cortado will not substitute one, so this
// program does — visibly, in four lines, because which of the two is right for
// a given screen is the application's call and not the toolkit's.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

const MOST: f64 = 8.0

/// The gauge, or the nearest thing this platform has.
fn strength_control() -> Result<widgets.Widget> {
    if widgets.WidgetKind.level_indicator.available() {
        return ok(widgets.LevelIndicator.of(0.0, MOST, 2.0)?)
    }
    var bar: widgets.ProgressBar = widgets.ProgressBar.of(0.0, MOST)?
    bar.set_value(2.0)?
    return ok(bar)
}

/// Moving it, whichever it is. One place knows which control it got.
fn show_strength(control: widgets.Widget, level: f64) -> Result<bool> {
    match control as? widgets.LevelIndicator {
        some(gauge) => { return gauge.set_level(level) }
        none => {}
    }
    match control as? widgets.ProgressBar {
        some(bar) => { return bar.set_value(level) }
        none => {}
    }
    return err("nothing here shows a level", "no_such_control")
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(340.0, 200.0, "Brew")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("How strong?")?
    var count: widgets.Label = widgets.Label.of("2 shots")?
    // Whole shots, one at a time, and never past the ends: a stepper refuses a
    // step of zero, so there is no way to build one whose arrows do nothing.
    var shots: widgets.Stepper = widgets.Stepper.of(1.0, MOST, 1.0, 2.0)?
    var strength: widgets.Widget = strength_control()?

    root.add(heading)?
    root.add(count)?
    root.add(shots)?
    root.add(strength)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)
    page.add(sheet.leaf("heading", heading))

    var line: layout.StackLayout = layout.StackLayout.row(12.0)
    var row: layout.LayoutNode = sheet.spacer("row", line)
    row.add(sheet.leaf("count", count))
    row.add(sheet.leaf("shots", shots))
    page.add(row)
    page.add(sheet.leaf("strength", strength))

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    io.println("strength is shown by a {strength.kind().name()} on this platform")

    app.router.on(shots.handle(), events.EventKind.value_changed,
        fn(event: events.UiEvent) {
            // Read the control, do not count the presses. The platform clamps
            // at the ends of the range, so a count of its own would run past
            // them and then disagree with what is on screen.
            let now: f64 = shots.value().or(1.0)
            count.set_text("{now as int} shots")
            show_strength(strength, now)
            io.println("{now as int} shots")
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
