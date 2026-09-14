// A search field, a spinner, and a table that filters as you type.
//
//     beansc build examples/finder.b -o build/finder && ./build/finder
//
// Three controls that were added for each other. The search field is the
// platform's own — `NSSearchField`, a `UISearchTextField`, a `GtkSearchEntry`,
// an `EDIT` with a cue banner — so it brings the magnifier, the clear button
// and the keyboard handling without cortado drawing any of it. The spinner
// says work is happening with no claim about how much is left, which is the
// honest thing to show when a filter is running. And the table asks for the
// rows it is about to draw, so filtering twenty thousand orders rebuilds
// nothing: the filter is a list of indices, and the table asks that list.
//
// The filter here is instant, so the spinner turns for one render. That is on
// purpose — it is the shape a real screen has, and the place a real program
// would hand the work to a thread and call `reload()` when it came back.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

const ORDERS: int = 20000

/// Every order, and the ones that match. The table sees `matching`.
///
/// `cell` is called by the platform while it is drawing, so it does the least
/// possible: one index lookup and one bit of arithmetic. The filtering happens
/// once, in `narrow`, when the words change.
class Orders implements widgets.TableRows {
    priv drinks: List<string> = []
    pub matching: List<int> = []

    pub fn init() {
        self.drinks = ["flat white", "espresso", "cortado", "long black", "macchiato"]
        self.narrow("")
    }

    pub fn drink_at(row: int) -> string {
        return self.drinks[row % self.drinks.len()]
    }

    /// Which rows match, worked out once rather than per drawn cell.
    pub fn narrow(words: string) {
        var kept: List<int> = []
        let wanted: string = words.to_lower().trim()
        var row: int = 0
        for row < ORDERS {
            if wanted.len() == 0 || self.drink_at(row).contains(wanted) {
                kept.push(row)
            }
            row = row + 1
        }
        self.matching = move kept
    }

    pub fn row_count() -> int { return self.matching.len() }

    pub fn cell(row: int, column: int) -> string {
        let order: int = self.matching[row]
        if column == 0 { return "{order + 1}" }
        if column == 1 { return self.drink_at(order) }
        return "{240 + (order % 5) * 60}p"
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    if !widgets.WidgetKind.table.available() {
        io.println("this platform has no table control")
        return ok(false)
    }

    var window: surface.Window = app.window(520.0, 380.0, "Finder")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var find: widgets.SearchField = widgets.SearchField.of("Search drinks")?
    var count: widgets.Label = widgets.Label.of("")?
    var orders: widgets.Table = widgets.Table.of(["#", "Drink", "Price"])?
    root.add(find)?
    root.add(orders)?
    root.add(count)?

    // A spinner where there is one. Windows has none, and the honest thing to
    // do is leave the row shorter rather than draw a substitute.
    var wheel: Option<widgets.Spinner> = none
    if widgets.WidgetKind.spinner.available() {
        var made: widgets.Spinner = widgets.Spinner.of(false)?
        root.add(made)?
        wheel = some(made)
    }

    orders.set_column_width(0, 70.0)?
    orders.set_column_width(1, 200.0)?
    orders.set_column_width(2, 90.0)?

    let book: Orders = new Orders()
    orders.set_source(book)?
    count.set_text("{book.row_count()} of {ORDERS}")

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.FlexLayout = layout.FlexLayout.column(10.0)
    body.set_padding(geometry.EdgeInsets.all(16.0))
    // Stretch, because a column hands a child the width it *measures* and a
    // table measures to nothing — its width is whatever room it is given.
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?

    // FlexLayout, not StackLayout: the search field asks to grow, and a stack
    // hands nothing out — it refuses a growing child rather than laying it out
    // at its intrinsic width and saying nothing.
    var line: layout.FlexLayout = layout.FlexLayout.row(8.0)
    var row: layout.LayoutNode = sheet.spacer("line", line)
    var search_node: layout.LayoutNode = sheet.leaf("find", find)
    search_node.spec = layout.LayoutSpec.flexible(1.0)
    row.add(search_node)
    match wheel {
        some(made) => { row.add(sized(sheet, "wheel", made, 20.0, 20.0)) }
        none => {}
    }
    page.add(row)

    var rows: layout.LayoutNode = sheet.leaf("orders", orders)
    rows.spec = layout.LayoutSpec.flexible(1.0)
    page.add(rows)
    page.add(sheet.leaf("count", count))

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    app.router.on(find.handle(), events.EventKind.text_commit,
        fn(event: events.UiEvent) {
            // The spinner turns while the filter runs. Here that is one render
            // — the place a real program would hand the work to a thread and
            // call `reload()` when it came back.
            match wheel {
                some(made) => { made.set_turning(true) }
                none => {}
            }
            book.narrow(event.text)
            orders.reload()
            count.set_text("{book.row_count()} of {ORDERS}")
            match wheel {
                some(made) => { made.set_turning(false) }
                none => {}
            }
            io.println("\"{event.text}\" matched {book.row_count()}")
        })

    window.show()?
    app.run()
    app.shutdown()
    return ok(true)
}

fn sized(sheet: widgets.WidgetLayout, name: string, control: widgets.Widget,
         width: f64, height: f64) -> layout.LayoutNode {
    var node: layout.LayoutNode = sheet.leaf(name, control)
    node.spec = layout.LayoutSpec.fixed(width, height)
    return node
}

fn main() {
    match run() {
        ok(done) => { io.println("done={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
