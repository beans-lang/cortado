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

    var choice: widgets.ComboBox = widgets.ComboBox.of(["flat white", "espresso"])?
    root.add(choice)?

    let tally: Tally = new Tally()

    app.router.on(order.handle(), events.EventKind.activate, fn(event: events.UiEvent) {
        tally.clicks = tally.clicks + 1
        tally.log.push("order {event.kind.name()} #{tally.clicks}")
    })
    // A check box reports `value_changed`, not `activate`: it carries a
    // value, and a button is a command. Both handlers are registered so the
    // golden records which one fires — a framework that reported every action
    // as "activate" would make a check box and a button indistinguishable to a
    // handler, and every application would work the difference out again from
    // the control's class.
    app.router.on(extra.handle(), events.EventKind.activate, fn(event: events.UiEvent) {
        tally.log.push("extra activate (a check box should not raise this)")
    })
    app.router.on(extra.handle(), events.EventKind.value_changed, fn(event: events.UiEvent) {
        tally.log.push("extra value_changed state={event.index}")
    })

    // A list control reports the same kind as a check box and carries which
    // row was picked. It is here because it is the only control whose event
    // reaches Beans through a *property notification* rather than through an
    // action — GTK4 has no "changed" signal on a drop-down — and a property
    // notification hands a callback a different set of arguments. Nothing else
    // in the suite went down that path, so nothing else could have noticed
    // that the host was reading one of them as the widget's handle.
    app.router.on(choice.handle(), events.EventKind.value_changed, fn(event: events.UiEvent) {
        tally.log.push("choice value_changed index={event.index} text=\"{event.text}\"")
    })

    io.println("registered={app.router.registered()}")

    order.activate()?
    order.activate()?
    extra.set_value_as_user(1, 0.0)?
    choice.set_value_as_user(1, 0.0)?

    // **A program's own write is silent.** The header is explicit about it —
    // `ctd_set_int` changes a control without raising anything, because a
    // render that heard about its own writes would feed itself for as long as
    // the program ran.
    //
    // It is checked here rather than trusted because the four hosts reach it
    // by four different mechanisms, and three of them raise something by
    // default: GTK emits on every property change whoever made it, Win32's
    // controls notify their parent, and UIKit's value-changed fires from
    // -setOn:animated: in some versions. AppKit is the one that is naturally
    // quiet. A divergence here is invisible in every other case in this suite,
    // because no other case both registers a handler and then writes.
    extra.set_state(widgets.CheckState.off)?
    choice.select(0)?

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
    app.router.forget(choice.handle())
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
