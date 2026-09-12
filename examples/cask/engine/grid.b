// A result set, and the two questions a table control asks about it.
package engine

import cortado.widgets

/// Every cell of one query's answer, already turned into text.
///
/// A `Table` is a *pull* control: it asks "how many rows" and "what is at row
/// r, column c" while it is drawing, and both answers have to come back
/// immediately. So a query is stepped to the end here, up front, and the grid
/// is what the control reads from. That is the right shape for a browser — a
/// person looking at a table wants to scroll it, and a cursor that has to be
/// re-stepped cannot be scrolled backwards.
///
/// The cells are one flat list rather than a list of rows. A `List<List<T>>`
/// is two allocations per row and a move out of the outer list every time a
/// cell is read; row-major arithmetic is neither.
pub class Grid implements widgets.TableRows {
    priv titles: List<string> = []
    priv cells: List<string> = []
    priv wide: int = 0
    priv complete: bool = true

    pub fn init(titles: List<string>) {
        self.wide = titles.len()
        for title: string in titles {
            self.titles.push(title)
        }
    }

    /// An empty grid with no columns — what a statement that returns no rows
    /// at all (an `INSERT`, a `PRAGMA` that sets something) leaves behind.
    pub static fn empty() -> Grid {
        return new Grid([])
    }

    // ---- filling ----

    /// Appends one row. The row must be as wide as the titles; a short one
    /// would silently shift every cell after it into the wrong column.
    pub fn push_row(row: List<string>) -> Result<bool> {
        if row.len() != self.wide {
            return err("a row of {row.len()} cells does not fit {self.wide} columns",
                "row_width")
        }
        for cell: string in row {
            self.cells.push(cell)
        }
        return ok(true)
    }

    /// Marks the grid as holding only part of the answer, because the query
    /// was cut off at a limit. The window says so rather than pretending the
    /// table ends where the reading stopped.
    pub fn set_complete(complete: bool) {
        self.complete = complete
    }

    pub fn is_complete() -> bool {
        return self.complete
    }

    // ---- reading ----

    pub fn column_count() -> int {
        return self.wide
    }

    pub fn column_titles() -> List<string> {
        var out: List<string> = []
        for title: string in self.titles {
            out.push(title)
        }
        return move out
    }

    /// One column's widest cell, in characters, capped so a row of JSON does
    /// not make a column wider than the window. Used to pick column widths,
    /// which is the one thing the layout solver above cannot do: it knows how
    /// big the table is and nothing about what is in it.
    pub fn widest(column: int, cap: int) -> int {
        if column < 0 || column >= self.wide {
            return 0
        }
        var most: int = self.titles[column].len()
        var row: int = 0
        for row < self.row_count() {
            let size: int = self.cells[row * self.wide + column].len()
            if size > most { most = size }
            if most >= cap { return cap }
            row = row + 1
        }
        return most
    }

    /// The rows whose text contains `needle`, in any column.
    ///
    /// The filter runs over what was read, not over the database, and that is
    /// a real limit rather than a shortcut: the grid holds at most `PAGE`
    /// rows, so this searches the page a person is looking at. Searching the
    /// whole table is a different feature — it is a `WHERE` clause, it needs
    /// to know which columns are text, and it belongs in the query tab where
    /// a person can write one.
    ///
    /// Matching is case-insensitive, because a person typing into a search
    /// field is not thinking about case, and it is done by lowering both
    /// sides rather than by a clever comparison: ASCII case is what SQLite's
    /// own `LIKE` folds by default, so this agrees with the database.
    pub fn filtered(needle: string) -> Grid {
        var out: Grid = new Grid(self.column_titles())
        let wanted: string = needle.to_lower()
        let everything: bool = needle == ""
        var row: int = 0
        for row < self.row_count() {
            var hit: bool = everything
            var column: int = 0
            for !hit && column < self.wide {
                if self.cells[row * self.wide + column].to_lower().contains(wanted) {
                    hit = true
                }
                column = column + 1
            }
            if hit {
                var copy: List<string> = []
                column = 0
                for column < self.wide {
                    copy.push(self.cells[row * self.wide + column])
                    column = column + 1
                }
                match out.push_row(move copy) {
                    ok(added) => {}
                    err(problem) => {}
                }
            }
            row = row + 1
        }
        out.set_complete(self.complete)
        return out
    }

    // ---- what the control asks ----

    pub fn row_count() -> int {
        if self.wide == 0 { return 0 }
        return self.cells.len() / self.wide
    }

    /// Runs on the UI thread while the platform is drawing, so it returns and
    /// never waits. Out of range answers empty rather than refusing: a table
    /// that is being reloaded under a scroll can ask for a row that was there
    /// a moment ago, and a crash is not the right answer to a race the
    /// platform owns.
    pub fn cell(row: int, column: int) -> string {
        if column < 0 || column >= self.wide { return "" }
        if row < 0 || row >= self.row_count() { return "" }
        return self.cells[row * self.wide + column]
    }
}
