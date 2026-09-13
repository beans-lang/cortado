// A component tag inside a component tag.
//
// `cortado-bx` numbers component tags from zero in every `render` it writes,
// so the first component tag in *any* `.bx` file is `c0`. The mount's map of
// prepared children was keyed by that string alone — one map for the whole
// mount — so a screen whose component contained a component had both asking
// for `c0`, and the inner one was handed the outer one's instance.
//
// It did not even reach the duplicate-key refusal. `obtain` looks in
// `prepared` first, found a component of the wrong class under `c0` and
// returned it, so the author was told `<Leaf> came back as something else` —
// a message about a downcast, for a mistake about identity.
//
// Nothing in this repository nested two component tags, which is the only
// reason it went unseen: `examples/markup/site/checkout.bx` has two of them as
// siblings, where the numbering already differs. The first `<Card>` with a
// `<Badge>` in it would have found this.
//
// So this case nests **three** deep and puts two siblings at the bottom: two
// levels would pass against a scheme that qualified a key with only the depth,
// and one child per level would pass against one that used only the class.
//
// Each component writes its own word into a shared log as it renders, so two
// tags sharing one instance shows up as the wrong words in the wrong order
// rather than only as a refusal — and the log names no platform class, so
// every host prints these same bytes.
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

/// A render that really does use one key twice. Still a mistake, and still
/// refused — scoping keys by the component that asked must not turn a genuine
/// collision into two components quietly sharing an identity.
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
