// The differ, with no platform anywhere near it.
//
// Two `Element` trees in, a list of edits out. Everything here is values, so
// this program prints the same thing on macOS, Windows and Linux, under the
// tree interpreter and as a native binary. A change to the output is a change
// to the reconciler and can be nothing else.
//
// What the goldens are checking is not only *what* the edits are but *how many*:
// the cost of cortado's rendering is decided here. A render that moved one row
// must emit one move, not five sets, because a control that is rebuilt loses
// its focus, its text selection, its input-method session and its scroll
// position — all of which a person watches happen.
package main

import cortado.component
import cortado.events
import std.io

// ---- harness ----

fn show(name: string, before: Option<component.Element>, after: component.Element) {
    io.println("== {name} ==")
    var differ: component.Differ = new component.Differ()
    let changes: List<component.Change> = differ.diff(before, after)
    if changes.len() == 0 {
        io.println("  (nothing changed)")
        return
    }
    for change: component.Change in changes {
        io.println("  {change.show()}")
    }
}

fn built(body: fn(component.Builder)) -> component.Element {
    var into: component.Builder = new component.Builder()
    body(into)
    match into.finish() {
        ok(tree) => { return tree }
        err(problem) => {
            io.println("  BUILD FAILED {problem.kind}: {problem.msg}")
            return new component.Element(component.Vocabulary.kind_of("Label").expect("label"), "Label")
        }
    }
}

fn nothing() {}

// ---- 1. first render ----

fn first_render() {
    let tree: component.Element = built(fn(into: component.Builder) {
        into.open("VStack")
            into.open("Label")
            into.text("Order a coffee")
            into.close()
            into.open("Button")
            into.text("Buy")
            into.close()
        into.close()
    })
    show("first render is one create", none, tree)
}

// ---- 2. properties ----

fn properties() {
    let before: component.Element = built(fn(into: component.Builder) {
        into.open("Label")
        into.text("before")
        into.close()
    })
    let after: component.Element = built(fn(into: component.Builder) {
        into.open("Label")
        into.text("after")
        into.close()
    })
    show("text changed", some(before), after)

    let same: component.Element = built(fn(into: component.Builder) {
        into.open("Label")
        into.text("before")
        into.close()
    })
    show("nothing changed", some(before), same)

    let plain: component.Element = built(fn(into: component.Builder) {
        into.open("Button")
        into.text("Buy")
        into.close()
    })
    let off: component.Element = built(fn(into: component.Builder) {
        into.open("Button")
        into.text("Buy")
        into.flag("enabled", false)
        into.close()
    })
    show("a property appeared", some(plain), off)
    // The property going away must put the control back, not leave it
    // disabled for the life of the window.
    show("a property went away", some(off), plain)

    let sized: component.Element = built(fn(into: component.Builder) {
        into.open("Label")
        into.number("font_size", 13.0)
        into.close()
    })
    let bigger: component.Element = built(fn(into: component.Builder) {
        into.open("Label")
        into.number("font_size", 18.0)
        into.close()
    })
    show("a number changed", some(sized), bigger)
}

// ---- 3. listeners ----

fn listeners() {
    let quiet: component.Element = built(fn(into: component.Builder) {
        into.open("Button")
        into.text("Buy")
        into.close()
    })
    let live: component.Element = built(fn(into: component.Builder) {
        into.open("Button")
        into.text("Buy")
        into.on("click", fn(event: events.UiEvent) {})
        into.close()
    })
    show("a handler appeared", some(quiet), live)
    show("a handler went away", some(live), quiet)

    // Two renders both listening for the same event must emit nothing. The
    // closures differ — they always do — and a differ that compared them
    // would unsubscribe and resubscribe every handler sixty times a second.
    let again: component.Element = built(fn(into: component.Builder) {
        into.open("Button")
        into.text("Buy")
        into.on("click", fn(event: events.UiEvent) { io.print("") })
        into.close()
    })
    show("the same handler, a different closure", some(live), again)
}

// ---- 4. children ----

fn rows(names: List<string>, keyed: bool) -> component.Element {
    var into: component.Builder = new component.Builder()
    into.open("VStack")
    for name: string in names {
        into.open("Label")
        if keyed { into.key(name) }
        into.text(name)
        into.close()
    }
    into.close()
    match into.finish() {
        ok(tree) => { return tree }
        err(problem) => {
            io.println("  BUILD FAILED {problem.msg}")
            return new component.Element(component.Vocabulary.kind_of("Label").expect("label"), "Label")
        }
    }
}

fn children() {
    show("append one unkeyed child",
         some(rows(["a", "b"], false)), rows(["a", "b", "c"], false))
    show("remove the last unkeyed child",
         some(rows(["a", "b", "c"], false)), rows(["a", "b"], false))

    // Unkeyed, removing the FIRST of three: every row is told it is now the
    // row below, so two labels are rewritten and one is removed. This is the
    // cost keys exist to remove, and the golden records it so the comparison
    // with the keyed case below is visible.
    show("remove the first unkeyed child",
         some(rows(["a", "b", "c"], false)), rows(["b", "c"], false))

    show("remove the first keyed child",
         some(rows(["a", "b", "c"], true)), rows(["b", "c"], true))

    show("reorder keyed children",
         some(rows(["a", "b", "c"], true)), rows(["c", "a", "b"], true))

    show("insert into the middle, keyed",
         some(rows(["a", "c"], true)), rows(["a", "b", "c"], true))

    show("reverse keyed children",
         some(rows(["a", "b", "c"], true)), rows(["c", "b", "a"], true))

    show("replace every keyed child",
         some(rows(["a", "b"], true)), rows(["x", "y"], true))

    show("empty the list", some(rows(["a", "b"], true)), rows([], true))
    show("fill an empty list", some(rows([], true)), rows(["a", "b"], true))
}

// ---- 5. structure ----

fn structure() {
    let label: component.Element = built(fn(into: component.Builder) {
        into.open("Label")
        into.text("hello")
        into.close()
    })
    let button: component.Element = built(fn(into: component.Builder) {
        into.open("Button")
        into.text("hello")
        into.close()
    })
    // No platform turns a label into a button, so the old one goes.
    show("the root changed kind", some(label), button)

    let shallow: component.Element = built(fn(into: component.Builder) {
        into.open("VStack")
            into.open("Label")
            into.text("one")
            into.close()
        into.close()
    })
    let deep: component.Element = built(fn(into: component.Builder) {
        into.open("VStack")
            into.open("HStack")
                into.open("Label")
                into.text("one")
                into.close()
            into.close()
        into.close()
    })
    show("a child gained a wrapper", some(shallow), deep)

    let nested_before: component.Element = built(fn(into: component.Builder) {
        into.open("VStack")
            into.open("HStack")
                into.open("Label")
                into.text("one")
                into.close()
                into.open("Label")
                into.text("two")
                into.close()
            into.close()
        into.close()
    })
    let nested_after: component.Element = built(fn(into: component.Builder) {
        into.open("VStack")
            into.open("HStack")
                into.open("Label")
                into.text("one")
                into.close()
                into.open("Label")
                into.text("TWO")
                into.close()
            into.close()
        into.close()
    })
    show("a deep leaf changed", some(nested_before), nested_after)
}

// ---- 6. properties the goldens cannot check for themselves ----

fn checks() {
    io.println("== checks ==")

    // 1. Diffing a tree against itself must produce nothing at all. It is the
    //    property every other case rests on: if an unchanged render emitted
    //    even one edit, every frame would touch the platform.
    io.println("  a tree against itself is silent: {silent()}")

    // 2. Reordering keyed rows must move controls, never rebuild them. A
    //    differ that rebuilt would still look right in a screenshot and would
    //    drop the focus ring, the selection and the scroll position.
    io.println("  reordering keys creates nothing: {reorder_is_moves()}")

    // 3. Keys must actually earn their cost: removing the first of many rows
    //    has to be cheaper keyed than unkeyed, or there is no reason for them.
    io.println("  keys beat positions on a head removal: {keys_are_cheaper()}")

    // 4. Nothing may be created and then removed in the same batch, and no
    //    change may name a child index outside its parent.
    io.println("  no edit is wasted or out of range: {batch_is_sane()}")
}

fn silent() -> bool {
    let tree: component.Element = rows(["a", "b", "c"], true)
    var differ: component.Differ = new component.Differ()
    return differ.diff(some(tree), tree).len() == 0
}

fn reorder_is_moves() -> bool {
    var differ: component.Differ = new component.Differ()
    let changes: List<component.Change> = differ.diff(
        some(rows(["a", "b", "c", "d"], true)), rows(["d", "c", "b", "a"], true))
    if changes.len() == 0 { return false }
    for change: component.Change in changes {
        if change.kind == component.ChangeKind.create { return false }
        if change.kind == component.ChangeKind.remove { return false }
        if change.kind == component.ChangeKind.set { return false }
    }
    return true
}

fn keys_are_cheaper() -> bool {
    var keyed: component.Differ = new component.Differ()
    var loose: component.Differ = new component.Differ()
    let with_keys: int = keyed.diff(some(rows(["a", "b", "c", "d"], true)),
                                    rows(["b", "c", "d"], true)).len()
    let without: int = loose.diff(some(rows(["a", "b", "c", "d"], false)),
                                  rows(["b", "c", "d"], false)).len()
    return with_keys < without
}

fn batch_is_sane() -> bool {
    var differ: component.Differ = new component.Differ()
    let changes: List<component.Change> = differ.diff(
        some(rows(["a", "b", "c"], true)), rows(["c", "x", "a"], true))
    var created: int = 0
    var removed: int = 0
    for change: component.Change in changes {
        if change.kind == component.ChangeKind.create { created = created + 1 }
        if change.kind == component.ChangeKind.remove { removed = removed + 1 }
        if change.kind == component.ChangeKind.create ||
           change.kind == component.ChangeKind.remove ||
           change.kind == component.ChangeKind.relocate {
            if change.index < 0 { return false }
        }
    }
    // "b" goes, "x" arrives: exactly one of each, never a row built only to
    // be torn down.
    return created == 1 && removed == 1
}

fn main() {
    first_render()
    properties()
    listeners()
    children()
    structure()
    checks()
}
