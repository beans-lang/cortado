// Where an outline's tree comes from.
package widgets

/// What an outline asks about a node.
///
/// **A table asks "what is at row 7"; an outline asks about a node.** That one
/// difference is the whole control. The rows a person sees are whichever nodes
/// happen to be open, so the source is never asked about a node inside a
/// closed one — which is why a schema with four hundred tables opens
/// instantly, and why this interface has no "how many rows are there" at all.
///
/// A **node** is an `int` the program chooses: a row id, an index into its own
/// list, anything. cortado never looks inside one. `OutlineNodes.ROOT` is the
/// node above the top level, and it is 0 — a program whose own ids start at 0
/// adds one to them.
///
/// The same rule `TableRows.cell` has applies to every method here, and more
/// sharply: **they are called while the platform is drawing**, on the UI
/// thread, and they must return. A node's children are a lookup in something
/// the program already has. If they are not there yet, answer none and call
/// `reload()` when they arrive.
pub interface OutlineNodes {
    /// How many children `node` has. Asked of `ROOT` for the top level.
    fn child_count(node: int) -> int

    /// Which node is child `index` of `node`.
    fn child_at(node: int, index: int) -> int

    /// Whether `node` can be opened at all.
    ///
    /// Asked separately from `child_count`, and the difference matters: a
    /// folder nobody has read yet has no children to report and must still
    /// draw a twisty, and a table in a database has none and must not. A
    /// control that inferred one from the other would make "empty" and
    /// "closed" the same thing.
    fn expandable(node: int) -> bool

    /// The text of `node` in `column`. Column 0 is the one with the indent
    /// and the twisty on every platform.
    fn cell(node: int, column: int) -> string
}
