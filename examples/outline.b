// A section you can fold away, and a group box you cannot.
//
//     beansc build examples/outline.b -o build/outline && ./build/outline
//
// Two containers that keep part of their own frame, side by side, because the
// difference between them is the point:
//
//   * a **group box** draws a border and a title band and always shows what is
//     inside it;
//   * a **disclosure** draws a header you press, and hides the body when it is
//     shut.
//
// Neither is on every platform. UIKit has no group box — on a phone the shape
// is a grouped table section, which is a different control — and the Win32
// common controls have no disclosure triangle. This example asks before it
// builds either, and prints why when the answer is no.
//
// **The layout is the interesting part.** A container that draws chrome has
// less room inside it than its frame says, and by how much is the platform's
// business: AppKit's title band is seventeen points, GTK's border is its
// stylesheet's, and Windows' is the dialog font's. cortado asks each host
// through `content_inset` when the layout tree is built, so nothing below
// writes a number down — take the `sheet.group` calls out and replace them
// with `sheet.spacer`, and the text inside both boxes lands on top of their
// titles.
//
// **A shut disclosure still takes up the room its children asked for**, unless
// the program stops describing them. That is why `fold` below removes the
// children rather than only shutting the header: a framework that silently
// re-solved the caller's layout would be doing something the caller did not
// ask for, and one that did not would leave a hole.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

/// What the screen is holding. A class, because the handlers capture it.
class Sheet {
    pub open: bool = true
    pub fn init() {}
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(400.0, 300.0, "Outline")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let sheet_state: Sheet = new Sheet()

    var heading: widgets.Label = widgets.Label.of("Preferences")?
    heading.set_font_size(17.0)?

    // ---------------------------------------------------------- the group box

    let have_box: bool = widgets.WidgetKind.group_box.available()
    var box: widgets.GroupBox = new widgets.GroupBox()
    var box_note: widgets.Label = widgets.Label.of("")?
    var beans: widgets.CheckBox = widgets.CheckBox.of("Grind fresh")?
    var water: widgets.CheckBox = widgets.CheckBox.of("Filtered water")?
    if have_box {
        box = widgets.GroupBox.of("Brewing")?
        box.add(beans)?
        box.add(water)?
        root.add(box)?
    } else {
        box_note.set_text("this platform has no group box")?
        root.add(box_note)?
    }

    // --------------------------------------------------------- the disclosure

    let have_fold: bool = widgets.WidgetKind.disclosure.available()
    var fold: widgets.Disclosure = new widgets.Disclosure()
    var fold_note: widgets.Label = widgets.Label.of("")?
    var detail: widgets.Label = widgets.Label.of("Pressure: 9 bar\nTemperature: 93 C")?
    if have_fold {
        fold = widgets.Disclosure.of("Advanced", true)?
        fold.add(detail)?
        root.add(fold)?
    } else {
        fold_note.set_text("this platform has no disclosure")?
        root.add(fold_note)?
    }

    root.add(heading)?

    // ------------------------------------------------------------ the layout
    //
    // Rebuilt on every twist rather than patched, because what changes when a
    // disclosure shuts is *which children exist*, and that is a different
    // tree rather than a different number in the same one.

    var solver: layout.Solver = new layout.Solver(new widgets.WidgetLayout())
    let content: geometry.Size = window.content_size()?

    // A closure cannot capture a field, so everything the re-solve needs is a
    // local — and `arrange` is called rather than inlined for the same reason:
    // one description of the page, used at start-up and after every twist.
    let arrange: fn() = fn() {
        var pages: widgets.WidgetLayout = new widgets.WidgetLayout()
        var body: layout.StackLayout = layout.StackLayout.column(12.0)
        body.set_padding(geometry.EdgeInsets.all(20.0))
        body.set_align(geometry.Align.stretch)
        var page: layout.LayoutNode = pages.group("page", root, body)
        page.add(pages.leaf("heading", heading))

        if have_box {
            var inside: layout.StackLayout = layout.StackLayout.column(8.0)
            inside.set_padding(geometry.EdgeInsets.all(8.0))
            inside.set_align(geometry.Align.stretch)
            // `group` and not `spacer`: a group asks the control how much of
            // its own frame it keeps, and a group box keeps its border and its
            // title band.
            var frame: layout.LayoutNode = pages.group("box", box, inside)
            frame.add(pages.leaf("beans", beans))
            frame.add(pages.leaf("water", water))
            page.add(frame)
        } else {
            page.add(pages.leaf("box_note", box_note))
        }

        if have_fold {
            var under: layout.StackLayout = layout.StackLayout.column(8.0)
            under.set_padding(geometry.EdgeInsets.all(8.0))
            under.set_align(geometry.Align.stretch)
            var section: layout.LayoutNode = pages.group("fold", fold, under)
            // Only while it is open. A shut disclosure that still described
            // its body would keep the body's height and show nothing in it.
            if sheet_state.open { section.add(pages.leaf("detail", detail)) }
            page.add(section)
        } else {
            page.add(pages.leaf("fold_note", fold_note))
        }

        var again: layout.Solver = new layout.Solver(pages)
        match again.solve(page, geometry.Rect.at(geometry.Point.zero(), content)) {
            ok(done) => {}
            err(problem) => { io.println("{problem.kind}: {problem.msg}") }
        }
        match pages.apply(page) {
            ok(done) => {}
            err(problem) => { io.println("{problem.kind}: {problem.msg}") }
        }
    }

    if have_fold {
        app.router.on(fold.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                sheet_state.open = event.index == 1
                arrange()
            })
    }

    arrange()

    io.println("a group box here: {have_box}; a disclosure here: {have_fold}")
    if have_fold {
        let kept: geometry.EdgeInsets = fold.content_inset()?
        io.println("its header takes {kept.top} points, and this platform chose that number")
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
