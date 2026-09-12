// The containers that keep part of their own frame.
//
// Every other control in cortado gets a frame and fills it. These do not: a
// group box draws a border and a title band, a disclosure draws a header, and
// what is left over is where the children go. That difference has to be
// visible to the caller's layout, or a screen with a group box on it adds
// padding by eye and is wrong on the other three platforms — whose borders and
// title bands are not the same size, and were never going to be.
//
// `ctd_view_content_inset` is how a host says how much it took, and this file
// is where the claims about it are written down:
//
//   * every control answers, and no answer is negative;
//   * a control that is not a container keeps nothing;
//   * a container that draws no chrome keeps nothing;
//   * a container that draws chrome keeps some, and only where it draws.
//
// The numbers themselves are deliberately **not** here. Seventeen points is
// AppKit's answer, GTK's is its stylesheet's and Windows' is the dialog font's,
// and a golden that named one would be a description of this machine. What is
// the same everywhere is the shape of the answer.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import cortado.host
import cortado.events
import std.io

/// Whether this kind holds children the caller adds.
///
/// Spelled out rather than read from the host, for the reason every other
/// rule in this suite is: a test that asked the host which kinds hold children
/// and then checked those kinds would agree with any answer.
fn holds_children(kind: widgets.WidgetKind) -> bool {
    match kind {
        container => { return true }
        scroll_view => { return true }
        group_box => { return true }
        disclosure => { return true }
        canvas => { return true }
        label => { return false }
        button => { return false }
        text_field => { return false }
        secure_field => { return false }
        check_box => { return false }
        radio_button => { return false }
        switch => { return false }
        image_view => { return false }
        slider => { return false }
        progress_bar => { return false }
        separator => { return false }
        text_area => { return false }
        combo_box => { return false }
        stepper => { return false }
        level_indicator => { return false }
        table => { return false }
        search_field => { return false }
        spinner => { return false }
        link => { return false }
        segmented => { return false }
        date_picker => { return false }
        color_well => { return false }
    }
}

/// And which of those draw something around what they hold.
///
/// A plain container and a scroll view draw nothing: their children start at
/// their own corner. A canvas holds children and draws whatever the program
/// draws, which is not chrome. The two that do are the two with a title.
fn draws_chrome(kind: widgets.WidgetKind) -> bool {
    return kind == widgets.WidgetKind.group_box ||
           kind == widgets.WidgetKind.disclosure
}

class Heard {
    pub count: int = 0
    pub last: int = 0
    pub fn init() {}
}

fn refusal(control: widgets.Widget, key: int, value: int) -> string {
    match control.set_property(key, value) {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(320.0, 240.0, "Panes")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let tally: Heard = new Heard()

    var asked: int = 0
    var answered: int = 0
    var never_negative: int = 0
    var right_shape: int = 0
    var open_right: int = 0

    for kind: widgets.WidgetKind in widgets.WidgetKind.all() {
        if !kind.available() { continue }
        asked = asked + 1
        var control: widgets.Widget = component.WidgetMaker.of_kind(kind)?

        var inset: geometry.EdgeInsets = geometry.EdgeInsets {}
        match control.content_inset() {
            ok(answer) => { answered = answered + 1; inset = answer }
            err(problem) => { io.println("  ...{kind.name()} refused to say ({problem.kind})") }
        }
        if inset.left >= 0.0 && inset.top >= 0.0 &&
           inset.right >= 0.0 && inset.bottom >= 0.0 {
            never_negative = never_negative + 1
        } else {
            io.println("  ...{kind.name()} keeps a negative inset")
        }

        // The shape, not the size. A kind that draws chrome keeps something; a
        // kind that does not keeps nothing at all.
        let keeps: bool = inset.left > 0.0 || inset.top > 0.0 ||
                          inset.right > 0.0 || inset.bottom > 0.0
        if keeps == draws_chrome(kind) { right_shape = right_shape + 1 }
        else { io.println("  ...{kind.name()} keeps {keeps}, expected {draws_chrome(kind)}") }

        // And the property that goes with the one that opens.
        let said: string = refusal(control, host.P_EXPANDED, 1)
        if (said == "") == (kind == widgets.WidgetKind.disclosure) {
            open_right = open_right + 1
        } else {
            io.println("  ...{kind.name()} answered '{said}' to being opened")
        }
    }

    io.println("-- what a control keeps for itself --")
    io.println("  every kind this platform builds was asked: {asked > 0}")
    io.println("  and every one of them answered: {answered == asked}")
    io.println("  no control keeps a negative amount: {never_negative == asked}")
    io.println("  exactly the containers that draw chrome keep any: {right_shape == asked}")
    io.println("  and only a disclosure can be opened: {open_right == asked}")

    // A group box's chrome is at the top, where the title is, and is the same
    // on both sides — which is a claim about a shape and holds on every
    // platform that has one. Where there is none, there is nothing to claim
    // and nothing to keep, and both halves print the same line.
    var box_shape: bool = true
    if widgets.WidgetKind.group_box.available() {
        var box: widgets.GroupBox = widgets.GroupBox.of("Options")?
        let inset: geometry.EdgeInsets = box.content_inset()?
        box_shape = inset.top >= inset.bottom && inset.left == inset.right &&
                    inset.left > 0.0
    }
    io.println("  a group box keeps a border, and more of it where the title is: {box_shape}")

    // ------------------------------------------------------ opening one

    io.println("-- a disclosure --")
    io.println("  every platform cortado builds for has one: {widgets.WidgetKind.disclosure.available()}")

    if widgets.WidgetKind.disclosure.available() {
        var twisty: widgets.Disclosure = widgets.Disclosure.of("Advanced", true)?
        let inset: geometry.EdgeInsets = twisty.content_inset()?
        io.println("  its header is at the top and nowhere else: {inset.top > 0.0 && inset.left == 0.0 && inset.right == 0.0 && inset.bottom == 0.0}")
        io.println("  its text is the title: {twisty.title()? == "Advanced"}")
        io.println("  it opens and shuts: {twisty.is_open()?}")
        twisty.set_open(false)?
        io.println("  and stays shut: {!twisty.is_open()?}")
        twisty.set_open(true)?
        io.println("  and opens again: {twisty.is_open()?}")

        // A shut disclosure keeps its header — it is still a title you can
        // press — so the room it takes does not change. A caller who wants the
        // column to close up renders no children, which is the caller's
        // decision and not the framework's.
        twisty.set_open(false)?
        let shut: geometry.EdgeInsets = twisty.content_inset()?
        twisty.set_open(true)?
        io.println("  shutting it does not change what it keeps: {shut.top == inset.top}")

        // It holds children like any other box.
        var inside: widgets.Label = widgets.Label.of("Nothing here yet")?
        twisty.add(inside)?
        io.println("  it holds children: {twisty.count() == 1}")

        root.add(twisty)?
        app.router.on(twisty.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                tally.count = tally.count + 1
                tally.last = event.index
            })
        let before: int = tally.count
        twisty.set_value_as_user(0, 0.0)?
        io.println("  a user shutting it raises value_changed: {tally.count > before}")
        io.println("  carrying the state it is now in: {tally.last == 0}")
        let after: int = tally.count
        twisty.set_open(true)?
        io.println("  and the program's own write raises nothing: {tally.count == after}")
        app.router.forget(twisty.handle())
    }

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
