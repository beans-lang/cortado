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
    pub fill: string = "#efefefff"
    pub ink: string = "#000000d8"
    pub accent: string = "#007affff"
    pub radius: f64 = 5.0
    pub font_size: f64 = 11.0

    // Theme tokens a template draws with. Refreshed whenever the theme moves.
    pub on_accent: string = "#ffffffff"
    pub muted: string = "#0000007f"
    pub faint: string = "#00000042"
    pub surface: string = "#efefefff"
    pub separator: string = "#00000019"
    pub hairline: string = "#e6e6e6ff"
    pub track_off: string = "#d8d8d8ff"
    pub background: string = "#ffffffff"
    pub grouped: string = "#f4f4f4ff"
    pub card: string = "#ffffffff"
    pub knob: string = "#ffffffff"
    pub selection: string = "#0064e1ff"
    pub stripe: string = "#f5f5f5ff"
    pub radius_small: f64 = 3.0
    pub radius_medium: f64 = 5.0
    pub radius_large: f64 = 6.0
    pub capsule: f64 = 1000.0
    pub control_height: f64 = 20.0
    pub headline: f64 = 11.0
    pub subheadline: f64 = 10.0
    pub footnote: f64 = 10.0
    pub caption: f64 = 9.0
    theme_revision: int = -1

    pub fn init() { super.init() }
    pub fn bind_actions(actions: render.ControlActions) {}
    pub fn decorate_popup(root: render.RenderObject) -> Result<bool> { return ok(false) }

    pub fn update(control: render.RenderObject, theme: render.Theme) {
        let down: bool = control.is_pressed()
        let bezel: int = if down { theme.surface_pressed() }
                         else if control.hovered() { theme.surface_hovered() }
                         else { theme.surface() }
        let fill: string = ControlTemplate.color(bezel)
        let ink: string = ControlTemplate.color(control.text_color())
        let accent: string = ControlTemplate.color(theme.accent())
        if self.title == control.text() && self.enabled == control.is_enabled() &&
           self.focused == control.focused() && self.hovered == control.hovered() && self.pressed == down && self.fill == fill &&
           self.ink == ink && self.accent == accent && self.font_size == control.font_size() &&
           self.theme_revision == theme.version() { return }
        self.title = control.text(); self.enabled = control.is_enabled(); self.focused = control.focused()
        self.hovered = control.hovered()
        self.pressed = down; self.fill = fill; self.ink = ink; self.accent = accent
        self.font_size = control.font_size()
        self.adopt(theme)
        self.request_render()
    }

    /// Copies every theme token a template can read. One revision guards them all.
    fn adopt(theme: render.Theme) {
        self.theme_revision = theme.version()
        self.on_accent = ControlTemplate.color(theme.on_accent())
        self.muted = ControlTemplate.color(theme.secondary_label())
        self.faint = ControlTemplate.color(theme.tertiary_label())
        self.surface = ControlTemplate.color(theme.surface())
        self.separator = ControlTemplate.color(theme.separator())
        self.hairline = ControlTemplate.color(theme.grid())
        self.track_off = ControlTemplate.color(theme.track())
        self.background = ControlTemplate.color(theme.background())
        self.grouped = ControlTemplate.color(theme.sunken())
        self.card = ControlTemplate.color(theme.card())
        self.knob = ControlTemplate.color(theme.knob())
        self.selection = ControlTemplate.color(theme.selection())
        self.stripe = ControlTemplate.color(theme.stripe())
        self.radius_small = theme.radius_small()
        self.radius_medium = theme.radius_medium()
        self.radius_large = theme.radius_large()
        self.capsule = theme.capsule()
        self.control_height = theme.control_height()
        self.headline = theme.headline()
        self.subheadline = theme.subheadline()
        self.footnote = theme.footnote()
        self.caption = theme.caption1()
        self.radius = theme.radius_medium()
    }

    static fn color(value: int) -> string { return render.Theme.hex(value) }
}

pub interface TemplateFactory {
    fn create(control: render.RenderObject) -> Option<ControlTemplate>
}

/// An optional extension: existing theme factories remain source compatible.
pub interface PopupTemplateFactory extends TemplateFactory {
    fn create_popup(control: render.RenderObject) -> Option<ControlTemplate>
}
