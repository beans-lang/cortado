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

/// The first control of a kind, anywhere under `box`.
///
/// Through `children()` rather than by downcasting to `Container`, which is
/// what this did and why it stopped working the moment the gallery's controls
/// moved inside disclosures: a disclosure, a group box, a scroll view and a
/// tab view all hold children and none of them is a `Container`. Every widget
/// answers `children()`, and a leaf answers with none.
fn find(box: widgets.Widget, wanted: widgets.WidgetKind) -> Option<widgets.Widget> {
    for child: widgets.Widget in box.children() {
        if child.kind() == wanted { return some(child) }
        match find(child, wanted) {
            some(found) => { return some(found) }
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
fn fill_drinks(root: widgets.Widget) -> Result<bool> {
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

/// The data the markup could not carry.
///
/// Three controls here are whole systems rather than controls, and each needs
/// something a tag cannot hold: a tab view's labels belong to its pages by
/// index, a split view's divider is a coordinate, and a page's HTML is a
/// document. All three are *data*, which is the same reason the combo box's
/// drinks are set here — markup describes structure.
///
/// Every one is guarded, because every one is missing on at least one
/// platform. Nothing is refused loudly: a gallery that could not run on GTK
/// because Windows has no splitter would be the wrong shape entirely.
/// Three drinks and what they cost, for the table to be asked about.
///
/// A table is filled by *asking* rather than by building: cortado hands the
/// platform a source and the platform asks for the cells it is about to paint.
/// That is why a hundred thousand rows cost what a thousand do, and why the
/// rows are a class here rather than markup.
class Prices implements widgets.TableRows {
    pub fn init() {}

    pub fn row_count() -> int { return 3 }

    pub fn cell(row: int, column: int) -> string {
        let names: List<string> = ["flat white", "espresso", "cortado"]
        let costs: List<string> = ["3.80", "2.60", "3.00"]
        if row < 0 || row >= 3 { return "" }
        if column == 0 { return names[row] }
        return costs[row]
    }
}

fn fill_systems(root: widgets.Widget) -> Result<bool> {
    match find(root, widgets.WidgetKind.table) {
        none => {}
        some(control) => {
            match control as? widgets.Table {
                none => {}
                some(rows) => {
                    rows.set_columns(2)?
                    rows.set_column_title(0, "Drink")?
                    rows.set_column_title(1, "Price")?
                    rows.set_column_width(0, 200.0)?
                    rows.set_column_width(1, 80.0)?
                    rows.set_source(new Prices())?
                }
            }
        }
    }
    match find(root, widgets.WidgetKind.tab_view) {
        none => {}
        some(control) => {
            match control as? widgets.TabView {
                none => {}
                some(tabs) => {
                    if tabs.count() == 2 {
                        tabs.set_label(0, "General")?
                        tabs.set_label(1, "Advanced")?
                    }
                }
            }
        }
    }
    match find(root, widgets.WidgetKind.split_view) {
        none => {}
        some(control) => {
            match control as? widgets.SplitView {
                none => {}
                some(split) => {
                    // Half of whatever the layout gave it, read back rather
                    // than written down: the divider is bounded by the
                    // control's own width, and a constant would be out of
                    // range on a narrow window and in the wrong place on a
                    // wide one.
                    let across: f64 = split.frame()?.width
                    split.set_divider(across / 2.0)?
                }
            }
        }
    }
    match find(root, widgets.WidgetKind.web_view) {
        none => {}
        some(control) => {
            match control as? widgets.WebView {
                none => {}
                some(page) => {
                    // Markup handed straight to the engine: no server, no
                    // network, and nothing for a gallery to depend on.
                    page.load_html(r"<meta charset='utf-8'><title>cortado</title>
<body style='font: 13px -apple-system, system-ui, sans-serif; margin: .6rem'>
<b>A real browser engine</b>, inside a native window, inside a disclosure.
", "")?
                }
            }
        }
    }
    return ok(true)
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
    fill_systems(root)?

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
