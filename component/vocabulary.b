// The names markup uses, and what they mean.
package component

import cortado.widgets
import cortado.events
import cortado.host
import cortado.layout
import cortado.geometry

/// Translates the names an author writes into the integers everything below
/// uses.
///
/// One table, in one place, consulted once per attribute per render. Markup
/// says `<Button title="Buy" on:click=… />`; the differ and the applier see
/// widget kind 3, property 0 and event 1. Keeping the translation here rather
/// than spreading it through the builder means adding a widget or a property
/// is one edit, and means the whole layer below is comparing integers.
///
/// Unknown names are refused rather than ignored. A misspelled attribute that
/// silently does nothing is the single most common way a user interface ends
/// up not matching the markup that describes it.
pub class Vocabulary {
    /// The widget behind a tag, or `none` for a tag cortado does not know.
    pub static fn kind_of(tag: string) -> Option<widgets.WidgetKind> {
        if tag == "VStack" || tag == "HStack" || tag == "VFlex" || tag == "HFlex" ||
           tag == "Grid" || tag == "Box" || tag == "Container" {
            return some(widgets.WidgetKind.container)
        }
        if tag == "Label" { return some(widgets.WidgetKind.label) }
        if tag == "Button" { return some(widgets.WidgetKind.button) }
        if tag == "TextField" { return some(widgets.WidgetKind.text_field) }
        if tag == "CheckBox" { return some(widgets.WidgetKind.check_box) }
        if tag == "Image" { return some(widgets.WidgetKind.image_view) }
        if tag == "Slider" { return some(widgets.WidgetKind.slider) }
        if tag == "ProgressBar" { return some(widgets.WidgetKind.progress_bar) }
        if tag == "Separator" { return some(widgets.WidgetKind.separator) }
        if tag == "TextArea" { return some(widgets.WidgetKind.text_area) }
        if tag == "ComboBox" { return some(widgets.WidgetKind.combo_box) }
        if tag == "ScrollView" { return some(widgets.WidgetKind.scroll_view) }
        if tag == "RadioButton" { return some(widgets.WidgetKind.radio_button) }
        if tag == "Canvas" { return some(widgets.WidgetKind.canvas) }
        if tag == "Switch" { return some(widgets.WidgetKind.switch) }
        if tag == "SecureField" { return some(widgets.WidgetKind.secure_field) }
        if tag == "Stepper" { return some(widgets.WidgetKind.stepper) }
        if tag == "LevelIndicator" { return some(widgets.WidgetKind.level_indicator) }
        if tag == "Table" { return some(widgets.WidgetKind.table) }
        if tag == "SearchField" { return some(widgets.WidgetKind.search_field) }
        if tag == "Spinner" { return some(widgets.WidgetKind.spinner) }
        return none
    }

    /// A fresh layout for a container tag. Fresh and not shared, because a
    /// layout holds the spacing and padding of the one container it belongs
    /// to; sharing one would make every `VStack` in an application take the
    /// spacing of whichever was configured last.
    pub static fn arranger_of(tag: string) -> Option<layout.Layout> {
        if tag == "VStack" { return some(layout.StackLayout.column(0.0)) }
        if tag == "HStack" { return some(layout.StackLayout.row(0.0)) }
        if tag == "VFlex" { return some(layout.FlexLayout.column(0.0)) }
        if tag == "HFlex" { return some(layout.FlexLayout.row(0.0)) }
        if tag == "Box" { return some(new layout.AbsoluteLayout()) }
        if tag == "Grid" { return some(layout.GridLayout.uniform(1, 0.0)) }
        return none
    }

    /// The host property an attribute name sets, or -1.
    pub static fn property_of(name: string) -> int {
        if name == "checked" { return host.P_CHECKED }
        if name == "enabled" { return host.P_ENABLED }
        if name == "hidden" { return host.P_HIDDEN }
        if name == "min" { return host.P_MIN }
        if name == "max" { return host.P_MAX }
        if name == "value" { return host.P_VALUE }
        if name == "editable" { return host.P_EDITABLE }
        if name == "alignment" { return host.P_ALIGNMENT }
        if name == "font_size" { return host.P_FONT_SIZE }
        if name == "step" { return host.P_STEP }
        if name == "selected" { return host.P_SELECTED }
        if name == "indeterminate" { return host.P_INDETERMINATE }
        if name == "opacity" { return host.P_OPACITY }
        return -1
    }

    /// How a property's value travels.
    pub static fn kind_of_property(name: string) -> AttributeKind {
        if name == "min" || name == "max" || name == "value" ||
           name == "font_size" || name == "step" || name == "opacity" {
            return AttributeKind.real
        }
        if name == "checked" || name == "alignment" || name == "selected" {
            return AttributeKind.whole
        }
        return AttributeKind.flag
    }

    /// The event an `on:` name subscribes to, or `none`.
    ///
    /// The names are the ones a web author already knows, mapped onto
    /// cortado's kinds. `click` is `activate` because a button is activated by
    /// a click, by the space bar, by a keyboard shortcut and by an
    /// accessibility client — a framework that named it `click` all the way
    /// down would tempt a handler into reading a mouse position that is not
    /// there.
    pub static fn event_of(name: string) -> Option<events.EventKind> {
        if name == "click" || name == "activate" { return some(events.EventKind.activate) }
        if name == "change" { return some(events.EventKind.value_changed) }
        if name == "commit" { return some(events.EventKind.text_commit) }
        if name == "select" { return some(events.EventKind.selection) }
        if name == "focus" { return some(events.EventKind.focus) }
        if name == "blur" { return some(events.EventKind.blur) }
        if name == "pointer_down" { return some(events.EventKind.pointer_down) }
        if name == "pointer_up" { return some(events.EventKind.pointer_up) }
        if name == "pointer_move" { return some(events.EventKind.pointer_move) }
        if name == "key_down" { return some(events.EventKind.key_down) }
        if name == "key_up" { return some(events.EventKind.key_up) }
        return none
    }

    /// Whether a name configures the layout rather than the control.
    ///
    /// `spacing`, `padding`, `justify` and `align` belong to the container's
    /// arrangement; `grow`, `shrink`, `basis`, `margin`, `width` and `height`
    /// belong to what this element asks of the run it sits in. Neither ever
    /// reaches the platform as a property, which is why they are separated
    /// here and not discovered by the applier finding no property id.
    pub static fn is_layout_name(name: string) -> bool {
        return name == "spacing" || name == "padding" || name == "justify" ||
               name == "align" || name == "grow" || name == "shrink" ||
               name == "basis" || name == "margin" || name == "width" ||
               name == "height"
    }

    pub static fn align_of(name: string) -> Option<geometry.Align> {
        if name == "start" { return some(geometry.Align.start) }
        if name == "center" { return some(geometry.Align.center) }
        if name == "end" { return some(geometry.Align.end) }
        if name == "stretch" { return some(geometry.Align.stretch) }
        return none
    }

    pub static fn justify_of(name: string) -> Option<layout.Justify> {
        if name == "start" { return some(layout.Justify.start) }
        if name == "center" { return some(layout.Justify.center) }
        if name == "end" { return some(layout.Justify.end) }
        if name == "space_between" { return some(layout.Justify.space_between) }
        if name == "space_around" { return some(layout.Justify.space_around) }
        if name == "space_evenly" { return some(layout.Justify.space_evenly) }
        return none
    }
}
