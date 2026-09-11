// What one child asks of the run it sits in.
package layout

import cortado.geometry

/// Per-child layout parameters.
///
/// Everything here belongs to the child but is read by the parent, which is
/// why it lives on the node rather than inside a layout object: the same child
/// keeps its margin and its size limits when it is moved from a stack into a
/// grid.
///
/// `-1.0` means "no opinion" for every size bound and for `basis`. Zero is a
/// legitimate minimum and a legitimate basis, so it cannot double as the empty
/// value, and an `Option<f64>` per bound would put four unwraps in the hot
/// path of every arrange pass.
pub struct LayoutSpec {
    /// Share of leftover main-axis space this child takes. 0 means it keeps
    /// its measured size. Read only by `FlexLayout`.
    pub grow: f64 = 0.0

    /// Share of main-axis overflow this child gives up, weighted by its size.
    /// The default of 1 matches the web's, where everything shrinks before
    /// anything overflows.
    pub shrink: f64 = 1.0

    /// Main-axis size to start distribution from, before growing or shrinking.
    /// -1 means start from the measured size.
    pub basis: f64 = -1.0

    pub min_width: f64 = -1.0
    pub max_width: f64 = -1.0
    pub min_height: f64 = -1.0
    pub max_height: f64 = -1.0

    /// Space kept outside this child's frame. The parent reserves it; the
    /// child never sees it.
    pub margin: geometry.EdgeInsets = geometry.EdgeInsets {}

    /// Cross-axis placement, or `inherit` to take the run's default.
    pub align: geometry.Align = geometry.Align.inherit

    /// Position inside an `AbsoluteLayout`, ignored by every other layout.
    pub x: f64 = 0.0
    pub y: f64 = 0.0

    pub static fn auto() -> LayoutSpec {
        return LayoutSpec {}
    }

    /// A child that takes `weight` shares of the leftover space.
    pub static fn flexible(weight: f64) -> LayoutSpec {
        return LayoutSpec { grow: weight }
    }

    /// A child pinned to one size on both axes.
    pub static fn fixed(width: f64, height: f64) -> LayoutSpec {
        return LayoutSpec { min_width: width, max_width: width,
                            min_height: height, max_height: height,
                            shrink: 0.0 }
    }

    /// A child placed at an explicit offset, for `AbsoluteLayout`.
    pub static fn at(x: f64, y: f64) -> LayoutSpec {
        return LayoutSpec { x: x, y: y }
    }

    /// This spec's own size bounds folded into `limit`.
    ///
    /// The child's bounds win where they are set, but they are still pulled
    /// inside the parent's: a child asking for 400 points of width inside a
    /// 300-point parent gets 300. Letting the child win outright is how a
    /// layout ends up drawing outside its window.
    pub fn constrain(limit: Constraint) -> Constraint {
        var out: Constraint = limit
        if self.min_width >= 0.0 { out.min_width = self.min_width }
        if self.max_width >= 0.0 {
            if !limit.has_max_width() || self.max_width < limit.max_width {
                out.max_width = self.max_width
            }
        }
        if self.min_height >= 0.0 { out.min_height = self.min_height }
        if self.max_height >= 0.0 {
            if !limit.has_max_height() || self.max_height < limit.max_height {
                out.max_height = self.max_height
            }
        }
        if out.has_max_width() && out.min_width > out.max_width {
            out.min_width = out.max_width
        }
        if out.has_max_height() && out.min_height > out.max_height {
            out.min_height = out.max_height
        }
        return out
    }

    /// This spec's lower bound on `axis`, or 0 when it sets none.
    pub fn min_on(axis: Direction) -> f64 {
        var value: f64 = self.min_height
        if axis.is_horizontal() { value = self.min_width }
        if value < 0.0 { return 0.0 }
        return value
    }

    /// This spec's upper bound on `axis`, or -1 when it sets none.
    pub fn max_on(axis: Direction) -> f64 {
        if axis.is_horizontal() { return self.max_width }
        return self.max_height
    }

    /// The margin taken along `axis`.
    pub fn margin_on(axis: Direction) -> f64 {
        if axis.is_horizontal() { return self.margin.horizontal() }
        return self.margin.vertical()
    }

    /// The margin before this child along `axis` — its left or its top.
    pub fn margin_lead(axis: Direction) -> f64 {
        if axis.is_horizontal() { return self.margin.left }
        return self.margin.top
    }
}
