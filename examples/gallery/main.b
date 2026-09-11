// Every control cortado has, in one window.
//
//     build/cortado-bx build examples/gallery/site/shelf.bx
//     beansc build examples/gallery/main.b -o build/gallery && ./build/gallery
//
// The screen is `site/shelf.bx`. This file opens a window, fills the combo box
// — items are data rather than markup — and mounts the screen.
package main

import cortado_app
import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import std.io
import std.os
import {Shelf} from gallery.generated.site

fn find(box: widgets.Container, wanted: widgets.WidgetKind) -> Option<widgets.Widget> {
    for child: widgets.Widget in box.children() {
        if child.kind() == wanted { return some(child) }
        match child as? widgets.Container {
            some(inner) => {
                match find(inner, wanted) {
                    some(found) => { return some(found) }
                    none => {}
                }
            }
            none => {}
        }
    }
    return none
}

/// Puts the drinks into the combo box.
///
/// Markup describes structure; a list of choices is data, and cortado's item
/// API replaces a control's items wholesale rather than diffing them. So this
/// runs after the mount, against the control the markup built.
fn fill_drinks(root: widgets.Container) -> Result<bool> {
    match find(root, widgets.WidgetKind.combo_box) {
        none => { return err("the markup built no combo box", "not_found") }
        some(control) => {
            match control as? widgets.ComboBox {
                none => { return err("that is not a combo box", "wrong_widget") }
                some(menu) => {
                    menu.set_items(["flat white", "espresso", "cortado"])?
                    return menu.select(0)
                }
            }
        }
    }
}

fn open(role: platform.AppRole, dumping: bool) -> Result<bool> {
    var app: surface.Application = new surface.Application(role)
    app.check_abi()?

    var window: surface.Window = app.window(460.0, 460.0, "Gallery")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var mount: component.Mount = new component.Mount(root, app.router)
    // The surface's own size, not a constant. A desktop window is whatever was
    // asked for; a phone's is the screen, and asking is the only thing that is
    // right on both.
    mount.set_bounds(window.content_size()?)
    mount.show(new Shelf())?
    fill_drinks(root)?

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
    let dumping: bool = args.len() > 0 && args[0] == "--dump"
    var role: platform.AppRole = platform.AppRole.gui
    if dumping { role = platform.AppRole.headless }
    match open(role, dumping) {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
