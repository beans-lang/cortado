// `@command`, read off a component and driven.
//
// The declaration replaced two hand-written tables — the menu's rows and the
// router's token-to-method match — so what has to be true is that the one
// declaration still produces both: the platform builds the command, and
// choosing it runs the method it was written on. A test that only counted the
// commands would pass with the routing deleted.
//
// It also drives every refusal, because each of them is a silent no-op if it
// is not a refusal: a method that never runs, an empty square in a toolbar,
// a command nothing can name, and a method the platform has no arguments for.
package main

import github.com/beans-lang/barista
import cortado_app
import cortado.platform
import cortado.surface
import cortado.events
import cortado.host
import cortado.component
import {view, command} from cortado.annotations
import std.io
import std.reflect

/// What the commands did, held apart from the screen so the test can read it
/// after the screen has been boxed into a `reflect.Value`.
pub class Tally {
    pub lines: List<string> = []
    pub fn init() {}
    pub fn note(what: string) { self.lines.push(what) }
}

@view
pub class Desk extends component.Component {
    pub log: Tally = new Tally()

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("Label")
        into.text("desk")
        into.close()
    }

    @command(title: "Refresh", key: "mod+r", icon: "refresh")
    pub fn refresh() { self.log.note("refresh") }

    @command(id: "go", title: "Execute", key: "mod+return", icon: "run")
    pub fn execute() { self.log.note("execute") }

    // No title: the id, and failing that the method's name, is what shows.
    @command(key: "mod+i")
    pub fn about_it() { self.log.note("about_it") }
}

/// Each of these is refused, and the refusal is the test.
@view
pub class TakesTheResponderChain extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {}
    @command(title: "Copy", role: "copy")
    pub fn copy_it() {}
}

@view
pub class NamesNoIcon extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {}
    @command(title: "Go", icon: "referesh")
    pub fn go() {}
}

@view
pub class SaysItTwice extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {}
    @command(id: "same", title: "One")
    pub fn one() {}
    @command(id: "same", title: "Two")
    pub fn two() {}
}

@view
pub class WantsAnArgument extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {}
    @command(title: "With")
    pub fn with_one(value: int) {}
}

fn refusal(named: string, described: reflect.Type) {
    match cortado_app.declared_commands(described) {
        ok(found) => {
            io.println("  {named}: ACCEPTED {found.len()} — it should not have")
        }
        err(problem) => { io.println("  {named}: {problem.kind}") }
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("-- what the declaration says --")
    let declared: List<cortado_app.DeclaredCommand> =
        cortado_app.declared_commands(type_of(Desk))?
    for one: cortado_app.DeclaredCommand in declared {
        io.println("  {one.token} id={one.id} title=\"{one.title}\" key={one.key} role={one.role.name()} icon={one.icon.name()}")
    }

    // Declaration order is the menu's order. Sorting by anything else would
    // reorder somebody's menu when they renamed an item.
    io.println("-- the platform's own words --")
    let menu: surface.Menu = cortado_app.build_menu("Desk", declared)?
    let rows: int = menu.count()?
    for index: int in 0..rows {
        let shown: string = menu.title_at(index)?
        let pressed: string = menu.key_at(index)?
        io.println("  '{shown}' [{pressed}]")
    }

    io.println("-- choosing them --")
    let tally: Tally = new Tally()
    var screen: Desk = new Desk()
    screen.log = tally
    let boxed: reflect.Value = reflect.value(move screen)
    cortado_app.route_commands(app.router, boxed, declared)

    for one: cortado_app.DeclaredCommand in declared {
        menu.invoke(one.token)?
    }
    for line: string in tally.lines {
        io.println("  ran {line}")
    }
    // Every command ran, and each ran once. A router that matched on the wrong
    // field would still run something, and a handler registered per command
    // rather than once would run each of them three times.
    io.println("  {tally.lines.len()} of {declared.len()} commands ran")

    io.println("-- refused --")
    refusal("a role the platform handles", type_of(TakesTheResponderChain))
    refusal("an icon no role spells", type_of(NamesNoIcon))
    refusal("two commands with one id", type_of(SaysItTwice))
    refusal("a command that wants an argument", type_of(WantsAnArgument))

    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
