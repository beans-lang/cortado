// A row or a column of children.
package layout

import cortado.geometry

/// Lays children out one after another along one axis.
///
/// This is the layout almost every screen is made of: a column of rows. Each
/// child keeps the size it measured; leftover space along the main axis is
/// shared out by `justify`, and the cross axis is settled per child by
/// `align`, with `Align.stretch` filling the run.
///
/// `FlexLayout` extends this class and replaces exactly one method,
/// `distribute`, which is the step that decides each child's main-axis size.
/// Everything else — measuring, margins, justification, cross alignment,
/// padding, the second measure pass — is shared, so a fix to any of it lands
/// in both layouts and cannot drift between them.
pub class StackLayout extends Layout {
    axis: Direction = Direction.vertical
    spacing: f64 = 0.0
    pad: geometry.EdgeInsets = geometry.EdgeInsets {}
    justify: Justify = Justify.start
    cross: geometry.Align = geometry.Align.start

    pub fn init(axis: Direction, spacing: f64) {
        self.axis = axis
        self.spacing = spacing
    }

    /// A left-to-right run.
    pub static fn row(spacing: f64) -> StackLayout {
        return new StackLayout(Direction.horizontal, spacing)
    }

    /// A top-to-bottom run.
    pub static fn column(spacing: f64) -> StackLayout {
        return new StackLayout(Direction.vertical, spacing)
    }

    pub fn set_spacing(gap: f64) {
        self.spacing = gap
    }

    pub fn set_padding(insets: geometry.EdgeInsets) {
        self.pad = insets
    }

    pub fn set_justify(mode: Justify) {
        self.justify = mode
    }

    /// The cross-axis alignment children take when they express no opinion.
    pub fn set_align(mode: geometry.Align) {
        self.cross = mode
    }

    pub fn direction() -> Direction {
        return self.axis
    }

    pub override fn padding() -> geometry.EdgeInsets {
        return self.pad
    }

    pub override fn label() -> string {
        return "stack"
    }

    // ---- pass one: how big does this run want to be ----

    pub override fn measure(node: LayoutNode, limit: Constraint,
                            ruler: Measure) -> Result<geometry.Size> {
        let inner: Constraint = limit.deflate(self.pad)
        let cross_axis: Direction = self.axis.cross()
        var main_total: f64 = 0.0
        var cross_max: f64 = 0.0
        var seen: int = 0
        for child: LayoutNode in node.children() {
            // Each child is measured with no limit along the main axis: the
            // run is asking how big everyone naturally is, and only once that
            // is known can it decide whether there is room to share out.
            let offer: Constraint = inner.deflate(child.spec.margin).unbound(self.axis).loosen()
            let size: geometry.Size = child.measure(offer, ruler)?
            main_total = main_total + self.axis.main_of(size) + child.spec.margin_on(self.axis)
            let reach: f64 = cross_axis.main_of(size) + child.spec.margin_on(cross_axis)
            if reach > cross_max { cross_max = reach }
            seen = seen + 1
        }
        if seen > 1 {
            main_total = main_total + self.spacing * ((seen - 1) as f64)
        }
        let padded: geometry.Size = self.axis.size(
            main_total + self.axis.main_of(insets_size(self.pad)),
            cross_max + cross_axis.main_of(insets_size(self.pad)))
        return ok(limit.clamp(padded))
    }

    // ---- pass two: place everyone ----

    pub override fn arrange(node: LayoutNode, content: geometry.Rect,
                            ruler: Measure) -> Result<bool> {
        let children: List<LayoutNode> = node.children()
        let count: int = children.len()
        if count == 0 {
            return ok(true)
        }
        let cross_axis: Direction = self.axis.cross()
        let room_main: f64 = self.axis.main_extent(content)
        let room_cross: f64 = self.axis.cross_extent(content)

        // Everything the children cannot use: their margins, and the fixed
        // gaps between them. Taking it off up front means `run.room` is the
        // space actually up for distribution, so `free` is a straight
        // subtraction rather than a running tally that is easy to get wrong.
        var reserved: f64 = self.spacing * ((count - 1) as f64)
        for child: LayoutNode in children {
            reserved = reserved + child.spec.margin_on(self.axis)
        }

        var run: AxisRun = new AxisRun(room_main - reserved)
        for child: LayoutNode in children {
            let offer: Constraint = Constraint.loose(
                geometry.Size.of(content.width, content.height))
                .deflate(child.spec.margin).unbound(self.axis)
            let measured: geometry.Size = child.measure(offer, ruler)?
            var base: f64 = self.axis.main_of(measured)
            if child.spec.basis >= 0.0 {
                base = child.spec.basis
            }
            run.add(base, child.spec.min_on(self.axis), child.spec.max_on(self.axis),
                    child.spec.grow, child.spec.shrink)
        }

        self.distribute(run)

        let free: f64 = run.room - run.total()
        let lead: f64 = self.justify.lead(free, count)
        let gap: f64 = self.justify.gap(free, count)

        var cursor: f64 = self.axis.main_start(content) + lead
        var index: int = 0
        for child: LayoutNode in children {
            let main_size: f64 = run.main_at(index)
            cursor = cursor + child.spec.margin_lead(self.axis)

            // The run of space this child's cross axis may use, after its own
            // margin is taken off both sides.
            var band: f64 = room_cross - child.spec.margin_on(cross_axis)
            if band < 0.0 { band = 0.0 }

            let placement: geometry.Align = child.spec.align.resolve(self.cross)
            var cross_size: f64 = band
            if placement != geometry.Align.stretch {
                // Measure again, now that the main size is settled. A label
                // that grew wider needs fewer lines, and a run that skipped
                // this would size it from the width it was guessed at.
                let settled: Constraint = self.axis.pin(main_size, band)
                let final_size: geometry.Size = child.measure(settled, ruler)?
                cross_size = cross_axis.main_of(final_size)
            }
            cross_size = clamp_cross(cross_size, child.spec, cross_axis, band)

            let band_start: f64 = self.axis.cross_start(content) + child.spec.margin_lead(cross_axis)
            let cross_at: f64 = band_start + placement.offset(cross_size, band)
            child.place(self.axis.rect(cursor, cross_at, main_size, cross_size), ruler)?

            let margin_trail: f64 = child.spec.margin_on(self.axis) - child.spec.margin_lead(self.axis)
            cursor = cursor + main_size + margin_trail + self.spacing + gap
            index = index + 1
        }
        return ok(true)
    }

    /// Decides each child's final main-axis size.
    ///
    /// A stack gives every child the size it measured, pulled inside whatever
    /// bounds that child set. It does not grow anyone into leftover space and
    /// does not shrink anyone to fit — that is `FlexLayout`, which replaces
    /// this method and nothing else.
    ///
    /// Package-private on purpose: it is the extension point between these two
    /// classes, not something an application overrides.
    fn distribute(run: AxisRun) {
        var index: int = 0
        for index: int in 0..run.count {
            run.set_main(index, run.clamp_at(index, run.base_at(index)))
        }
    }
}

// The padding of a box expressed as the size it costs, so the axis accessors
// can read it the same way they read any other size.
fn insets_size(insets: geometry.EdgeInsets) -> geometry.Size {
    return geometry.Size.of(insets.horizontal(), insets.vertical())
}

// A cross-axis size pulled inside the child's own bounds and the room it has.
fn clamp_cross(value: f64, spec: LayoutSpec, cross_axis: Direction, band: f64) -> f64 {
    var out: f64 = value
    let lower: f64 = spec.min_on(cross_axis)
    let upper: f64 = spec.max_on(cross_axis)
    if out < lower { out = lower }
    if upper >= 0.0 && out > upper { out = upper }
    if out > band { out = band }
    if out < 0.0 { out = 0.0 }
    return out
}
