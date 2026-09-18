package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import cortado.events
import cortado.render
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
fn verify() -> Result<bool> {
    let page: TablePage = new TablePage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(560.0, 610.0))
    scene.show(page)?
    let table: widgets.Table = (find(scene.root(), widgets.WidgetKind.table).expect("table page table") as? widgets.Table).expect("table type")
    let visual: render.TableRender = (table.render_object()? as? render.TableRender).expect("table render")
    require(page.rows.calls > 0 && page.rows.calls < 100, "table loaded more than visible cells")
    require(label(scene, "Order 0") && editor(scene, "Cup 0") != none,
            "editable cell is not a real accessible text field")
    require(editor(scene, "Order 0") == none, "read-only Order column became an editor")
    let cup: render.SemanticsNode = editor(scene, "Cup 0").expect("first Cup editor")
    let frame: geometry.Rect = cup.bounds()
    let point: geometry.Point = geometry.Point.at(frame.x + frame.width / 2.0, frame.y + frame.height / 2.0)
    scene.pointer(events.EventKind.pointer_down, point)?
    scene.pointer(events.EventKind.pointer_up, point)?
    require(scene.context().focused_object().expect("focused editor").handle() == cup.id(),
            "pointer did not focus visible table editor")
    scene.key(events.EventKind.key_down, events.Key.end)?
    scene.text_input(events.EventKind.text_input, "水☕")?
    require(page.rows.cell(0, 1) == "Cup 0", "draft changed the source before commit")
    page.choose_row(0)
    scene.refresh()?
    let draft: render.TextFieldRender = (scene.context().focused_object().expect("draft editor") as? render.TextFieldRender).expect("draft type")
    require(draft.handle() == cup.id() && draft.editing_text() == "Cup 0水☕",
            "unrelated rerender replaced an in-progress table editor")
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(page.rows.cell(0, 1) == "Cup 0水☕" && page.last_edit == "row 0, column 1: Cup 0水☕",
            "TextField Return did not commit through table owner")
    require(editor(scene, "Cup 0水☕") != none, "accepted edit did not remount from source")
    page.save_edits = false
    table.edit_as_user(1, 1, "Discard")?
    scene.refresh()?
    require(page.rows.cell(1, 1) == "Cup 1" && editor(scene, "Cup 1") != none,
            "unsaved edit did not revert to source")
    require(!table.edit_as_user(1, 0, "Rejected")?, "read-only column accepted a user edit")
    require(page.rows.cell(1, 0) == "Order 1", "read-only edit changed source")
    table.select(9999)?
    scene.refresh()?
    require(visual.scroll_offset() > 279000.0 && editor(scene, "Cup 0") != none,
            "last row did not present an editor after virtual scrolling")
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
