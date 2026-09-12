// The system's own icons, and what a host is allowed to not have.
//
// cortado names icons by **role** — "refresh", "open", "database" — and each
// host draws its own picture. That makes one claim worth testing and one worth
// being careful about.
//
// The claim: **a role a host says it has, it can draw, and no two roles are
// the same picture.** A mapping table is the kind of thing that gets a line
// copied and a name left behind, and the result is two commands with one icon
// — which nobody notices, because both icons look fine.
//
// The care: **the names name one platform.** `arrow.clockwise` is macOS's,
// `view-refresh-symbolic` is GTK's, `STD_FILEOPEN` is Windows'. So no name is
// in this file's golden. What is here is the shape of the answer, which is the
// same on a host with all twenty-seven and on one with fourteen.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.host
import std.io

/// The kind slug a call refuses with, or "" when it answered.
fn refusal(answer: Result<bool>) -> string {
    match answer {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("-- what this platform has --")
    let offered: bool = platform.Capability.icons.available()
    io.println("  an icon set is offered exactly where the capability says so: {offered}")

    var named: int = 0
    var blanks: int = 0
    var every_name_once: bool = true
    var seen: Map<string, bool> = {}
    for icon: widgets.SystemIcon in widgets.SystemIcon.all() {
        if icon == widgets.SystemIcon.none { continue }
        match icon.platform_name() {
            err(problem) => {
                blanks = blanks + 1
                // A role this host cannot draw refuses by name rather than
                // answering an empty string, because "no icon" and "an icon
                // with no name" are different answers and only one of them is
                // a bug.
                if problem.kind != "out_of_range" { every_name_once = false }
            }
            ok(words) => {
                named = named + 1
                if words == "" { every_name_once = false }
                // Two roles with one picture is the failure a table of names
                // invites and nobody sees.
                if seen.contains_key(words) { every_name_once = false }
                seen.set(words, true)
            }
        }
    }
    io.println("  every role it claims has its own name: {every_name_once}")
    io.println("  and it claims at least one: {named > 0}")
    // "No icon" is not a missing icon: every platform can not-draw one, and
    // it is what takes an icon away again.
    io.println("  the absence of an icon is always available: {widgets.SystemIcon.none.available()}")

    // `available` and `platform_name` are two views of one answer, so they
    // cannot disagree — the second is what the first is made of.
    var agree: bool = true
    for icon: widgets.SystemIcon in widgets.SystemIcon.all() {
        if icon == widgets.SystemIcon.none { continue }
        var can: bool = false
        match icon.platform_name() {
            ok(words) => { can = true }
            err(problem) => { can = false }
        }
        if can != icon.available() { agree = false }
    }
    io.println("  asking twice gives the same answer: {agree}")

    io.println("-- on a control --")
    var window: surface.Window = app.window(300.0, 200.0, "icons")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var press: widgets.Button = widgets.Button.of("Open")?
    root.add(press)?

    // The first role this host can draw, whichever it is. Naming one here
    // would be naming a platform: Windows has no "refresh".
    var first: widgets.SystemIcon = widgets.SystemIcon.none
    for icon: widgets.SystemIcon in widgets.SystemIcon.all() {
        if icon == widgets.SystemIcon.none { continue }
        if first == widgets.SystemIcon.none && icon.available() { first = icon }
    }

    var set_ok: bool = true
    var cleared: bool = true
    if first != widgets.SystemIcon.none {
        press.set_icon(first)?
        set_ok = press.icon()? == first
        press.set_icon(widgets.SystemIcon.none)?
        cleared = press.icon()? == widgets.SystemIcon.none
    }
    io.println("  a button keeps the icon it was given: {set_ok}")
    io.println("  and none takes it away again: {cleared}")

    // A control that does not carry one says so, rather than accepting a
    // write nothing will ever draw.
    var words: widgets.Label = widgets.Label.of("x")?
    root.add(words)?
    io.println("  a label has no icon to set: {refusal(words.set_property(host.P_ICON, host.ICON_INFO)) == "wrong_widget"}")
    // A number the header does not name, through the raw property, because
    // `SystemIcon` cannot spell one — which is the point of the enum and the
    // reason the host still has to check.
    let past_end: string = refusal(press.set_property(host.P_ICON, host.ICON_COUNT))
    let below_zero: string = refusal(press.set_property(host.P_ICON, -1))
    let both_refused: bool = past_end == "out_of_range" && below_zero == "out_of_range"
    io.println("  a role outside the list is refused: {both_refused}")

    io.println("-- on a command --")
    // A phone has no menu bar, and it says so one step earlier than this
    // section was first written for: `ctd_menu_new` answers nothing, so there
    // is no menu to refuse an icon. Both lines are written to be true either
    // way — where there are menus, a command takes an icon and a token nobody
    // added is refused; where there are none, there is nothing to be untrue.
    var took: bool = true
    var bad_token: bool = true
    if platform.Capability.menu_bar.available() {
        var commands: surface.Menu = surface.Menu.of("File")?
        commands.add("Open", "mod+o", surface.CommandRole.none, 7)?
        let on_command: string = refusal(commands.set_icon(7, first))
        let wrong_token: string = refusal(commands.set_icon(99, first))
        // A host with menus but no icons on them refuses both the same way,
        // which is why "unsupported" is an accepted answer to each.
        took = on_command == "" || on_command == "unsupported"
        bad_token = wrong_token == "out_of_range" || wrong_token == "unsupported"
    }
    io.println("  a command takes one, or the platform has no menus: {took}")
    io.println("  a token the menu does not have is refused: {bad_token}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
