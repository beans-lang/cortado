// Every control cortado has, built and read back off the platform.
//
// One case per kind, and the point of it is the `native class` column: that is
// the platform's own answer about its own object, and it is the only thing
// that proves a real control was built rather than something cortado drew.
// When a second host lands, this file gets a second golden and the two are
// read side by side.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import cortado.geometry
import cortado.host
import std.io

// The step property belongs to a slider. Asking a text field for it is the
// check below, and naming it here keeps the test readable.
/// Three rows, made up on demand. A table asks rather than holds, so this is
/// the whole of its contents.
class Prices implements widgets.TableRows {
    pub fn init() {}
    pub fn row_count() -> int { return 3 }
    pub fn cell(row: int, column: int) -> string {
        let names: List<string> = ["flat white", "espresso", "cortado"]
        if column == 0 { return names[row] }
        return "{(row + 1) * 120}p"
    }
}

fn host_step() -> int {
    return host.P_STEP
}

fn build() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(480.0, 520.0, "Shelf")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Every control")?
    root.add(heading)?

    var press: widgets.Button = widgets.Button.of("Press")?
    root.add(press)?

    var field: widgets.TextField = widgets.TextField.of("one line")?
    root.add(field)?

    var note: widgets.TextArea = widgets.TextArea.of("several\nlines\nof text")?
    root.add(note)?

    var tick: widgets.CheckBox = widgets.CheckBox.of("Extra shot")?
    tick.set_state(widgets.CheckState.on)?
    root.add(tick)?

    // The two controls that are not on every platform in the same way. A
    // secure field is everywhere; a switch is not, and the golden below is
    // this Mac's — `tests/controls.out` is where the portable claim lives.
    // What this file proves is the native class column: NSSwitch and
    // NSSecureTextField, not an NSButton wearing a different title.
    var remember: widgets.Switch = widgets.Switch.of(true)?
    root.add(remember)?

    var secret: widgets.SecureField = widgets.SecureField.of("hunter2")?
    root.add(secret)?

    var pick: widgets.RadioButton = widgets.RadioButton.of("Decaf")?
    pick.set_chosen(true)?
    root.add(pick)?

    var amount: widgets.Slider = widgets.Slider.of(0.0, 10.0, 4.0)?
    amount.set_step(1.0)?
    root.add(amount)?

    var done: widgets.ProgressBar = widgets.ProgressBar.of(0.0, 100.0)?
    done.set_value(35.0)?
    root.add(done)?

    var shots: widgets.Stepper = widgets.Stepper.of(0.0, 8.0, 2.0, 4.0)?
    root.add(shots)?

    // The gauge, where there is one. macOS has NSLevelIndicator and this file
    // is the macOS golden, so it is built unconditionally — and would refuse
    // by name on a host that has none, which `tests/controls.out` covers
    // portably.
    var battery: widgets.LevelIndicator = widgets.LevelIndicator.of(0.0, 10.0, 7.0)?
    root.add(battery)?

    var rule: widgets.Separator = new widgets.Separator()
    root.add(rule)?

    var drink: widgets.ComboBox = widgets.ComboBox.of(["flat white", "espresso", "cortado"])?
    drink.select(2)?
    root.add(drink)?

    var picture: widgets.ImageView = new widgets.ImageView()
    root.add(picture)?

    var ledger: widgets.Table = widgets.Table.of(["Drink", "Price"])?
    ledger.set_source(new Prices())?
    root.add(ledger)?

    var scroller: widgets.ScrollView = new widgets.ScrollView()
    scroller.add(widgets.Label.of("inside the scroller")?)?
    root.add(scroller)?

    // Frames are set by hand here on purpose: this file is about what each
    // control *is*, and a golden that also carried measured sizes would change
    // whenever a system font did.
    var index: int = 0
    for child: widgets.Widget in root.children() {
        child.set_frame(geometry.Rect.of(20.0, 20.0 + (index as f64) * 36.0, 300.0, 28.0))?
        index = index + 1
    }

    io.print(widgets.WidgetDump.of(root)?)

    // What each control answers about its own state, read back from the
    // platform rather than from the value that was written.
    io.println("-- state --")
    io.println("slider value={amount.value().or(-1.0)} low={amount.low().or(-1.0)} high={amount.high().or(-1.0)}")
    io.println("progress value={done.value().or(-1.0)} indeterminate={done.is_indeterminate().or(true)}")
    io.println("combo items={drink.count().or(-1)} selected={drink.selected().or(-9)} text=\"{drink.display_text().or("?")}\"")
    io.println("combo item 0=\"{drink.item_at(0).or("?")}\" item 2=\"{drink.item_at(2).or("?")}\"")
    io.println("radio chosen={pick.is_chosen().or(false)}")
    io.println("switch on={remember.is_on().or(false)}")
    io.println("stepper value={shots.value().or(-1.0)} step={shots.step().or(-1.0)} low={shots.low().or(-1.0)} high={shots.high().or(-1.0)}")
    io.println("level {battery.level().or(-1.0)} of {battery.high().or(-1.0)}")
    io.println("table columns={ledger.column_count()} cell(1,0)=\"{ledger.native_cell(1, 0).or("?")}\" cell(2,1)=\"{ledger.native_cell(2, 1).or("?")}\"")
    // Read back on purpose: a secure field keeps its text from the screen, not
    // from the program that owns it.
    io.println("secure value=\"{secret.value().or("?")}\" shown=\"{secret.display_text().or("?")}\"")
    io.println("text area text=\"{note.text().or("?").replace("\n", "\\n")}\"")
    io.println("scroller children={scroller.count()}")

    // A control asked for a property it does not have must say so, not answer
    // a default. This is the same rule the container's enabled flag follows,
    // and it is what lets `describe` print a flag only where it means
    // something.
    io.println("-- refusals --")
    // A slider takes an increment and will not read one back: AppKit stores it
    // as a count of tick marks, and a count is not the number that was
    // written. The rule is beside CTD_P_STEP in the header.
    match amount.set_step(2.0) {
        ok(done) => { io.println("a slider took a step of 2") }
        err(problem) => { io.println("slider set step: {problem.kind}") }
    }
    match amount.read_property_real(host.P_STEP) {
        ok(size) => { io.println("a slider answered step={size}") }
        err(problem) => { io.println("slider read step: {problem.kind}") }
    }
    // A switch is on or off. Mixed is a state it does not have anywhere, which
    // is `out_of_range` rather than `unsupported` — see the rule beside
    // CTD_P_CHECKED in the header, and `tests/checked.out` for all of it.
    match remember.set_property(host.P_CHECKED, 2) {
        ok(done) => { io.println("a switch took the mixed state") }
        err(problem) => { io.println("switch mixed: {problem.kind}") }
    }
    match rule.is_enabled() {
        ok(on) => { io.println("a separator answered enabled={on}") }
        err(problem) => { io.println("separator enabled: {problem.kind}") }
    }
    // A button has no range, so asking a combo box's question of one must be
    // refused rather than answered with a zero.
    var borrowed: widgets.Slider = new widgets.Slider()
    match drink.item_at(9) {
        ok(text) => { io.println("a combo box answered item 9=\"{text}\"") }
        err(problem) => { io.println("combo item 9: {problem.kind}") }
    }
    match press.is_enabled() {
        ok(on) => { io.println("a button answered enabled={on}") }
        err(problem) => { io.println("button enabled: {problem.kind}") }
    }
    match field.set_property(host_step(), 1) {
        ok(done2) => { io.println("a text field accepted a step") }
        err(problem) => { io.println("text field step: {problem.kind}") }
    }

    // The event a control raises has to say which control it was and what it
    // said. A framework that reported every action as "activate" would make a
    // slider indistinguishable from a button to a handler, and every
    // application would work the kind out again from the control's class.
    io.println("-- events --")
    var seen: List<string> = []
    app.router.on(press.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { seen.push("button {event.kind.name()}") })
    app.router.on(tick.handle(), events.EventKind.value_changed,
        fn(event: events.UiEvent) { seen.push("check {event.kind.name()} index={event.index}") })
    app.router.on(amount.handle(), events.EventKind.value_changed,
        fn(event: events.UiEvent) { seen.push("slider {event.kind.name()} index={event.index}") })
    app.router.on(drink.handle(), events.EventKind.value_changed,
        fn(event: events.UiEvent) { seen.push("combo {event.kind.name()} index={event.index} text=\"{event.text}\"") })
    app.router.on(field.handle(), events.EventKind.text_commit,
        fn(event: events.UiEvent) { seen.push("field {event.kind.name()} text=\"{event.text}\"") })

    press.activate()?
    tick.set_value_as_user(1, 0.0)?
    amount.set_value_as_user(0, 7.0)?
    drink.set_value_as_user(1, 0.0)?
    field.set_text_as_user("typed by hand")?
    for line: string in seen {
        io.println("  {line}")
    }

    app.shutdown()
    return ok(true)
}

fn main() {
    match build() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
