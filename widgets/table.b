// Rows and columns, filled by asking rather than by building.
package widgets

import cortado.host

/// A table.
///
/// `NSTableView`, a `GtkColumnView`, a virtual `SysListView32`, a
/// `UITableView` — and the one control cortado does not build out of widgets.
/// It holds no rows: it is given a `TableRows` and asks it for the cells it is
/// about to draw, which is what every native toolkit has done for thirty years
/// and the only way a hundred thousand rows costs what thirty rows cost.
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

    pub fn init() {
        super.init(WidgetKind.table)
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

    pub fn set_column_title(column: int, title: string) -> Result<bool> {
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
        unsafe {
            return host.check(
                host.ctd_table_column_width(self.handle().raw, column as i32, points) as int,
                "set the width of a table column")
        }
    }

    /// Where the cells come from, and how many rows there are.
    ///
    /// The row count is read once here and pushed to the host, because it is
    /// one integer the program already knows — asking for it during every
    /// draw would be a call per frame for a number that only changes when the
    /// program says so. `reload()` is how it changes.
    pub fn set_source(rows: TableRows) -> Result<bool> {
        TableDesk.instance.put(self.handle().raw, rows)
        return self.reload()
    }

    /// Ask again: the contents changed, the shape did not.
    pub fn reload() -> Result<bool> {
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
        let raw: u64 = self.handle().raw
        return host.HostText.read(
            "read a table cell back from the platform",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_table_cell(raw, row as i32, column as i32, out, cap) }
            })
    }

    /// The selected row, or -1 for none.
    pub fn selected() -> Result<int> {
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
        unsafe {
            return host.check(host.ctd_table_select(self.handle().raw, row as i32) as int,
                              "select a table row")
        }
    }

    pub override fn release() {
        // The desk routes on a handle, and a handle is reused once its slot's
        // generation moves on. A source left behind would answer for whatever
        // widget landed in that slot next.
        TableDesk.instance.forget(self.handle().raw)
        super.release()
    }
}
