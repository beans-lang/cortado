// One size bound at a time: `min_width`, `max_width`, `min_height` and
// `max_height`, from the attribute to the solved frame.
//
// `width={n}` always pinned both bounds. What was missing was a way to ask
// for one — a label that may shrink but not past 140, a card no wider than 200.
//
// Frames are solved against `TableMeasure`; nothing here needs a display.
package main

import cortado.component
import cortado.layout
import cortado.geometry
import std.io

// Every leaf measures 100 x 20, so a frame that moves between two cases
// moved because a bound did.
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

/// The four bounds the first child carries, `-1` where it has no opinion.
fn bounds_of(tree: component.Element) -> string {
    let spec: layout.LayoutSpec = tree.child_at(0).spec
    return "w {spec.min_width as int}..{spec.max_width as int}, h {spec.min_height as int}..{spec.max_height as int}"
}

/// The share the first child asks for on each axis, `-1` for none.
fn tree_share(tree: component.Element) -> string {
    let spec: layout.LayoutSpec = tree.child_at(0).spec
    return "w {spec.width_percent as int}%, h {spec.height_percent as int}%"
}

/// One stretching column holding one label, with `names` written on the
/// label in that order.
fn bounded(names: List<string>, values: List<f64>) -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open("VStack")
    into.word("align", "stretch")
    into.open("Label")
    into.text("inside")
    for index: int in 0..names.len() {
        into.number(names[index], values[index])
    }
    into.close()
    into.close()
    return into.finish()
}

/// A component's root placed in a column with one bound on the tag.
fn placed(name: string, value: f64) -> Result<component.Element> {
    var own: component.Builder = new component.Builder()
    own.open("HStack")
    own.close()
    let root: component.Element = own.finish()?
    var into: component.Builder = new component.Builder()
    into.open("VStack")
    into.embed(root).number(name, value)
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
    io.println("-- one bound, and the frame it moves --")
    let capped: component.Element = bounded(["max_width"], [60.0])?
    io.println("  max_width={60}: {bounds_of(capped)}")
    show("a label that measures 100 wide, capped at 60, stretched in 300", capped, 300.0, 100.0)
    let floored: component.Element = bounded(["min_width"], [140.0])?
    io.println("  min_width={140}: {bounds_of(floored)}")
    let squat: component.Element = bounded(["max_height"], [12.0])?
    io.println("  max_height={12}: {bounds_of(squat)}")
    show("a label that measures 20 tall, capped at 12", squat, 300.0, 100.0)
    let lofty: component.Element = bounded(["min_height"], [40.0])?
    io.println("  min_height={40}: {bounds_of(lofty)}")
    show("and one raised to 40", lofty, 300.0, 100.0)

    io.println("-- source order decides, bound by bound --")
    let pinned_then_capped: component.Element = bounded(["width", "max_width"], [150.0, 200.0])?
    io.println("  width={150} then max_width={200}: {bounds_of(pinned_then_capped)}")
    show("which stretches to the cap, not the pin", pinned_then_capped, 300.0, 100.0)
    let capped_then_pinned: component.Element = bounded(["max_width", "width"], [200.0, 150.0])?
    io.println("  max_width={200} then width={150}: {bounds_of(capped_then_pinned)}")
    show("which is pinned", capped_then_pinned, 300.0, 100.0)

    io.println("-- a range that ends up reversed --")
    refuse("min_width={200} max_width={100}", bounded(["min_width", "max_width"], [200.0, 100.0]), "at least 200 and at most 100")
    refuse("max_height={10} min_height={20}", bounded(["max_height", "min_height"], [10.0, 20.0]), "reversed")
    refuse("width={150} then min_width={200}", bounded(["width", "min_width"], [150.0, 200.0]), "at least 200 and at most 150")
    match bounded(["min_width", "max_width"], [100.0, 100.0]) {
        ok(tree) => { io.println("  but equal bounds are a pin, and fine: {bounds_of(tree)}") }
        err(problem) => { io.println("  equal bounds refused: {problem.msg}") }
    }

    io.println("-- on a component tag --")
    match placed("max_width", 200.0) {
        ok(tree) => { io.println("  max_width={200} places the root: {bounds_of(tree)}") }
        err(problem) => { io.println("  refused: {problem.msg}") }
    }

    io.println("-- a share of the room, and a shape --")
    let half: component.Element = bounded(["width_percent"], [50.0])?
    io.println("  width_percent={50} is kept as a share: {tree_share(half)}")
    show("half the width of a stretched 300", half, 300.0, 100.0)
    let shaped: component.Element = bounded(["width_percent", "aspect_ratio"], [50.0, 3.0])?
    show("half the width, three times as wide as tall", shaped, 300.0, 100.0)
    let floored_share: component.Element = bounded(["width_percent", "min_width"], [10.0, 80.0])?
    show("a tenth, but at least 80", floored_share, 300.0, 100.0)
    refuse("width_percent={150}", bounded(["width_percent"], [150.0]), "0 to 100")
    refuse("height_percent={-5}", bounded(["height_percent"], [0.0 - 5.0]), "0 to 100")
    refuse("width={100} then width_percent={50}", bounded(["width", "width_percent"], [100.0, 50.0]), "decided twice")
    refuse("width_percent={50} then width={100}", bounded(["width_percent", "width"], [50.0, 100.0]), "decided twice")
    refuse("aspect_ratio={0}", bounded(["aspect_ratio"], [0.0]), "above 0")
    match placed("aspect_ratio", 1.5) {
        ok(tree) => { io.println("  aspect_ratio={1.5} on a component tag: {tree.child_at(0).spec.aspect_ratio}") }
        err(problem) => { io.println("  refused: {problem.msg}") }
    }

    io.println("-- a bound inside a flexing row --")
    // Two that grow alike; one is capped, so the other takes what it left.
    var into: component.Builder = new component.Builder()
    into.open("HStack")
    into.open("Label")
    into.text("capped")
    into.number("grow", 1.0)
    into.number("max_width", 120.0)
    into.close()
    into.open("Label")
    into.text("free")
    into.number("grow", 1.0)
    into.close()
    into.close()
    let row: component.Element = into.finish()?
    show("two growing labels in 300, the first capped at 120", row, 300.0, 40.0)
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
