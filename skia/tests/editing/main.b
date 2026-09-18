package main

import cortado_skia
import cortado.render
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn verify() -> Result<bool> {
    let editor: render.TextEditor = new render.TextEditor(new cortado_skia.SkiaRenderer())
    editor.set_text("a\u{301}👩‍💻z")?
    editor.erase(true)?
    require(editor.text() == "a\u{301}👩‍💻", "backspace removed more than one grapheme")
    editor.erase(true)?
    require(editor.text() == "a\u{301}", "backspace split emoji sequence")
    require(editor.undo() && editor.text() == "a\u{301}👩‍💻", "undo lost emoji")
    require(editor.anchor() == editor.caret() && editor.caret() == editor.text().len(), "undo lost original caret")
    require(editor.redo() && editor.text() == "a\u{301}", "redo failed")
    match editor.select(1, 1) { ok(_) => { panic("caret split combining sequence") } err(_) => {} }
    editor.select(0, editor.text().len())?
    editor.update_composition("に")?
    editor.update_composition("日本")?
    require(editor.composing() && editor.text() == "日本", "composition accumulated updates")
    editor.cancel_composition()
    require(editor.text() == "a\u{301}", "cancel lost original selection")
    editor.update_composition("にほん")?
    editor.commit_composition("日本")?
    require(!editor.composing() && editor.text() == "日本", "composition did not commit")
    require(editor.undo() && editor.text() == "a\u{301}", "composition was not one undo step")
    editor.set_text("مرحبا")?
    editor.move_cursor(false, true)?
    editor.replace("!")?
    require(editor.text() == "مرحب!", "UTF-8 replacement used character indexes as bytes")
    editor.set_text("ab")?
    editor.select(1, 1)?
    editor.replace("\u{301}")?
    require(editor.text() == "a\u{301}b" && editor.caret() == 3, "inserted combining mark left invalid caret")
    io.println("ok Unicode editing, grapheme selection, undo, composition")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
