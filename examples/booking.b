// A day and a colour: the two controls whose value is neither text nor a
// number.
//
//     beansc build examples/booking.b -o build/booking && ./build/booking
//
// **The day is a day.** `NSDatePicker`, `UIDatePicker` and
// `SysDateTimePick32` can all show a time of day; `GtkCalendar` is a grid of
// squares and cannot. So cortado's date picker carries a *day* — midnight UTC
// of whatever was written — and every host floors on the way in. A screen that
// needs an hour as well wants two controls, and can say so; a screen that got
// one on three platforms and not the fourth would be a bug found by a user in
// Berlin.
//
// **The colour is four bytes.** It is written in cortado's own colour
// spelling — `#rrggbb`, the same one a shader takes — and comes back the same
// four bytes, because every host names sRGB rather than leaving the well in
// the machine's display profile. The Win32 common controls have no colour
// well at all, so this example asks before it builds one and prints why when
// the answer is no.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

/// What the form is holding. A class rather than locals, because the handlers
/// below capture it — a closure cannot capture a field, and a platform's
/// stored callback holds a strong reference the collector cannot see through.
class Booking {
    pub day: int = 20000       // days since 1970-01-01
    pub shade: string = "#3b82f6"
    pub fn init() {}

    /// The day as a date anybody can read, from the day number alone.
    ///
    /// The civil-calendar arithmetic rather than a library call, because the
    /// number cortado carries is UTC and every date formatter in reach is
    /// local: a booking made at 8pm in Sydney would print as the day before.
    pub fn written() -> string {
        var z: int = self.day + 719468
        var era: int = if z >= 0 { z / 146097 } else { (z - 146096) / 146097 }
        let doe: int = z - era * 146097
        let yoe: int = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy: int = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp: int = (5 * doy + 2) / 153
        let d: int = doy - (153 * mp + 2) / 5 + 1
        let m: int = if mp < 10 { mp + 3 } else { mp - 9 }
        let y: int = yoe + era * 400 + if m <= 2 { 1 } else { 0 }
        return "{y}-{Booking.two(m)}-{Booking.two(d)}"
    }

    static fn two(value: int) -> string {
        if value < 10 { return "0{value}" }
        return "{value}"
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(420.0, 260.0, "Booking")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let form: Booking = new Booking()

    var heading: widgets.Label = widgets.Label.of("Book a table")?
    heading.set_font_size(17.0)?
    var rule: widgets.Separator = new widgets.Separator()

    var day_label: widgets.Label = widgets.Label.of("Day")?
    var picker: widgets.DatePicker = widgets.DatePicker.of(form.day as f64 * 86400.0)?

    var shade_label: widgets.Label = widgets.Label.of("Table marker")?
    // Asked before it is built. On a platform with no colour well this is a
    // refusal naming the control, not a dead widget whose first write
    // complains about a handle.
    let have_well: bool = widgets.WidgetKind.color_well.available()
    var well: widgets.ColorWell = new widgets.ColorWell()
    var no_well: widgets.Label = widgets.Label.of("")?
    if have_well {
        well = widgets.ColorWell.of(widgets.Rgba.of_hex(form.shade)?)?
    } else {
        no_well.set_text("this platform has no colour well")?
    }

    var summary: widgets.Label = widgets.Label.of("")?
    var confirm: widgets.Button = widgets.Button.of("Confirm")?

    root.add(heading)?
    root.add(rule)?
    root.add(day_label)?
    root.add(picker)?
    root.add(shade_label)?
    if have_well { root.add(well)? } else { root.add(no_well)? }
    root.add(summary)?
    root.add(confirm)?

    // ------------------------------------------------------------ the layout

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)
    page.add(sheet.leaf("heading", heading))
    page.add(sheet.leaf("rule", rule))

    // A label and its control on one line. The row is a FlexLayout and not a
    // StackLayout because the control is told to grow into whatever is left
    // over, and a stack gives every child the size it measures — which a
    // StackLayout now refuses out loud rather than ignoring.
    var day_row: layout.FlexLayout = layout.FlexLayout.row(10.0)
    var days: layout.LayoutNode = sheet.spacer("day_row", day_row)
    var day_name: layout.LayoutNode = sheet.leaf("day_label", day_label)
    day_name.spec = layout.LayoutSpec.fixed(110.0, 16.0)
    days.add(day_name)
    var day_field: layout.LayoutNode = sheet.leaf("picker", picker)
    day_field.spec = layout.LayoutSpec.flexible(1.0)
    days.add(day_field)
    page.add(days)

    var shade_row: layout.FlexLayout = layout.FlexLayout.row(10.0)
    var shades: layout.LayoutNode = sheet.spacer("shade_row", shade_row)
    var shade_name: layout.LayoutNode = sheet.leaf("shade_label", shade_label)
    shade_name.spec = layout.LayoutSpec.fixed(110.0, 16.0)
    shades.add(shade_name)
    if have_well {
        var swatch: layout.LayoutNode = sheet.leaf("well", well)
        swatch.spec = layout.LayoutSpec.fixed(60.0, 24.0)
        shades.add(swatch)
    } else {
        var excuse: layout.LayoutNode = sheet.leaf("no_well", no_well)
        excuse.spec = layout.LayoutSpec.flexible(1.0)
        shades.add(excuse)
    }
    page.add(shades)

    page.add(sheet.leaf("summary", summary))

    var bar: layout.StackLayout = layout.StackLayout.row(10.0)
    bar.set_justify(layout.Justify.end)
    var buttons: layout.LayoutNode = sheet.spacer("buttons", bar)
    buttons.add(sheet.leaf("confirm", confirm))
    page.add(buttons)

    // ------------------------------------------------------------ the wiring

    // The event carries the value, so a handler never goes back to the control
    // to ask: by the time it runs the user may have moved it again.
    app.router.on(picker.handle(), events.EventKind.value_changed,
        fn(event: events.UiEvent) {
            form.day = event.index / 86400
            summary.set_text("{form.written()}, marked {form.shade}")
        })

    if have_well {
        app.router.on(well.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                let picked: widgets.Rgba = widgets.ColorWell.unpack(event.index)
                form.shade = picked.show()
                summary.set_text("{form.written()}, marked {form.shade}")
            })
    }

    app.router.on(confirm.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            io.println("booked {form.written()} marked {form.shade}")
            app.stop()
        })

    summary.set_text("{form.written()}, marked {form.shade}")?

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    io.println("the day is {form.written()}, and this platform has a colour well: {have_well}")

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
