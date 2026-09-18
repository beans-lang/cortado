package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import cortado.events
import cortado.render
import {EditingPage} from rendered_demo.generated.site
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn find(root: widgets.Widget, kind: widgets.WidgetKind) -> Option<widgets.Widget> {
    if root.kind() == kind { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, kind) { some(found) => { return some(found) } none => {} }
    }
    return none
}

fn verify() -> Result<bool> {
    let page: EditingPage = new EditingPage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(560.0, 650.0))
    scene.show(page)?
    let name: widgets.TextField = (find(scene.root(), widgets.WidgetKind.text_field).expect("name") as? widgets.TextField).expect("name type")
    let password: widgets.SecureField = (find(scene.root(), widgets.WidgetKind.secure_field).expect("password") as? widgets.SecureField).expect("password type")
    let search: widgets.SearchField = (find(scene.root(), widgets.WidgetKind.search_field).expect("search") as? widgets.SearchField).expect("search type")
    let notes: widgets.TextArea = (find(scene.root(), widgets.WidgetKind.text_area).expect("notes") as? widgets.TextArea).expect("notes type")

    name.focus()?
    scene.text_input(events.EventKind.composition_update, "e", 1, 1)?
    require(page.name == "", "preedit committed a value binding")
    scene.text_input(events.EventKind.composition_update, "é", 2, 2)?
    scene.text_input(events.EventKind.text_input, "é", -1, -1)?
    require(name.value()? == "é", "IME commit did not reach shared field")
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(page.name == "é", "field commit did not update binding")
    scene.text_input(events.EventKind.composition_update, "x", 1, 1)?
    scene.text_input(events.EventKind.composition_cancel, "")?
    require(name.value()? == "é", "composition cancel changed committed text")

    password.focus()?
    scene.text_input(events.EventKind.text_input, "secret", -1, -1)?
    require(password.value()? == "secret", "secure field lost program value")
    require(password.display_text()? == "", "secure field dump revealed value")
    let secure_render: render.SecureFieldRender = (password.render_object()? as? render.SecureFieldRender).expect("secure renderer")
    require(secure_render.visible_text() != "secret", "secure renderer painted raw value")
    for node: render.SemanticsNode in scene.semantics() {
        if node.id() == password.handle().raw { require(node.value() == "", "secure semantics revealed value") }
    }

    search.focus()?
    scene.text_input(events.EventKind.text_input, "cof")?
    scene.text_input(events.EventKind.text_input, "fee")?
    require(search.value()? == "coffee", "search entry failed")

    notes.focus()?
    scene.text_input(events.EventKind.text_input, "first\nsecond", -1, -1)?
    require(notes.value()? == "first\nsecond", "multiline input discarded a newline")
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(notes.value()? == "first\nsecond\n", "multiline Return committed instead of inserting newline")
    scene.close()
    io.println("ok shared IME, secure, search, multiline, and semantics")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
