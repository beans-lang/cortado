// A real window, with real controls.
//
//     beansc build examples/hello.b -o build/hello && ./build/hello
//
// Everything here is a native control. The text field takes input methods,
// dictation and the system editing shortcuts because it is the platform's own
// field, not a drawing of one.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
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

    var window: surface.Window = app.window(420.0, 230.0, "Cortado")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Order a coffee")?
    heading.set_frame(geometry.Rect.of(24.0, 24.0, 300.0, 22.0))?
    root.add(heading)?

    var drink: widgets.TextField = widgets.TextField.of("flat white")?
    drink.set_frame(geometry.Rect.of(24.0, 60.0, 240.0, 24.0))?
    root.add(drink)?

    var extra: widgets.CheckBox = widgets.CheckBox.of("Extra shot")?
    extra.set_frame(geometry.Rect.of(24.0, 100.0, 240.0, 22.0))?
    root.add(extra)?

    var status: widgets.Label = widgets.Label.of("Nothing ordered yet")?
    status.set_frame(geometry.Rect.of(24.0, 136.0, 340.0, 22.0))?
    root.add(status)?

    var order_button: widgets.Button = widgets.Button.of("Order")?
    order_button.set_frame(geometry.Rect.of(24.0, 176.0, 110.0, 32.0))?
    root.add(order_button)?

    var quit_button: widgets.Button = widgets.Button.of("Quit")?
    quit_button.set_frame(geometry.Rect.of(148.0, 176.0, 110.0, 32.0))?
    root.add(quit_button)?

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
