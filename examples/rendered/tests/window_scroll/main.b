package main

import cortado_skia
import cortado.component
import cortado.geometry
import cortado.surface
import cortado.platform
import cortado.widgets
import cortado.render
import cortado.events
import cortado.host
import {TablePage} from rendered_demo.generated.site
import std.io

class Counts { pub frames: int = 0; pub fn init() {} }
class NestedScrollPage extends component.Component {
    pub fn init() { super.init() }
    pub override fn render(b: component.Builder) {
        b.open("VStack")
        b.word("align", "stretch")
            b.open("ScrollView")
            b.number("height", 160.0)
                b.open("VStack")
                b.word("align", "stretch")
                    b.open("ScrollView")
                    b.number("height", 80.0)
                        b.open("VStack")
                        b.word("align", "stretch")
                            b.open("Label")
                            b.text("inner first")
                            b.number("height", 100.0)
                            b.close()
                            b.open("Label")
                            b.text("inner second")
                            b.number("height", 100.0)
                            b.close()
                        b.close()
                    b.close()
                    b.open("Label")
                    b.text("outer filler")
                    b.number("height", 400.0)
                    b.close()
                b.close()
            b.close()
        b.close()
    }
}
fn require(value: bool, message: string) { if !value { panic(message) } }
fn find(root: widgets.Widget, kind: widgets.WidgetKind) -> Option<widgets.Widget> {
    if root.kind() == kind { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, kind) { some(found) => { return some(found) } none => {} }
    }
    return none
}
fn send(router: events.EventRouter, canvas: host.Handle, kind: events.EventKind,
        point: geometry.Point, dy: f64, clicks: int = 0) {
    let event: events.UiEvent = events.UiEvent.of(kind, canvas)
    event.position = point
    event.size = geometry.Size.of(0.0, dy)
    event.index = 1
    event.token = clicks
    router.deliver(event)
}
/// The row a click that far down the table lands on, at a given scroll. Taken
/// from the table's own metrics: they are theme tokens and they have moved.
fn row_under(visual: render.TableRender, local_y: f64, offset: f64) -> int {
    return ((local_y + offset - visual.header_height()) / visual.row_height()) as int
}
fn stopped(window_handle: host.Handle) -> bool {
    unsafe { return host.ctd_clock_step(window_handle.raw, 0.016) as int != host.OK }
}
fn verify() -> Result<bool> {
    let app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    let page: TablePage = new TablePage()
    let window: cortado_skia.Window = cortado_skia.Window.open(app, geometry.Size.of(560.0, 610.0),
                                                               "wheel burst", page)?
    let table: widgets.Table = (find(window.scene().root(), widgets.WidgetKind.table).expect("table") as? widgets.Table).expect("table type")
    let visual: render.TableRender = (table.render_object()? as? render.TableRender).expect("render type")
    let bounds: geometry.Rect = window.scene().global_frame(table.render_object()?)?
    let point: geometry.Point = geometry.Point.at(bounds.x + 240.0, bounds.y + 60.0)
    let canvas: host.Handle = window.native_window().native_root().expect("canvas root")
    let counts: Counts = new Counts()
    app.router.on(window.native_window().handle(), events.EventKind.frame,
                  fn(_event: events.UiEvent) { counts.frames += 1 })
    send(app.router, canvas, events.EventKind.pointer_scroll, point, -5.0)
    send(app.router, canvas, events.EventKind.pointer_scroll, point, 5.0)
    unsafe { host.check(host.ctd_clock_step(window.native_window().handle().raw, 0.016) as int,
                        "flush reversed wheel")? }
    require(visual.scroll_offset() == 5.0 && counts.frames == 1,
            "opposite wheel deltas cancelled across the top boundary")
    require(stopped(window.native_window().handle()), "reversed wheel left frame clock active")
    visual.scroll_to(geometry.Point.zero())?
    window.refresh()?
    let calls_before_cap: int = page.rows.calls
    for _index: int in 0..300 {
        send(app.router, canvas, events.EventKind.pointer_scroll, point, 1.0)
    }
    require(visual.scroll_offset() == 256.0 && page.rows.calls == calls_before_cap && counts.frames == 1,
            "bounded wheel drain painted rows or ran a frame before the clock")
    unsafe { host.check(host.ctd_clock_step(window.native_window().handle().raw, 0.016) as int,
                        "flush bounded wheel")? }
    require(visual.scroll_offset() == 300.0 && counts.frames == 2,
            "bounded wheel drain lost reports or used extra frames")
    require(stopped(window.native_window().handle()), "bounded wheel left frame clock active")
    visual.scroll_to(geometry.Point.zero())?
    window.refresh()?
    let calls_before: int = page.rows.calls
    for _index: int in 0..100 {
        send(app.router, canvas, events.EventKind.pointer_scroll, point, 3.0)
    }
    require(visual.scroll_offset() == 0.0 && page.rows.calls == calls_before && counts.frames == 2,
            "wheel burst drew or read virtual rows before a frame")
    unsafe { host.check(host.ctd_clock_step(window.native_window().handle().raw, 0.016) as int,
                        "flush wheel burst")? }
    require(visual.scroll_offset() == 300.0 && counts.frames == 3,
            "wheel burst lost displacement or produced extra frames")
    require(stopped(window.native_window().handle()), "wheel frame clock stayed active while idle")
    send(app.router, canvas, events.EventKind.pointer_scroll, point, 5.0)
    send(app.router, canvas, events.EventKind.pointer_scroll,
         geometry.Point.at(point.x + 1.0, point.y), 7.0)
    require(visual.scroll_offset() == 300.0, "changed-target wheel painted before its frame")
    unsafe { host.check(host.ctd_clock_step(window.native_window().handle().raw, 0.016) as int,
                        "flush changed-target wheel")? }
    require(visual.scroll_offset() == 312.0 && counts.frames == 4,
            "changed-target wheel did not flush final displacement")
    require(stopped(window.native_window().handle()), "changed-target wheel left frame clock active")
    let settled_row: int = row_under(visual, 60.0, 340.0)
    let stale_row: int = row_under(visual, 60.0, 312.0)
    require(settled_row != stale_row,
            "the queued wheel no longer crosses a row boundary, so this case proves nothing")
    send(app.router, canvas, events.EventKind.pointer_scroll, point, 28.0)
    send(app.router, canvas, events.EventKind.pointer_down, point, 0.0, 2)
    send(app.router, canvas, events.EventKind.pointer_up, point, 0.0, 2)
    require(visual.scroll_offset() == 340.0 && table.selected()? == settled_row,
            "double-click hit row {table.selected()?}, not the {settled_row} under it once the wheel settled")
    var editing: bool = false
    for node: render.SemanticsNode in window.scene().semantics() {
        if node.role() == "textbox" && node.value() == "Cup {settled_row % 3}" { editing = true }
    }
    require(editing, "queued wheel followed by double-click did not edit intended row")
    require(stopped(window.native_window().handle()), "click flush left wheel frame clock active")
    require(window.last_error() == "", "window reported a native or render error: {window.last_error()}")
    send(app.router, canvas, events.EventKind.pointer_scroll, point, 9.0)
    require(visual.scroll_offset() == 340.0, "close-case wheel applied before its frame")
    window.close()
    require(app.router.watching() == 0, "close left native frame or input watches")
    require(stopped(window.native_window().handle()), "close kept a pending wheel frame clock")
    app.router.off(window.native_window().handle(), events.EventKind.frame)
    let nested: cortado_skia.Window = cortado_skia.Window.open(app, geometry.Size.of(320.0, 250.0),
                                                               "nested scroll", new NestedScrollPage())?
    let outer: widgets.ScrollView = (find(nested.scene().root(), widgets.WidgetKind.scroll_view).expect("outer") as? widgets.ScrollView).expect("outer type")
    let inner: widgets.ScrollView = (find(outer.children()[0], widgets.WidgetKind.scroll_view).expect("inner") as? widgets.ScrollView).expect("inner type")
    let outer_render: render.ScrollRender = (outer.render_object()? as? render.ScrollRender).expect("outer render")
    let inner_render: render.ScrollRender = (inner.render_object()? as? render.ScrollRender).expect("inner render")
    let inner_max: f64 = inner_render.content_size().height - inner_render.frame().height
    require(inner_max > 10.0, "nested test inner scroll has no overflow")
    inner_render.scroll_to(geometry.Point.at(0.0, inner_max - 5.0))?
    nested.refresh()?
    let inner_frame: geometry.Rect = nested.scene().global_frame(inner.render_object()?)?
    let inside: geometry.Point = geometry.Point.at(inner_frame.x + 20.0, inner_frame.y + 30.0)
    let nested_canvas: host.Handle = nested.native_window().native_root().expect("nested canvas")
    send(app.router, nested_canvas, events.EventKind.pointer_scroll, inside, 10.0)
    send(app.router, nested_canvas, events.EventKind.pointer_scroll, inside, 10.0)
    require(-inner_render.child_offset().y == inner_max - 5.0 && outer_render.child_offset().y == 0.0,
            "nested wheel burst applied before its frame")
    unsafe { host.check(host.ctd_clock_step(nested.native_window().handle().raw, 0.016) as int,
                        "flush nested wheel")? }
    require(-inner_render.child_offset().y == inner_max && outer_render.child_offset().y == -10.0,
            "nested wheel failed to bubble after inner edge")
    require(stopped(nested.native_window().handle()), "nested wheel left frame clock active")
    require(nested.last_error() == "", "nested window reported a native or render error")
    nested.close()
    require(app.router.watching() == 0, "nested close left event watches")
    app.shutdown()
    io.println("ok window wheel burst, order, double-click, frame idle, teardown")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
