package component

import cortado.render

/// Base for .bx visual templates. These values describe the owning control;
/// the template does not own its input, focus, or accessibility identity.
pub abstract class ControlTemplate extends Component {
    pub title: string = ""
    pub enabled: bool = true
    pub focused: bool = false
    pub hovered: bool = false
    pub pressed: bool = false
    pub fill: string = "#e8eaf0"
    pub ink: string = "#202128"
    pub accent: string = "#365eea"
    pub radius: f64 = 6.0
    pub font_size: f64 = 14.0

    pub fn init() { super.init() }
    pub fn bind_actions(actions: render.ControlActions) {}
    pub fn decorate_popup(root: render.RenderObject) -> Result<bool> { return ok(false) }

    pub fn update(control: render.RenderObject, theme: render.Theme) {
        let down: bool = control.is_pressed()
        let fill: string = ControlTemplate.color(if down { theme.accent() } else { theme.surface() })
        let ink: string = ControlTemplate.color(if down { 0xffffffff } else { control.text_color() })
        let accent: string = ControlTemplate.color(theme.accent())
        if self.title == control.text() && self.enabled == control.is_enabled() &&
           self.focused == control.focused() && self.hovered == control.hovered() && self.pressed == down && self.fill == fill &&
           self.ink == ink && self.accent == accent && self.font_size == control.font_size() { return }
        self.title = control.text(); self.enabled = control.is_enabled(); self.focused = control.focused()
        self.hovered = control.hovered()
        self.pressed = down; self.fill = fill; self.ink = ink; self.accent = accent
        self.font_size = control.font_size()
        self.request_render()
    }
    static fn color(value: int) -> string {
        let digits: string = "0123456789abcdef"
        var result: string = "#"
        for index: int in 0..8 {
            let shift: int = (7 - index) * 4
            let digit: int = (value >> shift) & 15
            result = "{result}{digits.slice(digit, digit + 1)}"
        }
        return result
    }
}

pub interface TemplateFactory {
    fn create(control: render.RenderObject) -> Option<ControlTemplate>
}

/// An optional extension: existing theme factories remain source compatible.
pub interface PopupTemplateFactory extends TemplateFactory {
    fn create_popup(control: render.RenderObject) -> Option<ControlTemplate>
}
