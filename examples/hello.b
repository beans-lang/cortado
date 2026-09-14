// A real window, with real controls, positioned by cortado's layout engine.
//
//     beansc build examples/hello.b -o build/hello && ./build/hello
//
// Two things are worth noticing. Every control is a native one, so the text
// field takes input methods, dictation and the system editing shortcuts
// because it is the platform's own field and not a drawing of one. And not a
// single coordinate appears below: the column, the row and the spacing
// describe the design, and the solver turns that into frames.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

// `Order` is a builtin interface name, so the tally needs one of its own.
class Tally {
    pub shots: int = 1
    pub fn init() {}
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(420.0, 240.0, "Cortado")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Order a coffee")?
    var drink: widgets.TextField = widgets.TextField.of("flat white")?
    var extra: widgets.CheckBox = widgets.CheckBox.of("Extra shot")?
    var status: widgets.Label = widgets.Label.of("Nothing ordered yet")?
    var order_button: widgets.Button = widgets.Button.of("Order")?
    var quit_button: widgets.Button = widgets.Button.of("Quit")?

    root.add(heading)?
    root.add(drink)?
    root.add(extra)?
    root.add(status)?
    root.add(order_button)?
    root.add(quit_button)?

    // ---- the design, described rather than measured ----

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()

    var body: layout.StackLayout = layout.StackLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(24.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?

    page.add(sheet.leaf("heading", heading))
    page.add(sheet.leaf("drink", drink))
    page.add(sheet.leaf("extra", extra))
    page.add(sheet.leaf("status", status))

    // The buttons sit in a row of their own, pushed to the trailing edge. The
    // row is a layout-only node: it costs no native view, and in a
    // right-to-left locale the solver moves it to the other side with no
    // change here.
    var bar: layout.StackLayout = layout.StackLayout.row(12.0)
    bar.set_justify(layout.Justify.end)
    var buttons: layout.LayoutNode = sheet.spacer("buttons", bar)
    buttons.add(sheet.leaf("order", order_button))
    buttons.add(sheet.leaf("quit", quit_button))
    page.add(buttons)

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    let placed: int = sheet.apply(page)?
    io.println("laid out {placed} controls in {content.show()}")

    // ---- behaviour ----

    let counter: Tally = new Tally()

    app.router.on(order_button.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            let what: string = drink.value().or("a coffee")
            let shots: string = match extra.state() {
                ok(state) => if state == widgets.CheckState.on { " with an extra shot" } else { "" },
                err(problem) => "",
            }
            counter.shots = counter.shots + 1
            status.set_text("Ordered {what}{shots} — {counter.shots} so far")
            io.println("ordered {what}{shots}")
        })

    app.router.on(quit_button.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            io.println("closing")
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
