// Which controls have an enabled state, and the same answer on every platform.
//
// This file exists because four hosts had four different answers and every
// golden in the suite was blind to it.
//
// `P_ENABLED` was never defined in `cortado_host.h` — it said what the property
// meant and not which widgets carry it — so each host answered from its own
// class tree, and the trees do not agree:
//
//   * AppKit accepted it for an `NSControl`, which a `Label` is and a
//     `ProgressBar`, `Separator`, `TextArea` and `ScrollView` are not;
//   * UIKit accepted it for a `UIControl`, which a `UILabel` is *not*;
//   * GTK4 and Win32 accepted it for everything, containers included.
//
// `tests/roles.out` could not see any of this, because it reads the state with
// `match … err(absent) => {}` — a refusal and "enabled" print the same bytes.
// `tests/applied.out` finally caught the Label shape on iOS, and only that one,
// because the generator happens to build labels.
//
// So the rule is written down here, as output, for every kind cortado has:
// **every widget has an enabled state except a container.** A container is a
// layout box with no appearance of its own; answering for it would be
// answering for its children, which is a different question. Everything else —
// including the ones that are not interactive, like a label or a progress bar
// — can be shown inactive, because "inactive" is a look every platform has and
// not a class in anybody's hierarchy.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import std.io

/// One empty control of every kind, in the order `WidgetKind` declares them,
/// so a kind added without a decision about this property shows up as a
/// missing line rather than as nothing at all.
fn every_kind() -> List<widgets.Widget> {
    return [
        new widgets.Container(),
        new widgets.Label(),
        new widgets.Button(),
        new widgets.TextField(),
        new widgets.CheckBox(),
        new widgets.ImageView(),
        new widgets.Slider(),
        new widgets.ProgressBar(),
        new widgets.Separator(),
        new widgets.TextArea(),
        new widgets.ComboBox(),
        new widgets.ScrollView(),
        new widgets.RadioButton(),
    ]
}

/// What one kind answers: whether it takes the property, and whether what it
/// reads back is what was written. Writing `false` and reading `true` is the
/// failure this catches that a write-only check would not.
fn report(widget: widgets.Widget) -> string {
    let name: string = widget.kind().name()
    match widget.set_enabled(false) {
        ok(done) => {}
        err(refusal) => { return "{name} refused {refusal.kind}" }
    }
    var off: bool = true
    match widget.is_enabled() {
        ok(value) => { off = value }
        err(refusal) => { return "{name} took a write and refused the read: {refusal.kind}" }
    }
    match widget.set_enabled(true) {
        ok(done) => {}
        err(refusal) => { return "{name} took false and refused true: {refusal.kind}" }
    }
    var on: bool = false
    match widget.is_enabled() {
        ok(value) => { on = value }
        err(refusal) => { return "{name} took a write and refused the read: {refusal.kind}" }
    }
    if !off && on { return "{name} enabled round-trips" }
    return "{name} round-trip wrong: off={off} on={on}"
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    for widget: widgets.Widget in every_kind() {
        io.println(report(widget))
    }
    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
