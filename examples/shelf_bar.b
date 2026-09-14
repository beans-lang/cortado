// A toolbar and a popover: the two things that hang off a window.
//
//     beansc build examples/shelf_bar.b -o build/shelf_bar && ./build/shelf_bar
//
// **A toolbar is a menu.** The same handle, the same tokens, the same
// `set_enabled` — so "Pour" in the menu bar and "Pour" on the toolbar are one
// command, and this program has one command table rather than two lists that
// can drift apart. Disabling it below disables it in both places with one
// call, which is the whole reason the ABI takes a menu rather than a list of
// titles.
//
// Where the row goes is the platform's business and differs: AppKit puts an
// NSToolbar in the title bar, GTK a header bar in place of one, Windows a real
// strip inside the frame. The last one takes room off the window and says so
// through `content_size`, so nothing below has to know.
//
// **A popover is its own window.** That is what lets it draw outside the one
// that spawned it. It holds an ordinary widget subtree and the caller lays
// that subtree out, because no platform here will size one to fit a tree the
// host cannot see. Windows has no popover at all and UIKit's becomes a
// full-screen sheet on a phone, so this asks first.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import cortado.host
import std.io

const GRIND: int = 11
const POUR: int = 12
const STOP: int = 13

/// What the program is doing. A class, because the handlers capture it.
class Brewing {
    pub running: bool = false
    pub fn init() {}
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(420.0, 260.0, "Shelf")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let state: Brewing = new Brewing()

    // One command table. It becomes the menu bar where there is one and the
    // toolbar where there is one, and on a platform with neither it is still
    // the thing `invoke` fires from a button.
    var commands: surface.Menu = surface.Menu.of("Brew")?
    commands.add("Grind", "mod+g", surface.CommandRole.none, GRIND)?
    commands.add("Pour", "mod+p", surface.CommandRole.none, POUR)?
    commands.separator()?
    commands.add("Stop", "", surface.CommandRole.none, STOP)?

    let have_bar: bool = platform.Capability.toolbar.available()
    if have_bar { window.set_toolbar(commands)? }

    var what: widgets.Label = widgets.Label.of("Idle")?
    what.set_font_size(15.0)?
    var options: widgets.Button = widgets.Button.of("Options")?
    var note: widgets.Label = widgets.Label.of("")?
    root.add(what)?
    root.add(options)?
    root.add(note)?

    // ------------------------------------------------------------- the popover

    let have_pop: bool = platform.Capability.popover.available()
    var inside: widgets.Container = new widgets.Container()
    var strength: widgets.Label = widgets.Label.of("Strength")?
    var bars: widgets.Slider = widgets.Slider.of(1.0, 5.0, 3.0)?
    inside.add(strength)?
    inside.add(bars)?

    // The popover's content is laid out here, once, into the size the popover
    // was made at. A popover has no layout of its own on any platform.
    var inner: widgets.WidgetLayout = new widgets.WidgetLayout()
    var stack: layout.StackLayout = layout.StackLayout.column(8.0)
    stack.set_padding(geometry.EdgeInsets.all(12.0))
    stack.set_align(geometry.Align.stretch)
    var panel: layout.LayoutNode = inner.group("panel", inside, stack)?
    panel.add(inner.leaf("strength", strength))
    panel.add(inner.leaf("bars", bars))
    var inner_solver: layout.Solver = new layout.Solver(inner)
    inner_solver.solve(panel, geometry.Rect.of(0.0, 0.0, 220.0, 90.0))?
    inner.apply(panel)?

    // ------------------------------------------------------------- the page

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?
    page.add(sheet.leaf("what", what))
    var pressable: layout.LayoutNode = sheet.leaf("options", options)
    pressable.spec = layout.LayoutSpec.fixed(110.0, 24.0)
    page.add(pressable)
    page.add(sheet.leaf("note", note))

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    // ------------------------------------------------------------ the wiring

    // One handler for every command, from the menu bar or the toolbar. The
    // token is the application's own number and cortado never looks at it.
    // A command event carries no target — it belongs to the application, not
    // to a control — so it is subscribed against no handle.
    app.router.on(host.Handle.none(), events.EventKind.command,
        fn(event: events.UiEvent) {
            if event.token == GRIND { what.set_text("Grinding") }
            if event.token == POUR {
                state.running = true
                what.set_text("Pouring")
                // One call, both places: the toolbar item and the menu item
                // are the same command.
                commands.set_enabled(POUR, false)
                commands.set_enabled(STOP, true)
            }
            if event.token == STOP {
                state.running = false
                what.set_text("Idle")
                commands.set_enabled(POUR, true)
            }
        })

    if have_pop {
        app.router.on(options.handle(), events.EventKind.activate,
            fn(event: events.UiEvent) {
                match surface.Popover.of(inside, 220.0, 90.0) {
                    err(problem) => { note.set_text("{problem.kind}: {problem.msg}") }
                    ok(shown) => {
                        match shown.show(options, surface.Edge.below) {
                            ok(up) => { note.set_text("") }
                            err(problem) => { note.set_text("{problem.kind}: {problem.msg}") }
                        }
                    }
                }
            })
    } else {
        note.set_text("this platform has no popover; the options would go in a sheet")?
        root.add(inside)?
    }

    io.println("a toolbar here: {have_bar}; a popover here: {have_pop}")
    if have_bar { io.println("the toolbar shows {window.toolbar_count()?} items") }

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
