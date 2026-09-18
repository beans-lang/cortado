package render

import cortado.geometry
import cortado.paint
import cortado.events
import cortado.host

pub class BoxRender extends RenderObject {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn accepts_children() -> bool { return true }
}

pub class TextRender extends RenderObject {
    paragraph_value: Option<paint.Paragraph> = none
    measured_text: string = ""
    measured_size: f64 = -1.0
    measured_width: f64 = -2.0
    measured_color: int = -1
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "text" }
    pub fn shaped(width: f64) -> Result<paint.Paragraph> {
        let text: string = self.visible_text()
        let size: f64 = self.font_size()
        let color: int = self.text_color()
        if self.measured_text == text && self.measured_size == size && self.measured_width == width && self.measured_color == color {
            match self.paragraph_value { some(value) => { return ok(value) } none => {} }
        }
        let paragraph: paint.Paragraph = self.renderer.paragraph(text, size, width, color)?
        self.paragraph_value = some(paragraph)
        self.measured_text = text; self.measured_size = size; self.measured_width = width; self.measured_color = color
        return ok(paragraph)
    }
    pub fn visible_text() -> string { return self.words }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        self.demand_alive()?
        // Label is single-line. Measure and paint the same unwrapped paragraph.
        return ok(self.shaped(-1.0)?.size())
    }
    pub override fn paint_self(canvas: paint.Canvas) -> Result<bool> {
        super.paint_self(canvas)?
        return canvas.paragraph(self.shaped(-1.0)?, 0.0, 0.0)
    }
}

/// Shared behavior; the optional visual is built from a .bx control template.
/// A template never receives pointer/keyboard ownership from its control.
pub class ButtonRender extends RenderObject {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) {
        super.init(renderer, theme, dirty)
        self.focusable = true
    }
    pub override fn role() -> string { return "button" }
    pub override fn needs_template() -> bool { return true }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        self.demand_alive()?
        let paragraph: paint.Paragraph = self.renderer.paragraph(self.words, self.font_size(), -1.0, self.text_color())?
        return ok(geometry.Size.of(paragraph.size().width + 24.0, paragraph.size().height + 16.0))
    }
    pub override fn paint_self(canvas: paint.Canvas) -> Result<bool> {
        super.paint_self(canvas)?
        return self.paint_template(canvas)
    }
    pub override fn handle_event(event: events.UiEvent) -> Option<events.UiEvent> {
        if !self.enabled || self.hidden || !self.alive { return none }
        if event.kind == events.EventKind.pointer_down && event.index == host.BTN_LEFT {
            self.pressed = true; self.dirty.paint()
        }
        if event.kind == events.EventKind.pointer_up {
            let was_pressed: bool = self.pressed
            self.pressed = false; self.dirty.paint()
            if was_pressed && geometry.Rect.of(0.0, 0.0, self.bounds.width, self.bounds.height).contains(event.position) {
                return some(events.UiEvent.of(events.EventKind.activate, host.Handle.of(self.identity)))
            }
        }
        if event.kind == events.EventKind.key_down &&
           (event.key() == events.Key.ret || event.key() == events.Key.space) {
            return some(events.UiEvent.of(events.EventKind.activate, host.Handle.of(self.identity)))
        }
        return none
    }
    pub override fn focus_changed(focused: bool) {
        super.focus_changed(focused)
        if !focused { self.pressed = false }
    }
}

pub class ScrollRender extends BoxRender {
    offset: geometry.Point = geometry.Point.zero()
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "scrollarea" }
    pub override fn clips_children() -> bool { return true }
    pub override fn child_offset() -> geometry.Point { return geometry.Point.at(-self.offset.x, -self.offset.y) }
    pub override fn set_content_size(size: geometry.Size) -> Result<bool> {
        self.demand_alive()?
        if !(size.width >= 0.0 && size.width < 10000000.0 && size.height >= 0.0 && size.height < 10000000.0) {
            return err("invalid scroll content size", "out_of_range")
        }
        self.content = size
        return self.scroll_to(self.offset)
    }
    pub fn scroll_to(offset: geometry.Point) -> Result<bool> {
        self.demand_alive()?
        if !(offset.x > -10000000.0 && offset.x < 10000000.0 && offset.y > -10000000.0 && offset.y < 10000000.0) {
            return err("invalid scroll offset", "out_of_range")
        }
        var x: f64 = offset.x; var y: f64 = offset.y
        let right: f64 = self.content.width - self.bounds.width
        let bottom: f64 = self.content.height - self.bounds.height
        if x > right { x = right }
        if y > bottom { y = bottom }
        if x < 0.0 { x = 0.0 }
        if y < 0.0 { y = 0.0 }
        if self.offset.x == x && self.offset.y == y { return ok(false) }
        self.offset = geometry.Point.at(x, y)
        self.dirty.paint(); self.dirty.semantics()
        return ok(true)
    }
    pub override fn scroll_by(dx: f64, dy: f64) -> Result<bool> {
        return self.scroll_to(geometry.Point.at(self.offset.x + dx, self.offset.y + dy))
    }
}
