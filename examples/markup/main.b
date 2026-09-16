// A window whose screen is written in markup.
//
//     beansc build examples/cortado_bx.b -o build/cortado-bx
//     build/cortado-bx build examples/markup/site/*.bx
//     beansc build examples/markup/main.b -o build/markup && ./build/markup
//
// `site/checkout.bx` and `site/price.bx` are the whole user interface. This
// file registers one service, opens a window, and mounts the screen — there is
// no widget construction here and no layout code.
//
// The generated halves live under `generated/`, mirroring `site/`, so the
// package they declare is the one their folder gives them and the import path
// picks up one segment: `markup.generated.site`. Nothing has to be renamed as
// markup is added or moved.
package main

import github.com/beans-lang/barista
import cortado_app
import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import std.io
import std.os
import {Checkout, Menu} from markup.generated.site

/// Mount the markup headless, print what the platform made of it, and exit.
///
/// The gate runs this. A screenshot proves a window appeared; this proves the
/// generated `render` produced the controls the markup describes, with the
/// right text in them, on a machine with no display — so the markup pipeline
/// is checked on every run rather than by eye once.
fn dump() -> Result<bool> {
    var services: barista.ServiceCollection = new barista.ServiceCollection()
    services.singleton<Menu>().expect("register the menu")
    let provider: barista.ServiceProvider = services.build_provider()
    let container: cortado_app.Container = new cortado_app.Container(provider)

    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(380.0, 300.0, "Markup")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.use_services(container)
    mount.use_activator(container)
    mount.set_bounds(geometry.Size.of(380.0, 300.0))
    var screen: Checkout = new Checkout()
    mount.show(screen)?
    io.print(widgets.WidgetDump.of(root)?)

    // The `$if` in the markup is not taken at one shot and is at three, so the
    // tree grows a row — which the differ has to work out for itself, because
    // markup has no way to say "this element may not be there".
    screen.shots = 3
    screen.request_render()
    mount.refresh_if_needed()?
    io.println("-- after three shots --")
    io.print(widgets.WidgetDump.of(root)?)

    // And the nested component's parameter, moved. `Badge` lives in
    // `site/parts/`, so it is in a package one level deeper than the screen —
    // the only thing that costs is the import line in checkout.bx's <beans>
    // block. Moving `rush` proves the whole path: the parameter crosses a
    // package boundary, the component re-renders, and the label changes.
    screen.rush = true
    screen.request_render()
    mount.refresh_if_needed()?
    io.println("-- after rushing it --")
    io.print(widgets.WidgetDump.of(root)?)

    mount.close()?
    app.shutdown()
    provider.close().expect("close the container")
    return ok(true)
}

fn run() -> Result<bool> {
    var services: barista.ServiceCollection = new barista.ServiceCollection()
    services.singleton<Menu>().expect("register the menu")
    let provider: barista.ServiceProvider = services.build_provider()
    let container: cortado_app.Container = new cortado_app.Container(provider)

    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(380.0, 300.0, "Markup")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.use_services(container)
    // `<Price />` names a type, not an object, so the mount builds one — and
    // through the container, so a component with constructor dependencies
    // would work from markup too.
    mount.use_activator(container)
    mount.set_bounds(window.content_size()?)
    mount.show(new Checkout())?

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
    let args: List<string> = os.args()
    if args.len() > 0 && args[0] == "--dump" {
        match dump() {
            ok(done) => {}
            err(problem) => { io.println("{problem.kind}: {problem.msg}") }
        }
        return
    }
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
