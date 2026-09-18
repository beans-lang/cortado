// The native table editor asks before each cell and reports committed text.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import cortado.geometry
import std.io

class Cells implements widgets.TableRows {
    pub value: string = "old"

    pub fn init() {}
    pub fn row_count() -> int { return 2 }
    pub fn cell(row: int, column: int) -> string {
        if column == 0 { return "row {row}" }
        if row == 1 { return self.value }
        return "locked"
    }
}

class Heard {
    pub count: int = 0
    pub row: int = -1
    pub column: int = -1
    pub value: string = ""
    pub persist: bool = true
    pub fn init() {}
}

fn refused(answer: Result<bool>) -> bool {
    match answer {
        ok(done) => { return false }
        err(problem) => { return true }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(320.0, 200.0, "Table edits")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var table: widgets.Table = widgets.Table.of(["Row", "Value"])?
    root.add(table)?
    table.set_frame(geometry.Rect.of(0.0, 0.0, 300.0, 160.0))?
    let cells: Cells = new Cells()
    table.set_source(cells)?

    let heard: Heard = new Heard()
    app.router.on(table.handle(), events.EventKind.text_commit,
        fn(event: events.UiEvent) {
            heard.count = heard.count + 1
            heard.row = event.index
            heard.column = event.token
            heard.value = event.text
            if heard.persist { cells.value = event.text }
        })

    let default_read_only: bool = refused(table.edit_as_user(1, 1, "no")) &&
                                  heard.count == 0 && cells.value == "old"
    table.set_editable_when(fn(row: int, column: int) -> bool {
        return row == 1 && column == 1
    })?
    let denied_cells: bool = refused(table.edit_as_user(0, 1, "no")) &&
                             refused(table.edit_as_user(1, 0, "no")) &&
                             heard.count == 0
    table.edit_as_user(1, 1, "café")?
    let committed: bool = heard.count == 1 && heard.row == 1 &&
                          heard.column == 1 && heard.value == "café" &&
                          table.native_cell(1, 1).or("?") == "café"
    table.edit_as_user(1, 1, "")?
    let empty_text: bool = heard.count == 2 && heard.value == "" &&
                           table.native_cell(1, 1).or("?") == ""
    heard.persist = false
    table.edit_as_user(1, 1, "not saved")?
    let rejected_reverts: bool = heard.count == 3 &&
                                 table.native_cell(1, 1).or("?") == ""
    table.clear_editable()?
    let read_only_again: bool = refused(table.edit_as_user(1, 1, "no")) &&
                                heard.count == 3

    io.println("default read-only: {default_read_only}")
    io.println("cell policy gates edits: {denied_cells}")
    io.println("row, column and UTF-8 text commit: {committed}")
    io.println("empty text commits: {empty_text}")
    io.println("unsaved edit reverts: {rejected_reverts}")
    io.println("clearing the policy restores read-only: {read_only_again}")
    app.router.forget(table.handle())
    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
