// A tree, filled by asking about one node at a time.
package widgets

import cortado.host

/// An outline view.
///
/// `NSOutlineView`, a `GtkColumnView` over a `GtkTreeListModel`, a
/// `SysTreeView32` — the table with one idea added, **identity**. A table asks
/// "what is at row 7"; this asks "how many children has this node, which is
/// child *i* of it, and can it be opened at all", and the rows a person sees
/// are whichever nodes happen to be open.
///
/// ```beans
/// var tree: widgets.OutlineView = widgets.OutlineView.of(["Name"])?
/// tree.set_source(catalogue)?    // catalogue is an OutlineNodes
/// tree.expand(connection)?
/// ```
///
/// A selection raises `selection`, carrying the **node** in `event.index` —
/// not a row number, because a row number changes every time something above
/// it opens.
///
/// **Not a table with indentation.** The control owns which nodes are
/// showing, so opening one costs the children of one node and nothing else,
/// which is what makes a schema with four hundred tables open instantly.
/// `examples/cask` had a hand-flattened tree over a `Table` before this
/// control existed, and its README says what that cost.
///
/// **Not on a phone.** UIKit has no outline view: what iOS has is a
/// collection view with a list layout and section snapshots, which is a
/// layout applied to a different control with a different data source. So
/// `WidgetKind.outline_view.available()` answers false there rather than
/// cortado substituting something that behaves differently.
///
/// **One platform has one column.** A `SysTreeView32` has no columns at all,
/// so asking for a second on Windows is `unsupported` rather than a second
/// column quietly not appearing.
pub class OutlineView extends Widget {
    priv columns: int = 0

    /// Dense native macOS data grid or sidebar.
    pub fn set_compact(on: bool) -> Result<bool> {
        return self.set_property(host.P_COMPACT, if on { 1 } else { 0 })
    }

    pub fn init() {
        super.init(WidgetKind.outline_view)
    }

    /// An outline with one column per title.
    pub static fn of(titles: List<string>) -> Result<OutlineView> {
        WidgetKind.outline_view.demand()?
        var tree: OutlineView = new OutlineView()
        tree.set_columns(titles.len())?
        var index: int = 0
        for index < titles.len() {
            tree.set_column_title(index, titles[index])?
            index = index + 1
        }
        return ok(tree)
    }

    /// The node above the top level. Its children are what a person sees
    /// first, and it is never itself a row — which is what lets it double as
    /// "nothing is selected".
    pub static fn root() -> int {
        return host.OUTLINE_ROOT
    }

    pub fn set_columns(count: int) -> Result<bool> {
        unsafe {
            host.check(host.ctd_outline_columns(self.handle().raw, count as i32) as int,
                       "give an outline {count} columns")?
        }
        self.columns = count
        return ok(true)
    }

    pub fn column_count() -> int {
        return self.columns
    }

    pub fn set_column_title(column: int, title: string) -> Result<bool> {
        let buffer: Bytes = host.HostText.encode(title, "title an outline column")?
        unsafe {
            return host.check(
                host.ctd_outline_column_title(self.handle().raw, column as i32,
                                              host.HostText.pointer(buffer),
                                              buffer.len() as i32) as int,
                "title outline column {column}")
        }
    }

    pub fn set_column_width(column: int, points: f64) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_outline_column_width(self.handle().raw, column as i32,
                                              points) as int,
                "size outline column {column}")
        }
    }

    /// Where the tree comes from.
    ///
    /// Registered against this control's handle in the one process-wide
    /// source, the same arrangement a table uses — see `OutlineDesk`.
    pub fn set_source(nodes: OutlineNodes) -> Result<bool> {
        OutlineDesk.instance.put(self.handle().raw, nodes)
        return self.reload()
    }

    /// Draw a system icon beside each visible node in the first column.
    /// Return `SystemIcon.none` for a row without an icon. The callback runs
    /// while the native view draws, so it must answer from data already held
    /// in memory. macOS uses SF Symbols; other hosts may show text only.
    pub fn set_icon_when(policy: fn(int) -> SystemIcon) -> Result<bool> {
        OutlineDesk.instance.set_icon_when(self.handle().raw, policy)
        return self.reload()
    }

    /// Ask again, from the root down. What is open stays open where the same
    /// nodes are still there.
    pub fn reload() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_outline_reload(self.handle().raw) as int,
                              "reload an outline")
        }
    }

    /// Open or close one node.
    ///
    /// Refused with `out_of_range` for a node the control is not showing —
    /// which includes a node inside a closed parent, because a control that
    /// has not been asked about it does not have it. So a tree is opened from
    /// the top down, one level at a time, which is also the order a person
    /// opens one in.
    pub fn expand(node: int) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_outline_expand(self.handle().raw, node as i64, 1) as int,
                "open node {node}")
        }
    }

    pub fn collapse(node: int) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_outline_expand(self.handle().raw, node as i64, 0) as int,
                "close node {node}")
        }
    }

    pub fn is_expanded(node: int) -> Result<bool> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var open: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_outline_expanded(self.handle().raw, node as i64,
                                                 slot) as int,
                       "ask whether node {node} is open")?
            open = slot.read()
        }
        return ok(open != 0)
    }

    /// The selected node, or `root()` for none.
    pub fn selected() -> Result<int> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var node: i64 = 0
        unsafe {
            let slot: RawPtr<i64> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_outline_selected(self.handle().raw, slot) as int,
                       "read an outline's selection")?
            node = slot.read()
        }
        return ok(node as int)
    }

    pub fn select(node: int) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_outline_select(self.handle().raw, node as i64) as int,
                "select node {node}")
        }
    }

    /// What the *platform* has for one cell, through its own data source.
    ///
    /// The round trip `Table.native_cell` is for a table: out through the
    /// source, into the control, and back. It exists because bookkeeping that
    /// is never checked against the thing it describes is how a tree ends up
    /// correct on paper and wrong on screen — and because it is the only way
    /// to check the path at all without a display.
    pub fn native_cell(node: int, column: int) -> Result<string> {
        unsafe {
            return host.HostText.read("read node {node} column {column}",
                fn(out: RawPtr<i8>, cap: i32) -> i32 {
                    return host.ctd_outline_cell(self.handle().raw, node as i64,
                                                 column as i32, out, cap)
                })
        }
    }
}
