// Something the user presses.
package widgets

import cortado.host

/// A push button.
///
/// Pressing it produces an `activate` event. There is no handler argument
/// here: handlers are registered on the application's event router by handle,
/// so a button holds no closure and cannot form a reference cycle with the
/// code that reacts to it.
pub class Button extends Widget {
    pub fn init() {
        super.init(WidgetKind.button)
    }

    pub static fn of(title: string) -> Result<Button> {
        var button: Button = new Button()
        button.set_title(title)?
        return ok(button)
    }

    /// A button's text is its title, which is the word every platform uses for
    /// it and the word that distinguishes it from a text field's value.
    pub fn set_title(title: string) -> Result<bool> {
        return self.set_text_raw(title)
    }

    pub fn title() -> Result<string> {
        return self.text_raw()
    }

    pub override fn display_text() -> Result<string> {
        return self.title()
    }

    /// The system icon this control shows, or `SystemIcon.none` for no icon.
    ///
    /// Refused with `out_of_range` where this platform has no icon for the
    /// role, rather than quietly leaving the control blank — ask
    /// `SystemIcon.available()` first and show a word when the answer is no.
    pub fn set_icon(icon: SystemIcon) -> Result<bool> {
        return self.set_property(host.P_ICON, icon.code())
    }

    pub fn icon() -> Result<SystemIcon> {
        return ok(SystemIcon.of(self.read_property(host.P_ICON)?))
    }
}
