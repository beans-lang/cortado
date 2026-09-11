// The applier, against real controls, on generated input.
//
// `tests/sweep.b` checks the differ: that a change list, applied to the old
// tree, reaches the new one. It does that with a reference applier written
// inside the test, so it runs anywhere and proves nothing about the applier
// that actually exists.
//
// This is the other side. It takes the same kind of generated tree pairs and
// drives `component.Applier` — the one that makes and moves real AppKit
// controls — down two different roads to the same place:
//
//   * **incrementally**: build `before`, then apply the diff to `after`;
//   * **from scratch**: build `after` directly, in a second container.
//
// Then it reads both *real widget trees* back off the platform and requires
// them to be identical. Nothing in this file describes what the answer should
// look like, which is the point: the assertion is that the cheap path and the
// obvious path agree, and any way the applier can mis-address a child, drop a
// property or lose an order breaks it.
//
// This needs a platform host, so unlike the sweep it is a macOS leg rather
// than a portable one.
//
// The tree generator here is deliberately *not* the one in `tests/sweep.b`:
// this one may only emit attributes a given control can really hold — a
// slider has a value and a label does not — because the applier talks to the
// platform and the platform refuses the rest. The differ has no such limit,
// which is why the two files generate differently.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.events
import cortado.host
import std.io

// ------------------------------------------------------------------ random

class Random {
    state: int = 1

    pub fn init(seed: int) {
        self.state = seed
        if self.state == 0 { self.state = 0x9e3779b9 }
    }

    pub fn next() -> int {
        var x: int = self.state
        x = x ^ (x << 13)
        x = x ^ ((x >> 7) & 0x01ffffffffffffff)
        x = x ^ (x << 17)
        self.state = x
        if x < 0 { return -(x + 1) }
        return x
    }

    pub fn below(bound: int) -> int {
        if bound <= 1 { return 0 }
        return self.next() % bound
    }

    pub fn chance(percent: int) -> bool {
        return self.below(100) < percent
    }
}

fn tags() -> List<string> {
    return ["Label", "Button", "TextField", "CheckBox", "Slider"]
}

fn words() -> List<string> {
    return ["flat", "white", "long", "black", "short", "hot"]
}

/// A control of a random kind, carrying only properties that kind can hold.
fn leaf(dice: Random, key: string) -> component.Element {
    let tag: string = tags()[dice.below(tags().len())]
    let kind: widgets.WidgetKind =
        component.Vocabulary.kind_of(tag).expect("every tag in tags() is a widget")
    var made: component.Element = new component.Element(kind, tag)
    made.key = key
    if tag != "Slider" && dice.chance(75) {
        made.set(component.Attribute.of_text(words()[dice.below(words().len())]))
    }
    if dice.chance(40) {
        made.set(component.Attribute.of_flag(host.P_ENABLED, dice.chance(50)))
    }
    if tag == "Slider" && dice.chance(60) {
        made.set(component.Attribute.of_real(host.P_VALUE, dice.below(100) as f64))
    }
    if dice.chance(35) {
        made.set(component.Attribute.of_flag(host.P_HIDDEN, dice.chance(40)))
    }
    if dice.chance(45) {
        made.listen(events.EventKind.activate, fn(event: events.UiEvent) {})
    }
    return made
}

fn grow(dice: Random, depth: int, names: Random) -> component.Element {
    let kind: widgets.WidgetKind =
        component.Vocabulary.kind_of("VStack").expect("VStack is a container")
    var box: component.Element = new component.Element(kind, "VStack")
    let width: int = 1 + dice.below(4)
    for slot: int in 0..width {
        var key: string = ""
        if dice.chance(85) { key = "k{names.next() % 500}" }
        if depth > 0 && dice.chance(30) {
            var inner: component.Element = grow(dice, depth - 1, names)
            inner.key = key
            box.add(inner)
        } else {
            box.add(leaf(dice, key))
        }
    }
    return box
}

/// Whether this element is one that can hold children and be laid out — which
/// is also the one that has no enabled state, because a plain view has none.
///
/// The generator has to know this and the differ does not: a render that puts
/// a child inside a `Label`, or asks a `VStack` to be disabled, is a program
/// cortado refuses by name — `a CheckBox cannot hold any children`, `that
/// widget does not have this property` — and a generator that produced them
/// would be testing the refusals rather than the applier.
fn is_box(element: component.Element) -> bool {
    return element.kind == widgets.WidgetKind.container
}

fn mutate(dice: Random, element: component.Element, names: Random) -> component.Element {
    var copy: component.Element = new component.Element(element.kind, element.tag)
    copy.key = element.key
    var drop_attribute: int = -1
    if element.attribute_count() > 0 && dice.chance(35) {
        drop_attribute = dice.below(element.attribute_count())
    }
    for index: int in 0..element.attribute_count() {
        if index != drop_attribute { copy.set(element.attribute_at(index)) }
    }
    var drop_listener: int = -1
    if element.listener_count() > 0 && dice.chance(30) {
        drop_listener = dice.below(element.listener_count())
    }
    for index: int in 0..element.listener_count() {
        if index != drop_listener {
            copy.listen(element.listener_at(index).kind, fn(event: events.UiEvent) {})
        }
    }

    var kept: List<component.Element> = []
    for child: component.Element in element.children() { kept.push(child) }

    // A leaf has no children to shuffle and no enabled state to write, so the
    // only mutation left for one is the attributes copied above.
    var action: int = 6
    if is_box(element) { action = dice.below(7) }
    if action == 0 && kept.len() >= 2 {
        let a: int = dice.below(kept.len())
        let b: int = dice.below(kept.len())
        let held: component.Element = kept[a]
        kept[a] = kept[b]
        kept[b] = held
    } else if action == 1 {
        kept.push(leaf(dice, "k{names.next() % 500}"))
    } else if action == 2 && kept.len() > 0 {
        let drop: int = dice.below(kept.len())
        var trimmed: List<component.Element> = []
        var at: int = 0
        for child: component.Element in kept {
            if at != drop { trimmed.push(child) }
            at = at + 1
        }
        kept = move trimmed
    } else if action == 3 && kept.len() > 0 {
        // Written on a child rather than on the box: a container has no
        // enabled state on any platform cortado targets.
        let who: int = dice.below(kept.len())
        if !is_box(kept[who]) {
            var touched: component.Element = mutate(dice, kept[who], names)
            touched.set(component.Attribute.of_flag(host.P_ENABLED, dice.chance(50)))
            kept[who] = touched
        }
    } else if action == 6 && kept.len() > 0 {
        // Give a child a listener it did not have. Without this the diff never
        // has one to add — the copy above keeps every listener an element
        // already carried — and `bind` was reached zero times in 120 cases.
        let who: int = dice.below(kept.len())
        var listening: component.Element = mutate(dice, kept[who], names)
        listening.listen(events.EventKind.value_changed, fn(event: events.UiEvent) {})
        kept[who] = listening
    } else if action == 4 && kept.len() > 0 {
        let spot: int = dice.below(kept.len())
        var spliced: List<component.Element> = []
        var at: int = 0
        for child: component.Element in kept {
            if at == spot { spliced.push(leaf(dice, "k{names.next() % 500}")) }
            spliced.push(child)
            at = at + 1
        }
        kept = move spliced
    }

    for child: component.Element in kept {
        if dice.chance(35) {
            copy.add(mutate(dice, child, names))
        } else {
            copy.add(child)
        }
    }
    return copy
}

// ------------------------------------------------- reading the real tree back

/// What the platform says it has, in cortado's own vocabulary. Nothing the
/// platform names, because this compares a tree with a tree and not with a
/// recorded file.
fn describe(widget: widgets.Widget, depth: int) -> Result<string> {
    var indent: string = ""
    for level: int in 0..depth { indent = "{indent}  " }
    var line: string = "{indent}{widget.kind().name()} \"{widget.display_text()?}\""
    match widget.is_enabled() {
        ok(on) => { if !on { line = "{line} disabled" } }
        err(absent) => {}
    }
    match widget.is_hidden() {
        ok(gone) => { if gone { line = "{line} hidden" } }
        err(absent) => {}
    }
    var out: string = "{line}\n"
    for child: widgets.Widget in widget.children() {
        out = "{out}{describe(child, depth + 1)?}"
    }
    return ok(out)
}

/// Applies a whole render into a fresh container and answers what the platform
/// ended up with.
fn realize(into: widgets.Container, tree: component.Element) -> Result<bool> {
    var router: events.EventRouter = new events.EventRouter()
    var owner: component.Mount = new component.Mount(into, router)
    var applier: component.Applier = new component.Applier(into, router, owner)
    var differ: component.Differ = new component.Differ()
    applier.apply(differ.diff(none, tree))?
    return ok(true)
}

/// What the incremental road actually had to do.
///
/// In the golden on purpose: a run that generated no moves would pass while
/// testing nothing about the operation keys exist for, and a green number is
/// not evidence until you can see what it covered.
class Tally {
    pub counts: List<int> = [0, 0, 0, 0, 0, 0]

    pub fn init() {}

    pub fn add(kind: component.ChangeKind) {
        let slot: int = index_of(kind)
        self.counts[slot] = self.counts[slot] + 1
    }

    pub fn show() -> string {
        return "create={self.counts[0]} remove={self.counts[1]} move={self.counts[2]} set={self.counts[3]} bind={self.counts[4]} unbind={self.counts[5]}"
    }
}

fn index_of(kind: component.ChangeKind) -> int {
    match kind {
        create => { return 0 }
        remove => { return 1 }
        relocate => { return 2 }
        set => { return 3 }
        bind => { return 4 }
        unbind => { return 5 }
    }
}

fn one_case(seed: int, tally: Tally) -> Result<bool> {
    var dice: Random = new Random(seed)
    var names: Random = new Random(seed * 7919 + 13)
    let before: component.Element = grow(dice, 2, names)
    let after: component.Element = mutate(dice, before, names)

    // The incremental road: build `before`, then apply the difference.
    var stepwise: widgets.Container = new widgets.Container()
    var router: events.EventRouter = new events.EventRouter()
    var owner: component.Mount = new component.Mount(stepwise, router)
    var applier: component.Applier = new component.Applier(stepwise, router, owner)
    var differ: component.Differ = new component.Differ()
    applier.apply(differ.diff(none, before))?
    let edits: List<component.Change> = differ.diff(some(before), after)
    for change: component.Change in edits { tally.add(change.kind) }
    applier.apply(edits)?

    // The obvious road: build `after` and nothing else.
    var direct: widgets.Container = new widgets.Container()
    realize(direct, after)?

    let updated: string = describe(stepwise, 0)?
    let fresh: string = describe(direct, 0)?
    if updated != fresh {
        io.println("FAULT seed={seed}: updating did not reach what building gives")
        io.println("-- after an update --")
        io.print(updated)
        io.println("-- built directly --")
        io.print(fresh)
        return ok(false)
    }
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    let cases: int = 120
    var faults: int = 0
    var tally: Tally = new Tally()
    for seed: int in 1..cases + 1 {
        match one_case(seed, tally) {
            ok(clean) => { if !clean { faults = faults + 1 } }
            err(problem) => {
                io.println("FAULT seed={seed}: {problem.kind}: {problem.msg}")
                faults = faults + 1
            }
        }
    }
    io.println("applied: {cases} cases, {faults} faults")
    io.println("edits: {tally.show()}")
    app.shutdown()
    return ok(true)
}
