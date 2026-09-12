// The pointer, the keyboard, and where the keys go.
//
// **Every kind checked here was declared in the header from the first version
// and emitted by nobody.** A control could be clicked and would say so;
// nothing could say *where* it was clicked, what was typed into it, or which
// control the keyboard was pointing at. This file is the other half.
//
// Cross-host, and in the agreement shape the rest of the suite uses, because
// the four hosts do not agree on the road an event travels. AppKit hands
// cortado a real NSEvent through -[NSApplication sendEvent:] and Win32 a real
// WM_LBUTTONDOWN; GTK4 and UIKit neither, because neither lets a program
// outside the toolkit build an event at all, so there a synthesised call emits
// the controller's own signal — the same handler a real click reaches, one
// step short of the platform's own dispatch. What every host does agree on is
// what arrives at the other end, and that is what these lines are.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import cortado.geometry
import cortado.host
import std.io

/// Everything the router heard, and the last of each, so a line can say more
/// than "something happened".
class Heard {
    pub downs: int = 0
    pub ups: int = 0
    pub moves: int = 0
    pub keys: int = 0
    pub focused: int = 0
    pub blurred: int = 0
    pub at_x: f64 = -1.0
    pub at_y: f64 = -1.0
    pub button: string = ""
    pub key: string = ""
    pub typed: string = ""
    pub modifiers: int = 0
    pub fn init() {}
}

fn refused_as(answer: Result<bool>, kind: string) -> bool {
    match answer {
        ok(done) => { return false }
        err(problem) => { return problem.kind == kind }
    }
}

fn took(answer: Result<bool>) -> bool {
    match answer {
        ok(done) => { return true }
        err(problem) => { return false }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("-- the names --")
    // A table of names is exactly the thing that ends up with two rows sharing
    // a word and nobody noticing, so it is asked for all of them at once.
    var named: int = 0
    var every_name_once: bool = true
    var seen: Map<string, bool> = {}
    for key: events.Key in events.Key.all() {
        let word: string = key.platform_name().or("")
        if word == "" { every_name_once = false }
        if seen.contains_key(word) { every_name_once = false }
        seen.set(word, true)
        // cortado's own word and the host's are two copies of one table, which
        // is one copy too many unless something checks they agree.
        if word != key.name() { every_name_once = false }
        named = named + 1
    }
    io.println("  every key has its own word, and no two share one: {every_name_once}")
    io.println("  and there is one for every key the header names: {named == 28}")

    var window: surface.Window = app.window(320.0, 240.0, "input")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var press: widgets.Button = widgets.Button.of("Press")?
    root.add(press)?
    press.set_frame(geometry.Rect.of(10.0, 10.0, 120.0, 30.0))?

    var field: widgets.TextField = widgets.TextField.of("")?
    root.add(field)?
    field.set_frame(geometry.Rect.of(10.0, 60.0, 200.0, 24.0))?

    var words: widgets.Label = widgets.Label.of("a label")?
    root.add(words)?
    words.set_frame(geometry.Rect.of(10.0, 100.0, 200.0, 20.0))?

    let tally: Heard = new Heard()
    let other: Heard = new Heard()

    io.println("-- the pointer --")
    // Registered before anything is clicked, which is also what turns the kind
    // on: a host is told what is wanted and does no work for the rest.
    app.router.on(press.handle(), events.EventKind.pointer_down,
        fn(event: events.UiEvent) {
            tally.downs = tally.downs + 1
            tally.at_x = event.position.x
            tally.at_y = event.position.y
            tally.button = event.button().name()
        })
    app.router.on(press.handle(), events.EventKind.pointer_up,
        fn(event: events.UiEvent) { tally.ups = tally.ups + 1 })
    app.router.on(press.handle(), events.EventKind.pointer_move,
        fn(event: events.UiEvent) { tally.moves = tally.moves + 1 })
    app.router.on(field.handle(), events.EventKind.pointer_down,
        fn(event: events.UiEvent) { other.downs = other.downs + 1 })

    // Aimed at a point inside the button, in the button's own space — the
    // same space set_frame uses, which is the whole reason a caller can work
    // out where to click without asking about windows or screens.
    press.click_as_user(geometry.Point.at(60.0, 15.0))?
    press.point_as_user(events.EventKind.pointer_move,
                        geometry.Point.at(30.0, 20.0),
                        events.PointerButton.left)?

    io.println("  a click is heard, down and up: {tally.downs == 1 && tally.ups == 1}")
    io.println("  and says where, in the control's own space: {tally.at_x == 60.0 && tally.at_y == 15.0}")
    io.println("  and which button it was: {tally.button == "left"}")

    // A second button, and the two answers a platform can honestly give. A
    // desktop carries it across — which takes doing, because on two of the
    // four hosts there is no event to carry it in and it is handed over beside
    // the call, and a host that dropped it would say "left" here. A phone has
    // no second button at all and says so, rather than reporting a left click
    // nobody asked for.
    var carried: bool = false
    var one_button: bool = false
    match press.point_as_user(events.EventKind.pointer_down,
                              geometry.Point.at(60.0, 15.0),
                              events.PointerButton.right) {
        ok(done) => { carried = tally.button == "right" }
        err(problem) => { one_button = problem.kind == "unsupported" }
    }
    io.println("  a right button is carried across, or this pointer has one: {carried != one_button}")
    io.println("  a move is heard too: {tally.moves == 1}")
    io.println("  and a control nobody clicked heard nothing: {other.downs == 0}")
    io.println("  a kind that is not a pointer event is refused: {refused_as(press.point_as_user(events.EventKind.activate, geometry.Point.zero(), events.PointerButton.left), "out_of_range")}")

    io.println("-- the keyboard --")
    app.router.on(field.handle(), events.EventKind.key_down,
        fn(event: events.UiEvent) {
            tally.keys = tally.keys + 1
            tally.key = event.key().name()
            tally.typed = event.text
            tally.modifiers = event.modifiers
        })

    // A key that types nothing. Its identity is the key, and there is no text.
    field.key_as_user(events.EventKind.key_down, events.Key.escape, "", 0)?
    let named_key: bool = tally.key == "escape" && tally.typed == ""

    // A key that types something. Its identity is the text, because a code per
    // character is a keyboard layout written into an ABI.
    field.key_as_user(events.EventKind.key_down, events.Key.character, "s",
                      host.MOD_SHIFT)?
    let typed_key: bool = tally.key == "character" && tally.typed == "s"

    io.println("  a key that types nothing says which key it was: {named_key}")
    io.println("  a key that types says what it typed: {typed_key}")
    io.println("  and the modifiers that were held: {(tally.modifiers & host.MOD_SHIFT) != 0}")
    io.println("  both were heard: {tally.keys == 2}")
  

    io.println("-- focus --")
    // Two text fields, because a field is the one control every platform here
    // lets take the keyboard: a phone has no Tab key and no focus ring, so
    // UIKit answers no to everything that is not text input. Driving focus
    // between two of them is the same on all four.
    var notes: widgets.TextField = widgets.TextField.of("")?
    root.add(notes)?
    notes.set_frame(geometry.Rect.of(10.0, 130.0, 200.0, 24.0))?

    app.router.on(field.handle(), events.EventKind.focus,
        fn(event: events.UiEvent) { tally.focused = tally.focused + 1 })
    app.router.on(field.handle(), events.EventKind.blur,
        fn(event: events.UiEvent) { tally.blurred = tally.blurred + 1 })
    app.router.on(notes.handle(), events.EventKind.focus,
        fn(event: events.UiEvent) { other.focused = other.focused + 1 })
    app.router.on(notes.handle(), events.EventKind.blur,
        fn(event: events.UiEvent) { other.blurred = other.blurred + 1 })

    // The field has the keyboard already — the key section above put it there,
    // which is what typing at a control means. Moving it and moving it back is
    // one blur and one focus on each.
    let moved_away: bool = took(notes.focus()) && notes.focused() && !field.focused()
    let moved_back: bool = took(field.focus()) && field.focused() && !notes.focused()

    io.println("  the keyboard moves from one field to another: {moved_away}")
    io.println("  and back: {moved_back}")
    io.println("  the one that took it is told: {tally.focused == 1 && other.focused == 1}")
    io.println("  and the one that lost it is told: {tally.blurred == 1 && other.blurred == 1}")

    // A button either takes it or says it cannot, which is a real platform
    // difference rather than a gap: a desktop has a Tab key and a focus ring
    // to reach and show it with, and a phone has neither.
    var button_took: bool = false
    var button_refused: bool = false
    match press.focus() {
        ok(done) => { button_took = press.focused() }
        err(problem) => { button_refused = problem.kind == "unsupported" }
    }
    io.println("  a button takes it, or says it cannot: {button_took != button_refused}")
    // A label cannot, anywhere. There is nothing to type into it.
    io.println("  a label cannot, on any platform: {refused_as(words.focus(), "unsupported")}")

    io.println("-- what nobody asked for --")
    // The one place cortado tells a host what it *wants* rather than what to
    // do. A count that rose on every `on` and never fell would leave every
    // host working forever for handlers that are gone.
    let watching: int = app.router.listening()
    app.router.forget(press.handle())
    app.router.forget(field.handle())
    app.router.forget(notes.handle())
    io.println("  a host is told which kinds are wanted: {watching > 0}")
    io.println("  and told again when the last handler goes: {app.router.listening() == 0}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
