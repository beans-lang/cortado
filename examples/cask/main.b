// cask — a database browser, shaped like the one everybody already knows.
//
//     beansc build examples/cortado_bx.b -o build/cortado-bx
//     build/cortado-bx build examples/cask/site/browser.bx
//     beansc build examples/cask/main.b -o build/cask && ./build/cask
//     ./build/cask some.db          # or point it at a file
//
// **The layout is DBeaver's**, because that shape is what a person who
// browses databases already has in their hands: a navigator tree down the
// left, an editor with tabs on the right, the SQL editor split so the
// statement is above its results, and a status bar that says what you are
// connected to. Nothing here is a new idea, and that is the point.
//
// **The screen is `site/browser.bx`, and this file no longer draws anything.**
// It used to: four hundred and fifty lines of it were controls built one at a
// time and an `arrange` closure that wrote out the layout tree node by node,
// rebuilt from scratch on every divider drag. All of that is markup now, and
// what is left here is the three things markup is not for — opening a
// database, describing the commands, and putting a window on the screen.
//
// **Nothing above `cask.engine` knows what SQLite is.** A database is a
// `Connection`; a kind of database is a `Driver`; the window asks a registry
// to open whatever it was given. Adding PostgreSQL means writing two classes
// and one line in `main`, and the navigator, the editor, the report and this
// file do not change. That is the whole reason for the shape.
//
// This is also the example that exists to be *used* rather than read. Written
// against cortado it found four bugs in it — a toolbar whose items all carried
// the first command's words, tab pages drawn on top of the tab strip, a split
// view that reported its own layout back as a value the user changed, and a
// layout spec whose obvious spelling silently meant "zero wide" — and
// converting it to markup found a fifth: `component.Stage` could name the
// control a key built and could not hand it over, so a screen written in
// markup could not point a table at its rows. See README.md.
package main

import barista
import cortado_app
import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import cortado.events
import cortado.host
import std.io
import std.os
import {Connection, DbObject, Grid, Registry} from cask.engine
import {SqliteDriver} from cask.sqlite_driver
import {Navigator, Session} from cask.ui
import {Browser} from cask.generated.site

const REFRESH: int = 21
const EXECUTE: int = 22
const RENDER: int = 23
const ABOUT: int = 24

fn run(target: string, showing: bool) -> Result<bool> {
    // ------------------------------------------------------ the drivers

    var drivers: Registry = new Registry()
    drivers.add(new SqliteDriver())
    let link: Connection = drivers.open(target)?
    let tree: Navigator = new Navigator(link)
    let work: Session = new Session(link, tree)

    // The screen asks for its session by type, so it is registered rather
    // than passed: a screen that took its database as a parameter could not
    // be shown by anything that did not already have one.
    var services: barista.ServiceCollection = new barista.ServiceCollection()
    // A factory that hands back the one already made, rather than a type
    // barista constructs: the session holds an open database, and a container
    // that built its own would open a second one.
    barista.add_singleton_factory(services,
        fn(from: barista.ServiceProvider) -> Result<Session> { return ok(work) })
        .expect("register the session")
    let provider: barista.ServiceProvider = services.build_provider()
    let container: cortado_app.Container = new cortado_app.Container(provider)

    // ------------------------------------------------------- the window

    var app: surface.Application = new surface.Application(
        if showing { platform.AppRole.gui } else { platform.AppRole.headless })
    app.check_abi()?

    var window: surface.Window = app.window(1000.0, 660.0, "cask")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    // One command table, which becomes the toolbar where there is one and the
    // menu bar where there is one. Two lists would drift.
    //
    // Still here rather than in the markup, and for the same reason the tab
    // labels are: a command is not a control. It has a role the platform
    // places by, a shortcut the platform spells, and an icon the platform may
    // not have — none of which is a shape on a screen.
    var commands: surface.Menu = surface.Menu.of("cask")?
    commands.add("Refresh", "mod+r", surface.CommandRole.none, REFRESH)?
    commands.add("Execute", "mod+return", surface.CommandRole.none, EXECUTE)?
    commands.add("Report", "mod+p", surface.CommandRole.none, RENDER)?
    commands.separator()?
    commands.add("Connection", "mod+i", surface.CommandRole.none, ABOUT)?
    // The system's own icons, where the system has one. A role a platform
    // cannot draw is left as words rather than as an empty square — Windows
    // has no standard picture for "run", and a toolbar of blanks is worse
    // than a toolbar of labels.
    wear(commands, REFRESH, widgets.SystemIcon.refresh)
    wear(commands, EXECUTE, widgets.SystemIcon.run)
    wear(commands, RENDER, widgets.SystemIcon.print)
    wear(commands, ABOUT, widgets.SystemIcon.info)

    let have_bar: bool = platform.Capability.toolbar.available()
    if have_bar { window.set_toolbar(commands)? }

    // -------------------------------------------------------- the screen

    let content: geometry.Size = window.content_size()?
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.use_services(container)
    mount.use_activator(container)
    mount.set_bounds(content)
    var screen: Browser = new Browser()
    mount.show(screen)?

    // Laid out, *then* the dividers, then laid out again — and the order is
    // the whole point. Every platform here re-divides a split view's panes
    // when the control itself is resized, so a divider written before the
    // control has its final frame is not the divider a moment later: the first
    // pass gives each split view its real size, and the second is the one
    // whose pane widths are true.
    //
    // It is here rather than inside `Session.dress` because a split view
    // refuses a divider wider than itself, and inside `on_mount` the control
    // exists with no frame at all — so every platform answers `out_of_range`
    // to a number that is fine one pass later.
    match work.place_dividers() {
        ok(placed) => {}
        err(problem) => { io.println("cask: {problem.kind}: {problem.msg}") }
    }
    mount.refresh()?

    // The commands, which belong to the window rather than to any control.
    app.router.on(host.Handle.none(), events.EventKind.command,
        fn(event: events.UiEvent) {
            if event.token == REFRESH { work.retree() }
            if event.token == EXECUTE { work.execute() }
            if event.token == RENDER { work.render() }
            if event.token == ABOUT { work.show_facts() }
        })

    io.println("cask: {link.label()?} via {link.server()?}")
    io.println("  drivers={drivers.count()} toolbar={have_bar} split={widgets.WidgetKind.split_view.available()} tabs={widgets.WidgetKind.tab_view.available()}")
    io.println("  day={widgets.WidgetKind.date_picker.available()} colour={widgets.WidgetKind.color_well.available()} web={widgets.WebView.offered()}")

    if !showing {
        // What a person would see in the navigator, and what opening a table
        // put on the Data tab. The control tree below says the window is laid
        // out; these say the database was read — which is the half a dump of
        // widgets cannot show, because a table's rows are not controls.
        io.println("-- the navigator --")
        // Walked through the *source*, not the control, and the difference is
        // the point: this is what a person would see if they opened every
        // node, and what the control shows is whichever of these are open.
        show_tree(tree, widgets.OutlineView.root(), 0)
        match find_node(tree, widgets.OutlineView.root(), "beans") {
            none => { io.println("-- no table called beans --") }
            some(node) => {
                work.open_object(node)
                io.println("-- opening a table --")
                io.println("  {work.data.column_count()} columns, {work.data.row_count()} rows")
                io.println("  titles: {joined(work.data.column_titles())}")
                io.println("  row 7: {joined(row_of(work.data, 7))}")
                io.println("  filtered to 'ethiopia': {work.data.filtered("ethiopia").row_count()} rows")
            }
        }
        work.execute()
        io.println("-- running the editor's statement --")
        io.println("  {work.answer.column_count()} columns, {work.answer.row_count()} rows")
        io.println("  titles: {joined(work.answer.column_titles())}")
        // The editor's own message, which names the day `:since` became — so
        // the golden shows the parameter and not only its effect. The table
        // has eight rows and this answers seven, which is the earliest one
        // falling outside the date the picker holds.
        io.println("  it said: {work.said_words()}")

        io.print(widgets.WidgetDump.of(root)?)
        link.close()?
        app.shutdown()
        return ok(true)
    }

    window.show()?
    app.run()
    link.close()?
    app.shutdown()
    return ok(true)
}

/// Puts a system icon on a command, if this platform has that one.
///
/// Asking first is the whole point: `set_icon` refuses a role the platform
/// cannot draw, and a program that ignored the refusal would show a blank
/// where a word would have done. The command keeps its title either way, so
/// the toolbar is usable on a host with no icon for it at all.
fn wear(commands: surface.Menu, token: int, icon: widgets.SystemIcon) {
    if !icon.available() { return }
    match commands.set_icon(token, icon) {
        ok(worn) => {}
        err(problem) => {}
    }
}

/// Prints one node and everything under it, indented.
///
/// The dump's view of the tree. It asks the *source* rather than the control,
/// because the control is showing only what is open and the golden is about
/// whether the database was read — which is the half a dump of widgets cannot
/// show, since a tree's nodes are not controls.
fn show_tree(tree: Navigator, node: int, depth: int) {
    var at: int = 0
    for at < tree.child_count(node) {
        let child: int = tree.child_at(node, at)
        var pad: string = ""
        var step: int = 0
        for step < depth {
            pad = "{pad}    "
            step = step + 1
        }
        io.println("  {pad}{tree.cell(child, 0)}")
        show_tree(tree, child, depth + 1)
        at = at + 1
    }
}

/// The first node under `node` whose object is called `name`, at any depth.
fn find_node(tree: Navigator, node: int, name: string) -> Option<DbObject> {
    var at: int = 0
    for at < tree.child_count(node) {
        let child: int = tree.child_at(node, at)
        match tree.object_at(child) {
            none => {}
            some(thing) => {
                if thing.name() == name { return some(thing) }
            }
        }
        match find_node(tree, child, name) {
            some(deeper) => { return some(deeper) }
            none => {}
        }
        at = at + 1
    }
    return none
}

/// One row of a grid, as a list. Only the dump uses it: a person reads rows
/// off the screen.
fn row_of(grid: Grid, row: int) -> List<string> {
    var out: List<string> = []
    var at: int = 0
    for at < grid.column_count() {
        out.push(grid.cell(row, at))
        at = at + 1
    }
    return move out
}

/// Words with a bar between them. Beans has no `+` for strings and no `join`
/// on a list, and a golden wants one line.
fn joined(words: List<string>) -> string {
    var out: string = ""
    for word: string in words {
        if out == "" { out = word } else { out = "{out} | {word}" }
    }
    return out
}

fn main() {
    var target: string = ""
    var showing: bool = true
    for arg: string in os.args() {
        // A word starting with two dashes is a switch, even one this program
        // does not know. Treating an unknown switch as a file name is how
        // `cask --help` answers "unable to open database file".
        if arg.starts_with("--") {
            if arg == "--dump" { showing = false }
        } else {
            target = arg
        }
    }
    match run(target, showing) {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
