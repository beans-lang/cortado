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
    pub fill: string = "#e9e9ebff"
    pub ink: string = "#000000ff"
    pub accent: string = "#0088ffff"
    pub radius: f64 = 1000.0
    pub font_size: f64 = 17.0

    // Theme tokens a template draws with. Refreshed whenever the theme moves.
    pub on_accent: string = "#ffffffff"
    pub muted: string = "#3c3c4399"
    pub faint: string = "#3c3c434c"
    pub surface: string = "#e9e9ebff"
    pub separator: string = "#3c3c431f"
    pub hairline: string = "#c6c6c8ff"
    pub track_off: string = "#e9e9eaff"
    pub background: string = "#ffffffff"
    pub grouped: string = "#f2f2f7ff"
    pub card: string = "#ffffffff"
    pub knob: string = "#ffffffff"
    pub radius_small: f64 = 6.0
    pub radius_medium: f64 = 10.0
    pub radius_large: f64 = 14.0
    pub capsule: f64 = 1000.0
    pub control_height: f64 = 34.0
    pub headline: f64 = 17.0
    pub subheadline: f64 = 15.0
    pub footnote: f64 = 13.0
    pub caption: f64 = 12.0
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
        self.hairline = ControlTemplate.color(theme.opaque_separator())
        self.track_off = ControlTemplate.color(theme.track())
        self.background = ControlTemplate.color(theme.background())
        self.grouped = ControlTemplate.color(theme.grouped_background())
        self.card = ControlTemplate.color(theme.card())
        self.knob = ControlTemplate.color(theme.knob())
        self.radius_small = theme.radius_small()
        self.radius_medium = theme.radius_medium()
        self.radius_large = theme.radius_large()
        self.capsule = theme.capsule()
        self.control_height = theme.control_height()
        self.headline = theme.headline()
        self.subheadline = theme.subheadline()
        self.footnote = theme.footnote()
        self.caption = theme.caption1()
        self.radius = theme.capsule()
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
