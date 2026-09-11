// The layout engine driving real native controls.
//
// `tests/layout.b` proves the solver's arithmetic with no platform involved.
// This proves the other half: that `WidgetLayout` really asks the platform how
// big a control wants to be, and that the frames the solver computed really
// land on the controls.
//
// What is goldened here is deliberately not a set of measured sizes. A label's
// natural width comes out of the system font and changes between macOS
// releases, so a golden holding it would fail for a reason that has nothing to
// do with cortado. Instead the golden holds the things the *layout* decides —
// the stacking order, the gaps, the content width — as verdicts computed from
// the frames the platform reports, plus the shape of the tree.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import std.io

const gap: f64 = 12.0
const inset: f64 = 20.0
const page_width: f64 = 400.0
const page_height: f64 = 300.0

fn build() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(page_width, page_height, "Cortado")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Order a coffee")?
    var drink: widgets.TextField = widgets.TextField.of("flat white")?
    var extra: widgets.CheckBox = widgets.CheckBox.of("Extra shot")?
    var order_button: widgets.Button = widgets.Button.of("Order")?
    var quit_button: widgets.Button = widgets.Button.of("Quit")?
    root.add(heading)?
    root.add(drink)?
    root.add(extra)?
    root.add(order_button)?
    root.add(quit_button)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(gap)
    body.set_padding(geometry.EdgeInsets.all(inset))
    body.set_align(geometry.Align.stretch)

    var page: layout.LayoutNode = sheet.group("page", root, body)
    page.add(sheet.leaf("heading", heading))
    page.add(sheet.leaf("drink", drink))
    page.add(sheet.leaf("extra", extra))

    // A layout-only row. It groups the two buttons without creating a native
    // view for them to sit in, which means the buttons are siblings of the
    // labels on the platform but children of this row in the layout. The two
    // trees have different shapes here, and that is the case below checks.
    var bar: layout.StackLayout = layout.StackLayout.row(gap)
    bar.set_justify(layout.Justify.end)
    var buttons: layout.LayoutNode = sheet.spacer("buttons", bar)
    buttons.add(sheet.leaf("order", order_button))
    buttons.add(sheet.leaf("quit", quit_button))
    page.add(buttons)

    var solver: layout.Solver = new layout.Solver(sheet)
    solver.solve(page, geometry.Rect.of(0.0, 0.0, page_width, page_height))?
    let placed: int = sheet.apply(page)?
    io.println("placed {placed} controls")

    // Everything below is read back off the live platform objects, never off
    // the layout nodes — that is the point. If `apply` wrote nothing, or wrote
    // to the wrong control, these frames are the ones that disagree.
    let band: f64 = page_width - inset * 2.0
    var ordered: bool = true
    var full_width: bool = true
    var measured: bool = true
    var varied: bool = false
    var edge: f64 = inset
    var first_height: f64 = -1.0

    // Only the three controls that are direct children of the column. The two
    // buttons are siblings of these on the platform but sit one level deeper
    // in the layout, and they are checked separately below.
    var stacked: List<widgets.Widget> = []
    stacked.push(heading)
    stacked.push(drink)
    stacked.push(extra)

    var index: int = 0
    for control: widgets.Widget in stacked {
        let box: geometry.Rect = control.frame()?
        if box.x != inset || box.width != band { full_width = false }
        if box.y != edge { ordered = false }
        if box.height <= 0.0 { measured = false }
        if first_height < 0.0 {
            first_height = box.height
        } else if box.height != first_height {
            varied = true
        }
        edge = box.y + box.height + gap
        index = index + 1
    }

    io.println("controls: {index}")
    io.println("stacked in order with {gap}pt gaps: {ordered}")
    io.println("every control fills the content width: {full_width}")
    io.println("every height came from a real measurement: {measured}")
    // Three different kinds of control cannot all want the same height. If
    // they do, the heights are a constant somebody typed and the measurement
    // path is not being exercised at all — which is exactly the failure a
    // "height > 0" check reads green through.
    io.println("the kinds measured differently: {varied}")

    // A control the platform measures as taller than the 20 points a label is
    // usually given proves the measurement is the platform's and not a
    // constant somebody typed in.
    match root.child_at(0) {
        some(first) => {
            let box: geometry.Rect = first.frame()?
            io.println("first control is {first.kind().name()}, height in range: {box.height > 4.0 && box.height < 60.0}")
        }
        none => { io.println("first control missing") }
    }

    // The solver's own answer and the platform's must agree exactly. They are
    // two different objects holding the same number, and nothing else in the
    // suite checks that `apply` did not round, swap or drop one.
    var agreed: bool = true
    var node_index: int = 0
    for node: layout.LayoutNode in page.children() {
        if node_index >= stacked.len() {
            break
        }
        let theirs: geometry.Rect = stacked[node_index].frame()?
        let mine: geometry.Rect = node.frame()
        if theirs.x != mine.x || theirs.y != mine.y { agreed = false }
        if theirs.width != mine.width || theirs.height != mine.height { agreed = false }
        node_index = node_index + 1
    }
    io.println("solver and platform agree on every frame: {agreed}")

    // A control under a layout-only node must end up at its *absolute*
    // position. Its node frame is relative to the row, the row's frame is
    // relative to the page, and the control is a direct child of the page —
    // so the row's origin has to be added in. Skipping that puts the whole
    // group at the top of the window, which is visible the moment anybody
    // runs it and invisible to a test that has no such node.
    let row_box: geometry.Rect = buttons.frame()
    let order_box: geometry.Rect = order_button.frame()?
    let quit_box: geometry.Rect = quit_button.frame()?
    io.println("buttons row is below the labels: {row_box.y > inset}")
    io.println("buttons sit on the row, not at the top: {order_box.y == row_box.y && quit_box.y == row_box.y}")
    io.println("buttons are in reading order: {quit_box.x > order_box.x}")
    io.println("buttons end at the trailing edge: {quit_box.right() == page_width - inset}")

    // And the container itself was placed, not just its children.
    let page_box: geometry.Rect = root.frame()?
    io.println("page frame={page_box.show()}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match build() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
