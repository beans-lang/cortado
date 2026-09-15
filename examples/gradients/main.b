// An animated mesh gradient with a screen of real controls over it.
//
//     build/cortado-bx build examples/gradients/site
//     beansc build examples/gradients/main.b -o build/gradients && ./build/gradients
//
// The screen is `site/Petrichor.bx`. This file opens a window and mounts it;
// the screen lays itself out at whatever size the window turns out to be.
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

fn open(role: platform.AppRole, dumping: bool, wide: f64, tall: f64) -> Result<bool> {
    var app: surface.Application = new surface.Application(role)
    app.check_abi()?

    var window: surface.Window = app.window(wide, tall, "Petrichor")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(window.content_size()?)

    // Nothing is passed in. The screen reads `viewport()` for the two things
    // it decides by size, and the mount tells it that before every render.
    var screen: Petrichor = new Petrichor()
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
    // A second dump, at a window too narrow for the chips beside the title.
    // The layout is the screen's own now, so the only way to check it holds at
    // another size is to mount it at one.
    let narrow: bool = args.len() > 0 && args[0] == "--dump-narrow"
    let dumping: bool = narrow || (args.len() > 0 && args[0] == "--dump")
    var role: platform.AppRole = platform.AppRole.gui
    if dumping { role = platform.AppRole.headless }
    var wide: f64 = 900.0
    var tall: f64 = 640.0
    if narrow {
        wide = 520.0
        tall = 760.0
    }
    match open(role, dumping, wide, tall) {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
