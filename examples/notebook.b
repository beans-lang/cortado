// One page at a time.
//
//     beansc build examples/notebook.b -o build/notebook && ./build/notebook
//
// A tab view, and what makes it different from every other container in
// cortado: **its children are its pages**. Adding a child adds a tab; the
// labels are set by index, because a page is a container and containers have
// no text on any platform cortado targets.
//
// The pages are ordinary containers, laid out by the same solver as anything
// else — which is the point of modelling pages as children rather than as a
// list the tab view keeps privately. A screen reader walks the same tree the
// program built.
//
// **Not on every platform.** UIKit has no tab *view*: `UITabBarController` is
// a view controller that owns the whole screen rather than a control that goes
// in a layout. On a phone the right shape is a segmented control with a
// container under it, and this example builds exactly that when there is no
// tab view — by hand, out of two controls the caller already has, which is the
// substitution cortado will not make on your behalf.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

/// Which page is showing. A class, because the handlers capture it.
class Chosen {
    pub page: int = 0
    pub fn init() {}
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(420.0, 300.0, "Notebook")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let showing: Chosen = new Chosen()

    // The two pages, built the same way whether a tab view holds them or a
    // hand-rolled substitute does.
    var general: widgets.Container = new widgets.Container()
    var grind: widgets.CheckBox = widgets.CheckBox.of("Grind fresh")?
    var milk: widgets.CheckBox = widgets.CheckBox.of("Oat milk")?
    general.add(grind)?
    general.add(milk)?

    var advanced: widgets.Container = new widgets.Container()
    var pressure: widgets.Label = widgets.Label.of("Pressure")?
    var bars: widgets.Slider = widgets.Slider.of(6.0, 12.0, 9.0)?
    advanced.add(pressure)?
    advanced.add(bars)?

    let have_tabs: bool = widgets.WidgetKind.tab_view.available()
    var tabs: widgets.TabView = new widgets.TabView()
    var picker: widgets.Segmented = new widgets.Segmented()
    var picker_note: widgets.Label = widgets.Label.of("")?

    if have_tabs {
        tabs = widgets.TabView.of()?
        tabs.add_page(general, "General")?
        tabs.add_page(advanced, "Advanced")?
        root.add(tabs)?
    } else {
        // The substitute, built by hand and on purpose. cortado will not hand
        // one back from `TabView.of` — see the note at the top of this file —
        // but a program that knows it wants this shape can say so.
        if widgets.WidgetKind.segmented.available() {
            picker = widgets.Segmented.of(["General", "Advanced"])?
            picker.select(0)?
            root.add(picker)?
        } else {
            picker_note.set_text("no tab view and no segmented control here")?
            root.add(picker_note)?
        }
        root.add(general)?
        root.add(advanced)?
        advanced.set_hidden(true)?
    }

    var where: widgets.Label = widgets.Label.of("General")?
    root.add(where)?

    // ------------------------------------------------------------ the layout

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.FlexLayout = layout.FlexLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?

    var inside: layout.StackLayout = layout.StackLayout.column(10.0)
    inside.set_padding(geometry.EdgeInsets.all(12.0))
    inside.set_align(geometry.Align.stretch)
    var one: layout.LayoutNode = sheet.group("general", general, inside)?
    one.add(sheet.leaf("grind", grind))
    one.add(sheet.leaf("milk", milk))

    var other: layout.StackLayout = layout.StackLayout.column(10.0)
    other.set_padding(geometry.EdgeInsets.all(12.0))
    other.set_align(geometry.Align.stretch)
    var two: layout.LayoutNode = sheet.group("advanced", advanced, other)?
    two.add(sheet.leaf("pressure", pressure))
    two.add(sheet.leaf("bars", bars))

    if have_tabs {
        // `group` and not `spacer`, so the tab strip's height comes off the
        // room the pages get — and the number is AppKit's, GTK's or Windows',
        // never one written here.
        var stack: layout.AbsoluteLayout = new layout.AbsoluteLayout()
        var book: layout.LayoutNode = sheet.group("tabs", tabs, stack)?
        book.spec = layout.LayoutSpec.flexible(1.0)
        // Both pages are laid out at the full size of the content area. The
        // platform shows one; which one is not the layout's business.
        one.spec = layout.LayoutSpec.at(0.0, 0.0)
        two.spec = layout.LayoutSpec.at(0.0, 0.0)
        book.add(one)
        book.add(two)
        page.add(book)
    } else {
        if widgets.WidgetKind.segmented.available() {
            page.add(sheet.leaf("picker", picker))
        } else {
            page.add(sheet.leaf("picker_note", picker_note))
        }
        one.spec = layout.LayoutSpec.flexible(1.0)
        two.spec = layout.LayoutSpec.flexible(1.0)
        page.add(one)
        page.add(two)
    }
    page.add(sheet.leaf("where", where))

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    // ------------------------------------------------------------ the wiring

    if have_tabs {
        app.router.on(tabs.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                showing.page = event.index
                where.set_text(if event.index == 0 { "General" } else { "Advanced" })
            })
    } else {
        app.router.on(picker.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                showing.page = event.index
                general.set_hidden(event.index != 0)
                advanced.set_hidden(event.index != 1)
                where.set_text(if event.index == 0 { "General" } else { "Advanced" })
            })
    }

    io.println("a tab view here: {have_tabs}")
    if have_tabs {
        let strip: geometry.EdgeInsets = tabs.content_inset()?
        io.println("its strip takes {strip.top} points off the top, and this platform chose that")
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
