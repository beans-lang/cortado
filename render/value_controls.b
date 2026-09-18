package render

import cortado.geometry
import cortado.paint
import cortado.events
import cortado.host

/// Input and state live here; the chrome comes from a .bx template.
pub abstract class ToggleRender extends RenderObject {
    checked_value: int = 0
    tracking: bool = false
    fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) {
        super.init(renderer, theme, dirty)
        self.focusable = true
    }
    pub override fn needs_template() -> bool { return true }
    pub fn checked() -> int { return self.checked_value }
    pub fn allows_mixed() -> bool { return false }
    pub override fn semantics() -> SemanticsNode {
        let label: string = if self.a11y_name == "" { self.words } else { self.a11y_name }
        let value: string = if self.checked_value == 2 { "mixed" } else if self.checked_value == 1 { "on" } else { "off" }
        return new SemanticsNode(self.identity, self.role(), label, value, self.bounds, self.enabled)
    }
    pub override fn exclusive_choice() -> bool { return false }
    pub override fn clear_choice() {}
    pub override fn set_value_as_user(index: int, value: f64) -> Result<bool> {
        return self.set_integer(host.P_CHECKED, index)
    }
    pub override fn set_integer(key: int, value: int) -> Result<bool> {
        if key != host.P_CHECKED { return super.set_integer(key, value) }
        self.demand_alive()?
        if value < 0 || value > (if self.allows_mixed() { 2 } else { 1 }) {
            return err("invalid checked state", "out_of_range")
        }
        if self.checked_value == value { return ok(false) }
        self.checked_value = value
        self.dirty.paint(); self.dirty.semantics()
        return ok(true)
    }
    pub override fn integer(key: int) -> Result<int> {
        if key == host.P_CHECKED { self.demand_alive()?; return ok(self.checked_value) }
        return super.integer(key)
    }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        self.demand_alive()?
        let paragraph: paint.Paragraph = self.renderer.styled_paragraph(self.words, self.text_style(), -1.0, self.text_color())?
        let lead: f64 = self.theme.toggle_size() + self.theme.toggle_gap()
        return ok(geometry.Size.of(lead + paragraph.size().width, self.theme.toggle_row_height()))
    }
    pub override fn paint_self(canvas: paint.Canvas) -> Result<bool> {
        super.paint_self(canvas)?
        return self.paint_template(canvas)
    }
    fn user_toggle() -> Option<events.UiEvent> {
        let next: int = if self.exclusive_choice() { 1 } else if self.checked_value == 0 { 1 } else { 0 }
        if next == self.checked_value { return none }
        self.checked_value = next
        self.dirty.paint(); self.dirty.semantics()
        let change: events.UiEvent = events.UiEvent.of(events.EventKind.value_changed, host.Handle.of(self.identity))
        change.index = next
        return some(change)
    }
    pub override fn handle_event(event: events.UiEvent) -> Option<events.UiEvent> {
        if !self.enabled || self.hidden || !self.alive { return none }
        if event.kind == events.EventKind.activate { return self.user_toggle() }
        if event.kind == events.EventKind.pointer_down && event.index == host.BTN_LEFT {
            self.tracking = true; self.pressed = true; self.dirty.paint()
        }
        if event.kind == events.EventKind.pointer_up {
            let was_tracking: bool = self.tracking
            self.tracking = false; self.pressed = false; self.dirty.paint()
            if was_tracking && geometry.Rect.of(0.0, 0.0, self.bounds.width, self.bounds.height).contains(event.position) {
                return self.user_toggle()
            }
        }
        if event.kind == events.EventKind.key_down && (event.key() == events.Key.space || event.key() == events.Key.ret) {
            return self.user_toggle()
        }
        return none
    }
    pub override fn focus_changed(focused: bool) {
        super.focus_changed(focused)
        if !focused { self.tracking = false; self.pressed = false }
    }
}

pub class CheckBoxRender extends ToggleRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "checkbox" }
    pub override fn allows_mixed() -> bool { return true }
}
pub class RadioButtonRender extends ToggleRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "radio" }
    pub override fn exclusive_choice() -> bool { return self.checked_value == 1 }
    pub override fn clear_choice() {
        if self.checked_value == 0 { return }
        self.checked_value = 0; self.dirty.paint(); self.dirty.semantics()
    }
}
pub class SwitchRender extends ToggleRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "switch" }
    pub override fn set_text(text: string) -> Result<bool> { self.demand_alive()?; return err("switch does not carry text", "unsupported") }
    /// The size it paints, not the 54 by 24 frame AppKit keeps at every control
    /// size. A drawing cannot be wider than the box it sits in, so a frame that
    /// small would clamp a large switch's track while its knob kept travelling
    /// the full distance — the knob then walks out of its own track.
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        return ok(geometry.Size.of(self.theme.switch_width(), self.theme.switch_height()))
    }
}

pub abstract class RangeRender extends RenderObject {
    low_value: f64 = 0.0
    high_value: f64 = 100.0
    current_value: f64 = 0.0
    increment: f64 = 0.0
    dragging: bool = false
    fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn needs_template() -> bool { return true }
    pub fn low() -> f64 { return self.low_value }
    pub fn high() -> f64 { return self.high_value }
    pub fn value() -> f64 { return self.current_value }
    pub fn step() -> f64 { return self.increment }
    pub override fn value_event_index(index: int, value: f64) -> int { return self.current_value as int }
    pub override fn value_event_value(index: int, value: f64) -> f64 { return self.current_value }
    pub override fn semantics() -> SemanticsNode {
        let label: string = if self.a11y_name == "" { self.words } else { self.a11y_name }
        return new SemanticsNode(self.identity, self.role(), label, "{self.current_value}", self.bounds, self.enabled)
    }
    pub override fn set_text(text: string) -> Result<bool> { self.demand_alive()?; return err("range control does not carry text", "unsupported") }
    pub fn fraction() -> f64 {
        if self.high_value <= self.low_value { return 0.0 }
        return (self.current_value - self.low_value) / (self.high_value - self.low_value)
    }
    pub fn needs_positive_step() -> bool { return false }
    pub fn allows_step() -> bool { return false }
    pub fn accepts_input() -> bool { return false }
    pub override fn set_real(key: int, value: f64) -> Result<bool> {
        if key != host.P_MIN && key != host.P_MAX && key != host.P_VALUE && key != host.P_STEP { return super.set_real(key, value) }
        self.demand_alive()?
        if !(value > -10000000.0 && value < 10000000.0) { return err("invalid range value", "out_of_range") }
        if key == host.P_STEP {
            if !self.allows_step() { return err("this range control has no step", "unsupported") }
            if value < 0.0 || (self.needs_positive_step() && value == 0.0) { return err("invalid range increment", "out_of_range") }
            self.increment = value
        } else if key == host.P_MIN {
            self.low_value = value
            if self.current_value < value { self.current_value = value }
        } else if key == host.P_MAX {
            self.high_value = value
            if self.current_value > value { self.current_value = value }
        } else {
            if self.high_value <= self.low_value || value < self.low_value || value > self.high_value {
                return err("value falls outside the range", "out_of_range")
            }
            self.current_value = value
        }
        self.dirty.paint(); self.dirty.semantics()
        return ok(true)
    }
    pub override fn real(key: int) -> Result<f64> {
        self.demand_alive()?
        if key == host.P_MIN { return ok(self.low_value) }
        if key == host.P_MAX { return ok(self.high_value) }
        if key == host.P_VALUE { return ok(self.current_value) }
        if key == host.P_STEP { return if self.allows_step() { ok(self.increment) } else { err("this range control has no step", "unsupported") } }
        return super.real(key)
    }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        return ok(geometry.Size.of(160.0, self.theme.slider_height()))
    }
    /// The knob reaches past the track on both edges, the way AppKit draws it.
    pub override fn visual_frame() -> geometry.Rect {
        let reach: f64 = self.theme.slider_overhang()
        return geometry.Rect.of(self.bounds.x, self.bounds.y - reach,
            self.bounds.width, self.bounds.height + reach * 2.0)
    }
    pub override fn paint_self(canvas: paint.Canvas) -> Result<bool> { super.paint_self(canvas)?; return self.paint_template(canvas) }
    fn change_as_user(value: f64) -> Option<events.UiEvent> {
        if self.high_value <= self.low_value || !(value > -10000000.0 && value < 10000000.0) { return none }
        var next: f64 = value
        if next < self.low_value { next = self.low_value }
        if next > self.high_value { next = self.high_value }
        if self.increment > 0.0 {
            let ticks: int = ((next - self.low_value) / self.increment + 0.5) as int
            next = self.low_value + ticks as f64 * self.increment
            if next > self.high_value { next = self.high_value }
        }
        if next == self.current_value { return none }
        self.current_value = next
        self.dirty.paint(); self.dirty.semantics()
        let change: events.UiEvent = events.UiEvent.of(events.EventKind.value_changed, host.Handle.of(self.identity))
        change.index = next as int; change.position = geometry.Point.at(next, 0.0)
        return some(change)
    }
}

pub class SliderRender extends RangeRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty); self.focusable = true }
    pub override fn role() -> string { return "slider" }
    pub override fn accepts_input() -> bool { return true }
    pub override fn allows_step() -> bool { return true }
    pub override fn set_value_as_user(index: int, value: f64) -> Result<bool> {
        self.demand_alive()?
        if !(value > -10000000.0 && value < 10000000.0) { return err("invalid user range value", "out_of_range") }
        let before: f64 = self.current_value
        self.change_as_user(value)
        return ok(before != self.current_value)
    }
    fn at(x: f64) -> Option<events.UiEvent> {
        let fraction: f64 = if self.bounds.width <= 0.0 { 0.0 } else { x / self.bounds.width }
        return self.change_as_user(self.low_value + fraction * (self.high_value - self.low_value))
    }
    pub override fn handle_event(event: events.UiEvent) -> Option<events.UiEvent> {
        if !self.enabled || self.hidden || !self.alive { return none }
        if event.kind == events.EventKind.pointer_down && event.index == host.BTN_LEFT { self.dragging = true; return self.at(event.position.x) }
        if event.kind == events.EventKind.pointer_move && self.dragging { return self.at(event.position.x) }
        if event.kind == events.EventKind.pointer_up && self.dragging { self.dragging = false; return self.at(event.position.x) }
        if event.kind == events.EventKind.key_down {
            let delta: f64 = if self.increment > 0.0 { self.increment } else { (self.high_value - self.low_value) / 100.0 }
            if event.key() == events.Key.left || event.key() == events.Key.down { return self.change_as_user(self.current_value - delta) }
            if event.key() == events.Key.right || event.key() == events.Key.up { return self.change_as_user(self.current_value + delta) }
        }
        return none
    }
}

pub class StepperRender extends RangeRender {
    tracking: bool = false
    /// Which half the pointer went down on: -1 none, 0 lower, 1 upper.
    pressed_half: int = -1
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty); self.increment = 1.0; self.focusable = true }
    pub override fn role() -> string { return "spinbutton" }
    pub override fn needs_positive_step() -> bool { return true }
    pub override fn allows_step() -> bool { return true }
    pub override fn set_value_as_user(index: int, value: f64) -> Result<bool> {
        self.demand_alive()?
        if !(value > -10000000.0 && value < 10000000.0) { return err("invalid user range value", "out_of_range") }
        let before: f64 = self.current_value
        self.change_as_user(value)
        return ok(before != self.current_value)
    }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        return ok(geometry.Size.of(self.theme.stepper_width(), self.theme.stepper_height()))
    }
    pub override fn handle_event(event: events.UiEvent) -> Option<events.UiEvent> {
        if !self.enabled || self.hidden || !self.alive { return none }
        if event.kind == events.EventKind.pointer_down && event.index == host.BTN_LEFT {
            self.tracking = true
            self.pressed = true
            // AppKit steps on the press, not on the release, and the half that
            // was pressed is the one that lights up.
            self.pressed_half = if event.position.y < self.bounds.height / 2.0 { 1 } else { 0 }
            self.dirty.paint()
            return self.change_as_user(self.current_value +
                if self.pressed_half == 1 { self.increment } else { 0.0 - self.increment })
        }
        if event.kind == events.EventKind.pointer_up {
            self.tracking = false
            if self.pressed { self.pressed = false; self.pressed_half = -1; self.dirty.paint() }
            return none
        }
        if event.kind == events.EventKind.key_down {
            if event.key() == events.Key.up || event.key() == events.Key.right { return self.change_as_user(self.current_value + self.increment) }
            if event.key() == events.Key.down || event.key() == events.Key.left { return self.change_as_user(self.current_value - self.increment) }
        }
        return none
    }
    /// -1 while nothing is held, else the half under the pointer.
    pub fn held_half() -> int { return self.pressed_half }
    pub override fn focus_changed(focused: bool) {
        super.focus_changed(focused)
        if !focused { self.tracking = false; self.pressed = false; self.pressed_half = -1 }
    }
}

pub class ProgressBarRender extends RangeRender {
    indeterminate_value: bool = false
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "progressbar" }
    pub fn indeterminate() -> bool { return self.indeterminate_value }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        return ok(geometry.Size.of(160.0, self.theme.bar_control_height()))
    }
    pub override fn set_integer(key: int, value: int) -> Result<bool> {
        if key != host.P_INDETERMINATE { return super.set_integer(key, value) }
        self.demand_alive()?
        if value != 0 && value != 1 { return err("invalid indeterminate state", "out_of_range") }
        self.indeterminate_value = value == 1
        self.dirty.paint(); self.dirty.semantics()
        return ok(true)
    }
    pub override fn integer(key: int) -> Result<int> {
        if key == host.P_INDETERMINATE { self.demand_alive()?; return ok(if self.indeterminate_value { 1 } else { 0 }) }
        return super.integer(key)
    }
}

pub class LevelIndicatorRender extends RangeRender {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "meter" }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> {
        return ok(geometry.Size.of(120.0, self.theme.level_height()))
    }
}

pub class SeparatorRender extends RenderObject {
    pub fn init(renderer: paint.Renderer, theme: Theme, dirty: Invalidation) { super.init(renderer, theme, dirty) }
    pub override fn role() -> string { return "separator" }
    pub override fn set_text(text: string) -> Result<bool> { self.demand_alive()?; return err("separator does not carry text", "unsupported") }
    pub override fn needs_template() -> bool { return true }
    pub override fn measure(available: geometry.Size) -> Result<geometry.Size> { return ok(geometry.Size.of(1.0, 1.0)) }
    pub override fn paint_self(canvas: paint.Canvas) -> Result<bool> { super.paint_self(canvas)?; return self.paint_template(canvas) }
}
