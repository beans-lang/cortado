// A real window, described by components and wired with dependency injection.
//
//     beansc build examples/counter/main.b -o build/counter && ./build/counter
//
// Nothing here positions a control and nothing here creates one. Each
// component says what it should look like; cortado works out the difference
// from the last render, changes only that, and lays the result out. The one
// service is registered with barista and reaches the component that needs it
// without any ancestor passing it down.
package main

import barista
import cortado_app
import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.events
import {view, param, inject} from cortado.annotations
import std.io

// ---- a service ----

/// What a drink costs. Registered once, injected where it is needed.
@barista.service(lifetime: barista.ServiceLifetime.singleton)
pub class Menu {
    pub fn init() {}

    pub fn price(drink: string) -> int {
        if drink == "flat white" { return 380 }
        if drink == "espresso" { return 260 }
        return 300
    }

    pub fn next(drink: string) -> string {
        if drink == "flat white" { return "espresso" }
        if drink == "espresso" { return "cortado" }
        return "flat white"
    }
}

// ---- components ----

/// Shows what the current order costs.
///
/// It takes the drink as a parameter and the price list by injection — no
/// ancestor passes the menu down. `should_render` says no unless the drink
/// actually moved, so the parent re-rendering for its own reasons does not
/// re-run this.
@view
pub class Price extends component.Component {
    @param pub drink: string = ""
    @inject pub menu: Menu = new Menu()
    last: string = ""

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        self.last = self.drink
        into.open("Label")
        into.number("font_size", 22.0)
        into.text("{self.menu.price(self.drink)}p")
        into.close()
    }

    pub override fn should_render() -> bool {
        return self.last != self.drink
    }
}

/// The whole window.
@view
pub class Counter extends component.Component {
    @param pub heading: string = "Order a coffee"
    @inject pub menu: Menu = new Menu()
    drink: string = "flat white"
    shots: int = 1
    price: Price = new Price()

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        self.price.drink = self.drink

        into.open("VStack")
        into.number("spacing", 14.0)
        into.number("padding", 24.0)
        into.word("align", "stretch")

            into.open("Label")
            into.number("font_size", 17.0)
            into.text(self.heading)
            into.close()

            into.open("Label")
            into.text("{self.shots} × {self.drink}")
            into.close()

            into.child("price", self.price)

            into.open("HStack")
            into.number("spacing", 10.0)
            into.word("justify", "end")

                into.open("Button")
                into.key("another")
                into.text("Another shot")
                into.flag("enabled", self.shots < 4)
                into.on("click", fn(event: events.UiEvent) { self.add_shot() })
                into.close()

                into.open("Button")
                into.key("change")
                into.text("Change drink")
                into.on("click", fn(event: events.UiEvent) { self.change_drink() })
                into.close()

            into.close()
        into.close()
    }

    fn add_shot() {
        self.shots = self.shots + 1
        self.request_render()
    }

    fn change_drink() {
        self.drink = self.menu.next(self.drink)
        self.shots = 1
        self.request_render()
    }
}

// ---- composition root ----

fn run() -> Result<bool> {
    // Every `@barista.service` class in this executable, found by a scan
    // rather than listed by hand — a list is a second place to keep in step.
    var services: barista.ServiceCollection = new barista.ServiceCollection()
    match barista.add_services(services) {
        ok(found) => { io.println("registered {found} service(s)") }
        err(problem) => { return err(problem.msg, "registration") }
    }
    let provider: barista.ServiceProvider = services.build_provider()

    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(380.0, 260.0, "Counter")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.use_services(new cortado_app.Container(provider))
    mount.set_bounds(window.content_size()?)
    mount.show(new Counter())?

    // Every event handler runs before this returns, so re-rendering after each
    // one is what keeps the window in step with the components. A handler that
    // changed nothing costs a render and no platform call at all, because the
    // differ answers an empty list.
    app.router.after(fn() {
        match mount.refresh_if_needed() {
            ok(done) => {}
            err(problem) => { io.println("render failed: {problem.msg}") }
        }
    })

    window.show()?
    app.run()
    mount.close()?
    app.shutdown()
    provider.close().expect("close the container")
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
