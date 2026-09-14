// A run that breaks into lines when its children do not fit.
package layout

import cortado.geometry

/// A row or a column that wraps: children go along the main axis until the
/// next would not fit, then start a new line along the cross axis.
///
/// Extends `FlexLayout` for its settings and its `distribute`, so each line
/// hands out its leftover by `grow` and takes back overflow by `shrink`.
pub class WrapLayout extends FlexLayout {
    line_gap: f64 = 0.0

    pub fn init(axis: Direction, spacing: f64) {
        super.init(axis, spacing)
    }

    pub static fn row(spacing: f64) -> WrapLayout {
        return new WrapLayout(Direction.horizontal, spacing)
    }

    pub static fn column(spacing: f64) -> WrapLayout {
        return new WrapLayout(Direction.vertical, spacing)
    }

    /// The gap between one line and the next, along the cross axis.
    pub fn set_line_spacing(gap: f64) {
        self.line_gap = gap
    }

    pub fn line_spacing() -> f64 {
        return self.line_gap
    }

    pub override fn label() -> string {
        return "wrap"
    }

    // ---- pass one: how big does this run want to be ----

    /// Lines are broken against the main-axis room offered; with none offered
    /// everything goes on one line, which is what an unbounded row is.
    pub override fn measure(node: LayoutNode, limit: Constraint,
                            ruler: Measure) -> Result<geometry.Size> {
        let inner: Constraint = limit.deflate(self.padding())
        let axis: Direction = self.direction()
        let cross_axis: Direction = axis.cross()
        let room: f64 = axis.main_of(inner.available())
        var widest: f64 = 0.0
        var stacked: f64 = 0.0
        var lines: int = 0
        var used: f64 = 0.0
        var band: f64 = 0.0
        var in_line: int = 0
        for index: int in 0..node.count() {
            let child: LayoutNode = node.at(index)
            let offer: Constraint = inner.deflate(child.spec.margin).unbound(axis).loosen()
            let size: geometry.Size = child.measure(offer, ruler)?
            let along: f64 = axis.main_of(size) + child.spec.margin_on(axis)
            let across: f64 = cross_axis.main_of(size) + child.spec.margin_on(cross_axis)
            if in_line > 0 && self.breaks_before(used, along, room) {
                if used > widest { widest = used }
                stacked = stacked + band
                lines = lines + 1
                used = 0.0
                band = 0.0
                in_line = 0
            }
            if in_line > 0 { used = used + self.spacing }
            used = used + along
            if across > band { band = across }
            in_line = in_line + 1
        }
        if in_line > 0 {
            if used > widest { widest = used }
            stacked = stacked + band
            lines = lines + 1
        }
        if lines > 1 {
            stacked = stacked + self.line_gap * ((lines - 1) as f64)
        }
        let pad: geometry.EdgeInsets = self.padding()
        let padded: geometry.Size = axis.size(
            widest + axis.main_of(geometry.Size.of(pad.horizontal(), pad.vertical())),
            stacked + cross_axis.main_of(geometry.Size.of(pad.horizontal(), pad.vertical())))
        return ok(limit.clamp(padded))
    }

    /// Whether a child `along` wide starts a new line after `used`. Never in
    /// unbounded room, and never for the first child of a line.
    fn breaks_before(used: f64, along: f64, room: f64) -> bool {
        if room < 0.0 { return false }
        return used + self.spacing + along > room + 0.0000001
    }

    // ---- pass two: place everyone, a line at a time ----

    pub override fn arrange(node: LayoutNode, content: geometry.Rect,
                            ruler: Measure) -> Result<bool> {
        let count: int = node.count()
        if count == 0 {
            return ok(true)
        }
        let axis: Direction = self.direction()
        let cross_axis: Direction = axis.cross()
        let room_main: f64 = axis.main_extent(content)

        // Break into lines by natural size, exactly as `measure` did.
        var starts: List<int> = []
        var used: f64 = 0.0
        var in_line: int = 0
        var mains: List<f64> = []
        for index: int in 0..count {
            let child: LayoutNode = node.at(index)
            let offer: Constraint = Constraint.loose(
                geometry.Size.of(content.width, content.height))
                .deflate(child.spec.margin).unbound(axis)
            let measured: geometry.Size = child.measure(offer, ruler)?
            var base: f64 = axis.main_of(measured)
            if child.spec.basis >= 0.0 { base = child.spec.basis }
            let share: f64 = child.spec.percent_size(axis, room_main - child.spec.margin_on(axis))
            if share >= 0.0 {
                if child.spec.basis >= 0.0 {
                    return err("\"{child.name}\" asks for a basis of {child.spec.basis} and a share of {child.spec.percent_on(axis)}% along the same axis — write one",
                               "basis_and_percent")
                }
                base = share
            }
            mains.push(base)
            let along: f64 = base + child.spec.margin_on(axis)
            if in_line > 0 && self.breaks_before(used, along, room_main) {
                used = 0.0
                in_line = 0
            }
            if in_line == 0 { starts.push(index) }
            if in_line > 0 { used = used + self.spacing }
            used = used + along
            in_line = in_line + 1
        }

        var cross_cursor: f64 = axis.cross_start(content)
        for line: int in 0..starts.len() {
            let first: int = starts[line]
            var last: int = count
            if line + 1 < starts.len() { last = starts[line + 1] }

            // Distribute this line's leftover by grow and shrink.
            var reserved: f64 = self.spacing * ((last - first - 1) as f64)
            for index: int in first..last {
                reserved = reserved + node.at(index).spec.margin_on(axis)
            }
            var run: AxisRun = new AxisRun(room_main - reserved)
            for index: int in first..last {
                let child: LayoutNode = node.at(index)
                run.add(mains[index], child.spec.min_on(axis), child.spec.max_on(axis),
                        child.spec.grow, child.spec.shrink)
            }
            self.distribute(run)

            // The line's band is the tallest child once its main size is settled.
            var band: f64 = 0.0
            var crosses: List<f64> = []
            for index: int in first..last {
                let child: LayoutNode = node.at(index)
                let settled: Constraint = axis.pin(run.main_at(index - first), -1.0)
                let final_size: geometry.Size = child.measure(settled, ruler)?
                let across: f64 = cross_axis.main_of(final_size)
                crosses.push(across)
                let reach: f64 = across + child.spec.margin_on(cross_axis)
                if reach > band { band = reach }
            }

            let free: f64 = run.room - run.total()
            let members: int = last - first
            var cursor: f64 = axis.main_start(content) + self.justify.lead(free, members)
            let gap: f64 = self.justify.gap(free, members)
            for index: int in first..last {
                let child: LayoutNode = node.at(index)
                let main_size: f64 = run.main_at(index - first)
                cursor = cursor + child.spec.margin_lead(axis)
                var room_across: f64 = band - child.spec.margin_on(cross_axis)
                if room_across < 0.0 { room_across = 0.0 }
                let placement: geometry.Align = child.spec.align.resolve(self.cross_default())
                var cross_size: f64 = room_across
                if placement != geometry.Align.stretch {
                    cross_size = crosses[index - first]
                }
                cross_size = clamp_cross(cross_size, child.spec, cross_axis, room_across)
                let cross_at: f64 = cross_cursor + child.spec.margin_lead(cross_axis) +
                                    placement.offset(cross_size, room_across)
                child.place(axis.rect(cursor, cross_at, main_size, cross_size), ruler)?
                let trail: f64 = child.spec.margin_on(axis) - child.spec.margin_lead(axis)
                cursor = cursor + main_size + trail + self.spacing + gap
            }
            cross_cursor = cross_cursor + band + self.line_gap
        }
        return ok(true)
    }
}
