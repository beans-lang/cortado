// Fifty thousand rows in a window, and nothing built to hold them.
//
//     beansc build examples/ledger.b -o build/ledger && ./build/ledger
//
// The point of this example is what is *not* in it. There is no list of row
// widgets, no loop that makes fifty thousand labels, and no code that runs
// when the user scrolls. `Ledger` implements `TableRows` — two methods, "how
// many" and "what is at row r, column c" — and the platform asks for the cells
// it is about to draw and no others. NSTableView calls that a data source,
// Win32 calls it LVS_OWNERDATA, GTK4 a list model; they all mean the same
// thing, and it is why this window opens instantly and scrolls at the
// display's rate.
//
// The rows here are computed rather than stored, which makes the point twice:
// fifty thousand rows of four columns is two hundred thousand strings that
// never exist, because only the ones on screen are ever asked for.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

const ROWS: int = 50000

/// A made-up order book. Nothing is stored: every cell is arithmetic.
///
/// The one rule `cell` has to keep is that it returns. It runs on the UI
/// thread while the platform is drawing, so no waiting and no fetching — if
/// the data is not here yet, answer what you have and call `reload()` when it
/// arrives.
class Book implements widgets.TableRows {
    priv drinks: List<string> = []

    pub fn init() {
        self.drinks = ["flat white", "espresso", "cortado", "long black", "macchiato"]
    }

    pub fn row_count() -> int { return ROWS }

    pub fn cell(row: int, column: int) -> string {
        if column == 0 { return "{row + 1}" }
        if column == 1 { return self.drinks[row % self.drinks.len()] }
        if column == 2 { return "{(row % 4) + 1}" }
        return "{240 + (row % 5) * 60}p"
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    if !widgets.WidgetKind.table.available() {
        io.println("this platform has no table control")
        return ok(false)
    }

    var window: surface.Window = app.window(520.0, 360.0, "Ledger")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("{ROWS} orders")?
    var chosen: widgets.Label = widgets.Label.of("Nothing selected")?
    var orders: widgets.Table = widgets.Table.of(["#", "Drink", "Shots", "Price"])?
    root.add(heading)?
    root.add(orders)?
    root.add(chosen)?

    // Widths are the one thing worth setting by hand: a column of numbers and
    // a column of names want different room, and the solver above knows about
    // the table but not about what is in it.
    orders.set_column_width(0, 60.0)?
    orders.set_column_width(1, 180.0)?
    orders.set_column_width(2, 70.0)?
    orders.set_column_width(3, 90.0)?

    let book: Book = new Book()
    orders.set_source(book)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.FlexLayout = layout.FlexLayout.column(10.0)
    body.set_padding(geometry.EdgeInsets.all(16.0))
    // Stretch, not the default. A column's cross axis defaults to `start`,
    // which gives a child the width it *measures* — and a table measures to
    // nothing, because its width is whatever room it is given. Without this
    // line the table is 0 points wide, laid out correctly and invisible.
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)
    page.add(sheet.leaf("heading", heading))
    // The table takes the room that is left. A fixed height would leave a gap
    // under it on a big screen and cut it off on a small one.
    var rows: layout.LayoutNode = sheet.leaf("orders", orders)
    rows.spec = layout.LayoutSpec.flexible(1.0)
    page.add(rows)
    page.add(sheet.leaf("chosen", chosen))

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    app.router.on(orders.handle(), events.EventKind.selection,
        fn(event: events.UiEvent) {
            let row: int = event.index
            if row < 0 {
                chosen.set_text("Nothing selected")
                return
            }
            // Read the table, not a copy: the row number is the event's, and
            // the text comes from the same place the platform got it.
            chosen.set_text("Order {book.cell(row, 0)} — {book.cell(row, 1)}, {book.cell(row, 3)}")
        })

    window.show()?
    app.run()
    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => { io.println("done={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
