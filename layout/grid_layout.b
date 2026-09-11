// Children in rows and columns.
package layout

import cortado.geometry

/// A fixed set of columns, filled row by row.
///
/// Children are placed in order: across the first row until the columns run
/// out, then down to the next. Each child occupies one cell and is aligned
/// inside it.
///
/// ### What this does not do yet, and why that is a choice
///
/// There is no explicit cell placement and no spanning. Both need per-child
/// column and row indices and a collision policy for the cells they skip, and
/// neither is needed by the layouts cortado's own examples and widgets are
/// built from. Adding them means two more `LayoutSpec` fields and an
/// occupancy map, and it is a change to this file alone — `arrange` computes
/// the cell rectangle in one place. When a real screen needs a spanning cell,
/// that is the moment to add it, with the test that screen justifies.
pub class GridLayout extends Layout {
    columns: List<Track> = []
    rows: List<Track> = []
    column_gap: f64 = 0.0
    row_gap: f64 = 0.0
    pad: geometry.EdgeInsets = geometry.EdgeInsets {}
    cell_align: geometry.Align = geometry.Align.start

    pub fn init() {}

    /// A grid of `count` equal columns.
    pub static fn uniform(count: int, gap: f64) -> GridLayout {
        var grid: GridLayout = new GridLayout()
        var index: int = 0
        for index: int in 0..count {
            grid.add_column(Track.fraction(1.0))
        }
        grid.set_gaps(gap, gap)
        return grid
    }

    pub fn add_column(track: Track) {
        self.columns.push(track)
    }

    /// Declares an explicit row. Rows beyond the declared ones size
    /// themselves to their content, which is what makes a grid with a fixed
    /// column set and a growing list of items work without declaring rows.
    pub fn add_row(track: Track) {
        self.rows.push(track)
    }

    pub fn set_gaps(column_gap: f64, row_gap: f64) {
        self.column_gap = column_gap
        self.row_gap = row_gap
    }

    pub fn set_padding(insets: geometry.EdgeInsets) {
        self.pad = insets
    }

    /// How a child sits in its cell when it does not fill it.
    pub fn set_align(mode: geometry.Align) {
        self.cell_align = mode
    }

    pub fn column_count() -> int {
        return self.columns.len()
    }

    pub override fn padding() -> geometry.EdgeInsets {
        return self.pad
    }

    pub override fn label() -> string {
        return "grid"
    }

    pub override fn measure(node: LayoutNode, limit: Constraint,
                            ruler: Measure) -> Result<geometry.Size> {
        let inner: Constraint = limit.deflate(self.pad)
        var width: f64 = 0.0
        if inner.has_max_width() {
            width = inner.max_width
        } else {
            // With no width offered there is nothing for a fraction track to
            // take a share of, so the grid asks for the width its content
            // needs and lets the parent decide.
            width = self.intrinsic_width(node, inner, ruler)?
        }
        let tracks: List<Track> = self.measured_columns(node, inner, ruler)?
        var widths: List<f64> = self.solve_tracks(tracks, width, self.column_gap)
        var heights: List<f64> = self.solve_rows(node, widths, inner, ruler)?
        var total_height: f64 = 0.0
        var index: int = 0
        for index: int in 0..heights.len() {
            total_height = total_height + heights[index]
        }
        if heights.len() > 1 {
            total_height = total_height + self.row_gap * ((heights.len() - 1) as f64)
        }
        return ok(limit.clamp(geometry.Size.of(width + self.pad.horizontal(),
                                               total_height + self.pad.vertical())))
    }

    pub override fn arrange(node: LayoutNode, content: geometry.Rect,
                            ruler: Measure) -> Result<bool> {
        let children: List<LayoutNode> = node.children()
        if children.len() == 0 || self.columns.len() == 0 {
            return ok(true)
        }
        let inner: Constraint = Constraint.loose(
            geometry.Size.of(content.width, content.height))
        let tracks: List<Track> = self.measured_columns(node, inner, ruler)?
        var widths: List<f64> = self.solve_tracks(tracks, content.width, self.column_gap)
        var heights: List<f64> = self.solve_rows(node, widths, inner, ruler)?

        let columns: int = self.columns.len()
        var index: int = 0
        for child: LayoutNode in children {
            let column: int = index % columns
            let row: int = index / columns
            var x: f64 = content.x
            var step: int = 0
            for step: int in 0..column {
                x = x + widths[step] + self.column_gap
            }
            var y: f64 = content.y
            for step: int in 0..row {
                y = y + heights[step] + self.row_gap
            }
            let cell: geometry.Rect = geometry.Rect.of(x, y, widths[column], heights[row])
            self.place_in_cell(child, cell, ruler)?
            index = index + 1
        }
        return ok(true)
    }

    // ---- track sizing ----

    /// Splits `room` across `tracks`, honouring fixed sizes first and sharing
    /// what is left among the fraction tracks by weight.
    ///
    /// `auto` tracks are resolved by the caller before this runs, which is why
    /// they are passed in already carrying a fixed size: the width of an auto
    /// column depends on the children in it, and this function knows nothing
    /// about children.
    fn solve_tracks(tracks: List<Track>, room: f64, gap: f64) -> List<f64> {
        var sizes: List<f64> = []
        let count: int = tracks.len()
        if count == 0 {
            return move sizes
        }
        var used: f64 = gap * ((count - 1) as f64)
        var weight: f64 = 0.0
        var index: int = 0
        for index: int in 0..count {
            let track: Track = tracks[index]
            match track.kind {
                fixed => { sizes.push(track.value); used = used + track.value }
                auto => { sizes.push(track.value); used = used + track.value }
                fraction => { sizes.push(0.0); weight = weight + track.value }
            }
        }
        var spare: f64 = room - used
        if spare < 0.0 { spare = 0.0 }
        if weight > 0.0 {
            for index: int in 0..count {
                let track: Track = tracks[index]
                if track.kind == TrackKind.fraction {
                    sizes[index] = spare * track.value / weight
                }
            }
        }
        return move sizes
    }

    /// The column widths with every `auto` column resolved to the widest
    /// child in it.
    fn measured_columns(node: LayoutNode, limit: Constraint,
                        ruler: Measure) -> Result<List<Track>> {
        var out: List<Track> = []
        let columns: int = self.columns.len()
        var index: int = 0
        for index: int in 0..columns {
            out.push(self.columns[index])
        }
        if columns == 0 {
            return ok(move out)
        }
        var position: int = 0
        for child: LayoutNode in node.children() {
            let column: int = position % columns
            position = position + 1
            if out[column].kind != TrackKind.auto {
                continue
            }
            let size: geometry.Size = child.measure(limit.loosen().unbound(Direction.horizontal), ruler)?
            let wanted: f64 = size.width + child.spec.margin.horizontal()
            if wanted > out[column].value {
                out[column] = Track { kind: TrackKind.auto, value: wanted }
            }
        }
        return ok(move out)
    }

    /// The width this grid needs when nobody has offered it one.
    fn intrinsic_width(node: LayoutNode, limit: Constraint,
                       ruler: Measure) -> Result<f64> {
        let tracks: List<Track> = self.measured_columns(node, limit, ruler)?
        var total: f64 = 0.0
        var index: int = 0
        for index: int in 0..tracks.len() {
            total = total + tracks[index].value
        }
        if tracks.len() > 1 {
            total = total + self.column_gap * ((tracks.len() - 1) as f64)
        }
        return ok(total)
    }

    /// The height of every row, with declared tracks honoured and the rest
    /// sized to the tallest child in the row.
    fn solve_rows(node: LayoutNode, widths: List<f64>, limit: Constraint,
                  ruler: Measure) -> Result<List<f64>> {
        var heights: List<f64> = []
        var pinned: List<bool> = []
        let columns: int = self.columns.len()
        if columns == 0 {
            return ok(move heights)
        }
        let children: List<LayoutNode> = node.children()
        let row_count: int = (children.len() + columns - 1) / columns
        var index: int = 0
        for index: int in 0..row_count {
            var height: f64 = 0.0
            var fixed: bool = false
            if index < self.rows.len() && self.rows[index].kind == TrackKind.fixed {
                height = self.rows[index].value
                fixed = true
            }
            heights.push(height)
            pinned.push(fixed)
        }
        var position: int = 0
        for child: LayoutNode in children {
            let column: int = position % columns
            let row: int = position / columns
            position = position + 1
            if pinned[row] {
                continue
            }
            // The child is measured at the width its column ended up with, so
            // a wrapping label in a narrow column reports the height it will
            // really need rather than the one it wanted when unconstrained.
            var band: f64 = 0.0
            if column < widths.len() {
                band = widths[column] - child.spec.margin.horizontal()
            }
            if band < 0.0 { band = 0.0 }
            let size: geometry.Size = child.measure(Constraint.of(0.0, band, 0.0, -1.0), ruler)?
            let wanted: f64 = size.height + child.spec.margin.vertical()
            if wanted > heights[row] {
                heights[row] = wanted
            }
        }
        return ok(move heights)
    }

    /// Sizes one child inside its cell and places it there.
    fn place_in_cell(child: LayoutNode, cell: geometry.Rect,
                     ruler: Measure) -> Result<bool> {
        var room: geometry.Rect = child.spec.margin.deflate(cell)
        let placement: geometry.Align = child.spec.align.resolve(self.cell_align)
        var size: geometry.Size = geometry.Size.of(room.width, room.height)
        if placement != geometry.Align.stretch {
            size = child.measure(Constraint.loose(size), ruler)?
        }
        let x: f64 = room.x + placement.offset(size.width, room.width)
        let y: f64 = room.y + placement.offset(size.height, room.height)
        return child.place(geometry.Rect.of(x, y, size.width, size.height), ruler)
    }
}
