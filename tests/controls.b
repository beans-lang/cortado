// Which controls this platform has, and what cortado says where it has none.
//
// **The same bytes on every host, and that is the point of how it is
// written.** cortado's first thirteen kinds are on every platform; `switch` is
// the first that is not, because the Win32 common controls have no toggle
// switch. So a file that printed the inventory would be a file per platform,
// and a file that printed only the kinds everybody has would never mention the
// interesting one.
//
// Every line here asks whether what happened *agrees with what the platform
// said would happen* — the shape `tests/gpu.b` uses for the same reason. A
// host with a switch builds one and reads its role; a host without refuses by
// name. Two different paths, one golden, and the claim being made is not
// "there is a switch" but "cortado tells the truth about whether there is one,
// and never quietly substitutes something else".
//
// Counted against `WidgetKind.all()` rather than against what was asked for,
// because "0 of 0 agreed" is true for the wrong reason.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.events
import cortado.host
import std.io

fn agrees(promised: bool, happened: bool) -> bool {
    return promised == happened
}

/// Handlers capture this rather than the control they are attached to: the
/// platform's stored callback holds a strong reference the collector cannot
/// see through, so a handler that closed over its own widget would be a cycle.
class Heard {
    pub count: int = 0
    pub fn init() {}
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    // A window and a root, because a control has to be in a tree before a
    // platform will deliver its events: Win32 sends a control's notification
    // to its *parent*, and a control with no parent has nowhere to send it.
    var window: surface.Window = app.window(320.0, 200.0, "Controls")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    let tally: Heard = new Heard()
    let every: List<widgets.WidgetKind> = widgets.WidgetKind.all()

    var answered: int = 0
    var built_where_offered: int = 0
    var refused_where_not: int = 0
    var refusal_names_the_control: int = 0
    var has_a_role: int = 0
    var has_a_class: int = 0
    var offered: int = 0

    for kind: widgets.WidgetKind in every {
        // `available()` is the platform's answer. Nothing below ever asks a
        // second time — every count is that one answer against what happened.
        let promised: bool = kind.available()
        if promised { offered = offered + 1 }
        answered = answered + 1

        match component.WidgetMaker.of_kind(kind) {
            ok(control) => {
                if agrees(promised, control.is_alive()) {
                    built_where_offered = built_where_offered + 1
                }
                if promised {
                    match control.a11y_role() {
                        ok(role) => { if role.len() > 0 { has_a_role = has_a_role + 1 } }
                        err(problem) => {}
                    }
                    match control.native_class() {
                        ok(name) => { if name.len() > 0 { has_a_class = has_a_class + 1 } }
                        err(problem) => {}
                    }
                }
            }
            err(problem) => {
                // A kind this platform has not got is refused before anything
                // is built, so the message is about the control rather than
                // about a handle that was never filled in.
                if !promised { refused_where_not = refused_where_not + 1 }
                if problem.kind == "no_such_control" && problem.msg.contains(kind.name()) {
                    refusal_names_the_control = refusal_names_the_control + 1
                }
            }
        }
    }

    // A kind that is offered is not refused, and one that is refused is not
    // offered — so these two together account for every kind exactly once.
    let refused: int = answered - offered

    io.println("-- what this platform can build --")
    io.println("  cortado has this many kinds: {every.len()}")
    io.println("  every one of them answers yes or no: {answered == every.len()}")
    io.println("  a control is alive exactly where the kind is offered: {built_where_offered == offered}")
    io.println("  and refused before it is built exactly where it is not: {refused_where_not == refused}")
    io.println("  every refusal names the control rather than a handle: {refusal_names_the_control == refused}")

    io.println("-- what a control that exists can say about itself --")
    io.println("  each has an accessibility role, and none is empty: {has_a_role == offered}")
    io.println("  each has the platform's own class name, and none is empty: {has_a_class == offered}")

    // The markup path reaches the same question through a tag. A `<Switch />`
    // written on a platform with no switch has to refuse in the same words,
    // because a component author never sees `WidgetKind` at all.
    io.println("-- the same question through markup --")
    var tags_agreed: int = 0
    var tags_asked: int = 0
    for kind: widgets.WidgetKind in every {
        match component.Vocabulary.kind_of(kind.name()) {
            some(found) => {
                tags_asked = tags_asked + 1
                var made: bool = false
                match component.WidgetMaker.of_kind(found) {
                    ok(control) => { made = control.is_alive() }
                    err(problem) => { made = false }
                }
                if agrees(found.available(), made) { tags_agreed = tags_agreed + 1 }
            }
            none => {}
        }
    }
    io.println("  this many kinds are reachable by their own name as a tag: {tags_asked}")
    io.println("  and each builds exactly where its kind is offered: {tags_agreed == tags_asked}")

    // The third answer, and the only part of this file that is *not* vacuous
    // on a host where every kind exists.
    //
    // Worth being exact about, because it is this file's weak spot: on macOS,
    // iOS and GTK4 every kind is available, so "refused exactly where it is
    // not offered" above compares nothing to nothing. The host that answers
    // "no" today is Win32, whose switch does not exist, and the gate runs its
    // goldens nowhere — what holds that answer is `tools/check_vocabulary.sh`,
    // which fails the build if any host leaves a kind out of its table, and
    // the cross-target compile.
    //
    // This part runs everywhere. A number that is not a kind has to come back
    // refused rather than as a no, and cortado has to have no name for it.
    var not_a_kind: int = 0
    var no_name: int = 0
    for probe: int in [-1, 99, 4242] {
        if !widgets.WidgetKind.is_a_kind(probe) { not_a_kind = not_a_kind + 1 }
        match widgets.WidgetKind.of(probe) {
            some(named) => {}
            none => { no_name = no_name + 1 }
        }
    }
    // Every control that carries a state, moved the way a user moves it, and
    // then written to the way a program writes to it. Two rules in one loop,
    // and both are rules no single-control case could state:
    //
    //   * a control that is a state raises `value_changed` when it is moved;
    //   * and raises nothing at all when the program sets it.
    //
    // The second is the one that needed writing down. Three of the four hosts
    // are quiet by construction — BM_SETCHECK sends no BN_CLICKED, -setState:
    // sends no action, -setOn: fires no value-changed — and GTK notifies on a
    // property change whoever made it. A render that heard about its own
    // writes would feed itself for as long as the program ran.
    var heard: int = 0
    var heard_on_a_write: int = 0
    var states: int = 0
    var states_here: int = 0
    for kind: widgets.WidgetKind in every {
        if !kind.has_state() { continue }
        // Counted before availability, so the number below is cortado's own
        // rule rather than this machine's inventory — the same reason nothing
        // else in this file prints what the platform has.
        states = states + 1
        if !kind.available() { continue }
        states_here = states_here + 1
        var control: widgets.Widget = component.WidgetMaker.of_kind(kind)?
        root.add(control)?
        let before: int = tally.count
        app.router.on(control.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) { tally.count = tally.count + 1 })
        control.set_value_as_user(1, 0.0)?
        if tally.count == before + 1 { heard = heard + 1 }
        let after_user: int = tally.count
        control.set_property(host.P_CHECKED, 0)?
        if tally.count != after_user { heard_on_a_write = heard_on_a_write + 1 }
        app.router.forget(control.handle())
    }
    io.println("-- moving a control, and writing to one --")
    io.println("  this many kinds are a state: {states}")
    io.println("  each one this platform has raises value_changed when it is moved: {heard == states_here}")
    io.println("  and none raises anything when the program writes to it: {heard_on_a_write == 0}")

    // One more per-kind rule, here rather than in a file of its own because it
    // is one property on one control. A spinner can be turning; nothing else
    // can. It is worth a line because the classes do not line up with it — a
    // spinner is an `NSProgressIndicator`, the same class as a progress bar,
    // so a host that asked the object would let a bar be "turning" on that one
    // platform.
    var turning_correct: int = 0
    for kind: widgets.WidgetKind in every {
        if !kind.available() { continue }
        var control: widgets.Widget = component.WidgetMaker.of_kind(kind)?
        var took_it: bool = false
        match control.set_property(host.P_ANIMATING, 1) {
            ok(done) => { took_it = true }
            err(problem) => { took_it = false }
        }
        if took_it == (kind == widgets.WidgetKind.spinner) {
            turning_correct = turning_correct + 1
        } else {
            io.println("  ...{kind.name()} answered {took_it} to being turned on")
        }
    }
    io.println("-- what can be turning --")
    io.println("  exactly a spinner, and only where there is one: {turning_correct == offered}")

    io.println("-- a number that is not a kind --")
    io.println("  the host refuses it rather than calling it a missing control: {not_a_kind == 3}")
    io.println("  and cortado has no name for it: {no_name == 3}")

    window.close()?
    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
