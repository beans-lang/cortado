package render

import cortado.paint
import cortado.geometry
import cortado.events
import cortado.host

pub class TextFieldRender extends TextRender {
    editor_value: TextEditor
    hint: string = ""
    editable: bool = true
    secure_value: bool = false
    multiline_value: bool = false
    text_offset: f64 = 0.0
    vertical_offset: f64 = 0.0
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) {
        self.editor_value = new TextEditor(renderer)
        super.init(renderer, theme, dirty)
        self.focusable = true
    }
    pub fn selection_anchor() -> int { return self.editor_value.anchor() }
    pub fn selection_caret() -> int { return self.editor_value.caret() }
    pub fn editing_text() -> string { return self.editor_value.text() }
    pub fn is_secure() -> bool { return self.secure_value }
    pub fn is_multiline() -> bool { return self.multiline_value }
    fn paragraph_width() -> f64 { return if self.multiline_value { self.bounds.width - 16.0 } else { -1.0 } }
    fn display_offset(offset: int) -> int {
        if !self.secure_value { return offset }
        var count: int = 0
        match self.renderer.graphemes(self.words) {
            ok(boundaries) => { for at: int in boundaries { if at > 0 && at <= offset { count += 1 } } }
            err(_) => {}
        }
        return count * 3 // one UTF-8 bullet per grapheme
    }
    fn source_offset(offset: int) -> int {
        if !self.secure_value { return offset }
        let index: int = offset / 3
        match self.renderer.graphemes(self.words) {
            ok(boundaries) => { if index >= 0 && index < boundaries.len() { return boundaries[index] } }
            err(_) => {}
        }
        return self.words.len()
    }
    pub fn caret_rect() -> Result<geometry.Rect> {
        self.demand_alive()?
        let caret: geometry.Rect = self.shaped(self.paragraph_width())?.caret(self.display_offset(self.editor_value.caret()))
        return ok(geometry.Rect.of(caret.x + 8.0 - self.text_offset,
                   caret.y + 8.0 - self.vertical_offset, caret.width, caret.height))
    }
    pub override fn needs_template() -> bool { return true }
    pub override fn role() -> string { return "textbox" }
    pub override fn semantics() -> SemanticsNode {
        return new SemanticsNode(self.identity, if self.secure_value { "securetext" } else { "textbox" },
            if self.a11y_name == "" { self.hint } else { self.a11y_name },
            if self.secure_value { "" } else { self.words }, self.bounds, self.enabled)
    }
    pub override fn set_text(text: string) -> Result<bool> {
        self.demand_alive()?
        if self.words == text { return ok(false) }
        self.editor_value.set_text(text)?
        return super.set_text(text)
    }
    pub override fn set_string(key: int, value: string) -> Result<bool> {
        self.demand_alive()?
        if key == host.S_HINT { self.hint = value; self.dirty.paint(); return ok(true) }
        return super.set_string(key, value)
    }
    pub override fn string_at(key: int) -> Result<string> {
        self.demand_alive()?
        if key == host.S_HINT { return ok(self.hint) }
        return super.string_at(key)
    }
    pub override fn set_integer(key: int, value: int) -> Result<bool> {
        self.demand_alive()?
        if key == host.P_EDITABLE { self.editable = value != 0; return ok(true) }
        return super.set_integer(key, value)
    }
    pub override fn integer(key: int) -> Result<int> {
        self.demand_alive()?
        if key == host.P_EDITABLE { return ok(if self.editable { 1 } else { 0 }) }
        return super.integer(key)
    }
    pub override fn visible_text() -> string {
        if self.words == "" { return self.hint }
        if !self.secure_value { return self.words }
        var masked: string = ""
        match self.renderer.graphemes(self.words) {
            ok(boundaries) => { for at: int in boundaries { if at > 0 { masked = "{masked}•" } } }
            err(_) => {}
        }
        return masked
    }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        self.demand_alive()?
        let measured: geometry.Size = self.shaped(if self.multiline_value { 180.0 } else { -1.0 })?.size()
        return ok(geometry.Size.of(180.0, if self.multiline_value { 100.0 } else { measured.height + 16.0 }))
    }
    pub override fn paint_self(canvas: paint.Canvas) -> Result<bool> {
        self.paint_template(canvas)?
        if self.bounds.width <= 16.0 || self.bounds.height <= 8.0 { return ok(true) }
        canvas.save()?
        canvas.clip(geometry.Rect.of(8.0, 4.0, self.bounds.width - 16.0, self.bounds.height - 8.0), 0.0)?
        let paragraph: paint.Paragraph = self.shaped(self.paragraph_width())?
        var caret: geometry.Rect = paragraph.caret(self.display_offset(self.editor_value.caret()))
        if self.has_focus {
            let available: f64 = self.bounds.width - 17.0
            if !self.multiline_value {
                if caret.x < self.text_offset { self.text_offset = caret.x }
                if caret.x > self.text_offset + available { self.text_offset = caret.x - available }
            } else {
                self.text_offset = 0.0
                let height: f64 = self.bounds.height - 16.0
                if caret.y < self.vertical_offset { self.vertical_offset = caret.y }
                if caret.y + caret.height > self.vertical_offset + height {
                    self.vertical_offset = caret.y + caret.height - height
                }
            }
        } else { self.text_offset = 0.0; self.vertical_offset = 0.0 }
        if self.has_focus && self.editor_value.anchor() != self.editor_value.caret() {
            var first: int = self.editor_value.anchor(); var last: int = self.editor_value.caret()
            if first > last { let swap: int = first; first = last; last = swap }
            let rectangles: List<geometry.Rect> = paragraph.selection(self.display_offset(first), self.display_offset(last))?
            for rect: geometry.Rect in rectangles {
                canvas.rectangle(geometry.Rect.of(rect.x + 8.0 - self.text_offset, rect.y + 8.0 - self.vertical_offset, rect.width, rect.height),
                    0.0, (self.theme.accent() & 0xffffff00) | 0x44, 0.0)?
            }
        }
        canvas.paragraph(paragraph, 8.0 - self.text_offset, 8.0 - self.vertical_offset)?
        if self.has_focus {
            caret.x += 8.0 - self.text_offset; caret.y += 8.0 - self.vertical_offset
            canvas.rectangle(caret, 0.0, self.theme.accent(), 0.0)?
        }
        canvas.restore()?
        return ok(true)
    }
    pub override fn handle_event(event: events.UiEvent) -> Option<events.UiEvent> {
        if !self.editable || !self.enabled || !self.alive { return none }
        if event.kind == events.EventKind.composition_cancel {
            self.editor_value.cancel_composition()
            self.words = self.editor_value.text()
            self.dirty.layout()
            return none
        }
        if event.kind == events.EventKind.composition_update || event.kind == events.EventKind.text_input {
            let was_composing: bool = self.editor_value.composing()
            let input: string = if self.multiline_value { event.text.replace("\r", "\n") }
                                else { event.text.replace("\n", "").replace("\r", "") }
            var operation: Result<bool> = ok(false)
            if event.kind == events.EventKind.text_input {
                if event.index >= 0 && event.token >= event.index {
                    self.editor_value.cancel_composition()
                    match self.editor_value.select(event.index, event.token) {
                        ok(_) => { operation = self.editor_value.replace(input) }
                        err(_) => { return none }
                    }
                } else { operation = self.editor_value.commit_composition(input) }
            } else { operation = self.editor_value.update_composition(input) }
            match operation { err(_) => { return none } ok(_) => {} }
            if event.kind == events.EventKind.composition_update {
                let start: int = self.editor_value.caret() - input.len()
                let anchor: int = start + event.index
                let caret: int = start + event.token
                // The IME's offsets are UTF-8 bytes. Grapheme validation in
                // TextEditor keeps the native selection out of split clusters.
                if start >= 0 { self.editor_value.select(anchor, caret) }
            }
            self.dirty.layout()
            self.dirty.semantics()
            let report: bool = event.kind == events.EventKind.text_input &&
                               (was_composing || self.words != self.editor_value.text())
            if self.words != self.editor_value.text() {
                self.words = self.editor_value.text()
            }
            if report {
                let changed: events.UiEvent = events.UiEvent.of(events.EventKind.value_changed, host.Handle.of(self.identity))
                changed.text = self.words
                return some(changed)
            }
            return none
        }
        if event.kind == events.EventKind.pointer_down && event.index == host.BTN_LEFT {
            match self.shaped(self.paragraph_width()) {
                ok(paragraph) => {
                    let hit: int = self.source_offset(paragraph.hit_test(event.position.x - 8.0 + self.text_offset,
                                                      event.position.y - 8.0 + self.vertical_offset))
                    match self.renderer.graphemes(self.words) {
                        ok(boundaries) => {
                            var at: int = 0
                            for boundary: int in boundaries {
                                if boundary > hit { break }
                                at = boundary
                            }
                            self.editor_value.select(if event.has_modifier(host.MOD_SHIFT) { self.editor_value.anchor() } else { at }, at)
                            self.dirty.paint()
                        }
                        err(_) => {}
                    }
                }
                err(_) => {}
            }
            return none
        }
        if event.kind != events.EventKind.key_down { return none }
        var operation: Result<bool> = ok(false)
        let extend: bool = event.has_modifier(host.MOD_SHIFT)
        let shortcut: bool = event.has_modifier(host.MOD_COMMAND) || event.has_modifier(host.MOD_CONTROL)
        if shortcut && event.key() == events.Key.character {
            if event.text == "a" || event.text == "A" { operation = self.editor_value.select(0, self.words.len()) }
            else if (event.text == "c" || event.text == "C") && !self.secure_value {
                var first: int = self.editor_value.anchor(); var last: int = self.editor_value.caret()
                if first > last { let swap: int = first; first = last; last = swap }
                if first < last { host.NativeServices.clipboard_write(self.words.slice(first, last)) }
                return none
            }
            else if (event.text == "x" || event.text == "X") && !self.secure_value {
                var first: int = self.editor_value.anchor(); var last: int = self.editor_value.caret()
                if first > last { let swap: int = first; first = last; last = swap }
                if first < last {
                    match host.NativeServices.clipboard_write(self.words.slice(first, last)) {
                        ok(_) => { operation = self.editor_value.replace("") }
                        err(_) => { return none }
                    }
                }
            }
            else if event.text == "v" || event.text == "V" {
                match host.NativeServices.clipboard_read() {
                    ok(text) => { operation = self.editor_value.replace(if self.multiline_value { text.replace("\r", "\n") }
                                                                 else { text.replace("\n", "").replace("\r", "") }) }
                    err(_) => { return none }
                }
            }
            else if event.text == "z" || event.text == "Z" {
                operation = ok(if extend { self.editor_value.redo() } else { self.editor_value.undo() })
            }
            else if event.text == "y" || event.text == "Y" { operation = ok(self.editor_value.redo()) }
        } else { match event.key() {
            character => { operation = self.editor_value.replace(if self.multiline_value { event.text.replace("\r", "\n") }
                                                                   else { event.text.replace("\n", "").replace("\r", "") }) }
            space => { operation = self.editor_value.replace(" ") }
            backspace => { operation = self.editor_value.erase(true) }
            delete => { operation = self.editor_value.erase(false) }
            left => { operation = self.editor_value.move_cursor(false, extend) }
            right => { operation = self.editor_value.move_cursor(true, extend) }
            home => { operation = self.editor_value.select(if extend { self.editor_value.anchor() } else { 0 }, 0) }
            end => { operation = self.editor_value.select(if extend { self.editor_value.anchor() } else { self.words.len() }, self.words.len()) }
            ret => {
                if self.multiline_value { operation = self.editor_value.replace("\n") }
                else {
                    let commit: events.UiEvent = events.UiEvent.of(events.EventKind.text_commit, host.Handle.of(self.identity))
                    commit.text = self.words
                    return some(commit)
                }
            }
            _ => {}
        } }
        match operation { err(_) => { return none } ok(_) => {} }
        self.dirty.paint()
        self.dirty.semantics()
        if self.words != self.editor_value.text() {
            self.words = self.editor_value.text()
            self.dirty.layout()
            let changed: events.UiEvent = events.UiEvent.of(events.EventKind.value_changed, host.Handle.of(self.identity))
            changed.text = self.words
            return some(changed)
        }
        return none
    }
}

pub class SecureFieldRender extends TextFieldRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) {
        super.init(renderer, theme, dirty)
        self.secure_value = true
    }
}

pub class SearchFieldRender extends TextFieldRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) {
        super.init(renderer, theme, dirty)
    }
}

pub class TextAreaRender extends TextFieldRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) {
        super.init(renderer, theme, dirty)
        self.multiline_value = true
    }
}
