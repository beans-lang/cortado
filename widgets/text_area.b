// Text across many lines.
package widgets

import cortado.host

/// A multi-line, scrolling text control.
///
/// Not a `TextField` with a taller frame. Every platform makes these two
/// different objects — `NSTextView` inside an `NSScrollView`, an `EDIT` with
/// `ES_MULTILINE`, a `GtkTextView` — and they differ in what Return does, in
/// what the caret keys do at a line end, and in whether the text scrolls when
/// it outgrows the box. A field stretched to five lines is a field whose
/// bottom is simply not visible.
pub class TextArea extends Widget {
    pub fn init() {
        super.init(WidgetKind.text_area)
    }

    pub static fn of(text: string) -> Result<TextArea> {
        var control: TextArea = new TextArea()
        control.set_text(text)?
        return ok(control)
    }

    pub fn set_text(text: string) -> Result<bool> {
        return self.set_text_raw(text)
    }

    pub fn text() -> Result<string> {
        return self.text_raw()
    }

    pub override fn display_text() -> Result<string> {
        return self.text_raw()
    }
}
