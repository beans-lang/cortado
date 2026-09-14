// A group box with a segmented control in it — and two controls that are not
// on every platform.
//
//     beansc build examples/settings.b -o build/settings && ./build/settings
//
// `NSBox` and `GtkFrame` and `BS_GROUPBOX` are the frame and title a platform
// draws around controls that belong together; **UIKit has nothing that means
// it**, because on a phone the shape is a grouped table section. And
// `NSSegmentedControl` and `UISegmentedControl` are real controls that **GTK
// and the Win32 common controls have none of** — a row of linked toggle
// buttons looks like one and is not one, because nothing keeps exactly one of
// them down.
//
// So this screen asks first, twice, and arranges itself around the answer. Six
// lines each, and the program is right on four platforms instead of wrong on
// two.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

/// The frame, or the plain box a platform without one gets.
///
/// Returned as a `ChildHolder` because that is all the layout and the children
/// need — which of the two it is matters only here.
fn panel(title: string) -> Result<widgets.ChildHolder> {
    if widgets.WidgetKind.group_box.available() {
        return ok(widgets.GroupBox.of(title)?)
    }
    return ok(new widgets.Container())
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(360.0, 240.0, "Settings")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Coffee")?
    var box: widgets.ChildHolder = panel("Options")?
    var chosen: widgets.Label = widgets.Label.of("")?

    // The size picker, or a drop-down where there is no segmented control.
    // Both carry the same item list, so only the construction differs.
    var sizes: widgets.Widget = new widgets.ComboBox()
    if widgets.WidgetKind.segmented.available() {
        sizes = widgets.Segmented.of(["Small", "Regular", "Large"])?
    } else {
        sizes = widgets.ComboBox.of(["Small", "Regular", "Large"])?
    }
    var oat: widgets.CheckBox = widgets.CheckBox.of("Oat milk")?

    box.add(sizes)?
    box.add(oat)?
    root.add(heading)?
    root.add(box)?
    root.add(chosen)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?
    page.add(sheet.leaf("heading", heading))

    var inside: layout.StackLayout = layout.StackLayout.column(10.0)
    inside.set_padding(geometry.EdgeInsets.all(12.0))
    inside.set_align(geometry.Align.stretch)
    var frame: layout.LayoutNode = sheet.group("box", box, inside)?
    frame.spec = layout.LayoutSpec.fixed(320.0, 100.0)
    frame.add(sheet.leaf("sizes", sizes))
    frame.add(sheet.leaf("oat", oat))
    page.add(frame)
    page.add(sheet.leaf("chosen", chosen))

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    io.println("the panel is a {box.kind().name()}, the picker a {sizes.kind().name()}")

    app.router.on(sizes.handle(), events.EventKind.value_changed,
        fn(event: events.UiEvent) {
            chosen.set_text("{event.text} it is")
            io.println("chose {event.text}")
        })

    window.show()?
    app.run()
    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => { io.println("done={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
