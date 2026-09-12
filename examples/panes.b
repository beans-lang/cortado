// Two panes and a handle to move between them.
//
//     beansc build examples/panes.b -o build/panes && ./build/panes
//
// A split view is the one control in cortado whose children the **platform**
// positions. `NSSplitView` and `GtkPaned` both lay their panes out from the
// divider's position, and neither can be talked out of it — so cortado's hosts
// do not write a pane's frame at all. What `layout.SplitLayout` does is
// compute the *same* two boxes, so that everything inside a pane is solved
// against the size the pane is actually going to have.
//
// `split.split_layout()` builds that arranger with the control's own two
// numbers already in it: where the handle is, and how thick it is. Reading
// either from anywhere else is how a pane ends up laid out against a size it
// does not have.
//
// **Not on every platform.** The Win32 common controls have no splitter —
// every Windows application draws its own, which is what cortado will not do —
// and UIKit's split view is a view controller that owns the screen. Where
// there is none, this example stacks the two panes and says so.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

/// Where the handle is. A class, because the handler captures it.
class Held {
    pub where: f64 = 160.0
    pub fn init() {}
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(480.0, 320.0, "Panes")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let held: Held = new Held()

    // The two panes, built the same way whether a split view holds them or a
    // plain column does.
    var list: widgets.Container = new widgets.Container()
    var heading: widgets.Label = widgets.Label.of("Beans")?
    var beans: widgets.Table = new widgets.Table()
    list.add(heading)?

    var detail: widgets.Container = new widgets.Container()
    var name: widgets.Label = widgets.Label.of("Ethiopia Yirgacheffe")?
    name.set_font_size(15.0)?
    var notes: widgets.TextArea = widgets.TextArea.of("Floral, citrus, tea-like.")?
    detail.add(name)?
    detail.add(notes)?

    let have_split: bool = widgets.WidgetKind.split_view.available()
    var split: widgets.SplitView = new widgets.SplitView()
    if have_split {
        split = widgets.SplitView.of(false)?
        split.add(list)?
        split.add(detail)?
        root.add(split)?
    } else {
        root.add(list)?
        root.add(detail)?
    }

    var where: widgets.Label = widgets.Label.of("")?
    root.add(where)?

    // ------------------------------------------------------------ the layout
    //
    // Rebuilt after every drag, because the divider's position is an input to
    // the arranger — and the arranger is what tells everything inside each
    // pane how much room it has.

    let content: geometry.Size = window.content_size()?

    let arrange: fn() = fn() {
        var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
        var body: layout.FlexLayout = layout.FlexLayout.column(10.0)
        body.set_padding(geometry.EdgeInsets.all(16.0))
        body.set_align(geometry.Align.stretch)
        var page: layout.LayoutNode = sheet.group("page", root, body)

        var left: layout.StackLayout = layout.StackLayout.column(8.0)
        left.set_align(geometry.Align.stretch)
        var one: layout.LayoutNode = sheet.group("list", list, left)
        one.add(sheet.leaf("heading", heading))

        var right: layout.StackLayout = layout.StackLayout.column(8.0)
        right.set_align(geometry.Align.stretch)
        var two: layout.LayoutNode = sheet.group("detail", detail, right)
        two.add(sheet.leaf("name", name))
        var body_notes: layout.LayoutNode = sheet.leaf("notes", notes)
        body_notes.spec = layout.LayoutSpec.tall(120.0)
        two.add(body_notes)

        if have_split {
            match split.split_layout() {
                err(problem) => { io.println("{problem.kind}: {problem.msg}") }
                ok(divided) => {
                    divided.set_padding(geometry.EdgeInsets.all(8.0))
                    var pair: layout.LayoutNode = sheet.group("split", split, divided)
                    pair.spec = layout.LayoutSpec.flexible(1.0)
                    pair.add(one)
                    pair.add(two)
                    page.add(pair)
                }
            }
        } else {
            one.spec = layout.LayoutSpec.flexible(1.0)
            two.spec = layout.LayoutSpec.flexible(1.0)
            page.add(one)
            page.add(two)
        }
        page.add(sheet.leaf("where", where))

        var solver: layout.Solver = new layout.Solver(sheet)
        match solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content)) {
            ok(done) => {}
            err(problem) => { io.println("{problem.kind}: {problem.msg}") }
        }
        match sheet.apply(page) {
            ok(done) => {}
            err(problem) => { io.println("{problem.kind}: {problem.msg}") }
        }
    }

    if have_split {
        split.set_frame(geometry.Rect.of(0.0, 0.0, content.width, content.height))?
        split.set_divider(held.where)?
        app.router.on(split.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                held.where = event.index as f64
                where.set_text("the handle is at {held.where}")
                arrange()
            })
        where.set_text("the handle is at {held.where}")
    } else {
        where.set_text("no split view on this platform; the panes are stacked")?
    }

    arrange()

    io.println("a split view here: {have_split}")
    if have_split {
        io.println("its handle is {split.handle_size()?} points thick, and this platform chose that")
    }

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
