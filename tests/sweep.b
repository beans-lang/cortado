// The reconciler, checked against an independent implementation of itself.
//
// `tests/diff.b` holds hand-written cases and says what the differ emits for
// each. That is the readable half and it is not the whole job: hand-written
// cases test the shapes somebody thought of, and a reconciler's bugs live in
// the shapes nobody did — a keyed row moved past an unkeyed one, a removal
// that renumbers a later move, an insert at the position a move is about to
// vacate.
//
// So this is the other half. It builds random trees, mutates them randomly,
// asks the differ for the edits, and then **applies those edits with a second
// implementation written here** — one that shares no line of code with
// `component.Applier` and does not know how the differ works. If the result is
// not the tree the differ was asked to reach, the edit list is wrong, and it
// says which seed produced it.
//
// The contract being checked is exactly one sentence: *applying a diff to the
// old tree must produce the new tree.* Everything a reconciler can get wrong
// breaks it.
//
// There is no platform anywhere in here, so it runs on every machine under
// both backends, and a failure is the reconciler and can be nothing else.
package main

import cortado.component
import cortado.widgets
import cortado.events
import std.io

// ---------------------------------------------------------------- the random
//
// Written here rather than taken from std, because the seed has to be part of
// the output: a sweep that cannot be replayed reports a failure nobody can
// reproduce. xorshift64* is four lines and its sequence is the same on every
// platform and in both backends, which a library's may not be.

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
        // The sign bit is dropped rather than masked off later, so every
        // caller gets a non-negative number and nobody has to remember.
        if x < 0 { return -(x + 1) }
        return x
    }

    /// A number in 0..bound.
    pub fn below(bound: int) -> int {
        if bound <= 1 { return 0 }
        return self.next() % bound
    }

    pub fn chance(percent: int) -> bool {
        return self.below(100) < percent
    }
}

// ------------------------------------------------------------- the mirror
//
// What a platform tree would look like, as plain values. This is the reference
// applier: it is told what changed and does the obvious thing, with none of
// `component.Applier`'s knowledge of handles, routers or widget makers, and
// none of the differ's knowledge of how the list was produced.

class Mirror {
    pub kind: widgets.WidgetKind = widgets.WidgetKind.container
    pub key: string = ""
    /// property:kind=value, one per line, in the order they were written.
    pub attributes: List<string> = []
    /// The event kinds currently subscribed, in the order they were bound.
    pub events: List<string> = []
    pub children: List<Mirror> = []

    pub fn init(kind: widgets.WidgetKind, key: string) {
        self.kind = kind
        self.key = key
    }

    /// Writes one property.
    ///
    /// A property written back to its default is **not** a property that is
    /// set: a platform control has every property at its default the moment it
    /// is made, and there is no operation that unsets one. So the differ says
    /// "this went away" by writing the default, and this drops it — which is
    /// the whole reason the model records properties rather than a log of
    /// writes. Modelling the write log instead made a control that had been
    /// disabled and re-enabled look different from one that never was.
    pub fn write(line: string) {
        let name: string = property_name(line)
        let is_default: bool = line == default_line(name)
        var rebuilt: List<string> = []
        var replaced: bool = false
        for existing: string in self.attributes {
            if property_name(existing) == name {
                if !is_default { rebuilt.push(line) }
                replaced = true
            } else {
                rebuilt.push(existing)
            }
        }
        if !replaced && !is_default { rebuilt.push(line) }
        self.attributes = move rebuilt
    }

    pub fn bind(name: string) {
        for existing: string in self.events {
            if existing == name { return }
        }
        self.events.push(name)
    }

    pub fn unbind(name: string) {
        var kept: List<string> = []
        for existing: string in self.events {
            if existing != name { kept.push(existing) }
        }
        self.events = move kept
    }

    pub fn insert(index: int, child: Mirror) {
        var rebuilt: List<Mirror> = []
        var at: int = 0
        for existing: Mirror in self.children {
            if at == index { rebuilt.push(child) }
            rebuilt.push(existing)
            at = at + 1
        }
        if index >= at { rebuilt.push(child) }
        self.children = move rebuilt
    }

    pub fn detach(index: int) -> Option<Mirror> {
        var rebuilt: List<Mirror> = []
        var taken: Option<Mirror> = none
        var at: int = 0
        for existing: Mirror in self.children {
            if at == index { taken = some(existing) } else { rebuilt.push(existing) }
            at = at + 1
        }
        self.children = move rebuilt
        return taken
    }
}

/// The "property:kind" half of a serialized attribute, which is what decides
/// whether a write replaces an earlier one.
fn property_name(line: string) -> string {
    var cut: int = line.len()
    var index: int = 0
    for character: string in line.chars() {
        if character == "=" { cut = index; break }
        index = index + 1
    }
    return line.slice(0, cut)
}

/// What `Attribute.default_for` serializes to, for a "property:kind" name.
fn default_line(name: string) -> string {
    var cut: int = name.len()
    var index: int = 0
    for character: string in name.chars() {
        if character == ":" { cut = index; break }
        index = index + 1
    }
    let property: int = name.slice(0, cut).to_int().expect("a serialized property is a number")
    let kind_name: string = name.slice(cut + 1, name.len())
    var kind: component.AttributeKind = component.AttributeKind.flag
    if kind_name == "text" { kind = component.AttributeKind.text }
    if kind_name == "whole" { kind = component.AttributeKind.whole }
    if kind_name == "real" { kind = component.AttributeKind.real }
    return attribute_line(component.Attribute.default_for(property, kind))
}

fn attribute_line(attribute: component.Attribute) -> string {
    match attribute.kind {
        text => { return "{attribute.property}:text={attribute.text}" }
        whole => { return "{attribute.property}:whole={attribute.whole}" }
        real => { return "{attribute.property}:real={attribute.number}" }
        flag => { return "{attribute.property}:flag={attribute.is_on()}" }
    }
}

/// A mirror of an element and everything under it — what a first render of
/// that element would leave behind.
fn mirror_of(element: component.Element) -> Mirror {
    var made: Mirror = new Mirror(element.kind, element.key)
    for index: int in 0..element.attribute_count() {
        made.write(attribute_line(element.attribute_at(index)))
    }
    for index: int in 0..element.listener_count() {
        made.bind(element.listener_at(index).kind.name())
    }
    for child: component.Element in element.children() {
        made.children.push(mirror_of(child))
    }
    return made
}

fn show_mirror(node: Mirror, depth: int) -> string {
    var indent: string = ""
    for level: int in 0..depth { indent = "{indent}  " }
    var line: string = "{indent}{node.kind.name()} key={node.key}"
    // Sorted, because the order properties were written in is not something a
    // platform control remembers or a program can observe. Comparing the
    // write order would fail two trees that are identical on screen.
    var attributes: List<string> = []
    for attribute: string in node.attributes { attributes.push(attribute) }
    attributes.sort()
    var subscribed: List<string> = []
    for event: string in node.events { subscribed.push(event) }
    subscribed.sort()
    for attribute: string in attributes { line = "{line} [{attribute}]" }
    for event: string in subscribed { line = "{line} <{event}>" }
    var out: string = "{line}\n"
    for child: Mirror in node.children {
        out = "{out}{show_mirror(child, depth + 1)}"
    }
    return out
}

// --------------------------------------------------------- applying an edit
//
// The reference applier. It walks the path, does what the change says, and
// knows nothing else.

fn walk(root: Mirror, change: component.Change) -> Option<Mirror> {
    var here: Mirror = root
    for level: int in 0..change.depth() {
        let step: int = change.step(level)
        if step < 0 || step >= here.children.len() { return none }
        here = here.children[step]
    }
    return some(here)
}

fn apply_one(root: Mirror, change: component.Change) -> Result<bool> {
    // A change at the surface acts on the root itself, which is the one place
    // the element tree's parent is not an element.
    var owner: Mirror = root
    if !change.at_surface {
        match walk(root, change) {
            some(found) => { owner = found }
            none => { return err("path {change.path_text()} names no node", "lost_path") }
        }
    }
    match change.kind {
        create => {
            match change.element {
                some(built) => {
                    owner.insert(change.index, mirror_of(built))
                    return ok(true)
                }
                none => { return err("create carried no element", "empty_create") }
            }
        }
        remove => {
            match owner.detach(change.index) {
                some(gone) => { return ok(true) }
                none => { return err("remove named child {change.index} of {owner.children.len()}", "bad_index") }
            }
        }
        relocate => {
            match owner.detach(change.index) {
                some(moving) => {
                    owner.insert(change.target, moving)
                    return ok(true)
                }
                none => { return err("move named child {change.index} of {owner.children.len()}", "bad_index") }
            }
        }
        set => {
            owner.write(attribute_line(change.attribute))
            return ok(true)
        }
        bind => {
            owner.bind(change.event.name())
            return ok(true)
        }
        unbind => {
            owner.unbind(change.event.name())
            return ok(true)
        }
    }
}

// ------------------------------------------------------------ random trees

// Functions rather than module constants: a constant in Beans is a number, a
// bool or a string, and these are the three vocabularies the sweep draws from.
fn kinds() -> List<string> {
    return ["Label", "Button", "TextField", "CheckBox", "Slider"]
}

fn words() -> List<string> {
    return ["flat", "white", "long", "black", "short", "hot"]
}

fn event_names() -> List<string> {
    return ["activate", "value_changed", "text_commit", "focus"]
}

fn event_named(name: string) -> events.EventKind {
    match name {
        "activate" => { return events.EventKind.activate }
        "value_changed" => { return events.EventKind.value_changed }
        "text_commit" => { return events.EventKind.text_commit }
        _ => { return events.EventKind.focus }
    }
}

fn leaf(dice: Random, key: string) -> component.Element {
    let tag: string = kinds()[dice.below(kinds().len())]
    let kind: widgets.WidgetKind =
        component.Vocabulary.kind_of(tag).expect("every tag in kinds() is a widget")
    var made: component.Element = new component.Element(kind, tag)
    made.key = key
    decorate(dice, made)
    return made
}

fn decorate(dice: Random, element: component.Element) {
    if dice.chance(70) {
        element.set(component.Attribute.of_text(words()[dice.below(words().len())]))
    }
    if dice.chance(40) {
        element.set(component.Attribute.of_flag(2, dice.chance(50)))
    }
    if dice.chance(30) {
        element.set(component.Attribute.of_real(6, dice.below(100) as f64))
    }
    if dice.chance(50) {
        let name: string = event_names()[dice.below(event_names().len())]
        element.listen(event_named(name), fn(event: events.UiEvent) {})
    }
}

fn grow(dice: Random, depth: int, names: Random) -> component.Element {
    let kind: widgets.WidgetKind =
        component.Vocabulary.kind_of("VStack").expect("VStack is a container")
    var box: component.Element = new component.Element(kind, "VStack")
    let width: int = dice.below(5)
    for slot: int in 0..width {
        // Some children are keyed and some are not, deliberately mixed: a
        // keyed element beside an unkeyed one is where a reconciler's matching
        // is hardest and where hand-written cases run out first.
        var key: string = ""
        if dice.chance(60) { key = "k{names.next() % 1000}" }
        if depth > 0 && dice.chance(35) {
            var inner: component.Element = grow(dice, depth - 1, names)
            inner.key = key
            box.add(inner)
        } else {
            box.add(leaf(dice, key))
        }
    }
    return box
}

/// A copy of `element` with something changed somewhere under it.
fn mutate(dice: Random, element: component.Element, names: Random) -> component.Element {
    var copy: component.Element = new component.Element(element.kind, element.tag)
    copy.key = element.key
    // One attribute may be dropped. A render that stops mentioning a property
    // has to put it back to a fresh control's value, or a control stays
    // disabled after the markup that disabled it is deleted — and until this
    // was here, four hundred cases produced one such tree.
    var drop_attribute: int = -1
    if element.attribute_count() > 0 && dice.chance(35) {
        drop_attribute = dice.below(element.attribute_count())
    }
    for index: int in 0..element.attribute_count() {
        if index != drop_attribute {
            copy.set(element.attribute_at(index))
        }
    }
    // One listener may be dropped, which is the only way an `unbind` is
    // reached without the whole element being rebuilt — and it was reached
    // three times in four hundred cases until this was here.
    var drop_listener: int = -1
    if element.listener_count() > 0 && dice.chance(30) {
        drop_listener = dice.below(element.listener_count())
    }
    for index: int in 0..element.listener_count() {
        if index != drop_listener {
            copy.listen(element.listener_at(index).kind, fn(event: events.UiEvent) {})
        }
    }

    var kids: List<component.Element> = element.children()
    var kept: List<component.Element> = []
    for child: component.Element in kids { kept.push(child) }

    let action: int = dice.below(7)
    if action == 0 && kept.len() >= 2 {
        // Reorder, which is the case keys exist for.
        let a: int = dice.below(kept.len())
        let b: int = dice.below(kept.len())
        let held: component.Element = kept[a]
        kept[a] = kept[b]
        kept[b] = held
    } else if action == 1 {
        kept.push(leaf(dice, "k{names.next() % 1000}"))
    } else if action == 2 && kept.len() > 0 {
        let drop: int = dice.below(kept.len())
        var trimmed: List<component.Element> = []
        var at: int = 0
        for child: component.Element in kept {
            if at != drop { trimmed.push(child) }
            at = at + 1
        }
        kept = move trimmed
    } else if action == 3 {
        // Change a property of this node.
        copy.set(component.Attribute.of_text(words()[dice.below(words().len())]))
    } else if action == 4 {
        let name: string = event_names()[dice.below(event_names().len())]
        copy.listen(event_named(name), fn(event: events.UiEvent) {})
    } else if action == 5 && kept.len() > 0 {
        // Insert in the middle, which renumbers everything after it.
        let spot: int = dice.below(kept.len())
        var spliced: List<component.Element> = []
        var at: int = 0
        for child: component.Element in kept {
            if at == spot { spliced.push(leaf(dice, "k{names.next() % 1000}")) }
            spliced.push(child)
            at = at + 1
        }
        kept = move spliced
    }

    for child: component.Element in kept {
        if child.count() > 0 && dice.chance(40) {
            copy.add(mutate(dice, child, names))
        } else if dice.chance(20) {
            copy.add(mutate(dice, child, names))
        } else {
            copy.add(child)
        }
    }
    return copy
}

// ------------------------------------------------------------------ the sweep

/// How many of each kind of edit the whole sweep produced.
///
/// This is in the golden on purpose. A sweep that generated no moves would
/// pass while testing nothing about the one operation keys exist for, and a
/// green number is not evidence of anything until you can see what it covered.
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
    let before: component.Element = grow(dice, 3, names)
    let after: component.Element = mutate(dice, before, names)

    var differ: component.Differ = new component.Differ()
    let changes: List<component.Change> = differ.diff(some(before), after)

    var model: Mirror = mirror_of(before)
    for change: component.Change in changes {
        tally.add(change.kind)
        apply_one(model, change)?
    }

    let reached: string = show_mirror(model, 0)
    let wanted: string = show_mirror(mirror_of(after), 0)
    if reached != wanted {
        io.println("FAULT seed={seed}: applying {changes.len()} changes did not reach the new tree")
        io.println("-- reached --")
        io.print(reached)
        io.println("-- wanted --")
        io.print(wanted)
        return ok(false)
    }
    return ok(true)
}

fn main() {
    // Fixed seeds, not a clock: a sweep whose input changes every run is a
    // gate that is sometimes red for reasons nobody can reproduce.
    let cases: int = 400
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
    io.println("sweep: {cases} cases, {faults} faults")
    io.println("edits: {tally.show()}")
}
