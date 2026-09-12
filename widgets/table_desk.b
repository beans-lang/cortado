// The one place the platform calls into Beans.
package widgets

import cortado.host

/// Which table is which, and the cell text behind it.
///
/// Held by a plain object rather than by the singleton's own fields, because a
/// callback closure may not capture a field — Beans refuses `move self.x` into
/// one — but may capture a local that holds a class reference. So the desk
/// keeps this, the closure captures this, and they are the same object.
class TableBook {
    priv handles: List<u64> = []
    priv sources: List<TableRows> = []

    pub fn init() {}

    pub fn put(handle: u64, rows: TableRows) {
        var index: int = 0
        for index < self.handles.len() {
            if self.handles[index] == handle {
                self.sources[index] = rows
                return
            }
            index = index + 1
        }
        self.handles.push(handle)
        self.sources.push(rows)
    }

    pub fn forget(handle: u64) {
        var index: int = 0
        for index < self.handles.len() {
            if self.handles[index] == handle {
                self.handles.remove(index)
                self.sources.remove(index)
                return
            }
            index = index + 1
        }
    }

    pub fn find(handle: u64) -> Option<TableRows> {
        var index: int = 0
        for index < self.handles.len() {
            if self.handles[index] == handle { return some(self.sources[index]) }
            index = index + 1
        }
        return none
    }

    /// What the platform asks for, answered the way `ctd_get_text` answers:
    /// write at most `cap` bytes, return the number the cell needs.
    ///
    /// A table nobody registered a source for answers 0 rather than a refusal.
    /// The platform is drawing; there is nothing it could do with an error,
    /// and an empty cell is what an unfilled table looks like anyway.
    pub fn fill(handle: u64, row: i32, column: i32,
                out: RawPtr<i8>, cap: i32) -> i32 {
        var text: string = ""
        match self.find(handle) {
            some(rows) => { text = rows.cell(row as int, column as int) }
            none => { return 0 }
        }
        let bytes: Bytes = Bytes.from(text)
        let needed: int = bytes.len()
        var index: int = 0
        for index < needed && index < (cap as int) {
            unsafe { out.offset(index).write(bytes.get(index) as i8) }
            index = index + 1
        }
        return needed as i32
    }
}

/// The process's one table data source.
///
/// One callback for the whole program, registered once, routed on the table's
/// handle — the same shape the event sink uses, and for the same reason. A
/// stored callback per control is a leak by construction: the platform holds a
/// strong reference the cycle collector cannot trace, and cortado cannot close
/// one it has handed out.
pub singleton class TableDesk {
    priv book: TableBook = new TableBook()
    priv hook: LocalStoredCallback<fn(RawPtr<u8>, u64, i32, i32, RawPtr<i8>, i32) -> i32>

    pub fn init() {
        let book: TableBook = new TableBook()
        self.book = book
        self.hook = LocalStoredCallback.create(0,
            fn(table: u64, row: i32, column: i32, out: RawPtr<i8>, cap: i32) -> i32 {
                return book.fill(table, row, column, out, cap)
            })
        unsafe {
            host.ctd_set_table_source(self.hook.function(), self.hook.context())
        }
    }

    pub fn put(handle: u64, rows: TableRows) { self.book.put(handle, rows) }
    pub fn forget(handle: u64) { self.book.forget(handle) }

    pub fn rows_of(handle: u64) -> Option<TableRows> { return self.book.find(handle) }
}
