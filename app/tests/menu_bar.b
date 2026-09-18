// A root command reaches the same handler through the desktop menu bar, and
// standard menus exist even for a screen with no commands.
package main

import cortado_app
import cortado.platform
import cortado.surface
import cortado.component
import {view, command} from cortado.annotations
import std.io
import std.reflect

@view
class Workbench extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {}

    @command(title: "Run", key: "mod+return")
    pub fn execute() { io.println("ran from menu") }
}

fn show(bar: surface.Menu) -> Result<bool> {
    for index: int in 0..bar.count()? {
        io.println(bar.title_at(index)?)
    }
    return ok(true)
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let empty: List<cortado_app.DeclaredCommand> = []
    let ordinary: surface.Menu = cortado_app.build_application_menu("Grounds", "Run", empty)?
    io.println("without commands:")
    show(ordinary)?

    let commands: List<cortado_app.DeclaredCommand> =
        cortado_app.declared_commands(type_of(Workbench))?
    let bar: surface.Menu = cortado_app.build_application_menu("Grounds", "Run", commands)?
    bar.install()?
    io.println("with commands:")
    show(bar)?

    let shortcut: surface.Menu = cortado_app.build_menu("Run", commands)?
    io.println("shortcut: {shortcut.key_at(0)?}")
    var screen: Workbench = new Workbench()
    let boxed: reflect.Value = reflect.value(move screen)
    cortado_app.route_commands(app.router, boxed, commands)
    bar.invoke(commands[0].token)?

    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
