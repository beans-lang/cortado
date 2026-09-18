// Rows and columns, filled by asking rather than by building.
package widgets

import cortado.host
import cortado.render

class SharedTableRows implements render.TableData {
    rows: TableRows
    pub fn init(rows: TableRows) { self.rows = rows }
    pub fn row_count() -> int { return self.rows.row_count() }
    pub fn cell(row: int, column: int) -> string { return self.rows.cell(row, column) }
}

/// A table.
///
/// `NSTableView`, a `GtkColumnView`, a virtual `SysListView32`, a
/// `UITableView` on the native backend. The shared backend uses `.bx` labels
/// for visible cells and one text field while editing. It receives a `TableRows`
/// source and asks only for visible rows plus overscan. Cached values stay valid
/// until the source is reloaded.
///
/// ```beans
/// var table: widgets.Table = widgets.Table.of(["Drink", "Price"])?
/// table.set_source(orders)?      // orders is a TableRows
/// ```
///
/// A selection raises `selection`, carrying the row in `event.index`.
///
/// **One platform has one column.** A `UITableView` is a list — the cell
/// styles that look like two columns are a label and a detail label, not
/// columns you can size or title — so asking for a second on iOS is
/// `unsupported` rather than four columns quietly collapsed into one.
pub class Table extends Widget {
    priv columns: int = 0

    /// Dense native macOS data grid or sidebar.
    pub fn set_compact(on: bool) -> Result<bool> {
        return self.set_property(host.P_COMPACT, if on { 1 } else { 0 })
    }

    pub fn init(context: Option<render.UiContext> = none) {
        super.init(WidgetKind.table, context)
    }

    /// A table with one column per title.
    pub static fn of(titles: List<string>) -> Result<Table> {
        WidgetKind.table.demand()?
        var table: Table = new Table()
        table.set_columns(titles.len())?
        var index: int = 0
        for index < titles.len() {
            table.set_column_title(index, titles[index])?
            index = index + 1
        }
        return ok(table)
    }

    /// How many columns. Set before the rows: a table with no columns has
    /// nothing to draw a row into, and every host treats this as the
    /// structural change it is.
    pub fn set_columns(count: int) -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            table.set_columns(count)?
            self.columns = count
            return ok(true)
        }
        unsafe {
            host.check(host.ctd_table_columns(self.handle().raw, count as i32) as int,
                       "give a table {count} columns")?
        }
        self.columns = count
        return ok(true)
    }

    pub fn column_count() -> int {
        return self.columns
    }

    /// Replaces the column titles used by a .bx table.
    pub fn set_titles(titles: List<string>) -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            table.set_titles(titles)?
            self.columns = table.column_count()
            return ok(true)
        }
        self.set_columns(titles.len())?
        for index: int in 0..titles.len() { self.set_column_title(index, titles[index])? }
        return ok(true)
    }

    /// Replaces every column width, in title order.
    pub fn set_widths(widths: List<f64>) -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.set_widths(widths)
        }
        if widths.len() != self.columns { return err("table widths must match columns", "out_of_range") }
        for index: int in 0..widths.len() { self.set_column_width(index, widths[index])? }
        return ok(true)
    }
    pub fn reset_widths() -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.reset_widths()
        }
        for index: int in 0..self.columns { self.set_column_width(index, 120.0)? }
        return ok(true)
    }

    pub fn set_column_title(column: int, title: string) -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.set_title(column, title)
        }
        let buffer: Bytes = host.HostText.encode(title, "title a table column")?
        unsafe {
            return host.check(
                host.ctd_table_column_title(self.handle().raw, column as i32,
                                            host.HostText.pointer(buffer),
                                            buffer.len() as i32) as int,
                "title a table column")
        }
    }

    pub fn set_column_width(column: int, points: f64) -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.set_width(column, points)
        }
        unsafe {
            return host.check(
                host.ctd_table_column_width(self.handle().raw, column as i32, points) as int,
                "set the width of a table column")
        }
    }

    /// Allow editing only for cells whose policy returns true.
    /// The policy must answer immediately. A committed edit raises
    /// `text_commit` on this table: `index` is the row, `token` the column,
    /// and `text` the proposed value. Save it in your source; call
    /// `reload()` if the row count changes. An unsaved cell reverts.
    /// Tables are read-only until this is called. The shared table opens one
    /// editor on double-click or Return and closes it on Escape.
    pub fn set_editable_when(policy: fn(int, int) -> bool) -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.set_editable_when(policy)
        }
        unsafe {
            host.check(host.ctd_table_editing(self.handle().raw, 1) as int,
                       "enable native table cell editing")?
        }
        TableDesk.instance.set_edit_policy(self.handle().raw, policy)
        return ok(true)
    }

    /// Return the table to its default read-only state.
    pub fn clear_editable() -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.clear_editable()
        }
        unsafe {
            host.check(host.ctd_table_editing(self.handle().raw, 0) as int,
                       "disable native table cell editing")?
        }
        TableDesk.instance.clear_edit_policy(self.handle().raw)
        return ok(true)
    }

    /// Simulate a user committing one cell through the table action path.
    /// Useful in tests that run without a visible window.
    pub fn edit_as_user(row: int, column: int, text: string) -> Result<bool> {
        if self.is_rendered() {
            self.render_object()?
            let context: render.UiContext = self.render_context().expect("shared table context")
            return context.actions(self.handle().raw).commit_cell(row, column, text)
        }
        let buffer: Bytes = host.HostText.encode(text, "edit a table cell")?
        unsafe {
            return host.check(
                host.ctd_table_edit_as_user(self.handle().raw, row as i32,
                                            column as i32,
                                            host.HostText.pointer(buffer),
                                            buffer.len() as i32) as int,
                "edit a table cell as the user")
        }
    }

    /// Where the cells come from, and how many rows there are.
    ///
    /// The row count is read once here and pushed to the host, because it is
    /// one integer the program already knows — asking for it during every
    /// draw would be a call per frame for a number that only changes when the
    /// program says so. `reload()` is how it changes.
    pub fn set_source(rows: TableRows) -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.set_source(new SharedTableRows(rows))
        }
        TableDesk.instance.put(self.handle().raw, rows)
        return self.reload()
    }
    pub fn clear_source() -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.clear_source()
        }
        TableDesk.instance.forget(self.handle().raw)
        return self.reload()
    }

    /// Ask again: the contents changed, the shape did not.
    pub fn reload() -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.reload()
        }
        var count: int = 0
        match TableDesk.instance.rows_of(self.handle().raw) {
            some(rows) => { count = rows.row_count() }
            none => { count = 0 }
        }
        if count < 0 {
            return err("a table's source answered {count} rows", "row_count_negative")
        }
        unsafe {
            host.check(host.ctd_table_rows(self.handle().raw, count as i32) as int,
                       "tell a table how many rows it has")?
            return host.check(host.ctd_table_reload(self.handle().raw) as int,
                              "reload a table")
        }
    }

    /// What the platform has for one cell, asked through its own data source.
    ///
    /// The round trip, and the counterpart of `native_child_count`: cortado
    /// knows what it told the table, and bookkeeping that is never checked
    /// against the thing it describes is how a table ends up correct on paper
    /// and wrong on screen. It is also the only way to see the path work with
    /// no display — a table asks for cells when it draws, and a headless
    /// window never draws.
    pub fn native_cell(row: int, column: int) -> Result<string> {
        if self.is_rendered() { return err("shared table has no native cell", "unsupported") }
        let raw: u64 = self.handle().raw
        return host.HostText.read(
            "read a table cell back from the platform",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_table_cell(raw, row as i32, column as i32, out, cap) }
            })
    }

    /// The selected row, or -1 for none.
    pub fn selected() -> Result<int> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return ok(table.selected())
        }
        let scratch: host.HostScratch = host.HostScratch.instance
        var row: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_table_selected(self.handle().raw, slot) as int,
                       "read a table's selected row")?
            row = slot.read()
        }
        return ok(row as int)
    }

    /// Select a row, or -1 to select none.
    pub fn select(row: int) -> Result<bool> {
        if self.is_rendered() {
            let table: render.TableRender = (self.render_object()? as? render.TableRender).expect("shared table")
            return table.select(row)
        }
        unsafe {
            return host.check(host.ctd_table_select(self.handle().raw, row as i32) as int,
                              "select a table row")
        }
    }

    pub override fn release() {
        // The desk routes on a handle, and a handle is reused once its slot's
        // generation moves on. A source left behind would answer for whatever
        // widget landed in that slot next.
        if !self.is_rendered() { TableDesk.instance.forget(self.handle().raw) }
        super.release()
    }
}
