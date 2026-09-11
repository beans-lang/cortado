// One box in the layout tree.
package layout

import cortado.geometry

/// A node the solver sizes and positions.
///
/// The layout tree is deliberately **not** the widget tree. It holds no
/// handles, makes no host calls and knows nothing about AppKit, so the whole
/// engine compiles and runs on a machine with no window server. A node names
/// the widget it stands for with an integer `key`, and whoever owns the
/// widgets turns keys back into controls after the solve.
///
/// That separation is what makes the layout goldens meaningful: they run on
/// every CI runner, under both backends, with no display and no foreign call,
/// so a frame that comes out wrong is a solver bug and never a font.
pub class LayoutNode {
    /// The name goldens and debug dumps print. Not an identifier — two
    /// siblings may share one, and the engine never looks at it.
    pub name: string = ""

    /// Which widget this node stands for, or -1 for a box that exists only to
    /// group others. `Measure` is asked about this key, and the caller uses it
    /// to find the control a computed frame belongs to.
    pub key: int = -1

    /// What this node asks of its parent. Assignable, because building a tree
    /// otherwise needs a constructor argument for every field on it.
    pub spec: LayoutSpec = LayoutSpec {}

    arranger: Layout
    contents: List<LayoutNode> = []
    box: geometry.Rect = geometry.Rect.zero()

    pub fn init(name: string, arranger: Layout) {
        self.name = name
        self.arranger = arranger
    }

    /// A node that measures itself and holds nothing.
    pub static fn leaf(name: string, key: int) -> LayoutNode {
        var node: LayoutNode = new LayoutNode(name, new LeafLayout())
        node.key = key
        return node
    }

    /// A node that arranges children with `arranger`.
    pub static fn group(name: string, arranger: Layout) -> LayoutNode {
        return new LayoutNode(name, arranger)
    }

    pub fn layout() -> Layout {
        return self.arranger
    }

    // ---- tree ----

    /// Appends `child` and answers it, so a tree can be built as an
    /// expression instead of as a sequence of statements.
    pub fn add(child: LayoutNode) -> LayoutNode {
        self.contents.push(child)
        return child
    }

    pub fn count() -> int {
        return self.contents.len()
    }

    pub fn child_at(index: int) -> Option<LayoutNode> {
        if index < 0 || index >= self.contents.len() {
            return none
        }
        return some(self.contents[index])
    }

    /// A copy of the child list, so a caller walking the tree cannot mutate it
    /// underneath the node. The nodes themselves are shared: a frame written
    /// through a walked list lands on the real child.
    pub fn children() -> List<LayoutNode> {
        var out: List<LayoutNode> = []
        for child: LayoutNode in self.contents {
            out.push(child)
        }
        return move out
    }

    // ---- results ----

    /// Where this node ended up, relative to its parent's frame origin.
    pub fn frame() -> geometry.Rect {
        return self.box
    }

    pub fn set_frame(frame: geometry.Rect) {
        self.box = frame
    }

    // ---- the two passes ----

    /// How big this node wants to be inside `limit`.
    ///
    /// The node's own `spec` bounds are folded in first, so a child that asks
    /// for a minimum width gets one even when its layout would have measured
    /// smaller, and the final answer is clamped to what the parent offered.
    pub fn measure(limit: Constraint, ruler: Measure) -> Result<geometry.Size> {
        let mine: Constraint = self.spec.constrain(limit)
        let wanted: geometry.Size = self.arranger.measure(self, mine, ruler)?
        return ok(mine.clamp(wanted))
    }

    /// Puts this node at `frame` and lays its children out inside it.
    ///
    /// This is the only place a frame is written, which is why a layout
    /// subclass never touches `box` directly: "who moved this node" has one
    /// answer, and a subclass that placed nodes itself could place one twice.
    pub fn place(frame: geometry.Rect, ruler: Measure) -> Result<bool> {
        self.box = frame
        let content: geometry.Rect = self.arranger.padding().deflate(
            geometry.Rect.of(0.0, 0.0, frame.width, frame.height))
        return self.arranger.arrange(self, content, ruler)
    }
}
