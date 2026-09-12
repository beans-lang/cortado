// The two controls whose value is not a number and not a string.
//
// Every other control in cortado carries text, a flag, or a number in a range.
// These two carry something else — a day and a colour — and each brought a
// rule with it that four hosts could have spelled four ways. This file is
// where those rules are written as output, so they cannot.
//
// **The day.** A date picker holds a *day*, not an instant. Three of the four
// platforms could show a time and `GtkCalendar` cannot, so cortado floors
// every write to midnight UTC of the day it names. That decision has one hard
// case, and it is the one this file spends most of its lines on: the day
// *before* the epoch. Truncating -1 toward zero gives 0, which is
// 1970-01-01 — a whole day wrong, on the one side of the epoch nobody tests.
//
// **The colour.** A colour crosses as four bytes and every platform holds it
// as four floats, in a colour space each platform picks for itself. What this
// file checks is that all four bytes survive the trip, in that order, for
// every level — not three colours, because three colours would pass with the
// channels swapped, with alpha dropped, and with the well left in the
// machine's own display profile instead of sRGB.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.host
import cortado.events
import std.io

const DAY: f64 = 86400.0

/// Handlers capture this, never the control they are attached to.
class Heard {
    pub count: int = 0
    pub last: int = 0
    pub fn init() {}
}

/// What a write answered: "" for yes, the refusal's kind for no.
fn refusal_real(control: widgets.Widget, key: int, value: f64) -> string {
    match control.set_property_real(key, value) {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn refusal_int(control: widgets.Widget, key: int, value: int) -> string {
    match control.set_property(key, value) {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

/// The day cortado says `seconds` falls in — the same arithmetic
/// `ctd_date_floor` does in C, written again here.
///
/// Stated twice and compared once, which is the whole point. A test that asked
/// the host to floor a number and then checked the host's answer against the
/// host's floor would agree with any rule at all, including the one that loses
/// a day before 1970.
fn day_of(seconds: f64) -> f64 {
    var days: f64 = seconds / DAY
    var whole: f64 = (days as int) as f64
    if days < 0.0 && whole != days { whole = whole - 1.0 }
    return whole * DAY
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    // A window and a root, because a platform will not deliver a control's
    // events until it is in a tree.
    var window: surface.Window = app.window(320.0, 240.0, "Pickers")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let tally: Heard = new Heard()

    // ------------------------------------------------------------ the day

    io.println("-- a date picker holds a day --")
    io.println("  every platform cortado builds for has one: {widgets.WidgetKind.date_picker.available()}")

    if widgets.WidgetKind.date_picker.available() {
        var picker: widgets.DatePicker = new widgets.DatePicker()

        // Instants spread across one day and over both edges of it, plus the
        // day before the epoch twice — once from a second before it and once
        // from a whole day before.
        let instants: List<f64> = [0.0, 1.0, 3600.0, 86399.0, 86400.0,
                                   1234567890.0, 1234483200.0,
                                   -1.0, -86400.0, -86401.0,
                                   -2208988800.0]
        var floored: int = 0
        var landed_on_midnight: int = 0
        for instant: f64 in instants {
            picker.set_day(instant)?
            let held: f64 = picker.day()?
            if held == day_of(instant) { floored = floored + 1 }
            else { io.println("  ...{instant} was floored to {held}, not {day_of(instant)}") }
            let in_days: f64 = held / DAY
            if in_days == (in_days as int) as f64 { landed_on_midnight = landed_on_midnight + 1 }
        }
        io.println("  any instant in a day names that day: {floored == instants.len()}")
        io.println("  and what comes back is always a midnight: {landed_on_midnight == instants.len()}")

        // The case the naive floor gets wrong, named on its own line because
        // it is the one worth seeing fail.
        picker.set_day(-1.0)?
        io.println("  a second before the epoch is the day before it: {picker.day()? == 0.0 - DAY}")

        // Ten thousand consecutive days, each written and read back. One day
        // and two literals prove nothing here: the conversions this exercises
        // are civil-calendar arithmetic on Win32 and a GDateTime on GTK, and
        // both have leap-year and century edges no handful of dates reaches.
        var exact: int = 0
        var day: int = -3000
        for day in -3000..7000 {
            let seconds: f64 = day as f64 * DAY
            picker.set_day(seconds)?
            if picker.day()? == seconds { exact = exact + 1 }
        }
        io.println("  10,000 consecutive days each read back the day written: {exact == 10000}")

        // A user picks a day, and the event carries it.
        root.add(picker)?
        app.router.on(picker.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                tally.count = tally.count + 1
                tally.last = event.index
            })
        let before_pick: int = tally.count
        picker.set_value_as_user(0, 1234567890.0)?
        io.println("  a day the user picks raises value_changed: {tally.count > before_pick}")
        io.println("  and the event carries the day, not the instant: {tally.last == 1234483200}")

        let after_pick: int = tally.count
        picker.set_day(0.0)?
        io.println("  a day the program writes raises nothing: {tally.count == after_pick}")
        app.router.forget(picker.handle())
    }

    // --------------------------------------------------------- the colour

    io.println("-- a colour well holds four bytes --")
    io.println("  every platform cortado builds for has one: {widgets.WidgetKind.color_well.available()}")

    if widgets.WidgetKind.color_well.available() {
        var well: widgets.ColorWell = new widgets.ColorWell()

        // All 256 values of each channel, one channel at a time, because a
        // host that truncated instead of rounding loses about half of them and
        // a test built from three colours would not notice.
        var kept: int = 0
        var level: int = 0
        for level in 0..256 {
            well.set_color(widgets.Rgba { red: level, green: 255 - level,
                                          blue: (level * 7) % 256, alpha: level })?
            let back: widgets.Rgba = well.color()?
            if back.red == level && back.green == 255 - level &&
               back.blue == (level * 7) % 256 && back.alpha == level {
                kept = kept + 1
            }
        }
        io.println("  all 256 levels of every channel come back unchanged: {kept == 256}")

        // The packing order, checked by a colour that is only one channel.
        // A host that put alpha in the high byte would round-trip every
        // opaque colour and fail exactly here.
        well.set_color(widgets.Rgba { red: 255, green: 0, blue: 0, alpha: 255 })?
        let red: widgets.Rgba = well.color()?
        io.println("  red is red and not alpha: {red.show()}")
        io.println("  and packs into the high byte: {widgets.ColorWell.pack(red) == 4278190335}")

        // Half transparent, which is the channel a host forgets.
        well.set_color(widgets.Rgba { red: 0, green: 128, blue: 255, alpha: 64 })?
        io.println("  a partly transparent colour keeps its alpha: {well.color()?.show()}")

        // Out of range is a refusal rather than a mask.
        io.println("  a number above 0xFFFFFFFF is refused: {refusal_int(well, host.P_COLOR, 4294967296) == "out_of_range"}")
        io.println("  and a negative one: {refusal_int(well, host.P_COLOR, -1) == "out_of_range"}")

        root.add(well)?
        app.router.on(well.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                tally.count = tally.count + 1
                tally.last = event.index
            })
        let before_pick: int = tally.count
        well.set_value_as_user(4278190335, 0.0)?
        io.println("  a colour the user picks raises value_changed: {tally.count > before_pick}")
        io.println("  and the event carries the packed colour: {tally.last == 4278190335}")

        let after_pick: int = tally.count
        well.set_color(widgets.Rgba { red: 0, green: 0, blue: 0, alpha: 255 })?
        io.println("  a colour the program writes raises nothing: {tally.count == after_pick}")
        app.router.forget(well.handle())
    }

    // ------------------------------------------------- and nothing else has one

    // Every kind is asked, so a kind that should refuse and does not is caught
    // by the same counter that catches one that should accept and does not.
    var asked: int = 0
    var day_right: int = 0
    var colour_right: int = 0
    for kind: widgets.WidgetKind in widgets.WidgetKind.all() {
        if !kind.available() { continue }
        asked = asked + 1
        var control: widgets.Widget = component.WidgetMaker.of_kind(kind)?

        let day_said: string = refusal_real(control, host.P_DATE, 0.0)
        let wants_day: bool = kind == widgets.WidgetKind.date_picker
        if (day_said == "") == wants_day { day_right = day_right + 1 }
        else { io.println("  ...{kind.name()} answered '{day_said}' to a day") }

        let colour_said: string = refusal_int(control, host.P_COLOR, 0)
        let wants_colour: bool = kind == widgets.WidgetKind.color_well
        if (colour_said == "") == wants_colour { colour_right = colour_right + 1 }
        else { io.println("  ...{kind.name()} answered '{colour_said}' to a colour") }
    }

    io.println("-- and no other control carries either --")
    io.println("  every kind this platform builds was asked: {asked > 0}")
    io.println("  only a date picker takes a day: {day_right == asked}")
    io.println("  only a colour well takes a colour: {colour_right == asked}")

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
