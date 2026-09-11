// Drives real controls and watches the events come back into Beans.
//
// Nothing here simulates an event. `activate()` sends the control's action
// through the platform's own target/action dispatch — the same path a mouse
// click takes — so what this proves is the whole round trip: a native control
// fires, the host's one callback runs, Beans decodes the record, the router
// finds the handler, and the handler's captured state changes.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import std.io

// Handlers capture this rather than the widget they are attached to. A
// handler that captured its own button would be a cycle the collector cannot
// see through, because the platform's stored callback holds a strong
// reference the tracer never walks.
class Tally {
    pub clicks: int = 0
    pub log: List<string> = []

    pub fn init() {}
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    var window: surface.Window = app.window(320.0, 200.0, "Events")?

    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var order: widgets.Button = widgets.Button.of("Order")?
    root.add(order)?

    var extra: widgets.CheckBox = widgets.CheckBox.of("Extra shot")?
    root.add(extra)?

    let tally: Tally = new Tally()

    app.router.on(order.handle(), events.EventKind.activate, fn(event: events.UiEvent) {
        tally.clicks = tally.clicks + 1
        tally.log.push("order {event.kind.name()} #{tally.clicks}")
    })
    app.router.on(extra.handle(), events.EventKind.activate, fn(event: events.UiEvent) {
        tally.log.push("extra toggled")
    })

    io.println("registered={app.router.registered()}")

    order.activate()?
    order.activate()?
    extra.activate()?

    for line: string in tally.log {
        io.println(line)
    }
    io.println("clicks={tally.clicks}")

    // A handler is registered against a full handle, generation included, so
    // dropping one widget's handlers leaves the others alone.
    app.router.forget(order.handle())
    order.activate()?
    io.println("after forgetting order: clicks={tally.clicks} registered={app.router.registered()}")

    // And nothing is left holding a widget alive once the tree goes.
    app.router.forget(extra.handle())
    io.println("registered at teardown={app.router.registered()}")

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
