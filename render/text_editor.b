package render

import cortado.paint

class EditingValue {
    text: string
    anchor: int
    caret: int
    pub fn init(text: string, anchor: int, caret: int) {
        self.text = text; self.anchor = anchor; self.caret = caret
    }
}

/// Editing policy is Beans code. The renderer supplies Unicode boundaries,
/// never selection, undo policy or control behavior. Positions are UTF-8 bytes.
pub class TextEditor {
    renderer: paint.Renderer
    value: EditingValue = new EditingValue("", 0, 0)
    undo_values: List<EditingValue> = []
    redo_values: List<EditingValue> = []
    composition: Option<EditingValue> = none
    pub fn init(renderer: paint.Renderer) { self.renderer = renderer }
    pub fn text() -> string { return self.value.text }
    pub fn caret() -> int { return self.value.caret }
    pub fn anchor() -> int { return self.value.anchor }
    pub fn composing() -> bool { return self.composition != none }
    pub fn set_text(text: string) -> Result<bool> {
        self.renderer.graphemes(text)?
        self.value = new EditingValue(text, text.len(), text.len())
        self.undo_values.clear(); self.redo_values.clear(); self.composition = none
        return ok(true)
    }
    fn boundary(offset: int) -> Result<bool> {
        let boundaries: List<int> = self.renderer.graphemes(self.value.text)?
        for at: int in boundaries { if at == offset { return ok(true) } }
        return err("selection splits a grapheme or is out of range", "out_of_range")
    }
    pub fn select(anchor: int, caret: int) -> Result<bool> {
        self.boundary(anchor)?; self.boundary(caret)?
        self.value = new EditingValue(self.value.text, anchor, caret)
        return ok(true)
    }
    fn checkpoint() {
        self.undo_values.push(self.value)
        if self.undo_values.len() > 100 { self.undo_values.remove(0) }
        self.redo_values.clear()
    }
    pub fn replace(text: string) -> Result<bool> {
        self.renderer.graphemes(text)?
        if self.composing() { self.cancel_composition() }
        if text == "" && self.value.anchor == self.value.caret { return ok(false) }
        self.checkpoint()
        return self.replace_selection(text)
    }
    fn replace_selection(text: string) -> Result<bool> {
        var first: int = self.value.anchor; var last: int = self.value.caret
        if first > last { let swap: int = first; first = last; last = swap }
        let next: string = "{self.value.text.slice(0, first)}{text}{self.value.text.slice(last, self.value.text.len())}"
        let requested: int = first + text.len()
        // Inserting a combining mark or ZWJ may merge adjacent clusters.
        // Put the caret at the end of the resulting cluster, never inside it.
        let boundaries: List<int> = self.renderer.graphemes(next)?
        var caret: int = next.len()
        for at: int in boundaries { if at >= requested { caret = at; break } }
        self.value = new EditingValue(next, caret, caret)
        return ok(true)
    }
    pub fn move_cursor(forward: bool, extend: bool) -> Result<bool> {
        if self.composing() { self.cancel_composition() }
        let boundaries: List<int> = self.renderer.graphemes(self.value.text)?
        var next: int = self.value.caret
        if !extend && self.value.anchor != self.value.caret {
            next = if forward {
                if self.value.anchor > self.value.caret { self.value.anchor } else { self.value.caret }
            } else {
                if self.value.anchor < self.value.caret { self.value.anchor } else { self.value.caret }
            }
        } else if forward {
            for at: int in boundaries { if at > self.value.caret { next = at; break } }
        } else {
            for at: int in boundaries { if at >= self.value.caret { break }
            next = at }
        }
        self.value = new EditingValue(self.value.text, if extend { self.value.anchor } else { next }, next)
        return ok(true)
    }
    pub fn erase(backward: bool) -> Result<bool> {
        if self.composing() { self.cancel_composition() }
        let before: EditingValue = self.value
        if self.value.anchor == self.value.caret { self.move_cursor(!backward, true)? }
        if self.value.anchor == self.value.caret { return ok(false) }
        self.undo_values.push(before)
        if self.undo_values.len() > 100 { self.undo_values.remove(0) }
        self.redo_values.clear()
        return self.replace_selection("")
    }
    pub fn update_composition(text: string) -> Result<bool> {
        self.renderer.graphemes(text)?
        match self.composition {
            none => { self.composition = some(self.value) }
            some(before) => { self.value = before }
        }
        return self.replace_selection(text)
    }
    pub fn commit_composition(text: string) -> Result<bool> {
        self.cancel_composition()
        return self.replace(text)
    }
    pub fn cancel_composition() {
        match self.composition { some(before) => { self.value = before } none => {} }
        self.composition = none
    }
    pub fn undo() -> bool {
        self.cancel_composition()
        if self.undo_values.len() == 0 { return false }
        self.redo_values.push(self.value)
        self.value = self.undo_values[self.undo_values.len() - 1]
        self.undo_values.remove(self.undo_values.len() - 1)
        return true
    }
    pub fn redo() -> bool {
        self.cancel_composition()
        if self.redo_values.len() == 0 { return false }
        self.undo_values.push(self.value)
        self.value = self.redo_values[self.redo_values.len() - 1]
        self.redo_values.remove(self.redo_values.len() - 1)
        return true
    }
}
