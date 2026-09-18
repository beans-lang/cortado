package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import cortado.events
import cortado.render
import cortado.component
import {TablePage} from rendered_demo.generated.site
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }
fn find(root: widgets.Widget, kind: widgets.WidgetKind) -> Option<widgets.Widget> {
    if root.kind() == kind { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, kind) { some(found) => { return some(found) } none => {} }
    }
    return none
}
fn editor(scene: cortado_skia.Scene, text: string) -> Option<render.SemanticsNode> {
    for node: render.SemanticsNode in scene.semantics() {
        if node.role() == "textbox" && node.value() == text { return some(node) }
    }
    return none
}
fn label(scene: cortado_skia.Scene, text: string) -> bool {
    for node: render.SemanticsNode in scene.semantics() {
        if node.label() == text { return true }
    }
    return false
}
fn label_node(scene: cortado_skia.Scene, text: string) -> Option<render.SemanticsNode> {
    for node: render.SemanticsNode in scene.semantics() {
        if node.label() == text { return some(node) }
    }
    return none
}
fn verify() -> Result<bool> {
    let page: TablePage = new TablePage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(560.0, 610.0))
    scene.show(page)?
    let table: widgets.Table = (find(scene.root(), widgets.WidgetKind.table).expect("table page table") as? widgets.Table).expect("table type")
    let visual: render.TableRender = (table.render_object()? as? render.TableRender).expect("table render")
    require(page.rows.calls > 0 && page.rows.calls < 100, "table loaded more than visible cells")
    require(label(scene, "Order 0") && label(scene, "Cup 0") && editor(scene, "Cup 0") == none,
            "idle table created editors or omitted visible labels")
    let table_frame: geometry.Rect = scene.global_frame(table.render_object()?)?
    let wheel: geometry.Point = geometry.Point.at(table_frame.x + 30.0, table_frame.y + 80.0)
    let calls_before_wheel: int = page.rows.calls
    scene.scroll(wheel, 0.0, 4.0)?
    require(page.rows.calls == calls_before_wheel, "fractional wheel reread unchanged visible cells")
    scene.scroll(wheel, 0.0, -4.0)?
    require(page.rows.calls == calls_before_wheel, "reverse fractional wheel reread unchanged visible cells")
    table.select(0)?
    table.focus()?
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(editor(scene, "Cup 0") != none, "Return did not choose the first editable column by default")
    scene.key(events.EventKind.key_down, events.Key.escape)?
    let cup: render.SemanticsNode = label_node(scene, "Cup 0").expect("first Cup label")
    let frame: geometry.Rect = cup.bounds()
    let point: geometry.Point = geometry.Point.at(frame.x + frame.width / 2.0, frame.y + frame.height / 2.0)
    scene.pointer(events.EventKind.pointer_down, point)?
    scene.pointer(events.EventKind.pointer_up, point)?
    require(table.selected()? == 0 && editor(scene, "Cup 0") == none,
            "single click opened an editor instead of selecting a row")
    scene.pointer(events.EventKind.pointer_down, point, 1, 2)?
    scene.pointer(events.EventKind.pointer_up, point, 1, 2)?
    let active: render.SemanticsNode = editor(scene, "Cup 0").expect("double-click Cup editor")
    require(scene.context().focused_object().expect("focused editor").handle() == active.id(),
            "double-click did not focus the sole table editor")
    scene.key(events.EventKind.key_down, events.Key.end)?
    scene.text_input(events.EventKind.text_input, "水☕")?
    require(page.rows.cell(0, 1) == "Cup 0", "draft changed the source before commit")
    page.choose_row(0)
    scene.refresh()?
    let draft: render.TextFieldRender = (scene.context().focused_object().expect("draft editor") as? render.TextFieldRender).expect("draft type")
    require(draft.handle() == active.id() && draft.editing_text() == "Cup 0水☕",
            "unrelated rerender replaced an in-progress table editor")
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(page.rows.cell(0, 1) == "Cup 0水☕" && page.last_edit == "row 0, column 1: Cup 0水☕",
            "TextField Return did not commit through table owner")
    require(editor(scene, "Cup 0水☕") == none && label(scene, "Cup 0水☕"),
            "accepted edit did not return to a source-backed label")
    page.save_edits = false
    table.edit_as_user(1, 1, "Discard")?
    scene.refresh()?
    require(page.rows.cell(1, 1) == "Cup 1" && label(scene, "Cup 1"),
            "unsaved edit did not revert to source")
    require(!table.edit_as_user(1, 0, "Rejected")?, "read-only column accepted a user edit")
    require(page.rows.cell(1, 0) == "Order 1", "read-only edit changed source")
    table.select(1)?
    table.focus()?
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(editor(scene, "Cup 1") != none, "Return did not open the selected row's editable cell")
    scene.text_input(events.EventKind.text_input, "draft")?
    scene.key(events.EventKind.key_down, events.Key.escape)?
    require(editor(scene, "Cup 1") == none && label(scene, "Cup 1") && page.rows.cell(1, 1) == "Cup 1",
            "Escape did not cancel the draft")
    let header: geometry.Point = geometry.Point.at(table_frame.x + 230.0, table_frame.y + 12.0)
    scene.pointer(events.EventKind.pointer_down, header, 1, 2)?
    scene.pointer(events.EventKind.pointer_up, header, 1, 2)?
    require(editor(scene, "Cup 0水☕") == none, "double-click on header opened a cell editor")
    let read_only: geometry.Point = geometry.Point.at(table_frame.x + 80.0, table_frame.y + 44.0)
    scene.pointer(events.EventKind.pointer_down, read_only, 1, 2)?
    scene.pointer(events.EventKind.pointer_up, read_only, 1, 2)?
    require(editor(scene, "Order 0") == none, "double-click on read-only column opened an editor")
    table.set_widths([500.0, 500.0])?
    scene.refresh()?
    scene.scroll(wheel, 350.0, 0.0)?
    require(visual.scroll_x() == 350.0, "wide table did not scroll horizontally")
    let shifted_cup: geometry.Point = geometry.Point.at(table_frame.x + 230.0, table_frame.y + 44.0)
    scene.pointer(events.EventKind.pointer_down, shifted_cup, 1, 2)?
    scene.pointer(events.EventKind.pointer_up, shifted_cup, 1, 2)?
    require(editor(scene, "Cup 0水☕") != none, "double-click ignored horizontal table offset")
    scene.text_input(events.EventKind.text_input, "lost")?
    scene.scroll(wheel, 0.0, 280.0)?
    scene.scroll(wheel, 0.0, -280.0)?
    require(editor(scene, "Cup 0水☕") == none && page.rows.cell(0, 1) == "Cup 0水☕",
            "scroll-away kept or committed an abandoned editor")
    scene.pointer(events.EventKind.pointer_down, shifted_cup, 1, 2)?
    scene.pointer(events.EventKind.pointer_up, shifted_cup, 1, 2)?
    require(editor(scene, "Cup 0水☕") != none, "second double-click did not reopen the editor")
    scene.text_input(events.EventKind.text_input, "unsaved")?
    let next_row: geometry.Point = geometry.Point.at(table_frame.x + 230.0, table_frame.y + 72.0)
    scene.pointer(events.EventKind.pointer_down, next_row)?
    scene.pointer(events.EventKind.pointer_up, next_row)?
    require(table.selected()? == 1 && editor(scene, "Cup 0水☕") == none &&
            page.rows.cell(0, 1) == "Cup 0水☕", "row selection retained an abandoned editor")
    table.set_widths([210.0, 190.0])?
    scene.refresh()?
    page.edit_policy = new component.TableEditRule(fn(row: int, column: int) -> bool { return true })
    page.request_render()
    scene.refresh()?
    table.select(0)?
    table.focus()?
    scene.key(events.EventKind.key_down, events.Key.left)?
    require(visual.selected_column() == 0, "Left did not choose the first table column")
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(editor(scene, "Order 0") != none, "Return could not edit the first of two editable columns")
    scene.key(events.EventKind.key_down, events.Key.escape)?
    scene.key(events.EventKind.key_down, events.Key.right)?
    require(visual.selected_column() == 1, "Right did not choose the second table column")
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(editor(scene, "Cup 0水☕") != none, "Return could not edit the second editable column")
    scene.key(events.EventKind.key_down, events.Key.escape)?
    table.select(9999)?
    scene.refresh()?
    require(visual.scroll_offset() > 279000.0 && label(scene, "Order 9999") && editor(scene, "Cup 0") == none,
            "last row did not present labels after virtual scrolling")
    require(visual.has_source() && visual.has_edit_policy(), "table lost source or rule before teardown")
    let actions: render.ControlActions = scene.context().actions(table.handle().raw)
    scene.close()
    require(!visual.has_source() && !visual.has_edit_policy(), "released table retained source or edit callback")
    match actions.commit_cell(0, 1, "Stale") { ok(_) => { panic("retained action accepted a stale cell") } err(_) => {} }
    match table.edit_as_user(0, 1, "Stale") { ok(_) => { panic("released table accepted an edit") } err(_) => {} }
    io.println("ok virtual table editors, commits, source refresh, policy, teardown")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
