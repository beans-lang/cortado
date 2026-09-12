// The controls that carry a number, and the same answers on every platform.
//
// The third file in the family `tests/enabled.out` started: a property whose
// *set of widgets* is part of the contract, written down as output so four
// hosts cannot drift into four answers. `enabled` was the first, `checked` the
// second, and this is the one about `CTD_P_MIN`, `CTD_P_MAX`, `CTD_P_VALUE`
// and `CTD_P_STEP`.
//
// Two rules here are worth stating before the code, because both were found by
// writing it:
//
//   * **A slider's step is write-only.** AppKit has no increment on a slider —
//     a stepped NSSlider is one with tick marks it must land on — so the host
//     holds a count of positions and not the number the caller wrote.
//     Reconstructing it is exact when the step divided the span evenly and
//     quietly wrong otherwise. Win32 *can* answer, which is the trap: one
//     platform answering a number the other three cannot is a divergence that
//     reads as a feature. Only a stepper reads its increment back.
//
//   * **Whole numbers are what a portable case can assert.** A Win32 trackbar
//     holds an `int32`, so a slider there is integer-valued. Every number
//     below is a whole one, and the fractional case is the stepper's, whose
//     host keeps the real range beside a tick index for exactly this reason.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.host
import cortado.events
import std.io

/// Which kinds carry a low end, a high end and a value.
///
/// Spelled out rather than read from the host: a test that asked which kinds
/// have the property and then checked those kinds would agree with any answer.
fn carries_a_number(kind: widgets.WidgetKind) -> bool {
    match kind {
        slider => { return true }
        progress_bar => { return true }
        stepper => { return true }
        level_indicator => { return true }
        container => { return false }
        label => { return false }
        button => { return false }
        text_field => { return false }
        secure_field => { return false }
        check_box => { return false }
        radio_button => { return false }
        switch => { return false }
        image_view => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        search_field => { return false }
        spinner => { return false }
        link => { return false }
        segmented => { return false }
        group_box => { return false }
        date_picker => { return false }
        color_well => { return false }
    }
}

/// And which of those takes an increment. A slider does, and it is the only
/// one that will not read it back.
fn takes_a_step(kind: widgets.WidgetKind) -> bool {
    match kind {
        slider => { return true }
        stepper => { return true }
        progress_bar => { return false }
        level_indicator => { return false }
        container => { return false }
        label => { return false }
        button => { return false }
        text_field => { return false }
        secure_field => { return false }
        check_box => { return false }
        radio_button => { return false }
        switch => { return false }
        image_view => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        search_field => { return false }
        spinner => { return false }
        link => { return false }
        segmented => { return false }
        group_box => { return false }
        date_picker => { return false }
        color_well => { return false }
    }
}

fn reads_its_step(kind: widgets.WidgetKind) -> bool {
    match kind {
        stepper => { return true }
        slider => { return false }
        progress_bar => { return false }
        level_indicator => { return false }
        container => { return false }
        label => { return false }
        button => { return false }
        text_field => { return false }
        secure_field => { return false }
        check_box => { return false }
        radio_button => { return false }
        switch => { return false }
        image_view => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        search_field => { return false }
        spinner => { return false }
        link => { return false }
        segmented => { return false }
        group_box => { return false }
        date_picker => { return false }
        color_well => { return false }
    }
}

/// And which of them a user can move. A progress bar and a gauge are outputs:
/// nothing the user does changes them, so nothing they do should raise an
/// event either.
fn moved_by_a_user(kind: widgets.WidgetKind) -> bool {
    match kind {
        slider => { return true }
        stepper => { return true }
        progress_bar => { return false }
        level_indicator => { return false }
        container => { return false }
        label => { return false }
        button => { return false }
        text_field => { return false }
        secure_field => { return false }
        check_box => { return false }
        radio_button => { return false }
        switch => { return false }
        image_view => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        search_field => { return false }
        spinner => { return false }
        link => { return false }
        segmented => { return false }
        group_box => { return false }
        date_picker => { return false }
        color_well => { return false }
    }
}

/// Handlers capture this, never the control they are attached to: the
/// platform's stored callback holds a strong reference the collector cannot
/// see through.
class Heard {
    pub count: int = 0
    pub fn init() {}
}

/// What a write answered: "" for yes, the refusal's kind for no.
///
/// A name rather than a bool, because two of the answers below are refusals
/// that mean different things — `wrong_widget` is "no control anywhere has
/// this" and `unsupported` is "this platform cannot" — and a test that folded
/// them together would let a host swap one for the other.
fn refusal(control: widgets.Widget, key: int, value: f64) -> string {
    match control.set_property_real(key, value) {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn took(control: widgets.Widget, key: int, value: f64) -> bool {
    match control.set_property_real(key, value) {
        ok(done) => { return true }
        err(problem) => { return false }
    }
}

fn read(control: widgets.Widget, key: int) -> Option<f64> {
    match control.read_property_real(key) {
        ok(value) => { return some(value) }
        err(problem) => { return none }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    // A window and a root, because a platform will not deliver a control's
    // events until it is in a tree: Win32 sends a control's notification to
    // its *parent*, and a control with no parent has nowhere to send it.
    var window: surface.Window = app.window(320.0, 200.0, "Numbers")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let tally: Heard = new Heard()

    let every: List<widgets.WidgetKind> = widgets.WidgetKind.all()
    var here: int = 0
    var movable: int = 0
    var raised_when_moved: int = 0
    var silent_when_written: int = 0
    var numbered: int = 0
    var carry: int = 0
    var range_correct: int = 0
    var value_round_trips: int = 0
    var range_reads_back: int = 0
    var step_correct: int = 0
    var zero_step_correct: int = 0
    var step_read_correct: int = 0

    for kind: widgets.WidgetKind in every {
        // Counted before availability, so the number printed is cortado's own
        // rule and not this machine's inventory. Every counter below is
        // against `here` or `numbered`, which are per host.
        if carries_a_number(kind) { carry = carry + 1 }
        if !kind.available() { continue }
        here = here + 1
        var control: widgets.Widget = component.WidgetMaker.of_kind(kind)?
        let wanted: bool = carries_a_number(kind)

        // Every kind is asked, so a kind that should refuse and does not is
        // caught by the same counter that catches one that should accept and
        // does not.
        let low_ok: bool = took(control, host.P_MIN, 0.0)
        let high_ok: bool = took(control, host.P_MAX, 10.0)
        let value_ok: bool = took(control, host.P_VALUE, 3.0)
        if low_ok == wanted && high_ok == wanted && value_ok == wanted {
            range_correct = range_correct + 1
        } else {
            io.println("  ...{kind.name()} took low={low_ok} high={high_ok} value={value_ok}, wanted {wanted}")
        }

        // The step, written. A slider takes one and a progress bar does not,
        // and both answers have to be the same on four platforms.
        // A slider's is a capability rather than a promise: AppKit, GTK and
        // Win32 can make one land on detents and a UISlider cannot, so the
        // answer there is `unsupported` — which is a different claim from
        // `wrong_widget`, and the difference is the whole point. What must
        // never happen is the write being taken and ignored.
        let step_said: string = refusal(control, host.P_STEP, 1.0)
        let step_ok: bool = step_said == ""
        let step_fine: bool = if takes_a_step(kind) {
            step_ok || step_said == "unsupported"
        } else {
            step_said == "wrong_widget"
        }
        if step_fine { step_correct = step_correct + 1 }
        else { io.println("  ...{kind.name()} answered {step_said} to an increment of 1") }

        // Zero. A slider takes it and means "continuous", which is a real
        // thing for a slider to be; a stepper that took it would be two arrows
        // that do nothing, so it is out of range there. Same value, two
        // answers, and both are the same on four platforms.
        let zero_said: string = refusal(control, host.P_STEP, 0.0)
        let zero_fine: bool = if reads_its_step(kind) {
            zero_said == "out_of_range"
        } else {
            if takes_a_step(kind) { zero_said == "" } else { zero_said == "wrong_widget" }
        }
        if zero_fine { zero_step_correct = zero_step_correct + 1 }
        else { io.println("  ...{kind.name()} answered {zero_said} to an increment of 0") }
        if reads_its_step(kind) { took(control, host.P_STEP, 1.0) }

        // And read back, which is a *narrower* set: only a stepper.
        var step_answered: bool = false
        var step_seen: string = "a refusal"
        match read(control, host.P_STEP) {
            some(size) => { step_answered = size == 1.0; step_seen = "{size}" }
            none => { step_answered = false }
        }
        if step_answered == reads_its_step(kind) { step_read_correct = step_read_correct + 1 }
        else { io.println("  ...{kind.name()} read its increment back as {step_seen}") }

        if !wanted { continue }
        numbered = numbered + 1

        var held: f64 = -1.0
        match read(control, host.P_VALUE) {
            some(value) => { held = value }
            none => {}
        }
        var lowest: f64 = -1.0
        var highest: f64 = -1.0
        match read(control, host.P_MIN) {
            some(value) => { lowest = value }
            none => {}
        }
        match read(control, host.P_MAX) {
            some(value) => { highest = value }
            none => {}
        }
        if held == 3.0 { value_round_trips = value_round_trips + 1 }
        else { io.println("  ...{kind.name()} was written 3 and read back {held}") }
        if lowest == 0.0 && highest == 10.0 { range_reads_back = range_reads_back + 1 }

        // Moved the way a user moves it, then written to the way a program
        // writes to it. Both halves are rules: a control that carries a number
        // the user can change says so, and a control's own program never hears
        // about its own writes.
        root.add(control)?
        app.router.on(control.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) { tally.count = tally.count + 1 })
        let before: int = tally.count
        match control.set_value_as_user(0, 7.0) {
            ok(done) => {}
            err(problem) => {}
        }
        let after_user: int = tally.count
        if (after_user > before) == moved_by_a_user(kind) {
            raised_when_moved = raised_when_moved + 1
        }
        control.set_property_real(host.P_VALUE, 5.0)?
        if tally.count == after_user { silent_when_written = silent_when_written + 1 }
        app.router.forget(control.handle())
        if moved_by_a_user(kind) { movable = movable + 1 }
    }

    io.println("-- which controls carry a number --")
    io.println("  cortado has this many kinds: {every.len()}")
    io.println("  every kind this platform builds was asked: {here > 0}")
    io.println("  exactly the kinds that carry one take a low end, a high end and a value: {range_correct == here}")
    io.println("  this many kinds carry one: {carry}")
    io.println("  each reads its range back unchanged: {range_reads_back == numbered}")
    io.println("  each reads the value that was written: {value_round_trips == numbered}")

    io.println("-- moving one --")
    io.println("  this many of them a user can move: {movable}")
    io.println("  each raises value_changed exactly where a user can move it: {raised_when_moved == numbered}")
    io.println("  and none raises anything when the program writes to it: {silent_when_written == numbered}")

    io.println("-- the increment --")
    io.println("  exactly the kinds that have one take it, or say the platform cannot: {step_correct == here}")
    io.println("  zero means continuous to a slider and is out of range to a stepper: {zero_step_correct == here}")
    io.println("  and only a stepper reads it back: {step_read_correct == here}")

    window.close()?
    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
