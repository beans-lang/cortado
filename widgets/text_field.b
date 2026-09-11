// One line of text the user can type into.
package widgets

import cortado.host

/// A single-line editable field.
///
/// The platform's own field, which is the entire point: it brings the system
/// input method, dictation, the emoji picker, spell-checking, the standard
/// editing shortcuts and the selection behaviour the user already knows.
/// Rebuilding any of that is how a toolkit ends up subtly wrong in every
/// language but English.
pub class TextField extends Widget {
    pub fn init() {
        super.init(WidgetKind.text_field)
    }

    pub static fn of(value: string) -> Result<TextField> {
        var field: TextField = new TextField()
        field.set_value(value)?
        return ok(field)
    }

    pub fn set_value(value: string) -> Result<bool> {
        return self.set_text_raw(value)
    }

    pub fn value() -> Result<string> {
        return self.text_raw()
    }

    pub fn set_editable(on: bool) -> Result<bool> {
        return self.set_flag(host.P_EDITABLE, on, "make a text field editable")
    }

    pub fn is_editable() -> Result<bool> {
        return self.read_flag(host.P_EDITABLE, "read whether a text field is editable")
    }

    pub override fn display_text() -> Result<string> {
        return self.value()
    }
}
