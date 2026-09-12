// Which controls have an enabled state, and the same answer on every platform.
//
// This is the case that caught four hosts answering four different things.
// Each was deciding from its own object system, and the object systems
// disagree:
//
//   * AppKit accepted it for an `NSControl`, which a `Label` is and a
//     `ProgressBar` is not;
//   * UIKit accepted it for a `UIControl`, which a `UILabel` is *not*;
//   * GTK4 and Win32 accepted it for everything, containers included.
//
// So the rule is cortado's, not any platform's, and it is written down here as
// output, for every kind cortado has:
//
//   **A widget has an enabled state exactly when it accepts input.**
//
// A container is refused for a second reason as well: it is a layout box with
// no appearance of its own, and answering for it would be answering for its
// children, which is a different question. Everything else that takes no
// input — a label, an image, a separator, a progress bar, a gauge — can still
// be shown inactive, because "inactive" is a look every platform has and
// `opacity` is where it lives.
//
// **Why the lines below are the rule rather than what happened.** They used to
// be what happened, one line per control, and that worked for exactly as long
// as every host had every kind. It stopped the day a level indicator landed:
// UIKit has none, so the iOS leg printed `LevelIndicator is not a control on
// this platform` where macOS printed `LevelIndicator refused wrong_widget`,
// and a golden that is supposed to be identical on four hosts was reporting an
// *inventory*. The inventory is `ctd_widget_supports`' business and
// `tests/controls.out`'s. What belongs here is the rule — which is the same
// everywhere, kind by kind — plus the count of controls that actually obey it,
// which is what makes the file a test rather than a restatement.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import std.io

/// Whether this kind accepts input, and therefore has an enabled state.
///
/// Spelled out rather than read from the host. A test that asked the host
/// which kinds carry the property and then checked those kinds would agree
/// with any answer at all — including the four wrong ones above.
fn takes_input(kind: widgets.WidgetKind) -> bool {
    match kind {
        button => { return true }
        text_field => { return true }
        secure_field => { return true }
        search_field => { return true }
        check_box => { return true }
        radio_button => { return true }
        switch => { return true }
        slider => { return true }
        stepper => { return true }
        combo_box => { return true }
        segmented => { return true }
        date_picker => { return true }
        color_well => { return true }
        container => { return false }
        label => { return false }
        image_view => { return false }
        progress_bar => { return false }
        level_indicator => { return false }
        separator => { return false }
        text_area => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        spinner => { return false }
        link => { return false }
        group_box => { return false }
        disclosure => { return false }
        tab_view => { return false }
        split_view => { return false }
    }
}

/// What one control does with the property: round-trips it, refuses it as the
/// wrong widget, or something else — which is the answer that fails.
///
/// Writing `false` and reading `true` is the failure this catches that a
/// write-only check would not.
fn behaviour(widget: widgets.Widget) -> string {
    match widget.set_enabled(false) {
        ok(done) => {}
        err(refusal) => { return refusal.kind }
    }
    var off: bool = true
    match widget.is_enabled() {
        ok(value) => { off = value }
        err(refusal) => { return "took a write and refused the read: {refusal.kind}" }
    }
    match widget.set_enabled(true) {
        ok(done) => {}
        err(refusal) => { return "took false and refused true: {refusal.kind}" }
    }
    var on: bool = false
    match widget.is_enabled() {
        ok(value) => { on = value }
        err(refusal) => { return "took a write and refused the read: {refusal.kind}" }
    }
    if !off && on { return "round-trips" }
    return "round-trip wrong: off={off} on={on}"
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var here: int = 0
    var obeyed: int = 0

    // Walked rather than listed. The first version of this file spelled the
    // kinds out by hand, under a comment claiming that a kind added without a
    // decision about this property would "show up as a missing line". It would
    // not have, and it did not: `canvas` landed with the GPU work, never
    // reached the list, and the golden simply stayed thirteen lines long. A
    // list that is one short looks exactly like a list.
    //
    // `WidgetMaker.of_kind`'s `match` the compiler checks for exhaustiveness,
    // and so is `takes_input` above — so a new kind stops the build twice
    // until somebody decides what it answers.
    for kind: widgets.WidgetKind in widgets.WidgetKind.all() {
        let wanted: bool = takes_input(kind)
        let says: string = if wanted { "has an enabled state" } else { "has none" }
        io.println("{kind.name()} {says}")
        if !kind.available() { continue }
        here = here + 1
        let did: string = behaviour(component.WidgetMaker.of_kind(kind)?)
        if did == (if wanted { "round-trips" } else { "wrong_widget" }) {
            obeyed = obeyed + 1
        } else {
            // Named, so a failure says which control and what it did instead
            // of only turning a `true` into a `false`.
            io.println("  ...but this platform answered: {did}")
        }
    }

    io.println("-- and what this platform does --")
    io.println("  every control it builds was asked: {here > 0}")
    io.println("  and every one of them obeys the rule above: {obeyed == here}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
