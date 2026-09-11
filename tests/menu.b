// A menu bar, built from roles, read back off the platform.
//
// What this checks is not that the menu exists — it is that a **role** came
// back named and keyed the way the platform names and keys it, rather than the
// way the program asked. That is the whole reason a command has a role: the
// same declaration produces "Settings…" with Command-comma here and
// "Preferences" with Control-P somewhere else, and an application that wrote
// titles by hand would be right on one machine only.
package main

import cortado.platform
import cortado.surface
import cortado.events
import cortado.host
import std.io

const NEW_ORDER: int = 101
const PRINT_ORDER: int = 102
const ABOUT: int = 103

class Log {
    pub lines: List<string> = []
    pub fn init() {}
}

fn build() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("menu bar available: {platform.Capability.menu_bar.available()}")

    // The application menu. Its title is ignored on macOS — AppKit renames the
    // first submenu after the running program — which is a platform rule
    // cortado does not hide, because hiding it would mean reordering somebody's
    // menus behind their back.
    var about: surface.Menu = surface.Menu.of("Cortado")?
    about.add("About This", "", surface.CommandRole.about, ABOUT)?
    about.add("", "", surface.CommandRole.preferences, 0)?
    about.separator()?
    about.add("", "", surface.CommandRole.hide, 0)?
    about.add("", "", surface.CommandRole.quit, 0)?

    var file: surface.Menu = surface.Menu.of("File")?
    file.add("New Order", "mod+n", surface.CommandRole.none, NEW_ORDER)?
    file.add("Print", "mod+p", surface.CommandRole.none, PRINT_ORDER)?
    file.separator()?
    file.add("", "", surface.CommandRole.close, 0)?

    var edit: surface.Menu = surface.Menu.of("Edit")?
    edit.add("", "", surface.CommandRole.undo, 0)?
    edit.add("", "", surface.CommandRole.redo, 0)?
    edit.separator()?
    edit.add("", "", surface.CommandRole.cut, 0)?
    edit.add("", "", surface.CommandRole.copy, 0)?
    edit.add("", "", surface.CommandRole.paste, 0)?
    edit.add("", "", surface.CommandRole.select_all, 0)?

    var bar: surface.Menu = surface.Menu.of("")?
    bar.submenu(about)?
    bar.submenu(file)?
    bar.submenu(edit)?
    bar.install()?

    io.println("-- what the platform made of it --")
    show("application", about)?
    show("file", file)?
    show("edit", edit)?

    // A command with a role that the platform handles raises nothing: choosing
    // Copy copies, and the program is not asked about it. A command of the
    // application's own raises `command` with its token.
    io.println("-- choosing commands --")
    let tally: Log = new Log()
    app.router.on(host_none(), events.EventKind.command, fn(event: events.UiEvent) {
        tally.lines.push("command token={event.token}")
    })

    file.invoke(NEW_ORDER)?
    about.invoke(ABOUT)?
    for line: string in tally.lines {
        io.println("  {line}")
    }

    io.println("-- enabling --")
    file.set_enabled(PRINT_ORDER, false)?
    match file.invoke(PRINT_ORDER) {
        ok(done) => { io.println("  a disabled command ran — it should not have") }
        err(problem) => { io.println("  a disabled command is refused: {problem.kind}") }
    }
    file.set_enabled(PRINT_ORDER, true)?
    match file.invoke(PRINT_ORDER) {
        ok(done) => { io.println("  re-enabled, and it ran") }
        err(problem) => { io.println("  still refused: {problem.kind}") }
    }
    io.println("  tokens seen: {tally.lines.len()}")

    io.println("-- refusals --")
    match file.set_enabled(9999, false) {
        ok(done) => { io.println("  enabling an unknown token worked — it should not") }
        err(problem) => { io.println("  an unknown token is refused: {problem.kind}") }
    }
    match file.title_at(99) {
        ok(text) => { io.println("  item 99 read \"{text}\"") }
        err(problem) => { io.println("  an out-of-range item is refused: {problem.kind}") }
    }

    app.shutdown()
    return ok(true)
}

// A menu command is not raised against any widget, so its event has no target.
fn host_none() -> host.Handle {
    return host.Handle.none()
}

fn show(name: string, menu: surface.Menu) -> Result<bool> {
    io.println("  {name}:")
    var index: int = 0
    for index: int in 0..menu.count()? {
        let title: string = menu.title_at(index)?
        let key: string = menu.key_at(index)?
        if key == "" {
            io.println("    {title}")
        } else {
            io.println("    {title}  [{key}]")
        }
    }
    return ok(true)
}

fn main() {
    match build() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
