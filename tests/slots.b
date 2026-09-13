// A template a parent hands a component, and the component decides where it
// goes.
//
// `Builder.fragment(site, body)` is what `$slot` compiles to. The body is a
// `fn(Builder)` written in the **parent's** markup — `self` inside it is the
// parent — and run against the **placing** component's builder, so the
// controls it describes land wherever the child put its `$slot`.
//
// The whole of the difficulty is in the keys. cortado-bx numbers component
// tags from zero per render, and a fragment body restarts that numbering: the
// body is emitted in a counter scope of its own, so the first component tag
// inside any fragment body asks for the key `c0` — which is exactly what the
// placing component's own first component tag asks for. Two things go wrong
// without a scope, and neither of them is visible from one placement or one
// component:
//
//   * **One template placed twice is one child, not two.** Both placements ask
//     for `c0`, so the second finds the first's instance and they share state.
//   * **A component inside a fragment collides with a sibling outside it.**
//     The placing component's own `c0` and the body's `c0` are one key.
//
// So `fragment` qualifies every child key written while the body runs with
// `$f{site}/`, and that composes with `Mount.scoped_key`, which qualifies by
// the component whose render is running. The cases below are the ones that can
// tell a correct scope from a plausible one: the same template at two sites,
// a fragment beside siblings on **both** sides of it, a fragment placed inside
// a fragment, and a fragment placed once per row of a loop.
//
// The last of those is why the site is a string and not the sequence number
// alone. A `$slot` in a `$for` body is *one* emitted call run once per row, so
// its number is the same on every turn and only the row tells the turns apart
// — the identity a component tag inside a loop has carried from the start, and
// the one a `$slot` did not.
//
// Every component writes its own identity into a shared log as it renders, and
// an identity is taken from that log the first time a component renders — so
// two placements that really did build two components carry two numbers, and
// one component shared between two placements carries one. The log names no
// platform class, so every host prints these same bytes.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import std.io

/// Handlers and renders capture this rather than the thing they are attached
/// to, for the reason `tests/events.b` gives.
class Log {
    pub words: List<string> = []
    serial: int = 0

    pub fn init() {}

    /// The next identity. Taken once per component, the first time it renders.
    pub fn next() -> int {
        self.serial = self.serial + 1
        return self.serial
    }

    pub fn note(word: string) { self.words.push(word) }

    pub fn joined() -> string { return self.words.join(",") }

    pub fn clear() { self.words = [] }
}

/// A leaf that says who it is every time it renders.
class Counter extends component.Component {
    pub label: string = "?"
    pub log: Option<Log> = none
    serial: int = 0

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        match self.log {
            some(sheet) => {
                if self.serial == 0 { self.serial = sheet.next() }
                sheet.note("{self.label}#{self.serial}")
            }
            none => {}
        }
        into.open("Label")
        into.text("{self.label}#{self.serial}")
        into.close()
    }
}

// ------------------------------------------------- one template, two places

/// Places one template at two sites — what `<Twice>` would be in markup if it
/// wrote `$slot` twice.
///
/// This is the case the `seq` argument exists for. The two calls hold the same
/// closure; only the site number differs.
class Twice extends component.Component {
    pub body: fn(component.Builder) = fn(_b: component.Builder) {}

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.fragment("0", self.body)
        into.fragment("1", self.body)
        into.close()
    }
}

class TwiceScreen extends component.Component {
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        let sheet: Option<Log> = self.log
        into.open("VStack")
        into.child<Twice>("c0", fn(c: Twice) {
            c.body = fn(inner: component.Builder) {
                inner.child<Counter>("c0", fn(k: Counter) {
                    k.label = "body"
                    k.log = sheet
                })
            }
        })
        into.close()
    }
}

// ------------------------------------- a fragment with siblings either side

/// A component tag, a fragment, and another component tag — in that order.
///
/// The tags either side are what prove the scope is pushed *and* popped: the
/// one before it shares the body's `c0`, and the one after it would be
/// swallowed by a scope that was never taken off again.
class Host extends component.Component {
    pub body: fn(component.Builder) = fn(_b: component.Builder) {}
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        let sheet: Option<Log> = self.log
        into.open("VStack")
        into.child<Counter>("c0", fn(k: Counter) {
            k.label = "before"
            k.log = sheet
        })
        into.fragment("1", self.body)
        into.child<Counter>("c2", fn(k: Counter) {
            k.label = "after"
            k.log = sheet
        })
        into.close()
    }
}

class HostScreen extends component.Component {
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        let sheet: Option<Log> = self.log
        into.open("VStack")
        into.child<Host>("c0", fn(c: Host) {
            c.log = sheet
            // The body's own first tag is `c0`, the same string the host's own
            // first tag asks for.
            c.body = fn(inner: component.Builder) {
                inner.child<Counter>("c0", fn(k: Counter) {
                    k.label = "given"
                    k.log = sheet
                })
            }
        })
        into.close()
    }
}

// --------------------------------------------- a fragment inside a fragment

/// `<Twice> $slot </Twice>` written inside a component that itself takes a
/// slot: the relay hands its own template on, so the template is placed inside
/// a placement.
///
/// Both placements of the relay's body run the same inner `fragment("0", ...)`,
/// so without a *stack* of prefixes the inner placement would write one key
/// for both.
class Relay extends component.Component {
    pub body: fn(component.Builder) = fn(_b: component.Builder) {}

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.child<Twice>("c0", fn(c: Twice) {
            c.body = fn(inner: component.Builder) { inner.fragment("0", self.body) }
        })
        into.close()
    }
}

class RelayScreen extends component.Component {
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        let sheet: Option<Log> = self.log
        into.open("VStack")
        into.child<Relay>("c0", fn(c: Relay) {
            c.body = fn(inner: component.Builder) {
                inner.child<Counter>("c0", fn(k: Counter) {
                    k.label = "deep"
                    k.log = sheet
                })
            }
        })
        into.close()
    }
}

// ------------------------------------------- one template, once per row

/// A template placed on every row of a loop — a table whose cells the screen
/// draws.
///
/// One `fragment` call in the source, run once per turn, so the sequence
/// number in it is the same every time and the row is the only thing that
/// differs. cortado-bx writes the site with the row interpolated into it here,
/// which is the same two-part identity it has always given a component tag
/// inside a loop; `tests/markup_refusals.b` holds the emitter to that.
class Rows extends component.Component {
    pub cell: fn(component.Builder, string) = fn(_b: component.Builder, _t: string) {}
    pub items: List<string> = []

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        var row: int = 0
        for item: string in self.items {
            into.fragment("0.{row}", fn(inner: component.Builder) { self.cell(inner, item) })
            row += 1
        }
        into.close()
    }
}

class RowsScreen extends component.Component {
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        let sheet: Option<Log> = self.log
        into.open("VStack")
        into.child<Rows>("c0", fn(c: Rows) {
            c.items = ["one", "two", "three"]
            c.cell = fn(inner: component.Builder, item: string) {
                inner.child<Counter>("c0", fn(k: Counter) {
                    k.label = item
                    k.log = sheet
                })
            }
        })
        into.close()
    }
}

// --------------------------------------------------- a real duplicate still

/// One key used twice inside one fragment body. Scoping a key by its placement
/// must not turn a genuine collision into two components quietly sharing an
/// identity.
class Clashing extends component.Component {
    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.fragment("0", fn(inner: component.Builder) {
            inner.child<Counter>("same", fn(k: Counter) { k.label = "one" })
            inner.child<Counter>("same", fn(k: Counter) { k.label = "two" })
        })
        into.close()
    }
}

// --------------------------------------------------------------- the driver

/// The text of every control under `box`, in tree order.
///
/// The text and not a dump: a dump names the platform's own classes, and this
/// file is one every host has to print identically. What it proves is that the
/// fragment's controls really reached the tree, in the places the placing
/// component put them, and not only that the renders ran.
fn texts_in(box: widgets.Widget) -> string {
    let found: List<string> = []
    gather_text(box, found)
    return found.join(",")
}

fn gather_text(box: widgets.Widget, into: List<string>) {
    match box.display_text() {
        ok(text) => { if text != "" { into.push(text) } }
        err(problem) => { into.push("<{problem.kind}>") }
    }
    for child: widgets.Widget in box.children() {
        gather_text(child, into)
    }
}

fn mount_for(app: surface.Application, root: widgets.Container) -> component.Mount {
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(240.0, 200.0))
    return mount
}

fn show(what: string, mount: component.Mount, screen: component.Component) {
    match mount.show(screen) {
        ok(done) => { io.println("  {what} mounted: true") }
        err(problem) => { io.println("  {what} mounted: false ({problem.kind}: {problem.msg})") }
    }
}

/// Closes a mount, saying so rather than giving up the whole run.
fn close(what: string, mount: component.Mount) {
    match mount.close() {
        ok(done) => {}
        err(problem) => { io.println("  closing {what} failed: {problem.kind}") }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let sheet: Log = new Log()

    io.println("-- one template placed at two sites --")
    var window: surface.Window = app.window(240.0, 200.0, "Slots")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var twice: component.Mount = mount_for(app, root)
    var screen: TwiceScreen = new TwiceScreen()
    screen.log = some(sheet)
    show("two placements", twice, screen)
    // Two placements, two identities. One shared child writes one number twice.
    io.println("  what rendered: {sheet.joined()}")
    io.println("  two separate children: {sheet.joined() == "body#1,body#2"}")
    io.println("  what is on screen: {texts_in(root)}")
    // And each keeps the identity it took, rather than being rebuilt.
    //
    // Answered rather than propagated with `?`, and every section below does
    // the same: one section that gave up would take the four after it with it,
    // and a golden that stops at the first failure says nothing about whether
    // the other cases still hold.
    sheet.clear()
    match twice.refresh() {
        ok(done) => { io.println("  and the same two after a refresh: {sheet.joined() == "body#1,body#2"}") }
        err(problem) => { io.println("  the refresh failed: {problem.kind}: {problem.msg}") }
    }
    close("twice", twice)

    io.println("-- a fragment with a sibling tag on either side --")
    var window2: surface.Window = app.window(240.0, 200.0, "Slots")?
    var root2: widgets.Container = new widgets.Container()
    window2.set_root(root2)?
    var host: component.Mount = mount_for(app, root2)
    var host_screen: HostScreen = new HostScreen()
    host_screen.log = some(sheet)
    sheet.clear()
    show("host", host, host_screen)
    io.println("  what rendered: {sheet.joined()}")
    io.println("  three separate children: {sheet.joined() == "before#3,given#4,after#5"}")
    io.println("  what is on screen: {texts_in(root2)}")
    close("host", host)

    io.println("-- a fragment placed inside a fragment --")
    var window3: surface.Window = app.window(240.0, 200.0, "Slots")?
    var root3: widgets.Container = new widgets.Container()
    window3.set_root(root3)?
    var relay: component.Mount = mount_for(app, root3)
    var relay_screen: RelayScreen = new RelayScreen()
    relay_screen.log = some(sheet)
    sheet.clear()
    show("relay", relay, relay_screen)
    io.println("  what rendered: {sheet.joined()}")
    io.println("  two separate children: {sheet.joined() == "deep#6,deep#7"}")
    io.println("  what is on screen: {texts_in(root3)}")
    close("relay", relay)

    io.println("-- one template placed once per row of a loop --")
    var window5: surface.Window = app.window(240.0, 200.0, "Slots")?
    var root5: widgets.Container = new widgets.Container()
    window5.set_root(root5)?
    var rows: component.Mount = mount_for(app, root5)
    var rows_screen: RowsScreen = new RowsScreen()
    rows_screen.log = some(sheet)
    sheet.clear()
    show("rows", rows, rows_screen)
    io.println("  what rendered: {sheet.joined()}")
    io.println("  one child per row: {sheet.joined() == "one#8,two#9,three#10"}")
    io.println("  what is on screen: {texts_in(root5)}")
    close("rows", rows)

    io.println("-- one key used twice inside one fragment body --")
    var window4: surface.Window = app.window(240.0, 200.0, "Slots")?
    var root4: widgets.Container = new widgets.Container()
    window4.set_root(root4)?
    var clash: component.Mount = mount_for(app, root4)
    match clash.show(new Clashing()) {
        ok(done) => { io.println("  was allowed, and should not have been") }
        err(problem) => {
            io.println("  refused: {problem.kind}")
            let said: string = problem.msg
            io.println("  naming the key the author wrote: {said.contains("child \"same\"")}")
            io.println("  and no key the author did not write: {!said.contains("$f0")}")
        }
    }
    close("clash", clash)

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
