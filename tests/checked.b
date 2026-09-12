// Which controls have a checked state, which of them have a third one, and the
// same answer on every platform.
//
// The companion to `tests/enabled.out`, and it exists because the same mistake
// had been made twice. `CTD_P_ENABLED` used to be answered by each host asking
// its own object system, and the object systems disagreed. `CTD_P_CHECKED` was
// still being answered that way:
//
//   * AppKit asked `isKindOfClass:[NSButton class]`, and a push button is one —
//     so ticking a button worked on macOS and was refused everywhere else.
//   * A radio button had no mixed state anywhere, and all four hosts had a
//     different idea of what to do when asked for one: AppKit turned it into
//     on, UIKit turned it into off, GTK4 held it as a real third state, and
//     Win32 refused it.
//
// Nothing in the suite could see either one, because no case wrote this
// property to a control that was not a check box. This is that case.
//
// It is a cross-host golden, so every line is a claim that holds on all four.
// The one genuine platform difference — iOS builds a check box out of a
// UISwitch, which has two positions — is written as what it is: the mixed
// state is either held or refused, and never quietly rounded.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.host
import std.io

/// Whether cortado says this kind is a state rather than a command.
///
/// Spelled out here rather than read from the host, because a test that asked
/// the host which kinds have the property and then checked those kinds would
/// agree with any answer at all.
fn should_have_it(kind: widgets.WidgetKind) -> bool {
    match kind {
        check_box => { return true }
        radio_button => { return true }
        switch => { return true }
        container => { return false }
        label => { return false }
        button => { return false }
        text_field => { return false }
        image_view => { return false }
        slider => { return false }
        progress_bar => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        search_field => { return false }
        spinner => { return false }
        link => { return false }
        secure_field => { return false }
        stepper => { return false }
        level_indicator => { return false }
    }
}

/// And which of those has the third state. Only a check box: "some of the
/// things this box stands for" is a real answer, and a radio is one of a set
/// while a switch is one thing.
fn should_have_mixed(kind: widgets.WidgetKind) -> bool {
    match kind {
        check_box => { return true }
        radio_button => { return false }
        switch => { return false }
        container => { return false }
        label => { return false }
        button => { return false }
        text_field => { return false }
        image_view => { return false }
        slider => { return false }
        progress_bar => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        search_field => { return false }
        spinner => { return false }
        link => { return false }
        secure_field => { return false }
        stepper => { return false }
        level_indicator => { return false }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let every: List<widgets.WidgetKind> = widgets.WidgetKind.all()
    var here: int = 0
    var states: int = 0
    var carries_it_correctly: int = 0
    var off_and_on_round_trip: int = 0
    var mixed_correct: int = 0
    var seven_refused: int = 0
    var minus_one_refused: int = 0

    for kind: widgets.WidgetKind in every {
        if !kind.available() { continue }
        here = here + 1
        var control: widgets.Widget = component.WidgetMaker.of_kind(kind)?
        let wanted: bool = should_have_it(kind)

        var took_it: bool = false
        match control.set_property(host.P_CHECKED, 0) {
            ok(done) => { took_it = true }
            err(problem) => { took_it = false }
        }
        if took_it == wanted { carries_it_correctly = carries_it_correctly + 1 }

        // A kind with no such state refuses every value, and there is nothing
        // further to ask it. The counters below are against `states`, not
        // against `here`, so a kind that is skipped here does not quietly make
        // one of them come out right.
        if !wanted { continue }
        states = states + 1

        // Off then on, read back each time. A write-only check would miss a
        // host that accepted `false` and showed `true`.
        var low: int = 1
        var high: int = 0
        control.set_property(host.P_CHECKED, 0)?
        match control.read_property(host.P_CHECKED) {
            ok(value) => { low = value }
            err(problem) => {}
        }
        control.set_property(host.P_CHECKED, 1)?
        match control.read_property(host.P_CHECKED) {
            ok(value) => { high = value }
            err(problem) => {}
        }
        if low == 0 && high == 1 { off_and_on_round_trip = off_and_on_round_trip + 1 }

        // The third state. Where cortado says the kind has none, the answer is
        // `out_of_range` — the value is not a state this control has, on any
        // platform, which is a different claim from "this platform cannot".
        // Where it has one, the platform either holds it or says it cannot
        // show it; what is never allowed is taking the write and showing
        // something else.
        match control.set_property(host.P_CHECKED, 2) {
            ok(done) => {
                var read_back: int = -1
                match control.read_property(host.P_CHECKED) {
                    ok(value) => { read_back = value }
                    err(problem) => {}
                }
                if should_have_mixed(kind) && read_back == 2 {
                    mixed_correct = mixed_correct + 1
                }
            }
            err(problem) => {
                if should_have_mixed(kind) {
                    if problem.kind == "unsupported" { mixed_correct = mixed_correct + 1 }
                } else {
                    if problem.kind == "out_of_range" { mixed_correct = mixed_correct + 1 }
                }
            }
        }

        match control.set_property(host.P_CHECKED, 7) {
            ok(done) => {}
            err(problem) => {
                if problem.kind == "out_of_range" { seven_refused = seven_refused + 1 }
            }
        }
        match control.set_property(host.P_CHECKED, -1) {
            ok(done) => {}
            err(problem) => {
                if problem.kind == "out_of_range" { minus_one_refused = minus_one_refused + 1 }
            }
        }
    }

    io.println("-- which controls are a state --")
    io.println("  cortado has this many kinds: {every.len()}")
    io.println("  every kind this platform builds was asked: {here > 0}")
    io.println("  exactly the kinds that are a state carry the property: {carries_it_correctly == here}")
    io.println("  this many of them are a state: {states}")
    io.println("  off and on round-trip on every one: {off_and_on_round_trip == states}")

    io.println("-- the third state --")
    io.println("  mixed is held where the kind has one, out of range where it")
    io.println("  has not, and never rounded to something else: {mixed_correct == states}")

    io.println("-- values that are not states --")
    io.println("  7 is out of range: {seven_refused == states}")
    io.println("  -1 is out of range: {minus_one_refused == states}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
