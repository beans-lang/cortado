// A component tag inside a component tag: both asked for `c0`, so the inner got
// the outer's instance. Three deep with siblings, or a wrong scheme passes.
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

    pub fn init() {}

    pub fn joined() -> string {
        return self.words.join(",")
    }
}

class Leaf extends component.Component {
    pub word: string = "leaf"
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        match self.log {
            some(sheet) => { sheet.words.push(self.word) }
            none => {}
        }
        into.open("Label")
        into.text(self.word)
        into.close()
    }
}

/// The middle of the sandwich. Its component tag is `c0` in its own render,
/// exactly as its parent's is in that one.
class Middle extends component.Component {
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        let sheet: Option<Log> = self.log
        into.open("VStack")
        into.child<Leaf>("c0", fn(c: Leaf) {
            c.word = "inner"
            c.log = sheet
        })
        into.close()
    }
}

/// Two children of the same class side by side, so a scheme that qualified a
/// key by the class rather than by the site would collapse them into one.
class Pair extends component.Component {
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        let sheet: Option<Log> = self.log
        into.open("VStack")
        into.child<Leaf>("c0", fn(c: Leaf) {
            c.word = "left"
            c.log = sheet
        })
        into.child<Leaf>("c1", fn(c: Leaf) {
            c.word = "right"
            c.log = sheet
        })
        into.close()
    }
}

class Top extends component.Component {
    pub log: Option<Log> = none

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        let sheet: Option<Log> = self.log
        into.open("VStack")
        into.child<Middle>("c0", fn(c: Middle) { c.log = sheet })
        into.child<Pair>("c1", fn(c: Pair) { c.log = sheet })
        into.close()
    }
}

/// One key used twice for real. Still refused: scoping must not turn a genuine
/// collision into two components sharing an identity.
class Clashing extends component.Component {
    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.child<Leaf>("same", fn(c: Leaf) { c.word = "one" })
        into.child<Leaf>("same", fn(c: Leaf) { c.word = "two" })
        into.close()
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(240.0, 200.0, "Nested")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(240.0, 200.0))

    let sheet: Log = new Log()
    var top: Top = new Top()
    top.log = some(sheet)

    io.println("-- three deep, two wide --")
    match mount.show(top) {
        ok(done) => { io.println("  it mounted: true") }
        err(problem) => { io.println("  it mounted: false ({problem.kind}: {problem.msg})") }
    }

    // One word per Leaf, in tree order. A shared instance prints the same word
    // twice, or loses one.
    let once: string = sheet.joined()
    let three: bool = once == "inner,left,right"
    io.println("  every Leaf rendered once, as itself: {three}")
    io.println("  what they wrote: {once}")

    // Rendering again must find the same three instances rather than build new
    // ones. The words repeat because each keeps the parameter it was given.
    sheet.words = []
    mount.refresh()?
    let twice: string = sheet.joined()
    let same: bool = twice == "inner,left,right"
    io.println("  and the same three after a refresh: {same}")

    mount.close()?

    io.println("-- one key used twice in one render --")
    var second: component.Mount = new component.Mount(root, app.router)
    second.set_bounds(geometry.Size.of(240.0, 200.0))
    match second.show(new Clashing()) {
        ok(done) => { io.println("  was allowed, and should not have been") }
        err(problem) => { io.println("  refused: {problem.kind}") }
    }
    second.close()?

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
