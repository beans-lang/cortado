// A component, mounted, driven and re-rendered — against real AppKit controls.
//
// The differ is checked exhaustively in `tests/diff.b`, which runs everywhere
// because it touches no platform. This is the other half: that a render really
// becomes native controls, that clicking one really reaches the closure the
// last render installed, and that a second render changes only what moved.
//
// Nothing appears on screen. The application runs headless, so controls are
// built, measured with the platform's real text metrics, and never shown.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.events
import cortado.geometry
import {view, param, inject} from cortado.annotations
import std.io
import std.reflect

// ---- a tiny service, and a source that answers for it ----

pub class Prices {
    pub fn init() {}
    pub fn of(what: string) -> int {
        if what == "flat white" { return 380 }
        return 300
    }
}

// Stands in for a real container. `cortado_app` has the barista-backed one;
// this keeps the gate free of a dependency on another package.
class OnePrice implements component.ServiceSource {
    held: Prices

    pub fn init() {
        self.held = new Prices()
    }

    pub fn provide(described: reflect.Type) -> Result<reflect.Value, string> {
        if described.qualified_name() == type_of(Prices).qualified_name() {
            return ok(reflect.value(self.held))
        }
        return err("nothing registered for {described.qualified_name()}")
    }

    pub fn knows(described: reflect.Type) -> bool {
        return described.qualified_name() == type_of(Prices).qualified_name()
    }
}

// ---- the components ----

@view
pub class Total extends component.Component {
    @param pub drink: string = ""
    @inject pub prices: Prices = new Prices()
    renders: int = 0

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        self.renders = self.renders + 1
        into.open("Label")
        into.text("{self.prices.of(self.drink)}p")
        into.close()
    }

    // Nothing about this component changes unless its parameter does, so a
    // parent re-rendering for its own reasons must not re-run this.
    pub override fn should_render() -> bool {
        return false
    }
}

@view
pub class OrderScreen extends component.Component {
    @param pub title: string = "Order a coffee"
    drink: string = "flat white"
    clicks: int = 0
    cancels: int = 0
    extra: bool = false
    total: Total = new Total()

    pub fn init() { super.init() }

    pub override fn on_init() {
        self.total.drink = self.drink
    }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.number("spacing", 8.0)
        into.number("padding", 16.0)
        into.word("align", "stretch")
            into.open("Label")
            into.text(self.title)
            into.close()

            into.child("total", self.total)

            into.open("CheckBox")
            into.text("Extra shot")
            into.flag("checked", self.extra)
            into.close()

            into.open("HStack")
            into.number("spacing", 8.0)
            into.word("justify", "end")
                into.open("Button")
                into.key("buy")
                into.text("Buy")
                into.flag("enabled", self.clicks < 2)
                into.on("click", fn(event: events.UiEvent) { self.buy() })
                into.close()

                into.open("Button")
                into.key("cancel")
                into.text("Cancel")
                into.on("click", fn(event: events.UiEvent) { self.cancel() })
                into.close()
            into.close()
        into.close()
    }

    fn buy() {
        self.clicks = self.clicks + 1
        self.extra = true
        self.request_render()
    }

    fn cancel() {
        self.cancels = self.cancels + 1
        self.request_render()
    }
}

// ---- the run ----

fn dump(root: widgets.Container) -> Result<bool> {
    io.print(widgets.WidgetDump.of(root)?)
    return ok(true)
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(320.0, 220.0, "Cortado")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.use_services(new OnePrice())
    mount.set_bounds(window.content_size()?)

    var screen: OrderScreen = new OrderScreen()
    mount.show(screen)?

    io.println("== first render ==")
    dump(root)?
    io.println("renders so far: {mount.render_count()}")
    io.println("the injected service answered: {screen.total.renders > 0}")

    // Nothing asked for a render, so nothing should happen at all.
    io.println("== nothing changed ==")
    let again: bool = mount.refresh_if_needed()?
    io.println("refresh_if_needed did anything: {again}")

    // A real click, through the platform's own target/action dispatch, into
    // the closure the last render installed.
    io.println("== after a click ==")
    let button: widgets.Widget = find(root, widgets.WidgetKind.button)?
    button.activate()?
    io.println("the click reached the component: {screen.clicks == 1}")
    io.println("it asked for a render: {mount.is_dirty()}")
    mount.refresh_if_needed()?
    dump(root)?
    io.println("renders so far: {mount.render_count()}")
    io.println("the checkbox followed the component: {is_checked(root)}")
    // The child said `should_render` is false and its parameter did not move,
    // so its render must not have run again.
    io.println("the memoised child rendered once: {screen.total.renders == 1}")

    io.println("== after a second click ==")
    button.activate()?
    mount.refresh_if_needed()?
    io.println("the button disabled itself: {is_disabled(button)}")
    io.println("a disabled button ignores a click: {ignores(button, screen)}")

    // Two controls of the same kind, side by side, each with its own closure.
    // A framework that keyed handlers by anything but the individual control
    // routes both to whichever was registered last, and every screenshot still
    // looks right. This is the check that catches it.
    io.println("== two buttons, two handlers ==")
    let buy: widgets.Widget = nth_button(root, 0)?
    let cancel: widgets.Widget = nth_button(root, 1)?
    io.println("they are different controls: {buy.handle().raw != cancel.handle().raw}")
    let clicks_before: int = screen.clicks
    let cancels_before: int = screen.cancels
    cancel.activate()?
    mount.refresh_if_needed()?
    io.println("cancel ran cancel: {screen.cancels == cancels_before + 1}")
    io.println("cancel did not run buy: {screen.clicks == clicks_before}")

    io.println("== closed ==")
    mount.close()?
    io.println("the container is empty: {root.count() == 0}")
    io.println("the router holds nothing: {app.router.registered() == 0}")

    app.shutdown()
    return ok(true)
}

fn find(box: widgets.Container, wanted: widgets.WidgetKind) -> Result<widgets.Widget> {
    for child: widgets.Widget in box.children() {
        if child.kind() == wanted {
            return ok(child)
        }
        match child as? widgets.Container {
            some(inner) => {
                match find(inner, wanted) {
                    ok(found) => { return ok(found) }
                    err(missing) => {}
                }
            }
            none => {}
        }
    }
    return err("no {wanted.name()} in this tree", "not_found")
}

// The n-th button in the tree, in the order the tree holds them.
fn nth_button(box: widgets.Container, wanted: int) -> Result<widgets.Widget> {
    var found: List<widgets.Widget> = []
    collect(box, widgets.WidgetKind.button, inout found)
    if wanted >= found.len() {
        return err("this tree has {found.len()} buttons, not {wanted + 1}", "not_found")
    }
    return ok(found[wanted])
}

fn collect(box: widgets.Container, wanted: widgets.WidgetKind,
           inout found: List<widgets.Widget>) {
    for child: widgets.Widget in box.children() {
        if child.kind() == wanted {
            found.push(child)
        }
        match child as? widgets.Container {
            some(inner) => { collect(inner, wanted, inout found) }
            none => {}
        }
    }
}

fn is_checked(root: widgets.Container) -> bool {
    match find(root, widgets.WidgetKind.check_box) {
        err(missing) => { return false }
        ok(control) => {
            match control as? widgets.CheckBox {
                none => { return false }
                some(box) => {
                    match box.state() {
                        ok(state) => { return state == widgets.CheckState.on }
                        err(problem) => { return false }
                    }
                }
            }
        }
    }
}

fn is_disabled(button: widgets.Widget) -> bool {
    match button.is_enabled() {
        ok(on) => { return !on }
        err(problem) => { return false }
    }
}

fn ignores(button: widgets.Widget, screen: OrderScreen) -> bool {
    let before: int = screen.clicks
    match button.activate() {
        ok(done) => {}
        err(problem) => {}
    }
    return screen.clicks == before
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
