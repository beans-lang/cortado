// An animated mesh gradient with a screen of real controls over it.
//
//     build/cortado-bx build examples/gradients/site
//     beansc build examples/gradients/main.b -o build/gradients && ./build/gradients
//
// The screen is `site/Petrichor.bx`. This file opens a window, tells the screen
// how big it is, and mounts it.
package main

import cortado_app
import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import std.io
import std.os
import {Petrichor} from gradients.generated.site

fn open(role: platform.AppRole, dumping: bool) -> Result<bool> {
    var app: surface.Application = new surface.Application(role)
    app.check_abi()?

    var window: surface.Window = app.window(900.0, 640.0, "Petrichor")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var mount: component.Mount = new component.Mount(root, app.router)
    let area: geometry.Size = window.content_size()?
    mount.set_bounds(area)

    // The screen places its controls by coordinate, so it has to be told the
    // size rather than measured into it.
    var screen: Petrichor = new Petrichor()
    screen.wide = area.width
    screen.tall = area.height
    mount.show(screen)?

    if dumping {
        io.print(widgets.WidgetDump.of(root)?)
        mount.close()?
        app.shutdown()
        return ok(true)
    }

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
    return ok(true)
}

fn main() {
    let args: List<string> = os.args()
    // What the toast's buttons do is not in a tree dump. `dismiss.b` is it.
    if args.len() > 0 && args[0] == "--dismiss" {
        report_dismiss()
        return
    }
    let dumping: bool = args.len() > 0 && args[0] == "--dump"
    var role: platform.AppRole = platform.AppRole.gui
    if dumping { role = platform.AppRole.headless }
    match open(role, dumping) {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
