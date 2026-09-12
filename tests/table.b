// A table, and the promise that makes it a table rather than a list of labels.
//
// **A hundred thousand rows costs what thirty rows costs.** That is the whole
// claim, and this file is where it stops being a claim: the source counts how
// many times it is asked for a cell, and the count does not move when the row
// count goes from three to a hundred thousand. Nothing is built, nothing is
// laid out, nothing is diffed — the control asks for what it is about to draw
// and no more.
//
// Cross-host, and every line is either cortado's own arithmetic or an
// agreement between what the platform was told and what it answers back
// through its own data source. `native_cell` is that round trip: out through
// the callback, into `NSTableView`'s dataSource / a `GListModel`'s bind /
// `LVN_GETDISPINFO`, and back. Bookkeeping that is never checked against the
// thing it describes is how a table ends up correct on paper and wrong on
// screen.
//
// Agreement rather than inventory, which is what lets one golden stand for
// every host: each line says "this is true wherever there is a table, and
// there is nothing to be untrue where there is not". All four hosts have one
// today — so the shape costs nothing here and is the reason `tests/outline.b`,
// which was written from this file, has one golden and not two.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import cortado.geometry
import std.io

/// Rows made up on demand, and a tally of how often the platform asked.
class Ledger implements widgets.TableRows {
    pub asked: int = 0
    pub rows: int = 0

    pub fn init(rows: int) { self.rows = rows }

    pub fn row_count() -> int { return self.rows }

    pub fn cell(row: int, column: int) -> string {
        self.asked = self.asked + 1
        if column == 0 { return "row {row}" }
        return "{row * 3}p"
    }
}

class Heard {
    pub rows: List<int> = []
    /// What the router heard, so a write that should be silent can be proved
    /// so.
    pub count: int = 0
    pub last: int = 0
    pub fn init() {}
}

/// Whether a call was refused. `match` at every call site would bury the four
/// lines it is used in; the name says what is being asked.
fn refused_text(answer: Result<string>) -> bool {
    match answer {
        ok(text) => { return false }
        err(problem) => { return true }
    }
}

fn refused_flag(answer: Result<bool>) -> bool {
    match answer {
        ok(done) => { return false }
        err(problem) => { return true }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var window: surface.Window = app.window(360.0, 240.0, "Table")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    let here: bool = widgets.WidgetKind.table.available()

    io.println("-- what this platform has --")
    // The kind and the constructor are two ways of asking one question, and
    // they must not answer differently: a program that laid out a screen from
    // the kind and built its controls from the constructor would build a
    // control it had decided not to show. A host with no table refuses by
    // name, and that refusal is this line's other half rather than a second
    // golden.
    var agrees: bool = false
    match widgets.Table.of(["one"]) {
        ok(made) => { agrees = here }
        err(problem) => { agrees = !here && problem.kind == "no_such_control" }
    }
    io.println("  the kind and building one agree: {agrees}")

    let small: Ledger = new Ledger(3)
    let some: Ledger = new Ledger(1000)
    let many: Ledger = new Ledger(100000)
    let tally: Heard = new Heard()

    // Every answer below starts true and stays true on a platform with no
    // table, because there is nothing there to be untrue. On a platform with
    // one, each is the agreement its line names — which is what keeps one
    // golden for every host instead of one per inventory.
    var one_column: bool = true
    var round_trip: bool = true
    var row_past_end: bool = true
    var no_such_column: bool = true
    var second_column: bool = true
    var reads_back: bool = true
    var clears: bool = true
    var select_past_end: bool = true
    var stayed_quiet: bool = true
    var heard_the_user: bool = true
    var stayed_cheap: bool = true
    var middle_cell: bool = true
    var two_asks: bool = true

    if here {
        // One column, because that is what every host has. The second column
        // is asked for separately below, where the answer may differ.
        var table: widgets.Table = widgets.Table.of(["Row"])?
        root.add(table)?
        table.set_frame(geometry.Rect.of(0.0, 0.0, 340.0, 200.0))?
        table.set_source(small)?

        app.router.on(table.handle(), events.EventKind.selection,
            fn(event: events.UiEvent) {
                tally.count = tally.count + 1
                tally.last = event.index as int
            })
        one_column = table.column_count() == 1

        // Out through the callback, into the platform's own data source, and
        // back.
        let first: string = table.native_cell(0, 0).or("?")
        let last: string = table.native_cell(2, 0).or("?")
        round_trip = first == "row 0" && last == "row 2"
        row_past_end = refused_text(table.native_cell(3, 0))
        no_such_column = refused_text(table.native_cell(0, 9))

        // Every host but one has columns you can size and title. A
        // UITableView is a list: the cell styles that look like two columns
        // are a label and a detail label. So the answer is either "done" or
        // "this platform cannot", and never four columns quietly collapsed
        // into one.
        var wide: widgets.Table = widgets.Table.of(["Row"])?
        var gave_two: bool = false
        var said_cannot: bool = false
        match wide.set_columns(2) {
            ok(done) => { gave_two = wide.column_count() == 2 }
            err(problem) => { said_cannot = problem.kind == "unsupported" }
        }
        second_column = gave_two != said_cannot

        // Counted across every write below, because the header's rule is that
        // a write is silent and a table is the control most likely to break
        // it: NSTableView posts a selection change for -selectRowIndexes:
        // exactly as it does for a click, GtkSingleSelection emits
        // "selection-changed" whoever moved it, and LVM_SETITEMSTATE sends
        // LVN_ITEMCHANGED to the parent. Three of the four hosts had to be
        // told; UIKit is quiet on its own.
        //
        // A program that hears its own selection is not a curiosity. A
        // navigator that opens a tree node and then selects it hears the
        // selection, treats it as a click, and shuts the node it just opened
        // — which is exactly what examples/cask did, on the first run, with
        // nothing in any log.
        let quiet_at: int = tally.count
        table.select(1)?
        reads_back = table.selected().or(-9) == 1
        table.select(-1)?
        clears = table.selected().or(-9) == -1
        select_past_end = refused_flag(table.select(99))
        stayed_quiet = tally.count == quiet_at

        // The other half, or the line above would pass on a host that raises
        // no selection event at all.
        table.set_value_as_user(2, 0.0)?
        heard_the_user = tally.count == quiet_at + 1 && tally.last == 2

        // The measurement this file exists for, and it is a *comparison*
        // rather than a count, because the count names a platform. AppKit and
        // UIKit ask for nothing at all until they draw, so they answer 0; GTK
        // realises a screenful when the model changes, so it answers a few
        // hundred. Both are right, and both say the same thing:
        //
        //   **a hundred times the rows is not a hundred times the work.**
        //
        // A table that built its rows would answer a hundred times the first
        // number here. What is asserted is that the second is no larger than
        // the first — which is what "the control holds a count, not rows"
        // means.
        var thousand: widgets.Table = widgets.Table.of(["Row"])?
        root.add(thousand)?
        thousand.set_frame(geometry.Rect.of(0.0, 0.0, 340.0, 200.0))?
        thousand.set_source(some)?

        var huge: widgets.Table = widgets.Table.of(["Row"])?
        root.add(huge)?
        huge.set_frame(geometry.Rect.of(0.0, 0.0, 340.0, 200.0))?
        huge.set_source(many)?

        stayed_cheap = many.asked <= some.asked

        let asked_before: int = many.asked
        middle_cell = huge.native_cell(99999, 0).or("?") == "row 99999"
        // Two asks for one cell, not one, and the reason is the two-call read
        // every text answer in this ABI uses: once with no buffer to learn
        // the length, once to fill it. A cell the platform *draws* is asked
        // once.
        two_asks = many.asked - asked_before == 2

        app.router.forget(table.handle())
    }

    io.println("  it has the columns it was given: {one_column}")

    io.println("-- the round trip --")
    io.println("  the platform answers what the source says: {round_trip}")
    io.println("  and a row past the end is refused: {row_past_end}")
    io.println("  as is a column that is not there: {no_such_column}")

    io.println("-- a second column --")
    io.println("  a second column is given, or refused as unsupported: {second_column}")

    io.println("-- selection --")
    io.println("  a selected row reads back: {reads_back}")
    io.println("  and -1 clears it: {clears}")
    io.println("  a row past the end is refused: {select_past_end}")
    io.println("  and none of that was reported as the user's doing: {stayed_quiet}")
    io.println("  a user picking a row is reported, and says which: {heard_the_user}")

    io.println("-- a thousand rows, then a hundred thousand --")
    io.println("  a hundred times the rows asked for no more cells: {stayed_cheap}")
    // And the two ledgers really were different sizes, so the line above is
    // not two zeros agreeing about nothing. Cortado's own arithmetic, so it
    // says the same thing on a platform with no table as on one with.
    io.println("  and the two really were 1,000 and 100,000 rows: {some.row_count() * 100 == many.row_count()}")
    io.println("  a cell out of the middle still answers: {middle_cell}")
    io.println("  which cost two asks, once to size and once to fill: {two_asks}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
