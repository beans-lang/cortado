// commands.b — `@command`, read.
//
// A menu is the one part of a desktop application that cannot be described as
// a shape, which is why it is not in markup and why it was, until now, twenty
// lines of `main.b` in every program that had one. `examples/cask` wrote the
// table twice: once as five `commands.add(...)` calls with a token each, and
// again as a `router.on(...)` handler matching those tokens back to methods.
// Two tables for one fact is a fact that goes out of step.
//
//     @command(title: "Execute", key: "mod+return", icon: "run")
//     pub fn execute() { ... }
//
// The declaration is on the method it runs, so there is nothing to keep in
// step, and a tool can read an application's commands without running it —
// which is the same reason `@window` is a declaration.
//
// Three things are refused rather than ignored, and each one is a silent
// no-op if it is not:
//
// **A role the platform handles itself.** `CommandRole.cut` and its four
// neighbours are wired to the platform's own editing machinery — choosing Copy
// copies, and the application is never asked. A method declared for one would
// never run, so it is an error naming the method rather than a handler that
// never fires.
//
// **An icon name no role spells.** `icon: "referesh"` would otherwise be an
// empty space in a toolbar, which is a thing people debug for an afternoon.
//
// **Two commands with the same id.** The id is what a person writes in a test
// or a script to press one; two of them means one is unreachable.
//
// An icon a *platform* does not have is not an error — that is the question
// `SystemIcon.available()` exists to answer, and the command keeps its words.

package cortado_app

import cortado.surface
import cortado.widgets
import cortado.events
import cortado.host
import std.reflect

/// One `@command`, as declared.
pub class DeclaredCommand {
    /// The method's own name, which is the id when none was written.
    pub id: string = ""
    pub title: string = ""
    pub key: string = ""
    pub role: surface.CommandRole = surface.CommandRole.none
    pub icon: widgets.SystemIcon = widgets.SystemIcon.none
    /// The method to call. Its receiver is the root component.
    pub method: reflect.Method
    /// A dividing line goes above this command.
    pub separator: bool = false
    /// The number the platform raises for this command.
    pub token: int = 0

    pub fn init(method: reflect.Method) {
        self.method = method
    }
}

fn annotation_text(marker: reflect.Annotation, field: string) -> string {
    match marker.argument(field) {
        some(argument) => { return argument.value().text() }
        none => { return "" }
    }
}

/// Every `@command` on a type, in declaration order.
///
/// Declaration order is the menu's order, because a menu has one and there is
/// nothing else for it to be. Sorting by title would reorder a menu when
/// somebody renamed an item, and sorting by id would put About above Execute
/// for no reason a reader could see.
pub fn declared_commands(described: reflect.Type) -> Result<List<DeclaredCommand>> {
    var found: List<DeclaredCommand> = []
    for method: reflect.Method in described.declared_methods() {
        var marker: Option<reflect.Annotation> = none
        for used: reflect.Annotation in method.annotations() {
            if used.qualified_name() == "cortado.annotations.command" {
                marker = some(used)
            }
        }
        match marker {
            none => { continue }
            some(used) => {
                var one: DeclaredCommand = new DeclaredCommand(method)
                one.id = annotation_text(used, "id")
                if one.id == "" { one.id = method.name() }
                one.title = annotation_text(used, "title")
                if one.title == "" { one.title = one.id }

                one.key = annotation_text(used, "key")
                match used.argument("separator") {
                    some(argument) => {
                        match argument.value().as_bool() {
                            some(wanted) => { one.separator = wanted }
                            none => {}
                        }
                    }
                    none => {}
                }

                let role_name: string = annotation_text(used, "role")
                if role_name != "" {
                    match surface.CommandRole.from_name(role_name) {
                        some(role) => { one.role = role }
                        none => {
                            return err(
                                "@command(role: \"{role_name}\") on {described.name()}.{method.name()} is not a role cortado has",
                                "command")
                        }
                    }
                }
                // A role the platform answers itself never raises a `command`
                // event, so a method declared for one is a handler that can
                // never run. Cut, Copy, Paste, Undo and Select All reach the
                // focused control through the responder chain, and taking them
                // over is how editing stops working in every system control in
                // the window.
                if one.role.is_platform_handled() {
                    return err(
                        "@command(role: \"{role_name}\") on {described.name()}.{method.name()}: the platform handles that command itself and raises no event, so this method would never run — leave it to the responder chain",
                        "command")
                }

                let icon_name: string = annotation_text(used, "icon")
                if icon_name != "" {
                    match widgets.SystemIcon.from_name(icon_name) {
                        some(icon) => { one.icon = icon }
                        none => {
                            return err(
                                "@command(icon: \"{icon_name}\") on {described.name()}.{method.name()} is not an icon role cortado has",
                                "command")
                        }
                    }
                }

                if !method.parameters().is_empty() {
                    return err(
                        "@command on {described.name()}.{method.name()}: a command takes no arguments — the platform has none to give it",
                        "command")
                }
                for already: DeclaredCommand in found {
                    if already.id == one.id {
                        return err(
                            "two commands on {described.name()} are both called '{one.id}' — an id is what names one of them",
                            "command")
                    }
                }
                // Tokens are one-based so that zero is never a command: a
                // handler reading an unset token would otherwise run the first
                // one.
                one.token = found.len() + 1
                found.push(one)
            }
        }
    }
    return ok(move found)
}

/// Build the command table a window shows, or nothing when there are none.
///
/// One table, which becomes the toolbar where the platform has one and the
/// menu bar where it has one. Two lists would drift.
pub fn build_menu(title: string, commands: List<DeclaredCommand>) -> Result<surface.Menu> {
    var menu: surface.Menu = surface.Menu.of(title)?
    for one: DeclaredCommand in commands {
        if one.separator { menu.separator()? }
        menu.add(one.title, one.key, one.role, one.token)?
        // The system's own icon, where the system has that role. A role this
        // platform cannot draw is left as words rather than as an empty
        // square — Windows has no standard picture for "run", and a toolbar of
        // blanks is worse than a toolbar of labels.
        if one.icon.available() {
            menu.set_icon(one.token, one.icon)?
        }
    }
    return ok(menu)
}

/// The native desktop menu bar around a screen's declared commands.
///
/// The toolbar and command submenu are both made from the same declarations.
/// Platform roles keep text editing and window commands in the responder
/// chain, so a focused native control handles them itself.
pub fn build_application_menu(title: string, command_menu_title: string,
                              commands: List<DeclaredCommand>) -> Result<surface.Menu> {
    var app: surface.Menu = surface.Menu.of(title)?
    app.add("About {title}", "", surface.CommandRole.about, 0)?
    app.separator()?
    app.add("Hide {title}", "", surface.CommandRole.hide, 0)?
    app.add("Quit {title}", "", surface.CommandRole.quit, 0)?

    var file: surface.Menu = surface.Menu.of("File")?
    file.add("", "", surface.CommandRole.close, 0)?

    var edit: surface.Menu = surface.Menu.of("Edit")?
    edit.add("", "", surface.CommandRole.undo, 0)?
    edit.add("", "", surface.CommandRole.redo, 0)?
    edit.separator()?
    edit.add("", "", surface.CommandRole.cut, 0)?
    edit.add("", "", surface.CommandRole.copy, 0)?
    edit.add("", "", surface.CommandRole.paste, 0)?
    edit.add("", "", surface.CommandRole.select_all, 0)?

    var window: surface.Menu = surface.Menu.of("Window")?
    window.add("", "", surface.CommandRole.minimize, 0)?
    window.add("", "", surface.CommandRole.fullscreen, 0)?

    var bar: surface.Menu = surface.Menu.of("")?
    bar.submenu(app)?
    bar.submenu(file)?
    bar.submenu(edit)?
    if !commands.is_empty() {
        let heading: string = if command_menu_title == "" { "Commands" } else { command_menu_title }
        let actions: surface.Menu = build_menu(heading, commands)?
        bar.submenu(actions)?
    }
    bar.submenu(window)?
    return ok(bar)
}

/// Route the platform's `command` events back to the methods that declared
/// them.
///
/// The handler is on `Handle.none()` because a command belongs to the window
/// and not to any control in it — which is also why this is one registration
/// and not one per command.
pub fn route_commands(router: events.EventRouter, screen: reflect.Value, commands: List<DeclaredCommand>) {
    router.on(host.Handle.none(), events.EventKind.command,
        fn(event: events.UiEvent) {
            for one: DeclaredCommand in commands {
                if one.token != event.token { continue }
                let arguments: List<reflect.Value> = []
                match one.method.call(screen.copy(), move arguments) {
                    ok(answered) => {}
                    err(problem) => {}
                }
            }
        })
}
