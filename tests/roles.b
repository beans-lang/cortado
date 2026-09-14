// The one golden every platform must print.
//
// This file is what makes "write once, run anywhere" a test rather than a
// claim. When a second host lands, it prints **this same output** — not a
// similar tree, the same bytes — and the diff is the port's definition of done.
//
// So what it holds is carefully only the things every platform agrees on:
//
//   * the kind of control, which is cortado's word;
//   * its accessibility role, which is one shared vocabulary;
//   * its text, its enabled and hidden state;
//   * the order of children.
//
// And what it deliberately leaves out:
//
//   * the platform's own class name — `NSButton` here, `UISwitch` on iOS,
//     `GtkButton` on Linux. That is in `tests/shelf.out`, which is per-platform
//     on purpose: it is the answer that proves a real native control was built,
//     and it cannot be the same everywhere.
//
//   * **frames.** This one was learned rather than designed, and it is worth
//     the paragraph. The first version of this file pinned every size to a
//     constant, on the theory that a layout with no measurement in it must
//     produce identical frames everywhere. It does — and then two controls
//     came back a different size anyway, because **a platform control is
//     allowed to refuse the frame it is given**. A `UISwitch` is 51 by 31 and
//     nothing else; a `UIProgressView` is 4 points tall whatever you ask for.
//     Both clamp, silently and correctly.
//
//     So a frame is not a portable fact, and the file that claims to be the
//     portable contract must not hold one. Frames are covered better
//     elsewhere: `tests/layout.out` checks 69 cases of the solver's own
//     arithmetic on every runner with no platform at all, and
//     `tests/shelf.out` records what each platform actually did with them.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import std.io

fn line(depth: int, widget: widgets.Widget) -> Result<string> {
    var indent: string = ""
    var level: int = 0
    for level: int in 0..depth {
        indent = "{indent}  "
    }
    let role: string = widget.a11y_role()?
    let text: string = widget.display_text()?
    var out: string = "{indent}{widget.kind().name()} role={role} \"{text}\""
    match widget.is_enabled() {
        ok(on) => { if !on { out = "{out} disabled" } }
        err(absent) => {}
    }
    match widget.is_hidden() {
        ok(hidden) => { if hidden { out = "{out} hidden" } }
        err(absent) => {}
    }
    let kids: List<widgets.Widget> = widget.children()
    if kids.len() > 0 {
        out = "{out} children={kids.len()}"
    }
    return ok(out)
}

fn walk(depth: int, widget: widgets.Widget) -> Result<bool> {
    io.println(line(depth, widget)?)
    for child: widgets.Widget in widget.children() {
        walk(depth + 1, child)?
    }
    return ok(true)
}

fn build() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(400.0, 400.0, "Roles")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Order a coffee")?
    var drink: widgets.TextField = widgets.TextField.of("flat white")?
    var note: widgets.TextArea = widgets.TextArea.of("no sugar")?
    var extra: widgets.CheckBox = widgets.CheckBox.of("Extra shot")?
    extra.set_state(widgets.CheckState.on)?
    var eat_in: widgets.RadioButton = widgets.RadioButton.of("Eat in")?
    eat_in.set_chosen(true)?
    var shots: widgets.Slider = widgets.Slider.of(1.0, 4.0, 2.0)?
    var done: widgets.ProgressBar = widgets.ProgressBar.of(0.0, 4.0)?
    done.set_value(2.0)?
    // A stepper is here and a level indicator is not, for the same reason the
    // secure field is here and the switch is not: every host has a stepper,
    // and only two have a gauge.
    var shots_up: widgets.Stepper = widgets.Stepper.of(1.0, 4.0, 1.0, 2.0)?
    var rule: widgets.Separator = new widgets.Separator()
    var choice: widgets.ComboBox = widgets.ComboBox.of(["flat white", "espresso"])?
    choice.select(1)?
    // A secure field is here and a switch is not, and the difference is the
    // whole of `ctd_widget_supports`: every host has a secure field, and the
    // Win32 common controls have no toggle switch. This file is the golden
    // every platform must print, so it holds only what every platform has.
    var find: widgets.SearchField = widgets.SearchField.of("Search orders")?
    var secret: widgets.SecureField = widgets.SecureField.of("hunter2")?
    // One column, because that is what every host has — a UITableView is a
    // list. `tests/table.out` is where the second column's answer lives.
    var orders: widgets.Table = widgets.Table.of(["Order"])?
    var manual: widgets.Link = widgets.Link.of("Read the manual", "https://beans-lang.org")?
    var picture: widgets.ImageView = new widgets.ImageView()
    picture.set_hidden(true)?
    // A canvas is here for the same reason every other control is: it is a
    // real control on all four hosts, laid out by the same solver and in the
    // same tree, and this file is where that is checked. Nothing is drawn into
    // it — that is `tests/canvas.b`'s job, and only two hosts can.
    var plot: widgets.Canvas = new widgets.Canvas()

    var buttons: widgets.Container = new widgets.Container()
    var order: widgets.Button = widgets.Button.of("Order")?
    var cancel: widgets.Button = widgets.Button.of("Cancel")?
    cancel.set_enabled(false)?
    buttons.add(order)?
    buttons.add(cancel)?

    root.add(heading)?
    root.add(drink)?
    root.add(note)?
    root.add(extra)?
    root.add(eat_in)?
    root.add(shots)?
    root.add(done)?
    root.add(shots_up)?
    root.add(rule)?
    root.add(choice)?
    root.add(find)?
    root.add(secret)?
    root.add(orders)?
    root.add(manual)?
    root.add(picture)?
    root.add(plot)?
    root.add(buttons)?

    // Every size here is a constant, and that is the point: the frames below
    // are arithmetic cortado did, not measurements a platform made, so two
    // platforms must agree on them exactly. A layout with one measured child
    // would move every sibling after it and make this file unportable.
    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(6.0)
    body.set_padding(geometry.EdgeInsets.all(16.0))
    body.set_align(geometry.Align.stretch)

    var page: layout.LayoutNode = sheet.group("page", root, body)?
    page.add(fixed(sheet, "heading", heading, 20.0))
    page.add(fixed(sheet, "drink", drink, 24.0))
    page.add(fixed(sheet, "note", note, 60.0))
    page.add(fixed(sheet, "extra", extra, 20.0))
    page.add(fixed(sheet, "eat_in", eat_in, 20.0))
    page.add(fixed(sheet, "shots", shots, 20.0))
    page.add(fixed(sheet, "done", done, 12.0))
    page.add(fixed(sheet, "shots_up", shots_up, 20.0))
    page.add(fixed(sheet, "rule", rule, 1.0))
    page.add(fixed(sheet, "choice", choice, 24.0))
    page.add(fixed(sheet, "find", find, 24.0))
    page.add(fixed(sheet, "secret", secret, 24.0))
    page.add(fixed(sheet, "orders", orders, 40.0))
    page.add(fixed(sheet, "manual", manual, 20.0))
    page.add(fixed(sheet, "picture", picture, 40.0))
    page.add(fixed(sheet, "plot", plot, 32.0))

    var bar: layout.StackLayout = layout.StackLayout.row(8.0)
    bar.set_justify(layout.Justify.end)
    var row: layout.LayoutNode = sheet.group("buttons", buttons, bar)?
    row.spec = pinned(28.0)
    row.add(sized(sheet, "order", order, 90.0, 28.0))
    row.add(sized(sheet, "cancel", cancel, 90.0, 28.0))
    page.add(row)

    var solver: layout.Solver = new layout.Solver(sheet)
    solver.solve(page, geometry.Rect.of(0.0, 0.0, 400.0, 400.0))?
    sheet.apply(page)?

    walk(0, root)?

    app.shutdown()
    return ok(true)
}

// A child of a fixed height, stretched to the column's width.
fn fixed(sheet: widgets.WidgetLayout, name: string,
         control: widgets.Widget, height: f64) -> layout.LayoutNode {
    var node: layout.LayoutNode = sheet.leaf(name, control)
    node.spec = pinned(height)
    return node
}

fn pinned(height: f64) -> layout.LayoutSpec {
    var spec: layout.LayoutSpec = layout.LayoutSpec.auto()
    spec.min_height = height
    spec.max_height = height
    return spec
}

fn sized(sheet: widgets.WidgetLayout, name: string, control: widgets.Widget,
         width: f64, height: f64) -> layout.LayoutNode {
    var node: layout.LayoutNode = sheet.leaf(name, control)
    node.spec = layout.LayoutSpec.fixed(width, height)
    return node
}

fn main() {
    match build() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
