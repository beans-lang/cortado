// What a component tag may carry: the placements `Builder.child`, `show` and
// `embed` answer, from the attribute to the solved frame.
//
// A component renders into a builder of its own, so `<Tile margin_left={8}>`
// is the parent's to write, and lands on the child's root after it rendered.
//
// Frames are solved against `TableMeasure`; nothing here needs a display.
package main

import cortado.component
import cortado.layout
import cortado.geometry
import std.reflect
import std.io

// Every leaf measures 100 x 20, so a frame that moves between two cases
// moved because a placement did.
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

/// The spec the child at `index` carries, as the numbers a placement writes.
fn spec_of(tree: component.Element, index: int) -> layout.LayoutSpec {
    return tree.child_at(index).spec
}

/// A component's root, rendered by a builder of its own, with `names` written
/// on it by that render — the child's own word, before the parent's.
fn subtree(tag: string, names: List<string>, values: List<f64>) -> Result<component.Element> {
    var own: component.Builder = new component.Builder()
    own.open(tag)
    for index: int in 0..names.len() {
        own.number(names[index], values[index])
    }
    own.open("Label")
    own.text("inside")
    own.close()
    own.close()
    return own.finish()
}

/// `root` shown inside `parent`, with one number placed on the tag.
fn placed_in(parent: string, root: component.Element, name: string, value: f64) -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open(parent)
    into.embed(root).number(name, value)
    into.close()
    return into.finish()
}

/// The same, with one word placed on the tag.
fn worded_in(parent: string, root: component.Element, name: string, word: string) -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open(parent)
    into.embed(root).word(name, word)
    into.close()
    return into.finish()
}

/// A component with a public field named like a placement, and a private one.
class Chip extends component.Component {
    pub x: f64 = 0.0
    priv y: f64 = 0.0
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {
        into.open("HStack")
        into.close()
    }
}

/// A placement made the way `child<Chip>` makes one: with the class known.
fn placed_as(parent: string, root: component.Element, kind: reflect.Type,
             name: string, value: f64) -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open(parent)
    into.embed(root)
    var placement: component.Placement = new component.Placement(into, some(root), some(kind))
    placement.number(name, value)
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
    io.println("-- the parent's word comes last --")
    // The child's render wrote `margin={6}`; the tag writes one edge over it.
    let own: component.Element = subtree("HStack", ["margin"], [6.0])?
    let over: component.Element = placed_in("VStack", own, "margin_left", 20.0)?
    io.println("  margin={6} inside, margin_left={20} on the tag: {spec_of(over, 0).margin.show()}")
    let sides: component.Element = placed_in("VStack", subtree("HStack", [], [])?, "margin_x", 7.0)?
    io.println("  margin_x={7} on a tag with no margin of its own: {spec_of(sides, 0).margin.show()}")

    io.println("-- what a run hands out is checked against the run the tag sits in --")
    let flexed: component.Element = placed_in("VFlex", subtree("HStack", [], [])?, "grow", 1.0)?
    io.println("  grow={1} in a <VFlex>: {spec_of(flexed, 0).grow}")
    refuse("grow={1} in a <VStack>", placed_in("VStack", subtree("HStack", [], [])?, "grow", 1.0), "<VFlex>")
    let boxed: component.Element = placed_in("Box", subtree("HStack", [], [])?, "x", 44.0)?
    io.println("  x={44} in a <Box>: {spec_of(boxed, 0).x}")
    refuse("y={44} in an <HFlex>", placed_in("HFlex", subtree("HStack", [], [])?, "y", 44.0), "<Box>")

    io.println("-- width, height and align --")
    let wide: component.Element = placed_in("VStack", subtree("HStack", [], [])?, "width", 120.0)?
    io.println("  width={120} pins both bounds: {spec_of(wide, 0).min_width},{spec_of(wide, 0).max_width}")
    let tall: component.Element = placed_in("VStack", subtree("HStack", [], [])?, "height", 30.0)?
    io.println("  height={30} pins both bounds: {spec_of(tall, 0).min_height},{spec_of(tall, 0).max_height}")
    let centred: component.Element = worded_in("VStack", subtree("HStack", [], [])?, "align", "center")?
    io.println("  align=\"center\" is the child's own: {spec_of(centred, 0).align == geometry.Align.center}")
    refuse("align=\"middle\"", worded_in("VStack", subtree("HStack", [], [])?, "align", "middle"), "start, center, end, stretch")

    io.println("-- refused by name, with the reason --")
    refuse("padding on a tag", placed_in("VStack", subtree("HStack", [], [])?, "padding", 8.0), "is <HStack>'s own to set")
    refuse("spacing on a tag", placed_in("VStack", subtree("HStack", [], [])?, "spacing", 8.0), "own to set")
    refuse("justify on a tag", worded_in("VStack", subtree("HStack", [], [])?, "justify", "end"), "own to set")
    refuse("background on a tag", worded_in("VStack", subtree("HStack", [], [])?, "background", "#fff"), "is a control's property")
    refuse("font_size on a tag", placed_in("VStack", subtree("HStack", [], [])?, "font_size", 11.0), "is a control's property")
    refuse("a name nobody has", placed_in("VStack", subtree("HStack", [], [])?, "elevation", 2.0), "has no attribute called 'elevation'")

    io.println("-- a field of the same name --")
    // `Chip.x` is public and would be set by the same markup, so it is refused;
    // `Chip.y` is private, so `y=` can only mean the placement.
    refuse("x on a <Chip> with a public x", placed_as("Box", subtree("HStack", [], [])?, type_of(Chip), "x", 5.0), "<Chip> has a field called x")
    match placed_as("Box", subtree("HStack", [], [])?, type_of(Chip), "y", 5.0) {
        ok(tree) => { io.println("  y on a <Chip> whose y is private places it: {spec_of(tree, 0).y}") }
        err(problem) => { io.println("  y refused: {problem.msg}") }
    }

    io.println("-- two placements on one tag, solved --")
    var into: component.Builder = new component.Builder()
    into.open("VFlex")
    into.word("align", "stretch")
    into.embed(subtree("HStack", [], [])?).number("grow", 1.0)
    into.embed(subtree("HStack", [], [])?).number("height", 30.0).number("margin_top", 5.0)
    into.close()
    let column: component.Element = into.finish()?
    show("one that grows above one that is 30 tall with 5 above it, in 300 x 100", column, 300.0, 100.0)

    io.println("-- a root nothing contains yet --")
    // A render whose whole tree is one component tag: the placement waits on
    // the container this render is embedded in, the way its own `grow` would.
    var alone: component.Builder = new component.Builder()
    let root: component.Element = subtree("HStack", [], [])?
    alone.embed(root).number("grow", 1.0)
    let single: component.Element = alone.finish()?
    io.println("  the requirement is still open: {single.pending == "flex"}")
    io.println("  and it names the attribute that asked: {single.pending_name == "grow"}")
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
