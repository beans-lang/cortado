// An about box, and a link that opens in the user's own browser.
//
//     beansc build examples/about.b -o build/about && ./build/about
//
// The link is the point. `GtkLinkButton` and `SysLink` are real controls;
// AppKit and UIKit have none, so the Mac uses an `NSTextField` holding an
// attributed string with a link attribute — which is what gives the blue
// underline, the pointing-hand cursor and the click that opens the URL through
// the user's own browser and the user's own handler registrations. None of
// that follows from drawing blue underlined text.
//
// **It opens, and raises nothing.** The four platforms disagree about who
// follows a link and none lets a program intercept the click, so cortado does
// not promise an event it could raise on only some of them. A screen that
// needs to handle the click itself wants a `Button` — which is a different
// control and says so.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(340.0, 200.0, "About")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var name: widgets.Label = widgets.Label.of("cortado")?
    name.set_font_size(20.0)?
    var line: widgets.Label = widgets.Label.of("Native desktop UI for Beans")?
    var manual: widgets.Link = widgets.Link.of("Read the manual",
                                               "https://github.com/beans-lang/cortado")?
    var close: widgets.Button = widgets.Button.of("Close")?

    root.add(name)?
    root.add(line)?
    root.add(manual)?
    root.add(close)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(10.0)
    body.set_padding(geometry.EdgeInsets.all(24.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?
    page.add(sheet.leaf("name", name))
    page.add(sheet.leaf("line", line))
    page.add(sheet.leaf("manual", manual))

    var bar: layout.StackLayout = layout.StackLayout.row(10.0)
    bar.set_justify(layout.Justify.end)
    var buttons: layout.LayoutNode = sheet.spacer("buttons", bar)
    buttons.add(sheet.leaf("close", close))
    page.add(buttons)

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    io.println("the link goes to {manual.url().or("nowhere")}")

    app.router.on(close.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { app.stop() })

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
