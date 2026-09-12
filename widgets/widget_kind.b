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
    /// Somewhere a program draws for itself, with a shader.
    ///
    /// A control on every host — laid out by the solver, in the tree, with an
    /// accessibility role — and on the hosts with no GPU it is simply an empty
    /// area rather than a missing one. `gpu.Device` is what fills it.
    canvas
    /// On or off — and **the first kind that is not on every platform**.
    ///
    /// `NSSwitch`, `UISwitch`, `GtkSwitch`; the Win32 common controls have
    /// none, and `available()` says so rather than cortado drawing one or
    /// quietly handing back a check box.
    switch
    /// A line of text the platform shows as dots, and keeps out of the
    /// pasteboard, out of dictation and off a screen recording.
    secure_field
    /// Two little arrows that step a number.
    stepper
    /// How full something is, drawn rather than typed into — and **not on
    /// every platform**: `NSLevelIndicator` and `GtkLevelBar` exist, UIKit
    /// and the Win32 common controls have nothing that means it.
    level_indicator
    /// Rows and columns, filled by asking rather than by building.
    table
    /// A text field that says what it is for.
    search_field
    /// Something is happening and nobody knows for how long — and **not on
    /// every platform**: the Win32 common controls have no spinner.
    spinner

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
            canvas => host.W_CANVAS,
            switch => host.W_SWITCH,
            secure_field => host.W_SECURE_FIELD,
            stepper => host.W_STEPPER,
            level_indicator => host.W_LEVEL_INDICATOR,
            table => host.W_TABLE,
            search_field => host.W_SEARCH_FIELD,
            spinner => host.W_SPINNER,
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
            canvas => "Canvas",
            switch => "Switch",
            secure_field => "SecureField",
            stepper => "Stepper",
            level_indicator => "LevelIndicator",
            table => "Table",
            search_field => "SearchField",
            spinner => "Spinner",
        }
    }

    /// Whether the platform running this program can build one.
    ///
    /// Most kinds answer yes everywhere and this is a question nobody needs to
    /// ask. `switch` is the one that does not: the Win32 common controls have
    /// no toggle switch, and cortado will not draw an imitation or quietly
    /// hand back a check box. The note beside `ctd_widget_supports` in
    /// `src/cortado_host.h` is the argument in full.
    pub fn available() -> bool {
        unsafe {
            return host.ctd_widget_supports(self.code() as i32) == 1
        }
    }

    /// Whether being checked is what this control *is*.
    ///
    /// cortado's rule rather than any platform's, and the reason it is here in
    /// Beans as well as in `src/cortado_rules.h` is that a test which asked
    /// the host which kinds carry the property and then checked those kinds
    /// would agree with any answer at all. Stated twice, compared once.
    pub fn has_state() -> bool {
        match self {
            check_box => { return true }
            radio_button => { return true }
            switch => { return true }
            container => { return false }
            label => { return false }
            button => { return false }
            text_field => { return false }
            image_view => { return false }
            slider => { return false }
            progress_bar => { return false }
            separator => { return false }
            text_area => { return false }
            combo_box => { return false }
            scroll_view => { return false }
            canvas => { return false }
            secure_field => { return false }
            stepper => { return false }
            level_indicator => { return false }
            table => { return false }
            search_field => { return false }
            spinner => { return false }
        }
    }

    /// Whether the host recognises a raw kind number at all.
    ///
    /// `available()` asks about a kind cortado has a name for, so it can only
    /// ever be answered yes or no. This asks about a *number*, and it is here
    /// because a host has a third answer and something has to check that it
    /// gives it: a code that is not a kind must be refused as out of range,
    /// not reported as a control this platform happens not to have. A caller
    /// that cannot tell those apart reads a typo as a platform difference.
    pub static fn is_a_kind(code: int) -> bool {
        unsafe {
            return host.ctd_widget_supports(code as i32) >= 0
        }
    }

    /// The same question as a refusal, for a constructor to lead with.
    ///
    /// Without it the first property write on a control that was never built
    /// fails with `stale_handle` — a message about a handle, for a problem
    /// about a platform, arriving one call after the one that could have
    /// explained it.
    pub fn demand() -> Result<bool> {
        if self.available() { return ok(true) }
        return err("this platform has no {self.name()} control", "no_such_control")
    }

    /// Every kind, in the order they are declared above.
    ///
    /// Hand-written, because Beans has no way to enumerate an enum's cases —
    /// and hand-written lists drift, so `tools/check_vocabulary.sh` holds this
    /// one to the declarations above. That gate is not decoration: before it
    /// existed, `canvas` was added to this enum and never reached
    /// `tests/enabled.b`, which walks the kinds by hand. The golden lost a
    /// line and stayed green, because a list that is one short looks exactly
    /// like a list.
    pub static fn all() -> List<WidgetKind> {
        var every: List<WidgetKind> = []
        every.push(WidgetKind.container)
        every.push(WidgetKind.label)
        every.push(WidgetKind.button)
        every.push(WidgetKind.text_field)
        every.push(WidgetKind.check_box)
        every.push(WidgetKind.image_view)
        every.push(WidgetKind.slider)
        every.push(WidgetKind.progress_bar)
        every.push(WidgetKind.separator)
        every.push(WidgetKind.text_area)
        every.push(WidgetKind.combo_box)
        every.push(WidgetKind.scroll_view)
        every.push(WidgetKind.radio_button)
        every.push(WidgetKind.canvas)
        every.push(WidgetKind.switch)
        every.push(WidgetKind.secure_field)
        every.push(WidgetKind.stepper)
        every.push(WidgetKind.level_indicator)
        every.push(WidgetKind.table)
        every.push(WidgetKind.search_field)
        every.push(WidgetKind.spinner)
        return move every
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
        if code == host.W_CANVAS { return some(WidgetKind.canvas) }
        if code == host.W_SWITCH { return some(WidgetKind.switch) }
        if code == host.W_SECURE_FIELD { return some(WidgetKind.secure_field) }
        if code == host.W_STEPPER { return some(WidgetKind.stepper) }
        if code == host.W_LEVEL_INDICATOR { return some(WidgetKind.level_indicator) }
        if code == host.W_TABLE { return some(WidgetKind.table) }
        if code == host.W_SEARCH_FIELD { return some(WidgetKind.search_field) }
        if code == host.W_SPINNER { return some(WidgetKind.spinner) }
        return none
    }
}
