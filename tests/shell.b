// The two things that hang off a window rather than sit inside it.
//
// A toolbar and a popover are the first things in cortado that are neither
// widgets nor properties of one. Neither has a frame the solver sets and
// neither is anybody's child: a toolbar belongs to a window and lives where
// the platform puts it, and a popover is its own window, which is what lets it
// draw outside the one that spawned it.
//
// **A toolbar is a menu.** The same handle, the same tokens, the same
// `set_enabled` — so a command that is in the menu bar and on the toolbar is
// one command, and a program with one command table needs no second one. That
// is the claim this file is mostly about, and the way it is checked is that
// choosing the command from either place produces the same token.
//
// Everything below prints agreement rather than inventory: a platform with no
// popover and a platform with one produce the same bytes, because each line
// says "this is true wherever the thing exists, and there is nothing to be
// untrue where it does not". Which platform has what is
// `tests/controls.out`'s business and `Capability`'s.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import cortado.host
import std.io

class Heard {
    pub count: int = 0
    pub last: int = 0
    pub fn init() {}
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(400.0, 300.0, "Shell")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let tally: Heard = new Heard()

    // ---------------------------------------------------------- the toolbar

    let have_bar: bool = platform.Capability.toolbar.available()
    var bar_ok: bool = true
    var bar_counts: bool = true
    var bar_commands: bool = true
    var bar_goes: bool = true

    if have_bar {
        var commands: surface.Menu = surface.Menu.of("Brew")?
        commands.add("Grind", "mod+g", surface.CommandRole.none, 11)?
        commands.add("Pour", "mod+p", surface.CommandRole.none, 12)?
        commands.separator()?
        commands.add("Stop", "", surface.CommandRole.none, 13)?

        window.set_toolbar(commands)?
        // Not the menu's count. A separator is a toolbar item on some
        // platforms and a gap on others, and a submenu is a toolbar item on
        // none — so what is asserted is that the toolbar has *some* items and
        // no more than the menu it was built from.
        let shown: int = window.toolbar_count()?
        bar_counts = shown > 0 && shown <= commands.count()?

        // The command reaches the same handler from the toolbar as from the
        // menu, because it is the same command. Invoking through the menu is
        // what a test can do without a mouse; what it proves is that the token
        // survives, which is the only thing the two paths share.
        app.router.on(host.Handle.none(), events.EventKind.command,
            fn(event: events.UiEvent) {
                tally.count = tally.count + 1
                tally.last = event.token
            })
        commands.invoke(12)?
        bar_commands = tally.count == 1 && tally.last == 12

        // Disabling it is one call, and it is the menu's.
        commands.set_enabled(12, false)?
        bar_ok = window.toolbar_count()? == shown

        window.clear_toolbar()?
        bar_goes = window.toolbar_count()? == 0
    }

    io.println("-- a toolbar --")
    io.println("  it shows some of the menu's items and no more: {bar_counts}")
    io.println("  a command reaches the same handler with the same token: {bar_commands}")
    io.println("  disabling one does not change what is shown: {bar_ok}")
    io.println("  and taking the toolbar away leaves nothing: {bar_goes}")

    // ---------------------------------------------------------- the popover

    let have_pop: bool = platform.Capability.popover.available()
    var pop_ok: bool = true
    var pop_refuse: bool = true
    var pop_shut: bool = true

    var anchor: widgets.Button = widgets.Button.of("Options")?
    root.add(anchor)?

    if have_pop {
        var inside: widgets.Container = new widgets.Container()
        var words: widgets.Label = widgets.Label.of("Nothing here yet")?
        inside.add(words)?

        var pop: surface.Popover = surface.Popover.of(inside, 200.0, 120.0)?
        pop_ok = !pop.is_shown()?

        // A size of nothing is a caller's bug rather than a popover.
        pop_refuse = refusal_size(inside, 0.0, 120.0) == "out_of_range" &&
                     refusal_size(inside, 200.0, -1.0) == "out_of_range"

        app.router.on(pop.handle(), events.EventKind.dismiss,
            fn(event: events.UiEvent) { tally.count = tally.count + 1 })

        // Showing one needs a window the user can see, and a headless run has
        // none. What is asserted is that asking gives an *answer* — either it
        // went up, or it was refused with a reason — because the thing that
        // must not happen is an exception: AppKit throws rather than returning
        // when a popover is anchored to a view in no window, and an exception
        // in a headless gate takes the process down with no status anybody can
        // read.
        var answered: bool = false
        match pop.show(anchor, surface.Edge.below) {
            ok(done) => { answered = true }
            err(problem) => { answered = problem.kind != "" }
        }
        pop_ok = pop_ok && answered

        pop.close()?
        pop_shut = !pop.is_shown()?
        pop.release()?
        // The content is still a widget afterwards: the caller built that tree
        // and may show it again.
        pop_shut = pop_shut && inside.count() == 1
        app.router.forget(pop.handle())
    }

    io.println("-- a popover --")
    io.println("  a fresh one is not showing, and asking to show gives an answer: {pop_ok}")
    io.println("  a size of nothing is refused: {pop_refuse}")
    io.println("  closing it shuts it and leaves its content alone: {pop_shut}")

    window.close()?
    app.shutdown()
    return ok(true)
}

fn refusal_size(content: widgets.Widget, width: f64, height: f64) -> string {
    match surface.Popover.of(content, width, height) {
        ok(made) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
