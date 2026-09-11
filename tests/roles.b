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
//   * the order of children;
//   * frames, from a layout where **every size is a constant**.
//
// And what it deliberately leaves out:
//
//   * the platform's own class name — `NSButton` here, `Button` on Win32,
//     `GtkButton` on Linux. That is in `tests/shelf.out`, which is per-platform
//     on purpose: it is the answer that proves a real native control was built,
//     and it cannot be the same everywhere.
//   * measured sizes. How wide "Order a coffee" renders depends on the system
//     font, so a golden carrying it would differ between two machines running
//     the same operating system, let alone two platforms.
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
    let frame: geometry.Rect = widget.frame()?
    var out: string = "{indent}{widget.kind().name()} role={role} \"{text}\" frame={frame.show()}"
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
    var rule: widgets.Separator = new widgets.Separator()
    var choice: widgets.ComboBox = widgets.ComboBox.of(["flat white", "espresso"])?
    choice.select(1)?
    var picture: widgets.ImageView = new widgets.ImageView()
    picture.set_hidden(true)?

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
    root.add(rule)?
    root.add(choice)?
    root.add(picture)?
    root.add(buttons)?

    // Every size here is a constant, and that is the point: the frames below
    // are arithmetic cortado did, not measurements a platform made, so two
    // platforms must agree on them exactly. A layout with one measured child
    // would move every sibling after it and make this file unportable.
    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(6.0)
    body.set_padding(geometry.EdgeInsets.all(16.0))
    body.set_align(geometry.Align.stretch)

    var page: layout.LayoutNode = sheet.group("page", root, body)
    page.add(fixed(sheet, "heading", heading, 20.0))
    page.add(fixed(sheet, "drink", drink, 24.0))
    page.add(fixed(sheet, "note", note, 60.0))
    page.add(fixed(sheet, "extra", extra, 20.0))
    page.add(fixed(sheet, "eat_in", eat_in, 20.0))
    page.add(fixed(sheet, "shots", shots, 20.0))
    page.add(fixed(sheet, "done", done, 12.0))
    page.add(fixed(sheet, "rule", rule, 1.0))
    page.add(fixed(sheet, "choice", choice, 24.0))
    page.add(fixed(sheet, "picture", picture, 40.0))

    var bar: layout.StackLayout = layout.StackLayout.row(8.0)
    bar.set_justify(layout.Justify.end)
    var row: layout.LayoutNode = sheet.group("buttons", buttons, bar)
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
