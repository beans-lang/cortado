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
        // Zero at every size, or a run has children past its box.
        io.println("overflowing runs: {mount.overflows()}")
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
    // Nor is the frame rate, which is a number that has to be counted.
    if args.len() > 0 && args[0] == "--rate" {
        report_rate()
        return
    }
    // Three dumps, because the screen changes shape twice: 900 is five tiles
    // and the legend beside the title; 520 hides the legend and goes to two
    // tiles a line; 300 is one a line, the title at its floor, and a scroll.
    let narrow: bool = args.len() > 0 && args[0] == "--dump-narrow"
    let tight: bool = args.len() > 0 && args[0] == "--dump-tight"
    let dumping: bool = narrow || tight || (args.len() > 0 && args[0] == "--dump")
    var role: platform.AppRole = platform.AppRole.gui
    if dumping { role = platform.AppRole.headless }
    var wide: f64 = 900.0
    var tall: f64 = 640.0
    if narrow {
        wide = 520.0
        tall = 760.0
    }
    if tight {
        wide = 300.0
        tall = 700.0
    }
    // Any size, for checking a screen at the window somebody is looking at.
    if args.len() > 2 && args[0] == "--dump-at" {
        role = platform.AppRole.headless
        match open(role, true, args[1].to_float().or(900.0), args[2].to_float().or(640.0)) {
            ok(done) => {}
            err(problem) => { io.println("{problem.kind}: {problem.msg}") }
        }
        return
    }
    match open(role, dumping, wide, tall) {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
