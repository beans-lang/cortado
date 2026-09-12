// The strings a control carries that are not the text it *is*.
//
// The fourth file in the family `tests/enabled.out` started, and the first
// about `ctd_set_string`. A control's own text — a button's title, a field's
// value — is `ctd_set_text`. A control can carry more than one: a field has
// words it shows while it is empty. Those are keyed, and which kinds have
// which key is part of the contract rather than each host's guess.
//
// Cross-host, and every line is cortado's own rule or a round trip through the
// platform. The hint is read back off the control rather than out of a copy
// cortado kept, because a string that goes in and does not come out is the
// failure this file exists to catch — and three of the four hosts store it
// somewhere different from where they store the value.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.host
import std.io

/// Which kinds carry somewhere to go. Only a link.
fn goes_somewhere(kind: widgets.WidgetKind) -> bool {
    match kind {
        link => { return true }
        segmented => { return false }
        group_box => { return false }
        text_field => { return false }
        secure_field => { return false }
        search_field => { return false }
        container => { return false }
        label => { return false }
        button => { return false }
        check_box => { return false }
        radio_button => { return false }
        switch => { return false }
        image_view => { return false }
        slider => { return false }
        stepper => { return false }
        progress_bar => { return false }
        level_indicator => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        spinner => { return false }
    }
}

/// Which kinds show words while they are empty.
///
/// Every single-line field, and nothing else. A text area could — NSTextView
/// and GtkTextView both have something like it — but neither has one cortado
/// could read back, and a string that goes in and does not come out is worse
/// than one that is refused.
fn shows_a_hint(kind: widgets.WidgetKind) -> bool {
    match kind {
        text_field => { return true }
        secure_field => { return true }
        search_field => { return true }
        container => { return false }
        label => { return false }
        button => { return false }
        check_box => { return false }
        radio_button => { return false }
        switch => { return false }
        image_view => { return false }
        slider => { return false }
        stepper => { return false }
        progress_bar => { return false }
        level_indicator => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        scroll_view => { return false }
        canvas => { return false }
        table => { return false }
        spinner => { return false }
        link => { return false }
        segmented => { return false }
        group_box => { return false }
    }
}

fn wrote(control: widgets.Widget, key: int, text: string) -> bool {
    match control.set_string_at(key, text) {
        ok(done) => { return true }
        err(problem) => { return false }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let every: List<widgets.WidgetKind> = widgets.WidgetKind.all()
    var here: int = 0
    var hinted: int = 0
    var carries_it_correctly: int = 0
    var round_trips: int = 0
    var survives_a_value: int = 0
    var url_correct: int = 0
    var linked: int = 0
    var url_survives_words: int = 0

    for kind: widgets.WidgetKind in every {
        if !kind.available() { continue }
        here = here + 1
        var control: widgets.Widget = component.WidgetMaker.of_kind(kind)?
        let wanted: bool = shows_a_hint(kind)

        if wrote(control, host.S_HINT, "Search orders") == wanted {
            carries_it_correctly = carries_it_correctly + 1
        }
        // The other key, on the same walk. A link's target is a string that
        // two hosts keep *inside* the control's own text — an attributed
        // string on the Mac, `<a href=...>` markup on Windows — so writing the
        // words must not drop it and reading it back must not answer the
        // markup.
        let url_ok: bool = wrote(control, host.S_URL, "https://example.com/a")
        if url_ok == goes_somewhere(kind) { url_correct = url_correct + 1 }
        else { io.println("  ...{kind.name()} answered {url_ok} to a URL") }
        if goes_somewhere(kind) {
            linked = linked + 1
            control.set_display_text("the manual")?
            var back: string = ""
            match control.string_at_key(host.S_URL) {
                ok(where) => { back = where }
                err(problem) => {}
            }
            if back == "https://example.com/a" && control.display_text().or("") == "the manual" {
                url_survives_words = url_survives_words + 1
            }
        }

        if !wanted { continue }
        hinted = hinted + 1

        match control.string_at_key(host.S_HINT) {
            ok(back) => { if back == "Search orders" { round_trips = round_trips + 1 } }
            err(problem) => {}
        }

        // The hint and the value are two different strings, and a host that
        // stored one where the other goes would pass every line above.
        //
        // Only the hint is read back here. A secure field answers "" to
        // `display_text` on purpose — a control tree printed to a log carries
        // the field and not what was typed into it — so comparing the value
        // would be testing that rule rather than this one.
        control.set_display_text("flat white")?
        var still: string = ""
        match control.string_at_key(host.S_HINT) {
            ok(back) => { still = back }
            err(problem) => {}
        }
        if still == "Search orders" { survives_a_value = survives_a_value + 1 }
    }

    io.println("-- which controls show words while they are empty --")
    io.println("  cortado has this many kinds: {every.len()}")
    io.println("  every kind this platform builds was asked: {here > 0}")
    io.println("  exactly the kinds that have a hint take one: {carries_it_correctly == here}")
    io.println("  this many kinds have one: {hinted > 0}")
    io.println("  each reads back the words it was given: {round_trips == hinted}")
    io.println("  and the hint and the value are different strings: {survives_a_value == hinted}")

    io.println("-- where a link goes --")
    io.println("  exactly the kinds that go somewhere take a URL: {url_correct == here}")
    io.println("  this many kinds go somewhere: {linked}")
    io.println("  and the target survives writing the words: {url_survives_words == linked}")

    io.println("-- a key that is not a string --")
    var field: widgets.TextField = new widgets.TextField()
    var unknown: bool = false
    match field.set_string_at(99, "nowhere") {
        ok(done) => { unknown = false }
        err(problem) => { unknown = problem.kind == "unsupported" }
    }
    io.println("  is refused as unsupported, not quietly written: {unknown}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
