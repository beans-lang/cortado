// Children at the coordinates the caller gave them.
package layout

import cortado.geometry

/// Places each child at its `LayoutSpec.x` and `LayoutSpec.y`.
///
/// The escape hatch. Overlays, badges pinned to a corner, a drawing canvas
/// with hand-placed handles — work where the positions *are* the design and
/// there is nothing for a run to compute. It is also what a tree looks like
/// before it is ported to stacks, which makes moving an existing screen onto
/// the engine a two-step job rather than a rewrite.
///
/// Children keep their measured size unless their spec pins one, and nothing
/// is clipped: a child placed past the edge stays where it was put. Silently
/// pulling it back inside would hide the mistake at the one moment it is
/// visible.
///
/// This layout does **not** mirror in right-to-left locales. Its coordinates
/// were written as physical positions by somebody who knew where they wanted
/// the box; flipping them would mean the caller had no way to say "here".
pub class AbsoluteLayout extends Layout {
    pad: geometry.EdgeInsets = geometry.EdgeInsets {}

    pub fn init() {}

    pub fn set_padding(insets: geometry.EdgeInsets) {
        self.pad = insets
    }

    pub override fn padding() -> geometry.EdgeInsets {
        return self.pad
    }

    pub override fn mirrors_in_rtl() -> bool {
        return false
    }

    pub override fn label() -> string {
        return "absolute"
    }

    /// The box that contains every child where it was placed.
    ///
    /// A node with absolute children has no natural size of its own, so it
    /// takes the extent of what it holds. That lets an absolute group sit
    /// inside a stack and still be sized by it.
    pub override fn measure(node: LayoutNode, limit: Constraint,
                            ruler: Measure) -> Result<geometry.Size> {
        var right: f64 = 0.0
        var bottom: f64 = 0.0
        let inner: Constraint = limit.deflate(self.pad)
        for child: LayoutNode in node.children() {
            let size: geometry.Size = child.measure(inner.loosen(), ruler)?
            let reach_x: f64 = child.spec.x + size.width
            let reach_y: f64 = child.spec.y + size.height
            if reach_x > right { right = reach_x }
            if reach_y > bottom { bottom = reach_y }
        }
        return ok(limit.clamp(geometry.Size.of(right + self.pad.horizontal(),
                                               bottom + self.pad.vertical())))
    }

    pub override fn arrange(node: LayoutNode, content: geometry.Rect,
                            ruler: Measure) -> Result<bool> {
        let offer: Constraint = Constraint.loose(
            geometry.Size.of(content.width, content.height))
        for child: LayoutNode in node.children() {
            let size: geometry.Size = child.measure(offer, ruler)?
            child.place(geometry.Rect.of(content.x + child.spec.x,
                                         content.y + child.spec.y,
                                         size.width, size.height), ruler)?
        }
        return ok(true)
    }
}
