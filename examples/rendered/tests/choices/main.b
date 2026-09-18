package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import cortado.events
import cortado.render
import {CollectionsPage, PopupClipProbe} from rendered_demo.generated.site
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }
fn find(root: widgets.Widget, kind: widgets.WidgetKind) -> Option<widgets.Widget> {
    if root.kind() == kind { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, kind) { some(found) => { return some(found) } none => {} }
    }
    return none
}
fn click(scene: cortado_skia.Scene, widget: widgets.Widget, fraction: f64) -> Result<bool> {
    let frame: geometry.Rect = scene.global_frame(widget.render_object()?)?
    let point: geometry.Point = geometry.Point.at(frame.x + frame.width * fraction, frame.y + frame.height / 2.0)
    scene.pointer(events.EventKind.pointer_down, point)?
    return scene.pointer(events.EventKind.pointer_up, point)
}
fn has_semantics(scene: cortado_skia.Scene, handle: u64) -> bool {
    for node: render.SemanticsNode in scene.semantics() { if node.id() == handle { return true } }
    return false
}
fn option_named(scene: cortado_skia.Scene, label: string) -> Option<render.SemanticsNode> {
    for node: render.SemanticsNode in scene.semantics() {
        if node.label() == label && (node.role() == "button" || node.role() == "option") { return some(node) }
    }
    return none
}
fn has_label(scene: cortado_skia.Scene, label: string) -> bool {
    for node: render.SemanticsNode in scene.semantics() { if node.label() == label { return true } }
    return false
}
fn node_named(scene: cortado_skia.Scene, label: string) -> Option<render.SemanticsNode> {
    for node: render.SemanticsNode in scene.semantics() { if node.label() == label { return some(node) } }
    return none
}
fn scroller_in(node: render.RenderObject) -> Option<render.ScrollRender> {
    match node as? render.ScrollRender { some(found) => { return some(found) } none => {} }
    for index: int in 0..node.child_count() {
        match node.child_at(index) {
            some(child) => {
                match scroller_in(child) { some(found) => { return some(found) } none => {} }
            }
            none => {}
        }
    }
    return none
}

fn verify() -> Result<bool> {
    let page: CollectionsPage = new CollectionsPage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(600.0, 850.0))
    scene.show(page)?
    let combo: widgets.ComboBox = (find(scene.root(), widgets.WidgetKind.combo_box).expect("combo from .bx") as? widgets.ComboBox).expect("combo type")
    let segmented: widgets.Segmented = (find(scene.root(), widgets.WidgetKind.segmented).expect("segmented from .bx") as? widgets.Segmented).expect("segmented type")
    let tabs: widgets.TabView = (find(scene.root(), widgets.WidgetKind.tab_view).expect("tabs from .bx") as? widgets.TabView).expect("tabs type")
    let split: widgets.SplitView = (find(scene.root(), widgets.WidgetKind.split_view).expect("split from .bx") as? widgets.SplitView).expect("split type")
    let table: widgets.Table = (find(scene.root(), widgets.WidgetKind.table).expect("table from .bx") as? widgets.Table).expect("table type")
    let combo_id: u64 = combo.handle().raw
    let segment_id: u64 = segmented.handle().raw
    require(combo.count()? == 3 && combo.item_at(1)? == "Coffee" && combo.selected()? == 1, "typed items did not initialize before selected")
    require(segmented.count()? == 3 && segmented.selected()? == 0, "segmented choices were not mounted")
    require(table.column_count() == 2 && page.table_rows.calls > 0 && page.table_rows.calls < 100,
            "virtual table queried more than visible cells")
    require(has_label(scene, "Order 0") && has_label(scene, "Cup 0"), "table cell template is absent from accessibility tree")
    click(scene, combo, 0.5)?
    require(scene.context().popups().owner() == combo_id && combo.selected()? == 1, "combo click did not open its list")
    let water: render.SemanticsNode = option_named(scene, "Water").expect("Water popup option")
    require(water.role() == "option" && water.value() == "", "popup row has no option semantics")
    let water_bounds: geometry.Rect = water.bounds()
    let water_point: geometry.Point = geometry.Point.at(water_bounds.x + water_bounds.width / 2.0, water_bounds.y + water_bounds.height / 2.0)
    scene.pointer(events.EventKind.pointer_down, water_point)?
    scene.pointer(events.EventKind.pointer_up, water_point)?
    require(combo.selected()? == 2 && page.drink_index == 2 && combo.display_text()? == "Water" &&
            page.last_drink_text == "Water" && page.last_drink_value == 2.0,
            "combo popup choice did not update Beans with its text and value")
    require(scene.context().popups().owner() == 0, "combo popup stayed open after selection")
    click(scene, combo, 0.5)?
    let coffee: render.SemanticsNode = option_named(scene, "Coffee").expect("Coffee popup option")
    require(coffee.role() == "option" && coffee.value() == "", "accessible option metadata was lost")
    scene.semantics_action(coffee.id(), 1)?
    require(combo.selected()? == 1 && page.drink_index == 1 && scene.context().popups().owner() == 0,
            "accessibility activation did not choose and close popup")
    click(scene, combo, 0.5)?
    scene.pointer(events.EventKind.pointer_down, geometry.Point.at(590.0, 840.0))?
    require(scene.context().popups().owner() == 0 && combo.selected()? == 1, "outside click did not dismiss combo popup")
    click(scene, combo, 0.5)?
    scene.key(events.EventKind.key_down, events.Key.escape)?
    require(scene.context().popups().owner() == 0 && combo.selected()? == 1, "Escape did not dismiss combo popup")
    scene.key(events.EventKind.key_down, events.Key.down)?
    require(scene.context().popups().owner() == combo_id, "Down did not open the combo popup")
    scene.key(events.EventKind.key_down, events.Key.down)?
    let combo_render: render.ComboBoxRender = (combo.render_object()? as? render.ComboBoxRender).expect("combo render")
    require(combo_render.highlighted() == 2 && combo.selected()? == 1, "arrow key committed a combo option before Return")
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(combo.selected()? == 2 && page.drink_index == 2 && scene.context().popups().owner() == 0,
            "Return did not commit highlighted combo option")
    scene.key(events.EventKind.key_down, events.Key.down)?
    scene.key(events.EventKind.key_down, events.Key.home)?
    require(combo_render.highlighted() == 0 && combo.selected()? == 2, "Home did not move popup highlight")
    scene.key(events.EventKind.key_down, events.Key.end)?
    require(combo_render.highlighted() == 2, "End did not move popup highlight")
    scene.key(events.EventKind.key_down, events.Key.escape)?
    require(combo.selected()? == 2 && scene.context().popups().owner() == 0, "Escape committed highlighted combo option")
    click(scene, segmented, 0.85)?
    require(segmented.selected()? == 2 && page.size_index == 2 && segmented.display_text()? == "Large", "segment click did not select third choice")
    page.replace_drinks()
    scene.refresh()?
    require(combo.handle().raw == combo_id && segmented.handle().raw == segment_id, "list update replaced choice controls")
    require(combo.count()? == 2 && combo.item_at(0)? == "Water" && combo.selected()? == 1 && combo.display_text()? == "Tea", "list update did not reapply selected after items")
    combo.set_items(["A|B", "", "水"])?
    require(combo.item_at(0)? == "A|B" && combo.item_at(1)? == "" && combo.item_at(2)? == "水", "typed items lost separators, empty text, or Unicode")
    combo.select(2)?
    require(combo.display_text()? == "水", "selected Unicode choice was lost")
    combo.select(0)?
    combo.set_value_as_user(2, 2.0)?
    require(page.last_drink_text == "水" && page.last_drink_value == 2.0,
            "programmatic user choice event lost item text or value")
    require(tabs.label(0)? == "Summary" && tabs.label(1)? == "History" && tabs.page()? == 0, "typed tab labels or initial selection missing")
    let summary: widgets.Widget = tabs.child_at(0).expect("summary page")
    let history: widgets.Widget = tabs.child_at(1).expect("history page")
    require(has_semantics(scene, summary.handle().raw) && !has_semantics(scene, history.handle().raw), "inactive tab page exposed semantics")
    let tab_frame: geometry.Rect = scene.global_frame(tabs.render_object()?)?
    let tab_point: geometry.Point = geometry.Point.at(tab_frame.x + tab_frame.width * 0.75, tab_frame.y + 14.0)
    scene.pointer(events.EventKind.pointer_down, tab_point)?
    scene.pointer(events.EventKind.pointer_up, tab_point)?
    require(tabs.page()? == 1 && page.tab_index == 1, "tab header did not change page")
    match tabs.set_page(2) { ok(_) => { panic("tab view accepted an absent page") } err(_) => {} }
    require(tabs.page()? == 1, "rejected tab page changed selection")
    let left_tab: geometry.Point = geometry.Point.at(tab_frame.x + tab_frame.width * 0.25, tab_frame.y + 14.0)
    scene.pointer(events.EventKind.pointer_down, left_tab)?
    tabs.render_object()?.focus_changed(false)
    scene.pointer(events.EventKind.pointer_up, left_tab)?
    require(tabs.page()? == 1, "blurred tab retained a pointer press")
    let segment_frame: geometry.Rect = scene.global_frame(segmented.render_object()?)?
    let first_segment: geometry.Point = geometry.Point.at(segment_frame.x + segment_frame.width * 0.15, segment_frame.y + segment_frame.height / 2.0)
    scene.pointer(events.EventKind.pointer_down, first_segment)?
    segmented.render_object()?.focus_changed(false)
    scene.pointer(events.EventKind.pointer_up, first_segment)?
    require(segmented.selected()? == 2, "blurred segment retained a pointer press")
    require(!has_semantics(scene, summary.handle().raw) && has_semantics(scene, history.handle().raw), "tab change did not switch visible subtree")
    let first: widgets.Widget = split.child_at(0).expect("first pane")
    let second: widgets.Widget = split.child_at(1).expect("second pane")
    require(first.frame()?.width == 190.0 && second.frame()?.x == 196.0, "split layout did not give pane frames")
    let split_frame: geometry.Rect = scene.global_frame(split.render_object()?)?
    let start: geometry.Point = geometry.Point.at(split_frame.x + 192.0, split_frame.y + 50.0)
    let finish: geometry.Point = geometry.Point.at(split_frame.x + 230.0, split_frame.y + 50.0)
    scene.pointer(events.EventKind.pointer_down, start)?
    scene.pointer(events.EventKind.pointer_move, finish)?
    scene.pointer(events.EventKind.pointer_up, finish)?
    require(split.divider()? == 230.0 && page.divider == 230.0 && first.frame()?.width == 230.0, "split drag did not update layout and binding")
    let table_frame: geometry.Rect = scene.global_frame(table.render_object()?)?
    // The middle of row 2, asked of the theme rather than pinned to the
    // metrics it happened to have when this case was written.
    let metrics: render.Theme = scene.context().theme()
    let table_row: geometry.Point = geometry.Point.at(table_frame.x + 60.0,
        table_frame.y + metrics.header_height() + metrics.row_height() * 2.5)
    scene.pointer(events.EventKind.pointer_down, table_row)?
    scene.pointer(events.EventKind.pointer_up, table_row)?
    require(table.selected()? == 2 && page.selected_row == 2, "table pointer did not select row")
    let calls_before_scroll: int = page.table_rows.calls
    // Ten rows down, whatever a row is worth, so the two labels below keep
    // meaning "the one that left" and "the one that arrived".
    let ten_rows: f64 = metrics.row_height() * 10.0
    scene.scroll(geometry.Point.at(table_frame.x + 60.0, table_frame.y + 70.0), 0.0, ten_rows)?
    let table_render: render.TableRender = (table.render_object()? as? render.TableRender).expect("table render")
    require(table_render.scroll_offset() >= ten_rows && page.table_rows.calls > calls_before_scroll &&
            page.table_rows.calls - calls_before_scroll < 100, "table scroll did not query only its new visible rows")
    require(!has_label(scene, "Order 0") && has_label(scene, "Order 10"), "table presenter kept offscreen rows")
    // Part of a row further on: row 10 is now cut in half, not gone.
    let nudge: f64 = metrics.row_height() * 0.7
    scene.scroll(geometry.Point.at(table_frame.x + 60.0, table_frame.y + 70.0), 0.0, nudge)?
    require(table_render.scroll_offset() == ten_rows + nudge && has_label(scene, "Order 10"),
            "fractional table scroll lost the partly visible row")
    // The middle of the sliver of row 10 still under the header.
    let sliver: f64 = (metrics.row_height() - nudge) / 2.0
    let partly_visible: geometry.Point = geometry.Point.at(table_frame.x + 60.0,
        table_frame.y + metrics.header_height() + sliver)
    scene.pointer(events.EventKind.pointer_down, partly_visible)?
    scene.pointer(events.EventKind.pointer_up, partly_visible)?
    require(table.selected()? == 10 && page.selected_row == 10, "partly visible table row did not select")
    table.select(5)?
    table.focus()?
    for index: int in 0..10 { scene.key(events.EventKind.key_down, events.Key.down)? }
    require(table.selected()? == 15 && page.selected_row == 15 && has_label(scene, "Order 15"),
            "keyboard table selection did not scroll the chosen row into view")
    table.select(9999)?
    scene.refresh()?
    // Within one row of the bottom, whatever a row costs.
    let content: f64 = page.table_rows.total as f64 * metrics.row_height()
    let body: f64 = table_frame.height - metrics.header_height()
    require(table_render.scroll_offset() >= content - body - metrics.row_height() &&
            has_label(scene, "Order 9999"),
            "programmatic table selection did not reveal the final row")
    match table.set_widths([9000000.0, 9000000.0]) {
        ok(_) => { panic("table accepted content width beyond renderer limit") }
        err(_) => {}
    }
    require(table_render.width(0)? == 210.0, "rejected table widths changed state")
    // A row count whose content height clears the renderer's 10,000,000 limit,
    // computed from the row height rather than pinned to one that used to.
    page.table_rows.total = (10000000.0 / metrics.row_height()) as int + 1000
    match table.reload() { ok(_) => { panic("table accepted content height beyond renderer limit") } err(_) => {} }
    require(table_render.row_count() == 10000, "rejected table reload changed row count")
    page.table_rows.total = 10000
    table.set_widths([500.0, 500.0])?
    scene.refresh()?
    scene.scroll(geometry.Point.at(table_frame.x + 60.0, table_frame.y + 70.0), 60.0, 0.0)?
    require(table_render.scroll_x() == 60.0, "wide table did not scroll horizontally")
    let partial_cell: render.SemanticsNode = node_named(scene, "Order 9999").expect("partly visible first column")
    require(partial_cell.bounds().x < table_frame.x &&
            partial_cell.bounds().x + partial_cell.bounds().width > table_frame.x,
            "horizontal scroll dropped partly visible first column")
    match table.native_cell(2, 0) { ok(_) => { panic("shared table pretended to have a native cell") } err(_) => {} }
    // Long enough to reach past the surface it opens in. A menu is as tall as
    // its rows and no taller than the room it has, which is what AppKit does
    // against the screen — there is no cap of its own.
    var many: List<string> = []
    for index: int in 0..48 { many.push("Item {index}") }
    combo.set_items(many)?
    combo.select(0)?
    scene.refresh()?
    click(scene, combo, 0.5)?
    let popup: render.RenderObject = scene.context().popups().root().expect("long combo popup")
    let popup_frame: geometry.Rect = scene.global_frame(popup)?
    let rows_tall: f64 = 48.0 * metrics.menu_row_height() + metrics.menu_padding() * 2.0
    let room: f64 = scene.root().render_object()?.frame().height
    require(popup_frame.height == (if rows_tall > room { room } else { rows_tall }),
            "a long popup is its rows, or the room it has, and it was neither")
    require(popup_frame.y >= 0.0 && popup_frame.y + popup_frame.height <= room,
            "a long popup opened outside the surface")
    // Found rather than indexed: a menu draws its sheet before its rows, so
    // the scroll view is not the first thing under the popup's root.
    let scroll: render.ScrollRender = scroller_in(popup).expect("popup scroll view")
    require(scroll.content_size().height > popup_frame.height, "popup list did not create scrollable content")
    scene.scroll(geometry.Point.at(popup_frame.x + popup_frame.width / 2.0, popup_frame.y + popup_frame.height / 2.0), 0.0, 96.0)?
    require(scroll.child_offset().y < 0.0, "long popup did not scroll")
    let lower: render.SemanticsNode = option_named(scene, "Item 8").expect("scrolled combo option")
    let lower_bounds: geometry.Rect = lower.bounds()
    let lower_point: geometry.Point = geometry.Point.at(lower_bounds.x + lower_bounds.width / 2.0,
                                                       lower_bounds.y + lower_bounds.height / 2.0)
    require(popup_frame.contains(lower_point), "scrolled choice is outside popup viewport")
    scene.pointer(events.EventKind.pointer_down, lower_point)?
    scene.pointer(events.EventKind.pointer_up, lower_point)?
    require(combo.selected()? == 8 && combo.display_text()? == "Item 8", "scrolled popup row did not select")
    scene.refresh()?
    require(!scene.refresh()?, "choice screen kept repainting while idle")
    scene.renderer().write_png("build/rendered-choices.png")?
    scene.close()
    require(!combo.is_alive(), "choice control survived scene close")
    match tabs.set_labels(["After", "Close"]) { ok(_) => { panic("released tab view accepted labels") } err(_) => {} }
    match tabs.set_page(0) { ok(_) => { panic("released tab view accepted a page") } err(_) => {} }
    let probe: PopupClipProbe = new PopupClipProbe()
    let nested: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(320.0, 250.0))
    nested.show(probe)?
    let nested_combo: widgets.ComboBox = (find(nested.root(), widgets.WidgetKind.combo_box).expect("nested combo") as? widgets.ComboBox).expect("nested combo type")
    let clip: widgets.ScrollView = (find(nested.root(), widgets.WidgetKind.scroll_view).expect("scroll ancestor") as? widgets.ScrollView).expect("scroll ancestor type")
    let clip_frame: geometry.Rect = nested.global_frame(clip.render_object()?)?
    click(nested, nested_combo, 0.5)?
    let outside: render.SemanticsNode = option_named(nested, "Water").expect("popup beyond clip")
    let outside_frame: geometry.Rect = outside.bounds()
    // A pop-up button opens its menu *over* the control, so a row can fall
    // either side of the clip. What matters is that a row lands outside it and
    // is still hit: the popup is not clipped by the scroll view it opened from.
    require(outside_frame.y + outside_frame.height > clip_frame.y + clip_frame.height ||
            outside_frame.y < clip_frame.y,
            "popup row did not reach past the scroll ancestor")
    nested.renderer().write_png("build/rendered-popup.png")?
    let outside_point: geometry.Point = geometry.Point.at(outside_frame.x + outside_frame.width / 2.0,
                                                         outside_frame.y + outside_frame.height / 2.0)
    nested.pointer(events.EventKind.pointer_down, outside_point)?
    nested.pointer(events.EventKind.pointer_up, outside_point)?
    require(nested_combo.selected()? == 2 && probe.selected == 2, "popup was clipped by owner scroll view")
    nested.close()
    io.println("ok typed choices, selection, list identity, templates, teardown")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
