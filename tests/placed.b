// A <Box> puts the coordinate on the element, and every other container
// refuses it instead of ignoring it.
//
// Nothing here builds a control. Where a child *ends up* is AbsoluteLayout's
// job and `tests/layout.b` already holds it; what was untested is the step
// before — that `x={10}` in markup reaches `spec.x`, and that a coordinate
// written where nothing reads one is refused rather than dropped. Both are
// arithmetic on a described tree, so all four hosts print these bytes.
package main

import cortado.component
import cortado.layout
import std.io

/// One element with a coordinate on it, inside `parent`.
fn under(parent: string, name: string, value: f64) -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open(parent)
    into.open("Label")
    into.text("placed")
    into.number(name, value)
    into.close()
    into.close()
    return into.finish()
}

/// A component's root element, which has no parent while it is being built.
///
/// This is the shape a component tag takes: `<Swatch x={600} />` renders into a
/// builder of its own, so the container it lands in is not known until the
/// subtree is embedded.
fn subtree_with(name: string, value: f64) -> Result<component.Element> {
    var own: component.Builder = new component.Builder()
    own.open("HStack")
    own.number(name, value)
    own.close()
    return own.finish()
}

/// That subtree, placed inside `parent` the way `Builder.child` places one.
fn embedded_in(parent: string, name: string, value: f64) -> Result<component.Element> {
    let subtree: component.Element = subtree_with(name, value)?
    var into: component.Builder = new component.Builder()
    into.open(parent)
    into.embed(subtree)
    into.close()
    return into.finish()
}

/// Where the first child of `box` was told to sit.
fn corner_of(box: component.Element, index: int) -> string {
    if index >= box.count() { return "missing" }
    let spec: layout.LayoutSpec = box.child_at(index).spec
    return "{spec.x as int},{spec.y as int}"
}

/// Reports a render that had to be refused, by what its message says.
fn refuse(what: string, outcome: Result<component.Element>) {
    match outcome {
        ok(tree) => { io.println("  {what} was allowed, and should not have been") }
        err(problem) => {
            io.println("  {what} is refused: {problem.kind == "bad_render"}")
            io.println("  and the message says where it belongs: {problem.msg.contains("<Box>")}")
        }
    }
}

/// Four labels at four corners of one box, because four coordinates that were
/// all dropped to zero would satisfy a test built from one.
fn corners() -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open("Box")

    into.open("Label")
    into.text("north")
    into.number("x", 10.0)
    into.number("y", 4.0)
    into.close()

    into.open("Label")
    into.text("east")
    into.number("x", 130.0)
    into.number("y", 40.0)
    into.close()

    into.open("Label")
    into.text("south")
    into.number("x", 24.0)
    into.number("y", 90.0)
    into.close()

    into.open("Label")
    into.text("west")
    into.number("x", 0.0)
    into.number("y", 56.0)
    into.close()

    into.close()
    return into.finish()
}

fn drive() -> Result<bool> {
    io.println("-- four children of a box, at four coordinates --")
    let box: component.Element = corners()?
    io.println("  north: {corner_of(box, 0)}")
    io.println("  east: {corner_of(box, 1)}")
    io.println("  south: {corner_of(box, 2)}")
    io.println("  west: {corner_of(box, 3)}")
    let every: bool = corner_of(box, 0) == "10,4" &&
                      corner_of(box, 1) == "130,40" &&
                      corner_of(box, 2) == "24,90" &&
                      corner_of(box, 3) == "0,56"
    io.println("  each one carries what it was written: {every}")
    io.println("  and no two of them carry the same: {corner_of(box, 0) != corner_of(box, 1) && corner_of(box, 1) != corner_of(box, 2) && corner_of(box, 2) != corner_of(box, 3)}")

    io.println("-- a coordinate where nothing reads one --")
    refuse("x in a <VStack>", under("VStack", "x", 30.0))
    refuse("y in an <HFlex>", under("HFlex", "y", 30.0))
    refuse("x in a <Grid>", under("Grid", "x", 30.0))

    io.println("-- a component's root, which had no parent when it was written --")
    // The requirement is carried on the element and answered by `embed`. Before
    // that, a component tag could not take a coordinate at all, and neither
    // could it take `grow`: both were refused for sitting in a container the
    // component's own builder could not see.
    match embedded_in("Box", "x", 600.0) {
        ok(tree) => { io.println("  a <Box> takes it: {corner_of(tree, 0) == "600,0"}") }
        err(problem) => { io.println("  refused inside a <Box>: {problem.msg}") }
    }
    refuse("the same subtree in a <VStack>", embedded_in("VStack", "x", 600.0))
    match embedded_in("VFlex", "grow", 1.0) {
        ok(tree) => {
            io.println("  and a <VFlex> takes a grow from one: {tree.child_at(0).spec.grow == 1.0}")
        }
        err(problem) => { io.println("  grow refused inside a <VFlex>: {problem.msg}") }
    }

    io.println("-- and a root nothing contains at all --")
    // A screen's root is contained by nothing, so its requirement can never be
    // answered. `Mount.refresh` is where that is caught; this is the half of it
    // that needs no platform: the subtree is simply never embedded.
    match subtree_with("x", 18.0) {
        ok(tree) => {
            io.println("  the requirement is still open: {tree.pending == "place"}")
            io.println("  and it names the attribute that asked: {tree.pending_name == "x"}")
        }
        err(problem) => { io.println("  refused too early: {problem.msg}") }
    }
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
