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
        tab_view => { return true }
        split_view => { return true }
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
/// their own corner, and a canvas draws whatever the program draws, which is
/// not chrome. The four that do are the two with a title, the one with a strip
/// of tabs, and the one with a handle between its panes.
fn draws_chrome(kind: widgets.WidgetKind) -> bool {
    return kind == widgets.WidgetKind.group_box ||
           kind == widgets.WidgetKind.disclosure ||
           kind == widgets.WidgetKind.tab_view ||
           kind == widgets.WidgetKind.split_view
}

class Heard {
    pub count: int = 0
    pub last: int = 0
    pub fn init() {}
}

fn refusal_pane(split: widgets.SplitView, pane: widgets.Widget) -> string {
    match split.add(pane) {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn refusal_real(control: widgets.Widget, key: int, value: f64) -> string {
    match control.set_property_real(key, value) {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn refusal_label(tabs: widgets.TabView, index: int) -> string {
    match tabs.set_label(index, "nowhere") {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
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
    //
    // Everything below prints an *agreement* rather than what this platform
    // has. A host with no disclosure and a host with one produce the same
    // bytes, because the claim on each line is "this is true wherever the
    // control exists, and there is nothing to be untrue where it does not" —
    // which is what lets one golden cover four platforms with four different
    // inventories. Which controls exist is `tests/controls.out`'s business.

    io.println("-- a disclosure --")
    var twist_ok: bool = true
    var twist_holds: bool = true
    var twist_raises: bool = true
    if widgets.WidgetKind.disclosure.available() {
        var twisty: widgets.Disclosure = widgets.Disclosure.of("Advanced", true)?
        let header: geometry.EdgeInsets = twisty.content_inset()?
        twist_ok = header.top > 0.0 && header.left == 0.0 &&
                   header.right == 0.0 && header.bottom == 0.0 &&
                   twisty.title()? == "Advanced" && twisty.is_open()?
        twisty.set_open(false)?
        // A shut disclosure keeps its header — it is still a title you can
        // press — so the room it takes does not change.
        let shut: geometry.EdgeInsets = twisty.content_inset()?
        twist_ok = twist_ok && !twisty.is_open()? && shut.top == header.top
        twisty.set_open(true)?
        twist_ok = twist_ok && twisty.is_open()?

        var inside: widgets.Label = widgets.Label.of("Nothing here yet")?
        twisty.add(inside)?
        twist_holds = twisty.count() == 1

        root.add(twisty)?
        app.router.on(twisty.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                tally.count = tally.count + 1
                tally.last = event.index
            })
        let before: int = tally.count
        twisty.set_value_as_user(0, 0.0)?
        let raised: bool = tally.count > before && tally.last == 0
        let after: int = tally.count
        twisty.set_open(true)?
        twist_raises = raised && tally.count == after
        app.router.forget(twisty.handle())
    }
    io.println("  its header is chrome at the top and nothing else: {twist_ok}")
    io.println("  it holds children like any other box: {twist_holds}")
    io.println("  a user opens it loudly and a program quietly: {twist_raises}")

    // ------------------------------------------------------------- pages

    io.println("-- a tab view --")
    var pages_ok: bool = true
    var pages_order: bool = true
    var pages_refuse: bool = true
    var pages_raise: bool = true
    if widgets.WidgetKind.tab_view.available() {
        var tabs: widgets.TabView = widgets.TabView.of()?
        var first: widgets.Container = new widgets.Container()
        var second: widgets.Container = new widgets.Container()
        tabs.add_page(first, "General")?
        tabs.add_page(second, "Advanced")?
        // A page is a container, so it holds controls and the solver reaches
        // them — which is the whole reason pages are children.
        var inside: widgets.Label = widgets.Label.of("Nothing here yet")?
        first.add(inside)?
        pages_ok = tabs.count() == 2 && first.count() == 1 &&
                   tabs.label(0)? == "General" && tabs.label(1)? == "Advanced" &&
                   tabs.page()? == 0

        tabs.set_page(1)?
        pages_ok = pages_ok && tabs.page()? == 1

        // Its pages are children in every sense, including order, and a label
        // belongs to the page rather than to the position.
        tabs.move_child(0, 1)?
        pages_order = tabs.label(0)? == "Advanced"
        tabs.move_child(0, 1)?
        pages_order = pages_order && tabs.label(0)? == "General"

        // Every other control with a selection takes -1 for "none". A tab view
        // does not: it always shows one of its pages, and a caller who wanted
        // to show nothing wanted a different control.
        pages_refuse = refusal_label(tabs, 2) == "out_of_range" &&
                       refusal(tabs, host.P_SELECTED, 2) == "out_of_range" &&
                       refusal(tabs, host.P_SELECTED, -1) == "out_of_range"

        root.add(tabs)?
        // Back to the first page before the next line, because choosing the
        // page that is already showing is not a change and no platform raises
        // an event for it — a check that skipped this step would be testing
        // that nothing happened.
        tabs.set_page(0)?
        app.router.on(tabs.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                tally.count = tally.count + 1
                tally.last = event.index
            })
        let before: int = tally.count
        tabs.set_value_as_user(1, 0.0)?
        pages_raise = tally.count > before && tally.last == 1
        app.router.forget(tabs.handle())

        tabs.remove(1)?
        pages_ok = pages_ok && tabs.count() == 1
    }
    io.println("  its children are its pages, and its labels are not: {pages_ok}")
    io.println("  a page that moves takes its label with it: {pages_order}")
    io.println("  a page that is not there is refused, and so is none at all: {pages_refuse}")
    io.println("  a user choosing a tab raises the page it chose: {pages_raise}")

    // ------------------------------------------------------------ panes

    io.println("-- a split view --")
    var split_ok: bool = true
    var split_refuse: bool = true
    var split_raise: bool = true
    if widgets.WidgetKind.split_view.available() {
        var split: widgets.SplitView = widgets.SplitView.of(false)?
        var left: widgets.Container = new widgets.Container()
        var right: widgets.Container = new widgets.Container()
        split.add(left)?
        split.add(right)?
        root.add(split)?
        split.set_frame(geometry.Rect.of(0.0, 0.0, 300.0, 200.0))?

        split_ok = split.count() == 2 && !split.is_stacked()?
        split.set_stacked(true)?
        split_ok = split_ok && split.is_stacked()?
        split.set_stacked(false)?

        // The handle keeps room out of the axis it sits on, and nowhere else.
        let kept: geometry.EdgeInsets = split.content_inset()?
        split_ok = split_ok && kept.right > 0.0 && kept.left == 0.0 &&
                   kept.top == 0.0 && kept.bottom == 0.0 &&
                   split.handle_size()? == kept.right

        split.set_divider(120.0)?
        split_ok = split_ok && split.divider()? == 120.0

        // A third pane is refused rather than dropped, and so is a divider
        // outside the control.
        var third: widgets.Container = new widgets.Container()
        split_refuse = refusal_pane(split, third) == "too_many_panes" &&
                       refusal_real(split, host.P_DIVIDER, -1.0) == "out_of_range" &&
                       refusal_real(split, host.P_DIVIDER, 9000.0) == "out_of_range"

        app.router.on(split.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                tally.count = tally.count + 1
                tally.last = event.index
            })
        let before: int = tally.count
        split.set_value_as_user(0, 80.0)?
        split_raise = tally.count > before && tally.last == 80 &&
                      split.divider()? == 80.0
        app.router.forget(split.handle())
    }
    io.println("  its handle keeps room on the axis it sits on: {split_ok}")
    io.println("  a third pane is refused, and so is a handle off the control: {split_refuse}")
    io.println("  a user dragging the handle raises where it landed: {split_raise}")

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
