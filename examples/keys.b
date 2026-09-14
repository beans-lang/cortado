// What the mouse and the keyboard are doing, said out loud.
//
//     beansc build examples/keys.b -o build/keys && ./build/keys
//
// A window that reports every pointer event, every keystroke and every move of
// the keyboard, in the words cortado uses for them. Click in it, type in it,
// press Tab — the line at the bottom says what just happened and which control
// it happened to.
//
// **This is the example for a set of events that existed on paper for a long
// time and were raised by nobody.** `pointer_down`, `key_down` and `focus` were
// declared in `src/cortado_host.h` from its first version; no host emitted one
// and no test asked. A program could hear that a button was pressed and could
// not hear *where*, what was typed into a field, or which control the keyboard
// was pointing at.
//
// Three things worth watching while it runs:
//
//   * **The position is in the control's own space.** Move the pointer to the
//     top-left corner of the box and it reads near 0, 0 — not the window's
//     corner and not the screen's. It is the same space `set_frame` uses.
//   * **A key that types nothing says which key it was**, and a key that types
//     says what it typed. There is no code here for the letter S: a code per
//     character is a keyboard layout written into a library, and what a program
//     wants about those keys is the text, already composed and already through
//     the input method.
//   * **Focus moves for two reasons and looks the same both ways.** Pressing
//     Tab and pressing the button below both report a blur and a focus, because
//     a handler should not have to care which one moved it.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io
import std.os

/// The last thing that happened, and how many things have.
class Log {
    pub said: string = "nothing yet — click, type, or press Tab"
    pub count: int = 0
    pub fn init() {}
}

/// A control and the name a person would call it, because a handle is a number
/// and "pointer_down on 4294967297" tells nobody anything.
class Named {
    pub what: widgets.Widget
    pub called: string = ""
    pub fn init(what: widgets.Widget, called: string) {
        self.what = what
        self.called = called
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(460.0, 300.0, "Keys and clicks")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var title: widgets.Label = widgets.Label.of("Click, type, or press Tab.")?
    var field: widgets.TextField = widgets.TextField.of("type here")?
    var notes: widgets.TextField = widgets.TextField.of("or here")?
    var press: widgets.Button = widgets.Button.of("Take the keyboard")?
    var said: widgets.Label = widgets.Label.of("")?

    root.add(title)?
    root.add(field)?
    root.add(notes)?
    root.add(press)?
    root.add(said)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(16.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?
    page.add(sheet.leaf("title", title))
    page.add(sheet.leaf("field", field))
    page.add(sheet.leaf("notes", notes))
    page.add(sheet.leaf("press", press))
    page.add(sheet.leaf("said", said))

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    let log: Log = new Log()
    var watched: List<Named> = []
    watched.push(new Named(field, "the first field"))
    watched.push(new Named(notes, "the second field"))
    watched.push(new Named(press, "the button"))

    // One handler per control per kind, which is what the router wants: a
    // handler is an ordinary function that takes the event, never a closure
    // over the control it is attached to — that is what keeps widgets and
    // handlers from forming a cycle the collector cannot see through.
    for one: Named in watched {
        let name: string = one.called
        app.router.on(one.what.handle(), events.EventKind.pointer_down,
            fn(event: events.UiEvent) {
                let x: int = event.position.x as int
                let y: int = event.position.y as int
                log.said = "{event.button().name()} button down on {name}, at {x}, {y}"
                log.count = log.count + 1
                said.set_text(log.said)
            })
        app.router.on(one.what.handle(), events.EventKind.key_down,
            fn(event: events.UiEvent) {
                // A key that types nothing has no text, and that is the whole
                // rule: cortado names the keys that mean the same thing on
                // every keyboard, and everything else says what it typed.
                var how: string = "the {event.key().name()} key"
                if event.text != "" { how = "\"{event.text}\"" }
                log.said = "{how} on {name}"
                log.count = log.count + 1
                said.set_text(log.said)
            })
        app.router.on(one.what.handle(), events.EventKind.focus,
            fn(event: events.UiEvent) {
                log.said = "the keyboard is on {name}"
                log.count = log.count + 1
                said.set_text(log.said)
            })
        app.router.on(one.what.handle(), events.EventKind.blur,
            fn(event: events.UiEvent) {
                log.said = "{name} gave the keyboard up"
                log.count = log.count + 1
                said.set_text(log.said)
            })
    }

    // The button does not carry a value; it moves the keyboard, which is the
    // one write in cortado that is deliberately *not* silent. Focus is not a
    // control's private state — it is one thing the whole window shares — so a
    // program that moves it has changed what every other control shows, and
    // the two controls involved are told.
    app.router.on(press.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            match field.focus() {
                ok(took) => {}
                err(problem) => { said.set_text("this platform said: {problem.msg}") }
            }
        })

    said.set_text(log.said)

    // `--dump` is the headless half: it drives the window with synthesised
    // input and prints what came back, so this file is checked by the suite
    // and not only by a person looking at it.
    var dumping: bool = false
    for arg: string in os.args() {
        if arg == "--dump" { dumping = true }
    }
    if dumping {
        press.click_as_user(geometry.Point.at(40.0, 14.0))?
        io.println("after a click: {log.said}")
        field.key_as_user(events.EventKind.key_down, events.Key.escape, "", 0)?
        io.println("after escape:  {log.said}")
        field.key_as_user(events.EventKind.key_down, events.Key.character, "s", 0)?
        io.println("after typing:  {log.said}")
        notes.focus()?
        io.println("after a move:  {log.said}")
        io.println("things heard:  {log.count > 0}")
        app.shutdown()
        return ok(true)
    }

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
