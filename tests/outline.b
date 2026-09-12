// A tree, and the one thing that makes it a tree rather than an indented list.
//
// **The control asks about the nodes it is showing and no others.** That is
// the whole claim, and this file is where it stops being one: the source
// counts every question it is asked, and opening one node of a tree a hundred
// thousand nodes wide costs the children of that node and nothing else.
//
// The other half is identity. A table's row 7 is row 7; a node stays the same
// node when something above it opens, and `selection` carries the node rather
// than the row — which is why a program that opens a folder does not find its
// selection pointing at a different thing.
//
// Cross-host, and every line is either cortado's own arithmetic or an
// agreement between what the source said and what the control answers back
// through its own data source. `native_cell` is that round trip.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import cortado.geometry
import std.io

/// A tree made up on demand, and a tally of what the platform asked.
///
/// Three levels, wide enough that reading all of it would show: 4 roots, 100
/// children each, 1000 grandchildren each — 400,004 nodes, of which this file
/// expects the control to ask about a few dozen.
///
/// The node number *is* the position: `1..4` are the roots, and a node's
/// children are derived from it by arithmetic, so nothing is stored and the
/// count of questions is the only thing that grows.
class Forest implements widgets.OutlineNodes {
    pub asked: int = 0
    pub cells: int = 0

    pub fn init() {}

    pub fn child_count(node: int) -> int {
        self.asked = self.asked + 1
        if node == 0 { return 4 }
        if node <= 4 { return 100 }
        if node <= 4 + 400 { return 1000 }
        return 0
    }

    pub fn child_at(node: int, index: int) -> int {
        self.asked = self.asked + 1
        if node == 0 { return index + 1 }
        // A child's number is its parent's block plus its position. Made up
        // rather than looked up, which is the point: there is no list.
        return node * 1000 + index + 1
    }

    pub fn expandable(node: int) -> bool {
        self.asked = self.asked + 1
        return node <= 4 + 400 * 1000
    }

    pub fn cell(node: int, column: int) -> string {
        self.cells = self.cells + 1
        if column == 0 { return "node {node}" }
        return "{node * 2}"
    }
}

/// What the router heard.
class Heard {
    pub count: int = 0
    pub last: int = 0
    pub fn init() {}
}

fn refused(answer: Result<bool>) -> bool {
    match answer {
        ok(done) => { return false }
        err(problem) => { return problem.kind == "out_of_range" }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let promised: bool = widgets.WidgetKind.outline_view.available()
    io.println("-- what this platform has --")
    io.println("  an outline is a control here exactly where the kind says so: {promised}")
    if !promised {
        // A host with no outline refuses by name and the file ends here.
        // Nothing below would be true of it, and printing that it was would be
        // worse than printing nothing.
        match widgets.OutlineView.of(["one"]) {
            ok(built) => { io.println("  but one was built anyway: true") }
            err(problem) => { io.println("  and building one is refused: {problem.kind == "no_such_control"}") }
        }
        app.shutdown()
        return ok(true)
    }

    var window: surface.Window = app.window(320.0, 240.0, "outline")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    // One column, because that is what every host with an outline has. A
    // SysTreeView32 has no columns at all, so a second is asked for below
    // where the answer may differ.
    var tree: widgets.OutlineView = widgets.OutlineView.of(["Name"])?
    root.add(tree)?
    tree.set_frame(geometry.Rect.of(0.0, 0.0, 300.0, 220.0))?

    let forest: Forest = new Forest()
    tree.set_source(forest)?

    io.println("-- the round trip --")
    // Out through the source, into the platform's own tree, and back. Node 1
    // is a root, so the control has it without anything being opened.
    let first: string = tree.native_cell(1, 0).or("?")
    io.println("  the platform answers what the source says: {first == "node 1"}")
    io.println("  and a node it is not showing is refused: {tree.native_cell(999999, 0).or("?") == "?"}")

    io.println("-- opening --")
    // The root is always open: its children are the top level, and a control
    // showing nothing would be one whose root was shut.
    io.println("  the root is open and cannot be closed: {tree.is_expanded(widgets.OutlineView.root()).or(false) && refused(tree.collapse(widgets.OutlineView.root()))}")
    io.println("  a node starts shut: {!tree.is_expanded(1).or(true)}")
    tree.expand(1)?
    io.println("  and opens: {tree.is_expanded(1).or(false)}")
    // Now that node 1 is open, its children are rows and can be asked about.
    io.println("  its children are now the control's: {tree.native_cell(1001, 0).or("?") == "node 1001"}")
    // A grandchild is not, because its parent is still shut — which is the
    // rule that makes a tree cheap, stated as a refusal.
    io.println("  a node inside a shut parent is not: {refused(tree.expand(1001001))}")
    tree.collapse(1)?
    io.println("  and closes again: {!tree.is_expanded(1).or(true)}")

    io.println("-- what it cost --")
    // The measurement this file exists for. Four roots and one opened node is
    // a few dozen questions; reading the tree would be four hundred thousand.
    // A comparison rather than a count, because the count names a platform:
    // AppKit asks about what it is about to draw, GTK realises a screenful,
    // and Windows fills a level when it opens.
    let spent: int = forest.asked
    io.println("  opening one node of 400,004 cost under a thousand questions: {spent < 1000}")
    io.println("  and it really is that big: {forest.child_count(0) * 100 * 1000 == 400000}")

    io.println("-- selection --")
    let tally: Heard = new Heard()
    app.router.on(tree.handle(), events.EventKind.selection,
        fn(event: events.UiEvent) {
            tally.count = tally.count + 1
            tally.last = event.index as int
        })
    let quiet_at: int = tally.count
    tree.select(2)?
    io.println("  a selected node reads back: {tree.selected().or(-1) == 2}")
    io.println("  and none of that was reported as the user's doing: {tally.count == quiet_at}")
    io.println("  the root means nothing is selected: {tree.select(widgets.OutlineView.root()).or(false) && tree.selected().or(-1) == widgets.OutlineView.root()}")
    io.println("  a node it is not showing is refused: {refused(tree.select(999999))}")

    io.println("-- a second column --")
    var gave_two: bool = false
    var said_cannot: bool = false
    match tree.set_columns(2) {
        ok(done) => { gave_two = tree.column_count() == 2 }
        err(problem) => { said_cannot = problem.kind == "unsupported" }
    }
    io.println("  a second column is given, or refused as unsupported: {gave_two != said_cannot}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
