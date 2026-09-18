package render

import cortado.geometry
import cortado.paint
import cortado.events
import cortado.host

/// A string list owned by one shared selection control.
pub abstract class ChoiceRender extends RenderObject {
    items: List<string> = []
    chosen: int = -1
    revision: int = 0
    tracking: bool = false
    fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) {
        super.init(renderer, theme, dirty)
        self.focusable = true
    }
    pub override fn needs_template() -> bool { return true }
    pub fn count() -> int { return self.items.len() }
    pub fn version() -> int { return self.revision }
    pub fn selected() -> int { return self.chosen }
    pub fn highlighted() -> int { return self.chosen }
    pub fn selected_text() -> string { return if self.chosen >= 0 && self.chosen < self.items.len() { self.items[self.chosen] } else { "" } }
    pub fn choices() -> List<string> {
        var copy: List<string> = []
        for item: string in self.items { copy.push(item) }
        return move copy
    }
    pub fn item_at(index: int) -> Result<string> {
        self.demand_alive()?
        if index < 0 || index >= self.items.len() { return err("choice index is outside the list", "out_of_range") }
        return ok(self.items[index])
    }
    pub fn replace_items(items: List<string>) -> Result<bool> {
        self.demand_alive()?
        self.dismiss_popup()
        var copy: List<string> = []
        for item: string in items { copy.push(item) }
        self.items = move copy
        self.chosen = if self.items.len() == 0 { -1 } else { 0 }
        self.revision += 1
        self.dirty.layout(); self.dirty.semantics()
        return ok(true)
    }
    pub fn add_item(item: string) -> Result<bool> {
        self.demand_alive()?
        self.items.push(item)
        if self.chosen == -1 { self.chosen = 0 }
        self.revision += 1
        self.dirty.layout(); self.dirty.semantics()
        return ok(true)
    }
    pub override fn set_text(text: string) -> Result<bool> { self.demand_alive()?; return err("use items to set a choice list", "unsupported") }
    pub override fn set_integer(key: int, value: int) -> Result<bool> {
        if key != host.P_SELECTED { return super.set_integer(key, value) }
        self.demand_alive()?
        if value < -1 || value >= self.items.len() { return err("choice selection is outside the list", "out_of_range") }
        if self.chosen == value { return ok(false) }
        self.chosen = value
        self.dirty.paint(); self.dirty.semantics()
        return ok(true)
    }
    pub override fn integer(key: int) -> Result<int> {
        if key == host.P_SELECTED { self.demand_alive()?; return ok(self.chosen) }
        return super.integer(key)
    }
    pub override fn set_value_as_user(index: int, value: f64) -> Result<bool> { return self.set_integer(host.P_SELECTED, index) }
    pub override fn value_event_text(index: int, value: f64) -> string { return self.selected_text() }
    pub override fn semantics() -> SemanticsNode {
        let label: string = if self.a11y_name == "" { self.words } else { self.a11y_name }
        return new SemanticsNode(self.identity, self.role(), label, self.selected_text(), self.bounds, self.enabled)
    }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        var width: f64 = 44.0
        for item: string in self.items {
            let paragraph: paint.Paragraph = self.renderer.paragraph(item, self.font_size(), -1.0, self.text_color())?
            if paragraph.size().width + 34.0 > width { width = paragraph.size().width + 34.0 }
        }
        return ok(geometry.Size.of(width, 31.0))
    }
    pub override fn paint_self(canvas: paint.Canvas) -> Result<bool> { super.paint_self(canvas)?; return self.paint_template(canvas) }
    fn select_as_user(index: int) -> Option<events.UiEvent> {
        if index < 0 || index >= self.items.len() || index == self.chosen { return none }
        self.chosen = index
        self.dismiss_popup()
        self.dirty.paint(); self.dirty.semantics()
        let change: events.UiEvent = events.UiEvent.of(events.EventKind.value_changed, host.Handle.of(self.identity))
        change.index = index; change.position = geometry.Point.at(index as f64, 0.0); change.text = self.items[index]
        return some(change)
    }
}

pub class ComboBoxRender extends ChoiceRender {
    open_value: bool = false
    highlighted_value: int = -1
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "combobox" }
    pub override fn highlighted() -> int { return self.highlighted_value }
    pub override fn popup_open() -> bool { return self.open_value && self.items.len() > 0 }
    pub override fn dismiss_popup() {
        if !self.open_value { return }
        self.open_value = false
        self.highlighted_value = -1
        self.tracking = false
        self.dirty.paint(); self.dirty.semantics()
    }
    pub override fn popup_bounds() -> geometry.Rect {
        let height: f64 = if self.items.len() * 32 < 240 { self.items.len() as f64 * 32.0 } else { 240.0 }
        return geometry.Rect.of(0.0, self.bounds.height + 2.0, self.bounds.width, height)
    }
    pub override fn set_value_as_user(index: int, value: f64) -> Result<bool> {
        let changed: bool = super.set_value_as_user(index, value)?
        self.dismiss_popup()
        return ok(changed)
    }
    pub override fn focus_changed(focused: bool) {
        super.focus_changed(focused)
        if !focused { self.tracking = false }
    }
    fn show_popup() {
        if self.open_value || self.items.len() == 0 { return }
        self.open_value = true
        self.highlighted_value = if self.chosen >= 0 { self.chosen } else { 0 }
        self.dirty.paint(); self.dirty.semantics()
    }
    fn move_highlight(index: int) {
        if index < 0 || index >= self.items.len() || index == self.highlighted_value { return }
        self.highlighted_value = index
        self.dirty.paint(); self.dirty.semantics()
    }
    pub override fn handle_event(event: events.UiEvent) -> Option<events.UiEvent> {
        if !self.enabled || self.hidden || !self.alive { return none }
        if event.kind == events.EventKind.activate { self.show_popup(); return none }
        if event.kind == events.EventKind.pointer_down && event.index == host.BTN_LEFT { self.tracking = true; return none }
        if event.kind == events.EventKind.pointer_up {
            let was_tracking: bool = self.tracking
            self.tracking = false
            if was_tracking && geometry.Rect.of(0.0, 0.0, self.bounds.width, self.bounds.height).contains(event.position) && self.items.len() > 0 {
                self.show_popup()
            }
        }
        if event.kind == events.EventKind.key_down && self.items.len() > 0 {
            if !self.open_value && (event.key() == events.Key.space || event.key() == events.Key.ret ||
                                    event.key() == events.Key.down || event.key() == events.Key.up) {
                self.show_popup()
                return none
            }
            if self.open_value {
                if event.key() == events.Key.down { self.move_highlight((self.highlighted_value + 1) % self.items.len()); return none }
                if event.key() == events.Key.up { self.move_highlight((self.highlighted_value + self.items.len() - 1) % self.items.len()); return none }
                if event.key() == events.Key.home { self.move_highlight(0); return none }
                if event.key() == events.Key.end { self.move_highlight(self.items.len() - 1); return none }
                if event.key() == events.Key.space || event.key() == events.Key.ret {
                    let changed: Option<events.UiEvent> = self.select_as_user(self.highlighted_value)
                    self.dismiss_popup()
                    return changed
                }
            }
        }
        return none
    }
}

pub class SegmentedRender extends ChoiceRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "radiogroup" }
    pub override fn focus_changed(focused: bool) {
        super.focus_changed(focused)
        if !focused { self.tracking = false }
    }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        var width: f64 = 0.0
        for item: string in self.items {
            let paragraph: paint.Paragraph = self.renderer.paragraph(item, self.font_size(), -1.0, self.text_color())?
            width += paragraph.size().width + 28.0
        }
        return ok(geometry.Size.of(if width > 48.0 { width } else { 48.0 }, 34.0))
    }
    pub override fn handle_event(event: events.UiEvent) -> Option<events.UiEvent> {
        if !self.enabled || self.hidden || !self.alive { return none }
        if event.kind == events.EventKind.pointer_down && event.index == host.BTN_LEFT { self.tracking = true; return none }
        if event.kind == events.EventKind.pointer_up {
            let was_tracking: bool = self.tracking
            self.tracking = false
            if was_tracking && self.items.len() > 0 && geometry.Rect.of(0.0, 0.0, self.bounds.width, self.bounds.height).contains(event.position) {
                let index: int = (event.position.x * self.items.len() as f64 / self.bounds.width) as int
                return self.select_as_user(index)
            }
        }
        if event.kind == events.EventKind.key_down && self.items.len() > 0 {
            if event.key() == events.Key.right { return self.select_as_user((self.chosen + 1) % self.items.len()) }
            if event.key() == events.Key.left { return self.select_as_user((self.chosen + self.items.len() - 1) % self.items.len()) }
        }
        return none
    }
}
