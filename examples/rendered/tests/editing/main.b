package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import cortado.events
import cortado.render
import cortado.host
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
    // Selection. Every way a person makes one: the keyboard against a held
    // anchor, the pointer dragged, and a shift-click from where the caret is.
    let entry: render.SearchFieldRender = (search.render_object()? as? render.SearchFieldRender).expect("search renderer")
    search.focus()?
    require(entry.selection_anchor() == 6 && entry.selection_caret() == 6, "typing left a selection behind")
    scene.key(events.EventKind.key_down, events.Key.left, "", host.MOD_SHIFT)?
    scene.key(events.EventKind.key_down, events.Key.left, "", host.MOD_SHIFT)?
    require(entry.selection_anchor() == 6 && entry.selection_caret() == 4,
            "shift+left selected {entry.selection_anchor()}..{entry.selection_caret()}, not 6..4")
    scene.key(events.EventKind.key_down, events.Key.left)?
    require(entry.selection_anchor() == entry.selection_caret(), "a plain arrow kept the selection")
    scene.key(events.EventKind.key_down, events.Key.home, "", host.MOD_SHIFT)?
    require(entry.selection_anchor() == 4 && entry.selection_caret() == 0, "shift+home did not extend to the start")

    let box: geometry.Rect = scene.global_frame(search.render_object()?)?
    let middle: f64 = box.y + box.height / 2.0
    let left: geometry.Point = geometry.Point.at(box.x + 2.0, middle)
    let right: geometry.Point = geometry.Point.at(box.x + box.width - 2.0, middle)
    scene.pointer(events.EventKind.pointer_down, left)?
    require(entry.selection_anchor() == 0 && entry.selection_caret() == 0, "a press did not put the caret where it landed")
    scene.pointer(events.EventKind.pointer_move, right)?
    require(entry.selection_anchor() == 0 && entry.selection_caret() == 6,
            "dragging selected {entry.selection_anchor()}..{entry.selection_caret()}, not 0..6")
    scene.pointer(events.EventKind.pointer_up, right)?
    scene.pointer(events.EventKind.pointer_move, left)?
    require(entry.selection_anchor() == 0 && entry.selection_caret() == 6, "hovering after the drag moved the selection")
    scene.pointer(events.EventKind.pointer_down, right)?
    scene.pointer(events.EventKind.pointer_up, right)?
    scene.pointer(events.EventKind.pointer_down, left, host.BTN_LEFT, 1, host.MOD_SHIFT)?
    require(entry.selection_anchor() == 6 && entry.selection_caret() == 0, "shift+click did not extend from the caret")
    scene.pointer(events.EventKind.pointer_up, left)?

    // A line command in a text area is about the line, not the whole document.
    let sheet: render.TextAreaRender = (notes.render_object()? as? render.TextAreaRender).expect("notes renderer")
    notes.focus()?
    scene.key(events.EventKind.key_down, events.Key.up)?
    require(sheet.selection_caret() == 6, "up from the last line landed on {sheet.selection_caret()}, not 6")
    scene.key(events.EventKind.key_down, events.Key.end)?
    require(sheet.selection_caret() == 12, "end ran past the line to {sheet.selection_caret()}")
    scene.key(events.EventKind.key_down, events.Key.home, "", host.MOD_SHIFT)?
    require(sheet.selection_anchor() == 12 && sheet.selection_caret() == 6,
            "shift+home in a text area selected {sheet.selection_anchor()}..{sheet.selection_caret()}, not 12..6")

    // Word selection: option+arrow on macOS, control+arrow elsewhere, and the
    // double-click that selects the word the pointer landed on.
    notes.focus()?
    scene.key(events.EventKind.key_down, events.Key.down)?
    scene.key(events.EventKind.key_down, events.Key.end)?
    scene.text_input(events.EventKind.text_input, " the quick fox", -1, -1)?
    let words: render.TextAreaRender = (notes.render_object()? as? render.TextAreaRender).expect("notes renderer")
    require(words.editing_text() == "first\nsecond\n the quick fox", "the word fixture did not type")
    let tail: int = words.editing_text().len()
    scene.key(events.EventKind.key_down, events.Key.left, "", host.MOD_ALT)?
    require(words.selection_caret() == tail - 3, "option+left stopped at {words.selection_caret()}, not the start of the word")
    scene.key(events.EventKind.key_down, events.Key.left, "", host.MOD_ALT | host.MOD_SHIFT)?
    require(words.selection_anchor() == tail - 3 && words.selection_caret() == tail - 9,
            "option+shift+left selected {words.selection_anchor()}..{words.selection_caret()}")
    scene.key(events.EventKind.key_down, events.Key.right, "", host.MOD_CONTROL)?
    require(words.selection_caret() == tail - 4 && words.selection_anchor() == tail - 4,
            "control+right did not step one word forward to {tail - 4}")

    let area: geometry.Rect = scene.global_frame(notes.render_object()?)?
    let word: geometry.Point = geometry.Point.at(area.x + 8.0, area.y + 8.0)
    scene.pointer(events.EventKind.pointer_down, word, host.BTN_LEFT, 2)?
    scene.pointer(events.EventKind.pointer_up, word, host.BTN_LEFT, 2)?
    require(words.selection_anchor() == 0 && words.selection_caret() == 5,
            "double-click selected {words.selection_anchor()}..{words.selection_caret()}, not the word first")
    scene.pointer(events.EventKind.pointer_down, word, host.BTN_LEFT, 3)?
    scene.pointer(events.EventKind.pointer_up, word, host.BTN_LEFT, 3)?
    require(words.selection_anchor() == 0 && words.selection_caret() == words.editing_text().len(),
            "triple-click did not take the whole value")


    // A delete takes the unit its modifier names, and the word delete is the
    // word step it is built on.
    scene.pointer(events.EventKind.pointer_down, word, host.BTN_LEFT, 3)?
    scene.pointer(events.EventKind.pointer_up, word, host.BTN_LEFT, 3)?
    scene.text_input(events.EventKind.text_input, "alpha beta gamma", -1, -1)?
    require(words.editing_text() == "alpha beta gamma", "the delete fixture did not replace the value")
    scene.key(events.EventKind.key_down, events.Key.backspace, "", host.MOD_ALT)?
    require(words.editing_text() == "alpha beta ", "option+backspace left \"{words.editing_text()}\"")
    scene.key(events.EventKind.key_down, events.Key.backspace, "", host.MOD_CONTROL)?
    require(words.editing_text() == "alpha ", "control+backspace left \"{words.editing_text()}\"")
    scene.key(events.EventKind.key_down, events.Key.home)?
    scene.key(events.EventKind.key_down, events.Key.delete, "", host.MOD_ALT)?
    require(words.editing_text() == " ", "option+delete left \"{words.editing_text()}\"")
    scene.text_input(events.EventKind.text_input, "one two", -1, -1)?
    require(words.editing_text() == "one two ", "the line-delete fixture did not type")
    scene.key(events.EventKind.key_down, events.Key.backspace, "", host.MOD_COMMAND)?
    require(words.editing_text() == " ", "command+backspace left \"{words.editing_text()}\"")

    scene.close()
    io.println("ok shared IME, secure, search, multiline, word selection, word deletes, and semantics")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
