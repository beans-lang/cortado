// What cortado costs, measured rather than claimed.
//
//     beansc build examples/bench.b -o build/bench && ./build/bench
//
// **"Native performance and smoothness" is a claim with a number behind it or
// it is nothing.** The number that matters for smoothness is not how fast
// anything is in isolation — it is how much of a *frame* cortado spends,
// because a frame is the budget: 8.33 ms at 120 Hz, 16.67 at 60. Everything
// below is reported against that.
//
// Four things are measured, and they are the four that happen while a person
// is looking at the screen:
//
//   1. **Laying out a screen.** The solver is pure Beans and runs on every
//      resize — on every frame of a resize, if somebody is dragging a corner.
//   2. **An event reaching a handler.** The whole road: a synthesised click
//      through the platform's own dispatch, into the host, across the one
//      callback edge, through the router, into a Beans function.
//   3. **Reading a cell.** What a table asks its source while it draws.
//   4. **Building a screen.** Not a frame cost — it happens once — but it is
//      what the first paint waits for.
//
// Timings are medians of many runs after a warm-up, because a mean is a report
// on the worst thing that happened while it ran and the tenth percentile is
// what a person feels as "always fast".
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io
import std.time

/// A table source that counts nothing and answers instantly, so what is being
/// measured is cortado's road to it rather than the program's own work.
class Rows implements widgets.TableRows {
    pub fn init() {}
    pub fn row_count() -> int { return 100000 }
    pub fn cell(row: int, column: int) -> string { return "r{row}" }
}

/// A handler's worth of work, counted so the compiler cannot decide the
/// handler does nothing and remove the call.
class Tally {
    pub heard: int = 0
    pub fn init() {}
}

/// Now, in seconds, from a clock that does not go backwards.
///
/// `std.time.monotonic_nanos` rather than a calendar: a wall clock moves when
/// somebody sets the date or when NTP corrects it, and a duration measured
/// across that is a negative number or a jump. A benchmark is exactly the code
/// that would notice.
fn now() -> f64 {
    return (time.monotonic_nanos() as f64) / 1000000000.0
}

/// The middle value of a list of timings.
///
/// A median rather than a mean, because a mean is a report on the worst thing
/// that happened while the benchmark ran — a page fault, the compositor waking
/// up — and what a person feels is the common case.
fn median(taken: List<f64>) -> f64 {
    var sorted: List<f64> = []
    for one: f64 in taken { sorted.push(one) }
    // Insertion sort: the lists here are hundreds long, and a sort worth
    // naming would be more code than the thing being measured.
    var at: int = 1
    for at < sorted.len() {
        let value: f64 = sorted[at]
        var back: int = at - 1
        for back >= 0 && sorted[back] > value {
            sorted[back + 1] = sorted[back]
            back = back - 1
        }
        sorted[back + 1] = value
        at = at + 1
    }
    return sorted[sorted.len() / 2]
}

fn micros(seconds: f64) -> string {
    let us: int = (seconds * 1000000.0) as int
    return "{us} us"
}

/// What share of one frame at 120 Hz this is, to one decimal place.
fn share_of_frame(seconds: f64) -> string {
    let tenths: int = ((seconds / 0.008333) * 1000.0) as int
    return "{tenths / 10}.{tenths % 10}% of a 120 Hz frame"
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(900.0, 700.0, "bench")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    io.println("cortado, on this machine, against a 120 Hz frame of 8333 us")
    io.println("")

    // ---- 1. building a screen ----
    let widgets_wanted: int = 200
    let built_at: f64 = now()
    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(4.0)
    body.set_padding(geometry.EdgeInsets.all(8.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?
    var made: int = 0
    for made < widgets_wanted {
        var one: widgets.Label = widgets.Label.of("row {made}")?
        root.add(one)?
        page.add(sheet.leaf("row{made}", one))
        made = made + 1
    }
    let building: f64 = now() - built_at
    let each: f64 = building / (widgets_wanted as f64)
    io.println("building {widgets_wanted} real controls: {micros(building)} total, {micros(each)} each")
    io.println("  (once, at startup — not a frame cost)")
    io.println("")

    // ---- 2. laying one out ----
    var title_probe: widgets.Label = widgets.Label.of("a control to measure")?
    root.add(title_probe)?

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    var solves: List<f64> = []
    var round: int = 0
    for round < 200 {
        let at: f64 = now()
        solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
        solves.push(now() - at)
        round = round + 1
    }
    let solving: f64 = median(solves)
    io.println("solving a {widgets_wanted}-control layout: {micros(solving)}")
    io.println("  {share_of_frame(solving)} — and this runs on every frame of a resize")
    io.println("")

    // ---- 2b. where that time goes ----
    //
    // A solve asks every control how big it wants to be, and a control is a
    // real native view: -fittingSize on an NSTextField lays out its text. So
    // the question is how much of the solve is cortado's arithmetic and how
    // much is AppKit's.
    var asks: List<f64> = []
    var ask: int = 0
    for ask < 400 {
        let at: f64 = now()
        title_probe.measure(content)?
        asks.push(now() - at)
        ask = ask + 1
    }
    let asking: f64 = median(asks)
    io.println("asking one control how big it wants to be: {micros(asking)}")
    let all_of_them: f64 = asking * (widgets_wanted as f64)
    io.println("  times {widgets_wanted} controls: {micros(all_of_them)}")
    io.println("  which is this share of the solve above: {((all_of_them / solving) * 100.0) as int}%")
    io.println("")

    // ---- 3. an event reaching a handler ----
    var press: widgets.Button = widgets.Button.of("press")?
    root.add(press)?
    press.set_frame(geometry.Rect.of(0.0, 0.0, 100.0, 30.0))?
    let tally: Tally = new Tally()
    app.router.on(press.handle(), events.EventKind.pointer_down,
        fn(event: events.UiEvent) { tally.heard = tally.heard + 1 })
    // Warm, because the first event through a path pays for everything the
    // path had to set up.
    var warm: int = 0
    for warm < 50 {
        press.point_as_user(events.EventKind.pointer_down,
                            geometry.Point.at(10.0, 10.0),
                            events.PointerButton.left)?
        warm = warm + 1
    }
    var clicks: List<f64> = []
    var click: int = 0
    for click < 500 {
        let at: f64 = now()
        press.point_as_user(events.EventKind.pointer_down,
                            geometry.Point.at(10.0, 10.0),
                            events.PointerButton.left)?
        clicks.push(now() - at)
        click = click + 1
    }
    let clicking: f64 = median(clicks)
    io.println("a pointer event, platform dispatch to Beans handler: {micros(clicking)}")
    io.println("  {share_of_frame(clicking)}")
    io.println("  and every one arrived: {tally.heard == 550}")
    io.println("")

    // ---- 4. reading a cell ----
    var table: widgets.Table = widgets.Table.of(["Row"])?
    root.add(table)?
    table.set_frame(geometry.Rect.of(0.0, 0.0, 300.0, 400.0))?
    table.set_source(new Rows())?
    var cells: List<f64> = []
    var cell: int = 0
    for cell < 500 {
        let at: f64 = now()
        table.native_cell(cell, 0)?
        cells.push(now() - at)
        cell = cell + 1
    }
    let reading: f64 = median(cells)
    io.println("a table cell, out to the platform and back: {micros(reading)}")
    // A screenful is what a table asks for while it draws, whatever the row
    // count — which is the claim tests/table.b proves and this one prices.
    let screenful: f64 = reading * 40.0
    io.println("  a screenful of 40: {micros(screenful)}, {share_of_frame(screenful)}")
    io.println("  out of 100,000 rows, none of which was built")
    io.println("")
    io.println("what these numbers are not:")
    io.println("  a comparison between platforms — the Simulator is about six")
    io.println("  times slower than this Mac at everything, so an iOS number")
    io.println("  read beside a macOS one says more about the Simulator than")
    io.println("  about the phone. What they are good for is finding the thing")
    io.println("  on *this* platform that costs a third of a frame, which is")
    io.println("  how the measure cache in src/mac/view.m came to exist.")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
