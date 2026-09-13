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
import cortado.layout
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

/// A screen whose one container carries a title, so a render can change what
/// the platform keeps for that container's own chrome.
@view
pub class Titled extends component.Component {
    pub caption: string = "Order"

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("GroupBox")
        into.text(self.caption)
            into.open("Label")
            into.text("inside")
            into.close()
        into.close()
    }

    pub fn retitle(words: string) {
        self.caption = words
        self.request_render()
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

            into.show("total", self.total)

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

/// What an application's own resize handler saw.
class Resizes {
    pub count: int = 0
    pub wide: f64 = 0.0
    /// How wide the tree was *while the handler ran*, which is the thing that
    /// says the framework's watch had already laid it out.
    pub laid_out: f64 = 0.0
    pub fn init() {}
}

/// How wide the tree under `root` is — the single child the mount put there.
fn widest(root: widgets.Container) -> f64 {
    match root.child_at(0) {
        none => { return 0.0 }
        some(child) => {
            match child.frame() {
                ok(box) => { return box.width }
                err(problem) => { return 0.0 }
            }
        }
    }
}

fn dump(root: widgets.Container) -> Result<bool> {
    io.print(widgets.WidgetDump.of(root)?)
    return ok(true)
}

/// A sheet asks a container about its chrome once, and again after it is told
/// the answer may have changed.
///
/// A group box's border is the same on every pass and a disclosure's header is
/// the same until its title moves, so the *answer* cannot show whether the
/// question was asked. The count can, and it is the only thing that can: a
/// cache that never forgot would print the same frames for ever and be wrong
/// the first time a title grew a line.
fn sheet_forgets() -> Result<bool> {
    var box: widgets.GroupBox = widgets.GroupBox.of("Order")?
    var frame: layout.StackLayout = layout.StackLayout.column(4.0)
    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()

    sheet.group("box", box, frame)
    io.println("  a container new to the sheet is asked: {sheet.chrome_asked() == 1}")

    sheet.reset()
    sheet.group("box", box, frame)
    io.println("  and not asked again on the next pass: {sheet.chrome_asked() == 0}")

    sheet.forget(box.handle().raw)
    sheet.reset()
    sheet.group("box", box, frame)
    io.println("  until something writes to it: {sheet.chrome_asked() == 1}")

    // The chrome a group box really keeps, so a forgotten answer is a
    // re-asked one and not a zero.
    let kept: geometry.EdgeInsets = box.content_inset()?
    io.println("  and the answer is the platform's, not a zero: {kept.top > 0.0}")
    box.release()
    return ok(true)
}

/// A render that retitles a container makes the sheet ask about its chrome
/// again.
///
/// The other half of `sheet_forgets`: that one proves the sheet forgets when
/// told, this one proves it is told. Without it the two could both be right
/// and the cache still never invalidate — a group box retitled from "Order" to
/// a title that wraps would keep laying its contents out for the old, shorter
/// border for the life of the program.
fn retitling_forgets() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    var window: surface.Window = app.window(200.0, 160.0, "titled")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)
    var screen: Titled = new Titled()
    mount.show(screen)?

    mount.refresh()?
    io.println("  a settled screen asks about no chrome: {mount.chrome_asked() == 0}")

    screen.retitle("Order a very large coffee indeed")
    mount.refresh_if_needed()?
    io.println("  a retitled container is asked again: {mount.chrome_asked() > 0}")

    mount.refresh()?
    io.println("  and then settles again: {mount.chrome_asked() == 0}")
    mount.close()?
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

    // **A layout pass that changes nothing must cost nothing.**
    //
    // It used to cost everything: the sheet was rebuilt from scratch on every
    // pass, so every container was asked for its chrome again and every
    // control had its frame written again — eighty platform calls to put a
    // tree back exactly where it already was. The frames were right either
    // way, which is why nothing caught it.
    io.println("== a pass that changes nothing ==")
    mount.refresh()?
    let touched: int = mount.frames_written()
    let left: int = mount.frames_kept()
    io.println("it wrote no frames: {touched == 0}")
    io.println("and left every control alone: {left > 0}")
    io.println("and asked no container about its chrome: {mount.chrome_asked() == 0}")

    // What the sheet remembers has to stop being remembered the moment it
    // stops being true.
    io.println("== what the sheet forgets ==")
    sheet_forgets()?
    retitling_forgets()?

    // And a pass that *does* change something still writes. The point is not
    // that the sheet stopped writing; it is that it writes what moved.
    io.println("== a pass that changes something ==")
    mount.set_bounds(geometry.Size.of(360.0, 220.0))
    mount.refresh()?
    io.println("it wrote the controls that moved: {mount.frames_written() > 0}")
    mount.set_bounds(window.content_size()?)
    mount.refresh()?

    // **A window the user drags has to reach the layout.**
    //
    // Nothing in this repository used to wire one to the other, so every
    // cortado program stayed laid out for the size its window opened at: the
    // window grew and not one control moved. The mount follows its own surface
    // now, and this is the case that says so — a real resize down the
    // platform's own road, and frames afterwards that are not the frames
    // before.
    io.println("== the window resized ==")
    io.println("the mount follows its surface: {mount.following().raw == window.handle().raw}")
    let before_resize: string = widgets.WidgetDump.of(root)?
    let renders_before: int = mount.render_count()
    var heard: Resizes = new Resizes()
    // An application handler for the very same event, to prove the two do not
    // displace each other. `on` replaces, and the framework's watch lives in
    // its own table for exactly this reason.
    app.router.on(window.handle(), events.EventKind.surface_resized,
        fn(event: events.UiEvent) {
            heard.count = heard.count + 1
            heard.wide = event.size.width
            // Read *inside* the handler, after the watch has run: the rule is
            // that a program looking at a control during a resize sees where
            // it is now, not where it was before the window changed.
            heard.laid_out = widest(root)
        })
    window.resize_as_user(geometry.Size.of(420.0, 300.0))?
    // A turn of the loop, because one host reports the size a turn later and
    // has to — see the note in tests/surface.b.
    app.run_for(0.05)?
    io.println("the application's own handler still ran: {heard.count == 1}")
    io.println("and it was told the new width: {heard.wide == 420.0}")
    dump(root)?
    io.println("the tree moved: {widgets.WidgetDump.of(root)? != before_resize}")
    io.println("it filled the new width: {widest(root) == 420.0}")
    io.println("the watch ran before the handler: {heard.laid_out == 420.0}")
    // A resize changes the room, not the state, so it lays out again and does
    // not render again. A framework that answered a drag with a full render
    // would run every component on every frame of one.
    io.println("no render was needed for it: {mount.render_count() == renders_before}")
    // A size it is already at is not a layout pass. AppKit sends a resize
    // notification for a window put back where it was, and GTK sends one per
    // dimension, so this is the guard that keeps a drag from solving twice for
    // every step of it.
    io.println("the same size again does nothing: {mount.resized(geometry.Size.of(420.0, 300.0))? == false}")
    app.router.off(window.handle(), events.EventKind.surface_resized)

    io.println("== closed ==")
    mount.close()?
    io.println("the container is empty: {root.count() == 0}")
    io.println("the router holds nothing: {app.router.registered() == 0}")
    io.println("and watches nothing: {app.router.watching() == 0}")

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
