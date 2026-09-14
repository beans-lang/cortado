// Per-edge padding and margin, from the attribute an author writes to the
// frame a child lands in.
//
// The engine took a lopsided `EdgeInsets` from the start (`tests/layout.b`);
// this holds the step before it: `padding_left={32}` reaching the arranger whole.
//
// Frames are solved against `TableMeasure`, so all four hosts print these
// bytes with no display and no foreign call.
package main

import cortado.component
import cortado.layout
import cortado.geometry
import std.io

// Every leaf measures 100 x 20, so a frame that moves between two cases
// moved because an inset did.
fn ruler() -> layout.TableMeasure {
    var table: layout.TableMeasure = new layout.TableMeasure()
    for key: int in 1..9 {
        table.put(key, 100.0, 20.0)
    }
    return table
}

/// Hands out leaf keys in render order, so `mirror` numbers leaves the way
/// a mount would.
class Keys {
    pub next: int = 1
}

/// A layout tree mirroring `element`, the way `Mount.node_for` builds one over
/// controls — here over the element's own arranger, so nothing needs a window.
fn mirror(element: component.Element, keys: Keys) -> layout.LayoutNode {
    match element.arranger {
        none => {
            var leaf: layout.LayoutNode = layout.LayoutNode.leaf(element.tag, keys.next)
            keys.next = keys.next + 1
            leaf.spec = element.spec
            return leaf
        }
        some(arranger) => {
            var group: layout.LayoutNode = layout.LayoutNode.group(element.tag, arranger)
            group.spec = element.spec
            for index: int in 0..element.count() {
                group.add(mirror(element.child_at(index), keys))
            }
            return group
        }
    }
}

/// Solves `tree` at `width` x `height` and prints every frame.
fn show(name: string, tree: component.Element, width: f64, height: f64) {
    io.println("== {name} ==")
    let root: layout.LayoutNode = mirror(tree, new Keys())
    var solver: layout.Solver = new layout.Solver(ruler())
    match solver.solve(root, geometry.Rect.of(0.0, 0.0, width, height)) {
        ok(done) => { io.print(layout.LayoutDump.tree(root)) }
        err(problem) => { io.println("  FAILED {problem.kind}: {problem.msg}") }
    }
}

/// The padding a container ended up with, as top,right,bottom,left.
fn padding_of(tree: component.Element) -> string {
    match tree.arranger {
        none => { return "no arranger" }
        some(arranger) => { return arranger.padding().show() }
    }
}

/// The margin the child at `index` carries, the same way round.
fn margin_of(tree: component.Element, index: int) -> string {
    return tree.child_at(index).spec.margin.show()
}

/// One container of `tag` holding one label, with `names` written on it in
/// that order. The order is the point: later attributes win, edge by edge.
fn padded(tag: string, names: List<string>, values: List<f64>) -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open(tag)
    into.word("align", "stretch")
    for index: int in 0..names.len() {
        into.number(names[index], values[index])
    }
    into.open("Label")
    into.text("inside")
    into.close()
    into.close()
    return into.finish()
}

/// A row of three labels, each carrying its own margins.
fn margined() -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open("HStack")
    into.number("spacing", 4.0)

    into.open("Label")
    into.text("hangs left")
    into.number("margin_left", 5.0)
    into.number("margin_right", 7.0)
    into.close()

    into.open("Label")
    into.text("sits low")
    into.number("margin_y", 3.0)
    into.close()

    // `margin` first, one edge after: three edges of 6 and one of 20.
    into.open("Label")
    into.text("one side wider")
    into.number("margin", 6.0)
    into.number("margin_left", 20.0)
    into.close()

    into.close()
    return into.finish()
}

/// A per-edge attribute on a `<Label>`, which has nothing inside it to pad.
fn on_a_leaf(name: string) -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open("VStack")
    into.open("Label")
    into.text("leaf")
    into.number(name, 3.0)
    into.close()
    into.close()
    return into.finish()
}

/// A component's root element, built by a builder of its own and embedded
/// later — the shape a `<Card margin_left={9} />` tag takes.
fn embedded(name: string, value: f64) -> Result<component.Element> {
    var own: component.Builder = new component.Builder()
    own.open("HStack")
    own.number(name, value)
    own.close()
    let subtree: component.Element = own.finish()?
    var into: component.Builder = new component.Builder()
    into.open("VStack")
    into.embed(subtree)
    into.close()
    return into.finish()
}

/// Reports a render that had to be refused, by what its message says.
fn refuse(what: string, outcome: Result<component.Element>, clue: string) {
    match outcome {
        ok(tree) => { io.println("  {what} was allowed, and should not have been") }
        err(problem) => {
            io.println("  {what} is refused: {problem.kind == "bad_render"}")
            io.println("  and the message says why: {problem.msg.contains(clue)}")
        }
    }
}

fn drive() -> Result<bool> {
    io.println("-- one edge at a time --")
    // Four different numbers, so an edge written to the wrong side shows.
    let four: component.Element = padded("VStack",
        ["padding_top", "padding_right", "padding_bottom", "padding_left"],
        [4.0, 8.0, 16.0, 32.0])?
    io.println("  the container keeps: {padding_of(four)}")
    show("four different edges, in a 300 x 100 column", four, 300.0, 100.0)

    io.println("-- one axis at a time --")
    let axes: component.Element = padded("VStack", ["padding_x", "padding_y"], [10.0, 3.0])?
    io.println("  the container keeps: {padding_of(axes)}")
    show("x and y, in a 300 x 100 column", axes, 300.0, 100.0)

    io.println("-- source order decides, edge by edge --")
    let base_then_sides: component.Element = padded("VStack", ["padding", "padding_x"], [8.0, 16.0])?
    io.println("  padding={8} then padding_x={16}: {padding_of(base_then_sides)}")
    let sides_then_base: component.Element = padded("VStack", ["padding_x", "padding"], [16.0, 8.0])?
    io.println("  padding_x={16} then padding={8}: {padding_of(sides_then_base)}")
    io.println("  and the two are not the same box: {padding_of(base_then_sides) != padding_of(sides_then_base)}")
    let stacked: component.Element = padded("VStack", ["padding_y", "padding_top"], [5.0, 12.0])?
    io.println("  padding_y={5} then padding_top={12}: {padding_of(stacked)}")
    show("padding={8} padding_x={16}", base_then_sides, 300.0, 100.0)

    io.println("-- every container that takes padding takes an edge of it --")
    for tag: string in ["HStack", "VFlex", "HFlex", "Grid", "Box"] {
        let one: component.Element = padded(tag, ["padding_left", "padding_top"], [11.0, 2.0])?
        io.println("  <{tag}> keeps: {padding_of(one)}")
    }

    io.println("-- margins --")
    let row: component.Element = margined()?
    io.println("  hangs left: {margin_of(row, 0)}")
    io.println("  sits low: {margin_of(row, 1)}")
    io.println("  one side wider: {margin_of(row, 2)}")
    show("three margined labels in a 400 x 60 row", row, 400.0, 60.0)

    io.println("-- a component's root keeps its edges when it is embedded --")
    match embedded("margin_left", 9.0) {
        ok(tree) => { io.println("  the embedded root carries: {margin_of(tree, 0)}") }
        err(problem) => { io.println("  refused: {problem.msg}") }
    }

    io.println("-- where nothing can be padded --")
    refuse("padding_left on a <Label>", on_a_leaf("padding_left"), "has no children to pad")
    refuse("padding_x on a <Label>", on_a_leaf("padding_x"), "has no children to pad")
    // A scroll view arranges one child and takes no padding at all, and a
    // per-edge form is refused with the same sentence the bare one gets.
    refuse("padding_top on a <ScrollView>",
           padded("ScrollView", ["padding_top"], [3.0]), "cannot be padded")
    // A margin is the child's own, so a leaf takes one edge of it gladly.
    match on_a_leaf("margin_top") {
        ok(tree) => { io.println("  but margin_top on a <Label> is its own to set: {margin_of(tree, 0)}") }
        err(problem) => { io.println("  margin_top on a <Label> refused: {problem.msg}") }
    }
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
