// What sort of control a widget is.
package widgets

import cortado.host

/// The kinds of control cortado can build.
///
/// One list, and every platform host answers all of it. A kind that some
/// platform cannot provide does not belong here — it belongs behind
/// `platform.Capability`, where a program can ask before it tries.
pub enum WidgetKind {
    container
    label
    button
    text_field
    check_box
    image_view
    slider
    progress_bar
    separator
    text_area
    combo_box
    scroll_view
    radio_button

    /// The number `cortado_host.h` uses for this kind.
    fn code() -> int {
        return match self {
            container => host.W_CONTAINER,
            label => host.W_LABEL,
            button => host.W_BUTTON,
            text_field => host.W_TEXT_FIELD,
            check_box => host.W_CHECK_BOX,
            image_view => host.W_IMAGE_VIEW,
            slider => host.W_SLIDER,
            progress_bar => host.W_PROGRESS_BAR,
            separator => host.W_SEPARATOR,
            text_area => host.W_TEXT_AREA,
            combo_box => host.W_COMBO_BOX,
            scroll_view => host.W_SCROLL_VIEW,
            radio_button => host.W_RADIO_BUTTON,
        }
    }

    /// The name the test dumps print.
    pub fn name() -> string {
        return match self {
            container => "Container",
            label => "Label",
            button => "Button",
            text_field => "TextField",
            check_box => "CheckBox",
            image_view => "ImageView",
            slider => "Slider",
            progress_bar => "ProgressBar",
            separator => "Separator",
            text_area => "TextArea",
            combo_box => "ComboBox",
            scroll_view => "ScrollView",
            radio_button => "RadioButton",
        }
    }

    pub static fn of(code: int) -> Option<WidgetKind> {
        if code == host.W_CONTAINER { return some(WidgetKind.container) }
        if code == host.W_LABEL { return some(WidgetKind.label) }
        if code == host.W_BUTTON { return some(WidgetKind.button) }
        if code == host.W_TEXT_FIELD { return some(WidgetKind.text_field) }
        if code == host.W_CHECK_BOX { return some(WidgetKind.check_box) }
        if code == host.W_IMAGE_VIEW { return some(WidgetKind.image_view) }
        if code == host.W_SLIDER { return some(WidgetKind.slider) }
        if code == host.W_PROGRESS_BAR { return some(WidgetKind.progress_bar) }
        if code == host.W_SEPARATOR { return some(WidgetKind.separator) }
        if code == host.W_TEXT_AREA { return some(WidgetKind.text_area) }
        if code == host.W_COMBO_BOX { return some(WidgetKind.combo_box) }
        if code == host.W_SCROLL_VIEW { return some(WidgetKind.scroll_view) }
        if code == host.W_RADIO_BUTTON { return some(WidgetKind.radio_button) }
        return none
    }
}
