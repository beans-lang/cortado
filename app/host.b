// host.b — the nine steps every cortado application used to write by hand.
//
// `examples/counter/main.b` opens with forty-five lines that are the same
// forty-five lines in every application: scan for services, build a provider,
// make an `Application`, check the ABI, open a window, give it a root
// container, build a `Mount`, point it at the container, set its bounds, show
// the root component, install the after-handler render, run, and then take all
// of it down in the reverse order. None of that is the application.
//
// It lives here for the reason `latte_app` exists: **a package under a module
// may not import its own module root**, so `cortado.component` cannot name
// anything that assembles an application and `cortado.surface` cannot name a
// container. A sibling module may name both, and this is cortado's.
//
//     fn main() {
//         var options: cortado_app.AppOptions = new cortado_app.AppOptions()
//         cortado_app.run_main<Home>(options)
//     }
//
// **The window comes from `@window` on the root component.** Not from an
// options field, because then there would be two places that say how big a
// screen is and a person would have to know which one wins. The annotation was
// already declared for this — "so a tool can read an application's windows
// without running it" — and until now nothing read it.
//
// **Every application gets `--dump`.** Mounted headless, the widget tree
// printed, exit. A program's gate can then assert what its screens actually
// built, on a machine with no display, from its first commit — which is the
// difference between a project that is tested and one that is looked at.

package cortado_app

import barista
import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import cortado.events
import std.io
import std.os
import std.reflect

/// What `@window` said, or what it would have said.
pub class WindowSpec {
    pub title: string = ""
    pub width: f64 = 640.0
    pub height: f64 = 480.0

    pub fn init() {}
}

/// Everything about starting an application that the root component cannot say.
pub class AppOptions {
    /// `gui` for a program, `headless` for a gate. `--dump` overrides it.
    pub role: platform.AppRole = platform.AppRole.gui
    /// Registrations a scan cannot find — a factory, a closed generic, an
    /// instance built before the container. Runs after `barista.add_services`,
    /// so it can also replace what the scan found.
    pub configure: fn(barista.ServiceCollection) -> Result<bool> =
        fn(services: barista.ServiceCollection) -> Result<bool> { return ok(true) }
    /// Called once the screen is mounted and its controls exist.
    ///
    /// This is not a convenience. Some things can only be done after the first
    /// layout: a split view refuses a divider wider than itself, so a divider
    /// written inside `on_mount` — where the control exists with no frame at
    /// all — is refused as `out_of_range` by every host, and the same number
    /// is fine one pass later. `examples/cask` is where that was found.
    pub on_ready: fn() -> Result<bool> = fn() -> Result<bool> { return ok(true) }
    /// Called after the application loop, before the platform is taken down.
    /// Closing a database, flushing a file — the things a program owns and
    /// cortado does not.
    pub on_closing: fn() -> Result<bool> = fn() -> Result<bool> { return ok(true) }

    pub fn init() {}
}

/// Read `@window` off a component type.
///
/// A type with no `@window` gets the annotation's own defaults and its own
/// name as the title, which is a window you can see rather than a refusal
/// about a declaration somebody has not written yet.
pub fn window_for(described: reflect.Type) -> Result<WindowSpec> {
    var spec: WindowSpec = new WindowSpec()
    spec.title = described.name()
    for annotation: reflect.Annotation in described.annotations() {
        if annotation.qualified_name() != "cortado.annotations.window" { continue }
        match annotation.argument("title") {
            some(argument) => {
                let written: string = argument.value().text()
                if written != "" { spec.title = written }
            }
            none => {}
        }
        match annotation.argument("width") {
            some(argument) => { spec.width = argument.value().text().to_float()? }
            none => {}
        }
        match annotation.argument("height") {
            some(argument) => { spec.height = argument.value().text().to_float()? }
            none => {}
        }
        // `resizable` is declared and cortado cannot honour it: there is no
        // entry in `src/cortado_host.h` that fixes a window's size, on any of
        // the four hosts. A window that ignored the word would be the silent
        // no-op this library refuses everywhere else, so it is named instead.
        // Removing this refusal means adding `ctd_set_window_resizable` to the
        // header and to every host, which is a port-shaped change and not this
        // one.
        match annotation.argument("resizable") {
            some(argument) => {
                match argument.value().as_bool() {
                    some(wanted) => {
                        if !wanted {
                            return err(
                                "@window(resizable: false) on {described.name()}: cortado cannot fix a window's size — no host implements it",
                                "unsupported")
                        }
                    }
                    none => {}
                }
            }
            none => {}
        }
    }
    return ok(spec)
}

/// The container every application is assembled through.
fn assemble(options: AppOptions) -> Result<Container> {
    var services: barista.ServiceCollection = new barista.ServiceCollection()
    barista.add_services(services)?
    let hook: fn(barista.ServiceCollection) -> Result<bool> = options.configure
    hook(services)?
    return ok(new Container(services.build_provider()))
}

/// A root screen, as both the thing to mount and the thing to call methods on.
///
/// Two shapes of the one object. `Mount.show` wants a `Component`; a
/// `@command` is invoked through `reflect.Method.call`, which wants the
/// receiver as a `reflect.Value`. Taking the `Value` before the downcast is
/// what keeps both without building the screen twice.
class Root {
    pub screen: component.Component
    pub boxed: reflect.Value

    pub fn init(screen: component.Component, boxed: reflect.Value) {
        self.screen = screen
        self.boxed = boxed
    }
}

/// Build the root component through the container, so a screen may take its
/// dependencies in its initializer like anything else the container makes.
fn root_component<T>(container: Container) -> Result<Root> {
    match container.build(type_of(T)) {
        ok(boxed) => {
            let receiver: reflect.Value = boxed.copy()
            match boxed as? component.Component {
                some(built) => { return ok(new Root(built, receiver)) }
                none => {
                    return err(
                        "{type_of(T).qualified_name()} is not a cortado component — a root screen extends component.Component",
                        "root")
                }
            }
        }
        err(why) => { return err(why, "root") }
    }
}

/// Build the command table and put it where the platform shows one.
///
/// **Before the mount is given its bounds**, and that order is the whole of
/// this function's contract: a toolbar changes what `content_size()` answers,
/// so a tree laid out against the size read before it is a tree laid out for a
/// window that no longer exists. Adding the toolbar afterwards moved a tab
/// page by ten points and thirty-three, which is how this was found.
///
/// Routing is separate and comes after the screen exists — see
/// `route_commands` — because a handler needs something to call.
fn install_commands(described: reflect.Type, window: surface.Window, title: string) -> Result<List<DeclaredCommand>> {
    let declared: List<DeclaredCommand> = declared_commands(described)?
    if declared.is_empty() { return ok(move declared) }
    let menu: surface.Menu = build_menu(title, declared)?
    // A platform with no toolbar still gets the menu bar, which is where the
    // host puts a command table when there is nowhere else for it.
    if platform.Capability.toolbar.available() {
        window.set_toolbar(menu)?
    }
    return ok(move declared)
}

/// Open a window on `T` and run until the application is closed.
pub fn run<T>(options: AppOptions) -> Result<bool> {
    let spec: WindowSpec = window_for(type_of(T))?
    let container: Container = assemble(options)?

    var app: surface.Application = new surface.Application(options.role)
    app.check_abi()?

    var window: surface.Window = app.window(spec.width, spec.height, spec.title)?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let declared: List<DeclaredCommand> =
        install_commands(type_of(T), window, spec.title)?

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.use_services(container)
    mount.use_activator(container)
    mount.set_bounds(window.content_size()?)
    let root_screen: Root = root_component<T>(container)?
    mount.show(root_screen.screen)?
    route_commands(app.router, root_screen.boxed, declared)

    // The controls exist now, so anything that needed them can happen — and
    // then one more pass, because whatever it did is a change the tree has not
    // been laid out for.
    let ready: fn() -> Result<bool> = options.on_ready
    ready()?
    mount.refresh()?

    // Every event handler runs before this returns, so re-rendering after each
    // one is what keeps the window in step with the components. A handler that
    // changed nothing costs a render and no platform call at all, because the
    // differ answers an empty list.
    app.router.after(fn() {
        match mount.refresh_if_needed() {
            ok(done) => {}
            err(problem) => { io.eprintln("render failed: {problem.msg}") }
        }
    })

    window.show()?
    app.run()
    let closing: fn() -> Result<bool> = options.on_closing
    closing()?
    mount.close()?
    app.shutdown()
    container.provider_ref().close()?
    return ok(true)
}

/// Mount `T` with no display and print the widget tree the platform made.
pub fn dump<T>(options: AppOptions) -> Result<bool> {
    let spec: WindowSpec = window_for(type_of(T))?
    let container: Container = assemble(options)?

    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(spec.width, spec.height, spec.title)?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let declared: List<DeclaredCommand> =
        install_commands(type_of(T), window, spec.title)?

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.use_services(container)
    mount.use_activator(container)
    mount.set_bounds(window.content_size()?)
    let root_screen: Root = root_component<T>(container)?
    mount.show(root_screen.screen)?
    route_commands(app.router, root_screen.boxed, declared)
    if !declared.is_empty() { io.println("{declared.len()} command(s)") }
    let ready: fn() -> Result<bool> = options.on_ready
    ready()?
    mount.refresh()?
    io.print(widgets.WidgetDump.of(root)?)

    let closing: fn() -> Result<bool> = options.on_closing
    closing()?
    mount.close()?
    app.shutdown()
    container.provider_ref().close()?
    return ok(true)
}

/// The whole of an application's `main`.
///
/// `--dump` is answered here rather than being left to every program to wire
/// up, so that "what did this screen actually build" is one word on a command
/// line in every cortado application rather than a thing each one reinvents.
pub fn run_main<T>(options: AppOptions) {
    let arguments: List<string> = os.args()
    var headless: bool = false
    for one: string in arguments {
        if one == "--dump" { headless = true }
    }
    let outcome: Result<bool> =
        if headless { dump<T>(options) } else { run<T>(options) }
    match outcome {
        ok(done) => {}
        err(problem) => {
            io.eprintln("{problem.kind}: {problem.msg}")
            os.exit(1)
        }
    }
}
