// The layout engine, exercised without a display.
//
// Every frame in the golden file is arithmetic the solver did from numbers
// written down here, so this program produces identical output on macOS,
// Windows and Linux, under the tree interpreter and a native binary. No
// window server, no foreign function call, no font. A difference is a solver
// change and can be nothing else.
package main

import cortado.layout
import cortado.geometry
import std.io

// ---- harness ----

// Every case gets the same measurements, so a frame that moves between two
// cases moved because the layout changed and not because a leaf did.
//
//   1  100 x 20     2  60 x 30      3  40 x 40
//   4  200 x 16     5  24 x 24      6  80 x 12
fn ruler() -> layout.TableMeasure {
    var table: layout.TableMeasure = new layout.TableMeasure()
    table.put(1, 100.0, 20.0)
    table.put(2, 60.0, 30.0)
    table.put(3, 40.0, 40.0)
    table.put(4, 200.0, 16.0)
    table.put(5, 24.0, 24.0)
    table.put(6, 80.0, 12.0)
    return table
}

fn show(name: string, root: layout.LayoutNode, solver: layout.Solver,
        width: f64, height: f64) {
    io.println("== {name} ==")
    match solver.solve(root, geometry.Rect.of(0.0, 0.0, width, height)) {
        ok(done) => { io.print(layout.LayoutDump.tree(root)) }
        err(problem) => { io.println("  FAILED {problem.kind}: {problem.msg}") }
    }
}

fn run(name: string, root: layout.LayoutNode, width: f64, height: f64) {
    var solver: layout.Solver = new layout.Solver(ruler())
    show(name, root, solver, width, height)
}

fn run_rtl(name: string, root: layout.LayoutNode, width: f64, height: f64) {
    var solver: layout.Solver = new layout.Solver(ruler())
    solver.set_direction(layout.TextDirection.rtl)
    show(name, root, solver, width, height)
}

fn run_scaled(name: string, root: layout.LayoutNode, scale: f64,
              width: f64, height: f64) {
    var solver: layout.Solver = new layout.Solver(ruler())
    solver.set_scale(scale)
    show(name, root, solver, width, height)
}

fn leaf(name: string, key: int) -> layout.LayoutNode {
    return layout.LayoutNode.leaf(name, key)
}

fn spec_leaf(name: string, key: int, spec: layout.LayoutSpec) -> layout.LayoutNode {
    var node: layout.LayoutNode = layout.LayoutNode.leaf(name, key)
    node.spec = spec
    return node
}

fn column(spacing: f64) -> layout.StackLayout {
    return layout.StackLayout.column(spacing)
}

fn row(spacing: f64) -> layout.StackLayout {
    return layout.StackLayout.row(spacing)
}

/// A run that stretches its children across, so a child with no opinion about
/// its cross-axis size gets the whole width — which is what makes the `tall`
/// and `wide` cases below mean something: a spec that pinned the other axis
/// to zero would win over the stretch and show it.
fn stretched_column(spacing: f64) -> layout.StackLayout {
    var stack: layout.StackLayout = layout.StackLayout.column(spacing)
    stack.set_align(geometry.Align.stretch)
    return stack
}

fn stretched_row(spacing: f64) -> layout.StackLayout {
    var stack: layout.StackLayout = layout.StackLayout.row(spacing)
    stack.set_align(geometry.Align.stretch)
    return stack
}

// ---- 1. stacks ----

fn stacks() {
    var plain: layout.LayoutNode = layout.LayoutNode.group("root", column(0.0))
    plain.add(leaf("a", 1))
    plain.add(leaf("b", 2))
    plain.add(leaf("c", 3))
    run("column, no spacing", plain, 300.0, 300.0)

    var spaced: layout.LayoutNode = layout.LayoutNode.group("root", column(8.0))
    spaced.add(leaf("a", 1))
    spaced.add(leaf("b", 2))
    spaced.add(leaf("c", 3))
    run("column, spacing 8", spaced, 300.0, 300.0)

    var across: layout.LayoutNode = layout.LayoutNode.group("root", row(12.0))
    across.add(leaf("a", 1))
    across.add(leaf("b", 2))
    run("row, spacing 12", across, 300.0, 300.0)

    var padded_layout: layout.StackLayout = column(4.0)
    padded_layout.set_padding(geometry.EdgeInsets.all(10.0))
    var padded: layout.LayoutNode = layout.LayoutNode.group("root", padded_layout)
    padded.add(leaf("a", 1))
    padded.add(leaf("b", 2))
    run("column, padding 10", padded, 300.0, 300.0)

    var lopsided_layout: layout.StackLayout = column(0.0)
    lopsided_layout.set_padding(geometry.EdgeInsets.of(4.0, 8.0, 16.0, 32.0))
    var lopsided: layout.LayoutNode = layout.LayoutNode.group("root", lopsided_layout)
    lopsided.add(leaf("a", 1))
    run("column, asymmetric padding", lopsided, 300.0, 300.0)

    var empty: layout.LayoutNode = layout.LayoutNode.group("root", column(8.0))
    run("column, no children", empty, 300.0, 300.0)

    var single: layout.LayoutNode = layout.LayoutNode.group("root", column(8.0))
    single.add(leaf("only", 1))
    run("column, one child", single, 300.0, 300.0)
}

// ---- 2. cross-axis alignment ----

fn alignment() {
    var starts: layout.StackLayout = column(4.0)
    starts.set_align(geometry.Align.start)
    var a: layout.LayoutNode = layout.LayoutNode.group("root", starts)
    a.add(leaf("wide", 4))
    a.add(leaf("narrow", 5))
    run("align start", a, 300.0, 300.0)

    var centred: layout.StackLayout = column(4.0)
    centred.set_align(geometry.Align.center)
    var b: layout.LayoutNode = layout.LayoutNode.group("root", centred)
    b.add(leaf("wide", 4))
    b.add(leaf("narrow", 5))
    run("align center", b, 300.0, 300.0)

    var ends: layout.StackLayout = column(4.0)
    ends.set_align(geometry.Align.end)
    var c: layout.LayoutNode = layout.LayoutNode.group("root", ends)
    c.add(leaf("wide", 4))
    c.add(leaf("narrow", 5))
    run("align end", c, 300.0, 300.0)

    var filled: layout.StackLayout = column(4.0)
    filled.set_align(geometry.Align.stretch)
    var d: layout.LayoutNode = layout.LayoutNode.group("root", filled)
    d.add(leaf("wide", 4))
    d.add(leaf("narrow", 5))
    run("align stretch", d, 300.0, 300.0)

    // A child's own alignment beats the run's default; a child that says
    // nothing takes the default.
    var mixed: layout.StackLayout = column(4.0)
    mixed.set_align(geometry.Align.center)
    var e: layout.LayoutNode = layout.LayoutNode.group("root", mixed)
    e.add(leaf("inherits", 5))
    var pinned: layout.LayoutSpec = layout.LayoutSpec.auto()
    pinned.align = geometry.Align.end
    e.add(spec_leaf("overrides", 5, pinned))
    run("align per child", e, 300.0, 300.0)

    var stretched_row: layout.StackLayout = row(4.0)
    stretched_row.set_align(geometry.Align.stretch)
    var f: layout.LayoutNode = layout.LayoutNode.group("root", stretched_row)
    f.add(leaf("a", 1))
    f.add(leaf("b", 2))
    run("row align stretch", f, 300.0, 120.0)
}

// ---- 3. main-axis justification ----

fn justification() {
    var modes: List<layout.Justify> = [layout.Justify.start, layout.Justify.center,
                                       layout.Justify.end, layout.Justify.space_between,
                                       layout.Justify.space_around,
                                       layout.Justify.space_evenly]
    for mode: layout.Justify in modes {
        var bar: layout.StackLayout = row(0.0)
        bar.set_justify(mode)
        var node: layout.LayoutNode = layout.LayoutNode.group("root", bar)
        node.add(leaf("a", 5))
        node.add(leaf("b", 5))
        node.add(leaf("c", 5))
        run("justify {mode.name()}", node, 300.0, 60.0)
    }

    // One child has no "between", so space_between pins it to the start while
    // the other two still centre it.
    var lone: layout.StackLayout = row(0.0)
    lone.set_justify(layout.Justify.space_between)
    var one: layout.LayoutNode = layout.LayoutNode.group("root", lone)
    one.add(leaf("only", 5))
    run("justify space_between, one child", one, 300.0, 60.0)

    var lone_even: layout.StackLayout = row(0.0)
    lone_even.set_justify(layout.Justify.space_evenly)
    var one_even: layout.LayoutNode = layout.LayoutNode.group("root", lone_even)
    one_even.add(leaf("only", 5))
    run("justify space_evenly, one child", one_even, 300.0, 60.0)

    // Overflow: there is no free space to share, so every mode packs at the
    // start and the run spills past its own edge rather than overlapping.
    var tight: layout.StackLayout = row(0.0)
    tight.set_justify(layout.Justify.space_between)
    var over: layout.LayoutNode = layout.LayoutNode.group("root", tight)
    over.add(leaf("a", 4))
    over.add(leaf("b", 4))
    run("justify with overflow", over, 300.0, 60.0)
}

// ---- 4. margins ----

fn margins() {
    var node: layout.LayoutNode = layout.LayoutNode.group("root", column(0.0))
    var top: layout.LayoutSpec = layout.LayoutSpec.auto()
    top.margin = geometry.EdgeInsets.all(6.0)
    node.add(spec_leaf("boxed", 1, top))
    var side: layout.LayoutSpec = layout.LayoutSpec.auto()
    side.margin = geometry.EdgeInsets.of(2.0, 40.0, 2.0, 8.0)
    node.add(spec_leaf("lopsided", 1, side))
    run("margins in a column", node, 300.0, 300.0)

    var across: layout.LayoutNode = layout.LayoutNode.group("root", row(0.0))
    var gap: layout.LayoutSpec = layout.LayoutSpec.auto()
    gap.margin = geometry.EdgeInsets.symmetric(10.0, 0.0)
    across.add(spec_leaf("a", 5, gap))
    across.add(spec_leaf("b", 5, gap))
    run("margins in a row", across, 300.0, 60.0)

    // A stretched child fills the room its margin leaves, not the whole box.
    var filling: layout.StackLayout = column(0.0)
    filling.set_align(geometry.Align.stretch)
    var stretched: layout.LayoutNode = layout.LayoutNode.group("root", filling)
    var inset: layout.LayoutSpec = layout.LayoutSpec.auto()
    inset.margin = geometry.EdgeInsets.symmetric(25.0, 0.0)
    stretched.add(spec_leaf("banner", 1, inset))
    run("margin under stretch", stretched, 300.0, 60.0)
}

// ---- 5. size bounds ----

fn bounds() {
    var node: layout.LayoutNode = layout.LayoutNode.group("root", column(0.0))
    var floor: layout.LayoutSpec = layout.LayoutSpec.auto()
    floor.min_width = 150.0
    floor.min_height = 50.0
    node.add(spec_leaf("has minimum", 2, floor))
    var ceiling: layout.LayoutSpec = layout.LayoutSpec.auto()
    ceiling.max_width = 40.0
    ceiling.max_height = 10.0
    node.add(spec_leaf("has maximum", 1, ceiling))
    run("min and max on a child", node, 300.0, 300.0)

    var exact: layout.LayoutNode = layout.LayoutNode.group("root", column(0.0))
    exact.add(spec_leaf("pinned", 1, layout.LayoutSpec.fixed(77.0, 33.0)))
    run("fixed size", exact, 300.0, 300.0)

    // One axis pinned and the other left alone, which is what a text area, a
    // status row and a sidebar all want, and what `fixed` cannot say. Writing
    // `fixed(0.0, 33.0)` for it reads like "33 tall, whatever wide" and asks
    // for a box zero points across — laid out exactly as written, reporting
    // nothing, invisible on screen. `examples/panes.b` shipped that way, so
    // both of these are stretched here in a run that would otherwise give
    // them their measured size: the height case must come out full width and
    // the width case full height.
    var one_axis: layout.LayoutNode = layout.LayoutNode.group("root", stretched_column(0.0))
    one_axis.add(spec_leaf("tall only", 1, layout.LayoutSpec.tall(33.0)))
    run("height pinned, width left alone", one_axis, 300.0, 300.0)

    var across_axis: layout.LayoutNode = layout.LayoutNode.group("root", stretched_row(0.0))
    across_axis.add(spec_leaf("wide only", 1, layout.LayoutSpec.wide(77.0)))
    run("width pinned, height left alone", across_axis, 300.0, 300.0)

    // A child may not out-grow the room its parent has, even asking for it.
    var greedy: layout.LayoutNode = layout.LayoutNode.group("root", column(0.0))
    var huge: layout.LayoutSpec = layout.LayoutSpec.auto()
    huge.min_width = 500.0
    greedy.add(spec_leaf("too wide", 1, huge))
    run("child wider than parent", greedy, 300.0, 300.0)

    // A child that asks to grow, in a layout that hands nothing out. Refused
    // rather than ignored: the silent version cost three afternoons — a canvas
    // 0 points wide, a table 0 points wide, a search field squeezed to its
    // intrinsic size — each laid out exactly as asked and none of them saying
    // anything.
    var mistaken: layout.LayoutNode = layout.LayoutNode.group("root", row(0.0))
    mistaken.add(spec_leaf("wants room", 5, layout.LayoutSpec.flexible(1.0)))
    run("grow in a stack", mistaken, 300.0, 60.0)

    // A leaf measures at most what it is offered — the table's 200pt label in
    // a 120pt box comes back 120 wide.
    var narrow: layout.StackLayout = column(0.0)
    narrow.set_padding(geometry.EdgeInsets.symmetric(90.0, 0.0))
    var clipped: layout.LayoutNode = layout.LayoutNode.group("root", narrow)
    clipped.add(leaf("long label", 4))
    run("leaf clipped by padding", clipped, 300.0, 300.0)
}

// ---- 6. flex ----

fn flexing() {
    var even: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    even.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    even.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    even.add(spec_leaf("c", 5, layout.LayoutSpec.flexible(1.0)))
    run("flex, equal weights", even, 300.0, 60.0)

    var weighted: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    weighted.add(spec_leaf("one", 5, layout.LayoutSpec.flexible(1.0)))
    weighted.add(spec_leaf("two", 5, layout.LayoutSpec.flexible(2.0)))
    run("flex, 1 and 2", weighted, 300.0, 60.0)

    var partial: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    partial.add(leaf("fixed", 1))
    partial.add(spec_leaf("rest", 5, layout.LayoutSpec.flexible(1.0)))
    run("flex, one rigid one flexible", partial, 300.0, 60.0)

    var spaced: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(10.0))
    spaced.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    spaced.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    run("flex with spacing", spaced, 300.0, 60.0)

    // The freeze loop: `b` cannot pass 80, so the space it refuses goes to
    // `a` and `c` rather than being lost. Dividing once and clamping after
    // would leave 300 points of room holding 260 points of children.
    var capped: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    capped.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    var limited: layout.LayoutSpec = layout.LayoutSpec.flexible(1.0)
    limited.max_width = 80.0
    capped.add(spec_leaf("b", 5, limited))
    capped.add(spec_leaf("c", 5, layout.LayoutSpec.flexible(1.0)))
    run("flex with a maximum", capped, 300.0, 60.0)

    var floored: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    var big: layout.LayoutSpec = layout.LayoutSpec.flexible(1.0)
    big.min_width = 200.0
    floored.add(spec_leaf("a", 5, big))
    floored.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    run("flex with a minimum", floored, 300.0, 60.0)

    var based: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    var from: layout.LayoutSpec = layout.LayoutSpec.flexible(1.0)
    from.basis = 100.0
    based.add(spec_leaf("a", 5, from))
    based.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    run("flex from a basis", based, 300.0, 60.0)

    // Nobody grows, so the run under-fills and justify decides where the
    // leftover shows up.
    var idle: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    idle.add(leaf("a", 5))
    idle.add(leaf("b", 5))
    run("flex with no weights", idle, 300.0, 60.0)

    var column_flex: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.column(0.0))
    column_flex.add(spec_leaf("head", 6, layout.LayoutSpec.auto()))
    column_flex.add(spec_leaf("body", 6, layout.LayoutSpec.flexible(1.0)))
    column_flex.add(spec_leaf("foot", 6, layout.LayoutSpec.auto()))
    run("flex column, body fills", column_flex, 200.0, 200.0)
}

fn shrinking() {
    // 200 + 200 into 300: both give up 50.
    var even: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    even.add(leaf("a", 4))
    even.add(leaf("b", 4))
    run("shrink, equal sizes", even, 300.0, 60.0)

    // 200 and 100 into 240: the wider one gives up more, because shrinking is
    // weighted by size as well as by factor. A plain factor split would take
    // the same 30 from each and squeeze the narrow one twice as hard.
    var uneven: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    uneven.add(leaf("wide", 4))
    var half: layout.LayoutSpec = layout.LayoutSpec.auto()
    half.max_width = 100.0
    uneven.add(spec_leaf("narrow", 4, half))
    run("shrink, weighted by size", uneven, 240.0, 60.0)

    // shrink 0 means "do not take it out of me": the other child absorbs all
    // of the overflow.
    var rigid: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    var never: layout.LayoutSpec = layout.LayoutSpec.auto()
    never.shrink = 0.0
    rigid.add(spec_leaf("rigid", 4, never))
    rigid.add(leaf("gives", 4))
    run("shrink, one refuses", rigid, 300.0, 60.0)

    // A minimum stops the shrink and the run overflows, visibly, rather than
    // crushing the child to nothing.
    var floored: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    var keep: layout.LayoutSpec = layout.LayoutSpec.auto()
    keep.min_width = 180.0
    floored.add(spec_leaf("keeps 180", 4, keep))
    floored.add(leaf("b", 4))
    run("shrink against a minimum", floored, 300.0, 60.0)
}

// ---- 7. nesting ----

fn nesting() {
    var outer: layout.StackLayout = column(10.0)
    outer.set_padding(geometry.EdgeInsets.all(16.0))
    var root: layout.LayoutNode = layout.LayoutNode.group("root", outer)
    root.add(leaf("title", 4))

    var inner: layout.StackLayout = row(8.0)
    inner.set_justify(layout.Justify.end)
    var buttons: layout.LayoutNode = layout.LayoutNode.group("buttons", inner)
    buttons.add(leaf("ok", 2))
    buttons.add(leaf("cancel", 2))
    var fill: layout.LayoutSpec = layout.LayoutSpec.auto()
    fill.align = geometry.Align.stretch
    buttons.spec = fill
    root.add(buttons)

    run("nested row inside a column", root, 320.0, 200.0)

    // A flex row nested in a flex column: the inner row shares the width it
    // was given, not the width it measured.
    var shell: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.column(0.0))
    var band: layout.LayoutNode = layout.LayoutNode.group("band", layout.FlexLayout.row(0.0))
    band.add(spec_leaf("left", 5, layout.LayoutSpec.flexible(1.0)))
    band.add(spec_leaf("right", 5, layout.LayoutSpec.flexible(3.0)))
    var wide: layout.LayoutSpec = layout.LayoutSpec.flexible(1.0)
    wide.align = geometry.Align.stretch
    band.spec = wide
    shell.add(band)
    run("flex inside flex", shell, 200.0, 100.0)
}

// ---- 8. grid ----

fn grids() {
    var three: layout.GridLayout = layout.GridLayout.uniform(3, 10.0)
    var root: layout.LayoutNode = layout.LayoutNode.group("root", three)
    root.add(leaf("a", 5))
    root.add(leaf("b", 5))
    root.add(leaf("c", 5))
    root.add(leaf("d", 5))
    run("grid, three equal columns", root, 320.0, 200.0)

    var mixed: layout.GridLayout = new layout.GridLayout()
    mixed.add_column(layout.Track.fixed(80.0))
    mixed.add_column(layout.Track.fraction(1.0))
    mixed.set_gaps(12.0, 6.0)
    var form: layout.LayoutNode = layout.LayoutNode.group("root", mixed)
    form.add(leaf("label", 6))
    form.add(leaf("field", 1))
    form.add(leaf("label2", 6))
    form.add(leaf("field2", 1))
    run("grid, fixed and fraction", form, 300.0, 200.0)

    var sized: layout.GridLayout = new layout.GridLayout()
    sized.add_column(layout.Track.auto())
    sized.add_column(layout.Track.fraction(1.0))
    sized.set_gaps(8.0, 8.0)
    var auto: layout.LayoutNode = layout.LayoutNode.group("root", sized)
    auto.add(leaf("narrow", 5))
    auto.add(leaf("rest", 1))
    auto.add(leaf("wider", 2))
    auto.add(leaf("rest2", 1))
    run("grid, auto column takes the widest", auto, 300.0, 200.0)

    var weighted: layout.GridLayout = new layout.GridLayout()
    weighted.add_column(layout.Track.fraction(1.0))
    weighted.add_column(layout.Track.fraction(2.0))
    var split: layout.LayoutNode = layout.LayoutNode.group("root", weighted)
    split.add(leaf("one", 5))
    split.add(leaf("two", 5))
    run("grid, 1fr and 2fr", split, 300.0, 100.0)

    var filled: layout.GridLayout = layout.GridLayout.uniform(2, 0.0)
    filled.set_align(geometry.Align.stretch)
    var cells: layout.LayoutNode = layout.LayoutNode.group("root", filled)
    cells.add(leaf("a", 5))
    cells.add(leaf("b", 5))
    run("grid, stretch into the cell", cells, 200.0, 100.0)

    var centred: layout.GridLayout = layout.GridLayout.uniform(2, 0.0)
    centred.set_align(geometry.Align.center)
    var middled: layout.LayoutNode = layout.LayoutNode.group("root", centred)
    middled.add(leaf("a", 5))
    middled.add(leaf("b", 5))
    run("grid, centre in the cell", middled, 200.0, 100.0)

    // Rows are as tall as the tallest child, and the last row may be ragged.
    var ragged: layout.GridLayout = layout.GridLayout.uniform(2, 4.0)
    var five: layout.LayoutNode = layout.LayoutNode.group("root", ragged)
    five.add(leaf("a", 5))
    five.add(leaf("tall", 3))
    five.add(leaf("c", 5))
    five.add(leaf("d", 5))
    five.add(leaf("odd one out", 5))
    run("grid, ragged last row", five, 200.0, 200.0)

    var pinned: layout.GridLayout = layout.GridLayout.uniform(2, 0.0)
    pinned.add_row(layout.Track.fixed(50.0))
    var rows: layout.LayoutNode = layout.LayoutNode.group("root", pinned)
    rows.add(leaf("a", 5))
    rows.add(leaf("b", 5))
    rows.add(leaf("c", 5))
    rows.add(leaf("d", 5))
    run("grid, first row pinned to 50", rows, 200.0, 200.0)

    var padded: layout.GridLayout = layout.GridLayout.uniform(2, 10.0)
    padded.set_padding(geometry.EdgeInsets.all(12.0))
    var inset: layout.LayoutNode = layout.LayoutNode.group("root", padded)
    inset.add(leaf("a", 5))
    inset.add(leaf("b", 5))
    run("grid, padded", inset, 200.0, 100.0)

    var bare: layout.LayoutNode = layout.LayoutNode.group("root", layout.GridLayout.uniform(3, 8.0))
    run("grid, no children", bare, 200.0, 100.0)
}

// ---- 9. absolute ----

fn absolute() {
    var free: layout.LayoutNode = layout.LayoutNode.group("root", new layout.AbsoluteLayout())
    free.add(spec_leaf("badge", 5, layout.LayoutSpec.at(240.0, 8.0)))
    free.add(spec_leaf("caption", 6, layout.LayoutSpec.at(12.0, 120.0)))
    run("absolute positions", free, 300.0, 160.0)

    var padded: layout.AbsoluteLayout = new layout.AbsoluteLayout()
    padded.set_padding(geometry.EdgeInsets.all(20.0))
    var inset: layout.LayoutNode = layout.LayoutNode.group("root", padded)
    inset.add(spec_leaf("pinned", 5, layout.LayoutSpec.at(0.0, 0.0)))
    run("absolute inside padding", inset, 300.0, 160.0)

    // Nothing is pulled back inside: a child placed past the edge stays put,
    // where it can be seen and fixed.
    var spilling: layout.LayoutNode = layout.LayoutNode.group("root", new layout.AbsoluteLayout())
    spilling.add(spec_leaf("outside", 5, layout.LayoutSpec.at(290.0, 150.0)))
    run("absolute past the edge", spilling, 300.0, 160.0)
}

// ---- 10. right to left ----

fn mirroring() {
    var bar: layout.LayoutNode = layout.LayoutNode.group("root", row(10.0))
    bar.add(leaf("first", 5))
    bar.add(leaf("second", 2))
    bar.add(leaf("third", 5))
    run("row, left to right", bar, 300.0, 60.0)

    var mirrored: layout.LayoutNode = layout.LayoutNode.group("root", row(10.0))
    mirrored.add(leaf("first", 5))
    mirrored.add(leaf("second", 2))
    mirrored.add(leaf("third", 5))
    run_rtl("row, right to left", mirrored, 300.0, 60.0)

    // A column does not reorder, but its children still sit against the other
    // edge, because `start` is a logical edge.
    var down: layout.StackLayout = column(4.0)
    down.set_align(geometry.Align.start)
    var stacked: layout.LayoutNode = layout.LayoutNode.group("root", down)
    stacked.add(leaf("a", 5))
    stacked.add(leaf("b", 2))
    run_rtl("column start edge, right to left", stacked, 300.0, 100.0)

    // Padding belongs to the container, not to the reading order: 30 points
    // on the left stay on the left after the flip.
    var uneven: layout.StackLayout = row(0.0)
    uneven.set_padding(geometry.EdgeInsets.of(0.0, 10.0, 0.0, 30.0))
    var lopsided: layout.LayoutNode = layout.LayoutNode.group("root", uneven)
    lopsided.add(leaf("a", 5))
    lopsided.add(leaf("b", 5))
    run_rtl("asymmetric padding, right to left", lopsided, 300.0, 60.0)

    var deep: layout.LayoutNode = layout.LayoutNode.group("root", column(0.0))
    var inner: layout.LayoutNode = layout.LayoutNode.group("inner", row(6.0))
    inner.add(leaf("a", 5))
    inner.add(leaf("b", 5))
    var fill: layout.LayoutSpec = layout.LayoutSpec.auto()
    fill.align = geometry.Align.stretch
    inner.spec = fill
    deep.add(inner)
    run_rtl("nested row, right to left", deep, 300.0, 100.0)

    // Absolute coordinates are physical by definition, so they do not flip.
    var fixed: layout.LayoutNode = layout.LayoutNode.group("root", new layout.AbsoluteLayout())
    fixed.add(spec_leaf("badge", 5, layout.LayoutSpec.at(240.0, 8.0)))
    run_rtl("absolute, right to left", fixed, 300.0, 60.0)

    var grid: layout.LayoutNode = layout.LayoutNode.group("root", layout.GridLayout.uniform(2, 20.0))
    grid.add(leaf("a", 5))
    grid.add(leaf("b", 5))
    run_rtl("grid, right to left", grid, 200.0, 100.0)
}

// ---- 11. pixel snapping ----

fn snapping() {
    // Three children into 100 points is 33.333…; unsnapped, the golden shows
    // the repeating fraction the arithmetic really produced.
    var raw: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    raw.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    raw.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    raw.add(spec_leaf("c", 5, layout.LayoutSpec.flexible(1.0)))
    run_scaled("thirds, snapping off", raw, 0.0, 100.0, 40.0)

    var whole: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    whole.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    whole.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    whole.add(spec_leaf("c", 5, layout.LayoutSpec.flexible(1.0)))
    run_scaled("thirds, snapped to whole points", whole, 1.0, 100.0, 40.0)

    var retina: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    retina.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    retina.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    retina.add(spec_leaf("c", 5, layout.LayoutSpec.flexible(1.0)))
    run_scaled("thirds, snapped to half points", retina, 2.0, 100.0, 40.0)

    // Snapping runs on absolute edges, so a fractional parent does not shift
    // its children by the fraction it absorbed.
    var outer: layout.StackLayout = column(0.0)
    outer.set_padding(geometry.EdgeInsets.all(10.5))
    var nested: layout.LayoutNode = layout.LayoutNode.group("root", outer)
    var inner: layout.LayoutNode = layout.LayoutNode.group("inner", layout.FlexLayout.row(0.0))
    inner.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    inner.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    inner.add(spec_leaf("c", 5, layout.LayoutSpec.flexible(1.0)))
    var fill: layout.LayoutSpec = layout.LayoutSpec.auto()
    fill.align = geometry.Align.stretch
    inner.spec = fill
    nested.add(inner)
    run_scaled("fractional padding, snapped", nested, 1.0, 100.0, 60.0)
}

// ---- 12. checks the goldens cannot make for themselves ----
//
// A frame table proves the numbers did not change. It does not prove they were
// ever right. These four print a verdict computed from the frames, so the
// golden carries an answer and not only an observation — and a solver that
// quietly stopped doing anything would print "no" here long before anybody
// noticed the frames were stale.

fn checks() {
    io.println("== checks ==")

    // 1. Snapped neighbours must share an edge exactly. This is the whole
    //    reason snapping works on absolute edges instead of on sizes.
    var strip: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    strip.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    strip.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(1.0)))
    strip.add(spec_leaf("c", 5, layout.LayoutSpec.flexible(1.0)))
    var solver: layout.Solver = new layout.Solver(ruler())
    solver.set_scale(1.0)
    match solver.solve(strip, geometry.Rect.of(0.0, 0.0, 100.0, 40.0)) {
        ok(done) => {
            var gaps: int = 0
            var previous: f64 = 0.0
            for child: layout.LayoutNode in strip.children() {
                if child.frame().x != previous { gaps = gaps + 1 }
                previous = child.frame().right()
            }
            io.println("  snapped neighbours meet: {gaps == 0}, last edge {previous}")
        }
        err(problem) => { io.println("  FAILED {problem.msg}") }
    }

    // 2. Every frame must land on a whole point at scale 1, and on a half
    //    point at scale 2.
    io.println("  whole points at scale 1: {all_on_grid(1.0)}")
    io.println("  half points at scale 2: {all_on_grid(2.0)}")

    // 3. A right-to-left layout must be the exact reflection of the
    //    left-to-right one about the container's *content* box, with every
    //    width unchanged. A mirror that reflected about the frame instead
    //    passes every symmetric case and fails this one.
    io.println("  mirror is exact: {mirror_is_exact()}")

    // 4. `fit` must agree with what a solve actually needs.
    var stack: layout.LayoutNode = layout.LayoutNode.group("root", column(8.0))
    stack.add(leaf("a", 1))
    stack.add(leaf("b", 2))
    var sizer: layout.Solver = new layout.Solver(ruler())
    match sizer.fit(stack, layout.Constraint.unbounded()) {
        ok(wanted) => { io.println("  fit answers {wanted.show()}") }
        err(problem) => { io.println("  FAILED {problem.msg}") }
    }
}

fn all_on_grid(scale: f64) -> bool {
    var root: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(3.0))
    root.add(spec_leaf("a", 5, layout.LayoutSpec.flexible(1.0)))
    root.add(spec_leaf("b", 5, layout.LayoutSpec.flexible(2.0)))
    root.add(spec_leaf("c", 5, layout.LayoutSpec.flexible(4.0)))
    var solver: layout.Solver = new layout.Solver(ruler())
    solver.set_scale(scale)
    match solver.solve(root, geometry.Rect.of(0.0, 0.0, 101.0, 41.0)) {
        ok(done) => {}
        err(problem) => { return false }
    }
    for child: layout.LayoutNode in root.children() {
        let box: geometry.Rect = child.frame()
        if !on_grid(box.x, scale) || !on_grid(box.width, scale) { return false }
        if !on_grid(box.y, scale) || !on_grid(box.height, scale) { return false }
    }
    return true
}

fn on_grid(value: f64, scale: f64) -> bool {
    let steps: f64 = value * scale
    return steps == steps.floor()
}

// Solves the same asymmetrically padded row both ways and checks every child
// against the reflection formula, computed here from the public API rather
// than copied from the solver.
fn mirror_is_exact() -> bool {
    var plain: layout.LayoutNode = asymmetric_tree()
    var flipped: layout.LayoutNode = asymmetric_tree()
    var forward: layout.Solver = new layout.Solver(ruler())
    var backward: layout.Solver = new layout.Solver(ruler())
    backward.set_direction(layout.TextDirection.rtl)
    let room: geometry.Rect = geometry.Rect.of(0.0, 0.0, 300.0, 60.0)
    match forward.solve(plain, room) {
        ok(done) => {}
        err(problem) => { return false }
    }
    match backward.solve(flipped, room) {
        ok(done) => {}
        err(problem) => { return false }
    }
    let pad: geometry.EdgeInsets = plain.layout().padding()
    let left: f64 = pad.left
    let right: f64 = plain.frame().width - pad.right
    var moved: bool = false
    var index: int = 0
    let originals: List<layout.LayoutNode> = plain.children()
    for mirrored: layout.LayoutNode in flipped.children() {
        let before: geometry.Rect = originals[index].frame()
        let after: geometry.Rect = mirrored.frame()
        index = index + 1
        if after.width != before.width || after.y != before.y {
            return false
        }
        if after.x != left + right - before.x - before.width {
            return false
        }
        if after.x != before.x {
            moved = true
        }
    }
    // A mirror that never moved anything would satisfy the formula only on a
    // perfectly symmetric tree; this one is not, so nothing moving is a fail.
    return moved
}

fn asymmetric_tree() -> layout.LayoutNode {
    var bar: layout.StackLayout = row(6.0)
    bar.set_padding(geometry.EdgeInsets.of(0.0, 4.0, 0.0, 28.0))
    var root: layout.LayoutNode = layout.LayoutNode.group("root", bar)
    root.add(leaf("a", 5))
    root.add(leaf("b", 2))
    root.add(leaf("c", 5))
    return root
}

// ---- what a solve costs ----

/// A ruler that answers a constant size and counts how often it is asked.
class Counting implements layout.Measure {
    pub asked: int = 0
    pub fn init() {}
    pub fn measure(key: int, available: geometry.Size) -> Result<geometry.Size> {
        self.asked = self.asked + 1
        return ok(geometry.Size.of(40.0, 20.0))
    }
}

/// A column of `wide` children, nested `deep` levels, with a leaf at the
/// bottom of every branch.
fn ladder(deep: int, wide: int, inout next_key: int) -> layout.LayoutNode {
    var node: layout.LayoutNode = layout.LayoutNode.group("g{deep}", column(4.0))
    for index: int in 0..wide {
        if deep <= 1 {
            node.add(leaf("leaf{next_key}", next_key))
            next_key = next_key + 1
        } else {
            node.add(ladder(deep - 1, wide, inout next_key))
        }
    }
    return node
}

fn leaves_of(deep: int, wide: int) -> int {
    var total: int = 1
    for index: int in 0..deep { total = total * wide }
    return total
}

/// How many times one solve asks the ruler, per leaf in the tree.
fn asks_per_leaf(deep: int, wide: int) -> int {
    var next_key: int = 1
    var tree: layout.LayoutNode = ladder(deep, wide, inout next_key)
    var counter: Counting = new Counting()
    var solver: layout.Solver = new layout.Solver(counter)
    match solver.solve(tree, geometry.Rect.of(0.0, 0.0, 400.0, 40000.0)) {
        ok(done) => {}
        err(problem) => { io.println("  FAILED {problem.msg}") }
    }
    return counter.asked / leaves_of(deep, wide)
}

/// **What a solve costs must not depend on how deep the tree is.**
///
/// A two-pass layout asks the same node the same question more than once by
/// construction — a run measures its children to size itself, then arranges
/// them, and arranging one means placing it, which measures its children
/// again. Without a memo that repetition compounds down the tree: this
/// measured 2, 4, 6, 8, 10 and 12 asks per leaf at depths one to six, so a
/// screen five containers deep reached the platform ten times for every label
/// on it. The engine is `O(nodes)`, or it is not, and the only way to tell
/// from the outside is to count.
///
/// Three depths, not two: two points fit any line, and the shape being ruled
/// out here is growth.
fn cost() {
    io.println("== cost ==")
    let shallow: int = asks_per_leaf(2, 3)
    let middling: int = asks_per_leaf(4, 3)
    let deep: int = asks_per_leaf(6, 3)
    io.println("  asks per leaf at depth 2: {shallow}")
    io.println("  asks per leaf at depth 4: {middling}")
    io.println("  asks per leaf at depth 6: {deep}")
    io.println("  and it does not grow with depth: {shallow == middling && middling == deep}")
}

/// **A remembered measurement must not outlive the pass that took it.**
///
/// The memo above is what stops a solve asking the same node the same question
/// ten times; a memo that survived into the next solve would lay the screen
/// out for the words a label used to have. Nothing on the platform side can
/// see the difference — the frames are self-consistent either way — so the
/// only way to catch it is to change what a leaf measures between two solves
/// and look at where it lands.
///
/// A leaf that got wider, not one that got narrower: a narrower one still fits
/// the room the stale answer reserved, and a stale layout would look right.
fn remeasuring() {
    io.println("== remeasuring ==")
    var table: layout.TableMeasure = new layout.TableMeasure()
    table.put(1, 100.0, 20.0)
    // Stretched, and that is not a detail. A run whose children are not
    // stretched measures each one a second time once its main size is settled,
    // and a memo of one answer per node keeps only the last question — so the
    // next pass asks a *different* question first and misses the stale answer
    // by luck. This case was written unstretched, passed with the clear taken
    // out, and proved nothing at all.
    var bar: layout.StackLayout = row(0.0)
    bar.set_align(geometry.Align.stretch)
    var strip: layout.LayoutNode = layout.LayoutNode.group("root", bar)
    strip.add(leaf("a", 1))
    strip.add(leaf("b", 1))
    var solver: layout.Solver = new layout.Solver(table)
    let room: geometry.Rect = geometry.Rect.of(0.0, 0.0, 600.0, 60.0)

    match solver.solve(strip, room) {
        ok(done) => {} err(problem) => { io.println("  FAILED {problem.msg}") }
    }
    let first: f64 = strip.at(0).frame().width
    let first_x: f64 = strip.at(1).frame().x

    // The same tree, the same solver, a leaf that now wants more room.
    table.put(1, 250.0, 20.0)
    match solver.solve(strip, room) {
        ok(done) => {} err(problem) => { io.println("  FAILED {problem.msg}") }
    }
    let second: f64 = strip.at(0).frame().width
    let second_x: f64 = strip.at(1).frame().x

    io.println("  first solve sizes it at what it measured: {first == 100.0}")
    io.println("  a leaf that grew is solved again, not remembered: {second == 250.0}")
    io.println("  and its neighbour moved with it: {first_x == 100.0 && second_x == 250.0}")
}

// ---- 16. scrolling ----

fn scroller(name: string, child: layout.LayoutNode) -> layout.LayoutNode {
    var view: layout.LayoutNode = layout.LayoutNode.group(name, new layout.ScrollLayout())
    view.add(child)
    return view
}

/// A stretched column of `count` leaves, each 100 x 20.
fn tall_content(count: int) -> layout.LayoutNode {
    var node: layout.LayoutNode = layout.LayoutNode.group("content", stretched_column(0.0))
    for index: int in 0..count {
        node.add(leaf("row{index}", 1))
    }
    return node
}

fn scrolling() {
    // Sixty points of labels behind a forty-point viewport. The content keeps
    // its own height; the viewport keeps the box it was given.
    var over: layout.LayoutNode = scroller("scroller", tall_content(3))
    run("content taller than the viewport", over, 200.0, 40.0)
    io.println("  the viewport is the box it was given: {over.frame().height == 40.0}")
    io.println("  the content is as tall as it measured: {over.at(0).frame().height == 60.0}")
    io.println("  and that is what the platform is told to scroll: {over.content.height == 60.0}")
    io.println("  across, they are the same: {over.content.width == 200.0}")

    // The same tree in a box with room to spare. Nothing to scroll, and the
    // content size says so by matching the viewport rather than by being zero.
    var under: layout.LayoutNode = scroller("scroller", tall_content(2))
    run("content shorter than the viewport", under, 200.0, 120.0)
    io.println("  the content fills the viewport: {under.at(0).frame().height == 120.0}")
    io.println("  and there is nothing to scroll: {under.content.height == 120.0}")

    // Two children. Every platform here scrolls one content view, so the
    // second would be laid on top of the first.
    var crowded: layout.LayoutNode = scroller("crowded", tall_content(2))
    crowded.add(leaf("stray", 2))
    run("two children in a scroll view", crowded, 200.0, 40.0)

    // A scroll view in a column that hands out no height: it would grow to its
    // content and scroll nothing, which is the silent version of this bug.
    var loose: layout.LayoutNode = layout.LayoutNode.group("root", stretched_column(0.0))
    loose.add(scroller("unbounded", tall_content(3)))
    run("a scroll view with no height", loose, 200.0, 400.0)

    // The two ways out, both taken.
    var pinned: layout.LayoutNode = layout.LayoutNode.group("root", stretched_column(0.0))
    var sized: layout.LayoutNode = scroller("sized", tall_content(3))
    var spec: layout.LayoutSpec = layout.LayoutSpec.auto()
    spec.max_height = 40.0
    spec.align = geometry.Align.stretch
    sized.spec = spec
    pinned.add(sized)
    run("a scroll view told its height", pinned, 200.0, 400.0)
    io.println("  it scrolls: {sized.content.height == 60.0}")

    var flexed: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.column(0.0))
    var grown: layout.LayoutNode = scroller("grown", tall_content(6))
    var share: layout.LayoutSpec = layout.LayoutSpec.flexible(1.0)
    share.align = geometry.Align.stretch
    grown.spec = share
    flexed.add(grown)
    run("a scroll view that takes the leftover", flexed, 200.0, 50.0)
    io.println("  it scrolls: {grown.content.height == 120.0}")
}

// ---- 17. a share of the room, and a shape ----

fn proportions() {
    // Across a stretched column, a share is the width: half of 300 is 150, a
    // cap still caps it, and a margin comes off the room before the share.
    var across: layout.LayoutNode = layout.LayoutNode.group("root", stretched_column(0.0))
    var half: layout.LayoutSpec = layout.LayoutSpec.auto()
    half.width_percent = 50.0
    across.add(spec_leaf("half", 1, half))
    var capped: layout.LayoutSpec = layout.LayoutSpec.auto()
    capped.width_percent = 90.0
    capped.max_width = 200.0
    across.add(spec_leaf("nine tenths, capped at 200", 1, capped))
    var inset: layout.LayoutSpec = layout.LayoutSpec.auto()
    inset.width_percent = 100.0
    inset.margin = geometry.EdgeInsets.symmetric(10.0, 0.0)
    across.add(spec_leaf("all of it, inside a margin", 1, inset))
    var quarter: layout.LayoutSpec = layout.LayoutSpec.auto()
    quarter.width_percent = 25.0
    quarter.align = geometry.Align.center
    across.add(spec_leaf("a quarter, centred", 1, quarter))
    run("shares across a stretched column", across, 300.0, 200.0)

    // Along a flexing row a share is a basis: the child grows from it.
    var shared: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    var fixed_share: layout.LayoutSpec = layout.LayoutSpec.auto()
    fixed_share.width_percent = 25.0
    shared.add(spec_leaf("a quarter", 1, fixed_share))
    shared.add(spec_leaf("the rest", 1, layout.LayoutSpec.flexible(1.0)))
    run("a share beside one that grows", shared, 300.0, 40.0)

    var both_grow: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    var growing_share: layout.LayoutSpec = layout.LayoutSpec.flexible(1.0)
    growing_share.width_percent = 50.0
    both_grow.add(spec_leaf("half, growing", 1, growing_share))
    both_grow.add(spec_leaf("natural, growing", 1, layout.LayoutSpec.flexible(1.0)))
    run("a share that grows too", both_grow, 300.0, 40.0)

    // In a plain row it is the size, and nothing grows.
    var plain: layout.LayoutNode = layout.LayoutNode.group("root", row(0.0))
    var three_tenths: layout.LayoutSpec = layout.LayoutSpec.auto()
    three_tenths.width_percent = 30.0
    plain.add(spec_leaf("three tenths", 1, three_tenths))
    plain.add(leaf("natural", 1))
    run("a share along a plain row", plain, 300.0, 40.0)

    // A box offers its content on both axes.
    var placed: layout.AbsoluteLayout = new layout.AbsoluteLayout()
    var box: layout.LayoutNode = layout.LayoutNode.group("root", placed)
    var corner: layout.LayoutSpec = layout.LayoutSpec.at(10.0, 10.0)
    corner.width_percent = 50.0
    corner.height_percent = 50.0
    box.add(spec_leaf("half each way", 1, corner))
    run("shares in a box", box, 200.0, 100.0)

    // Inside a scroll view the content is as tall as the viewport at least,
    // and a share is of that: the content is measured unbounded, but placed in a box.
    var scrolling: layout.LayoutNode = layout.LayoutNode.group("root", stretched_column(0.0))
    var viewport: layout.LayoutNode = layout.LayoutNode.group("viewport", new layout.ScrollLayout())
    viewport.spec = layout.LayoutSpec.tall(100.0)
    var content: layout.LayoutNode = layout.LayoutNode.group("content", stretched_column(0.0))
    var half_tall: layout.LayoutSpec = layout.LayoutSpec.auto()
    half_tall.height_percent = 50.0
    content.add(spec_leaf("half the viewport", 1, half_tall))
    viewport.add(content)
    scrolling.add(viewport)
    run("a share inside a scroll view", scrolling, 300.0, 100.0)

    // A basis and a share along one axis contradict each other.
    var torn: layout.LayoutNode = layout.LayoutNode.group("root", layout.FlexLayout.row(0.0))
    var twice: layout.LayoutSpec = layout.LayoutSpec.auto()
    twice.basis = 50.0
    twice.width_percent = 50.0
    torn.add(spec_leaf("basis and share", 1, twice))
    run("basis and share together", torn, 300.0, 40.0)

    // A shape follows whichever axis is settled: a pinned width, a pinned
    // height, the stretch of a column, or — with none of those — the width measured.
    var shapes: layout.LayoutNode = layout.LayoutNode.group("root", column(0.0))
    var from_width: layout.LayoutSpec = layout.LayoutSpec.wide(120.0)
    from_width.aspect_ratio = 2.0
    shapes.add(spec_leaf("2:1 from a width of 120", 1, from_width))
    var from_height: layout.LayoutSpec = layout.LayoutSpec.tall(30.0)
    from_height.aspect_ratio = 2.0
    shapes.add(spec_leaf("2:1 from a height of 30", 1, from_height))
    var from_measure: layout.LayoutSpec = layout.LayoutSpec.auto()
    from_measure.aspect_ratio = 4.0
    shapes.add(spec_leaf("4:1 from the 100 it measures", 1, from_measure))
    var from_share: layout.LayoutSpec = layout.LayoutSpec.auto()
    from_share.width_percent = 50.0
    from_share.aspect_ratio = 3.0
    from_share.align = geometry.Align.stretch
    shapes.add(spec_leaf("3:1 from half the room", 1, from_share))
    var from_stretch: layout.LayoutSpec = layout.LayoutSpec.auto()
    from_stretch.aspect_ratio = 2.0
    from_stretch.align = geometry.Align.stretch
    shapes.add(spec_leaf("2:1 from being stretched", 1, from_stretch))
    run("shapes in a column", shapes, 300.0, 400.0)

    // Both pinned: the pin wins and the ratio is ignored, not enforced.
    var overruled: layout.LayoutNode = layout.LayoutNode.group("root", column(0.0))
    var pinned_both: layout.LayoutSpec = layout.LayoutSpec.fixed(80.0, 80.0)
    pinned_both.aspect_ratio = 2.0
    overruled.add(spec_leaf("pinned square, asking for 2:1", 1, pinned_both))
    run("a shape overruled by a pin", overruled, 300.0, 100.0)
}

fn main() {
    stacks()
    alignment()
    justification()
    margins()
    bounds()
    flexing()
    shrinking()
    nesting()
    grids()
    absolute()
    mirroring()
    snapping()
    checks()
    cost()
    remeasuring()
    scrolling()
    proportions()
}
