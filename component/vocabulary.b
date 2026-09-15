// The names markup uses, and what they mean.
package component

import cortado.widgets
import cortado.events
import cortado.host
import cortado.platform
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
        if tag == "VStack" || tag == "HStack" ||
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
        if tag == "Link" { return some(widgets.WidgetKind.link) }
        if tag == "Segmented" { return some(widgets.WidgetKind.segmented) }
        if tag == "GroupBox" { return some(widgets.WidgetKind.group_box) }
        if tag == "DatePicker" { return some(widgets.WidgetKind.date_picker) }
        if tag == "ColorWell" { return some(widgets.WidgetKind.color_well) }
        if tag == "Disclosure" { return some(widgets.WidgetKind.disclosure) }
        if tag == "TabView" { return some(widgets.WidgetKind.tab_view) }
        if tag == "SplitView" { return some(widgets.WidgetKind.split_view) }
        if tag == "WebView" { return some(widgets.WidgetKind.web_view) }
        if tag == "OutlineView" { return some(widgets.WidgetKind.outline_view) }
        return none
    }

    /// A fresh layout for a container tag. Fresh and not shared, because a
    /// layout holds the spacing and padding of the one container it belongs
    /// to; sharing one would make every `VStack` in an application take the
    /// spacing of whichever was configured last.
    pub static fn arranger_of(tag: string) -> Option<layout.Layout> {
        // Every stack flexes: grow and shrink share the leftover, and `wrap`
        // breaks it into lines. `StackLayout` stays for hand-built trees.
        if tag == "VStack" { return some(layout.FlexLayout.column(0.0)) }
        if tag == "HStack" { return some(layout.FlexLayout.row(0.0)) }
        if tag == "Box" { return some(new layout.AbsoluteLayout()) }
        // No columns declared: `columns` or `min_column` says what they are,
        // and a grid that is told neither is the one column it always was.
        if tag == "Grid" { return some(new layout.GridLayout()) }
        // The containers that hold a subtree and have nothing to say about
        // where it goes. Without an arranger a node is a leaf, and a leaf
        // places none of its children — so before this line every control
        // inside a `<GroupBox>` in markup came out at 0,0,0,0, laid out
        // correctly by a layout that had decided there was nothing to lay out.
        //
        // `Container` and `Canvas` are deliberately not here. A bare
        // `<Container />` is a box a program fills itself, and a canvas is
        // drawn rather than filled; giving either one children that fill it
        // would change what those two tags have always meant.
        // A scroll view fills like the rest, except on the axis it scrolls:
        // its content is measured with no ceiling, or nothing ever scrolls.
        if tag == "ScrollView" { return some(new layout.ScrollLayout()) }
        if tag == "GroupBox" || tag == "Disclosure" ||
           tag == "TabView" || tag == "SplitView" {
            return some(new layout.FillLayout())
        }
        return none
    }

    /// The sentence for a container tag that no longer exists, or `""`.
    /// Mirrors `bx.retired_tag`; `tools/check_vocabulary.sh` holds them together.
    pub static fn retired(tag: string) -> string {
        if tag == "VFlex" { return "<VFlex> is retired: every <VStack> shares out its leftover by grow and shrink now — write <VStack>" }
        if tag == "HFlex" { return "<HFlex> is retired: every <HStack> shares out its leftover by grow and shrink now — write <HStack>" }
        if tag == "VWrap" { return "<VWrap> is retired: wrapping is an attribute of a stack now — write <VStack wrap>" }
        if tag == "HWrap" { return "<HWrap> is retired: wrapping is an attribute of a stack now — write <HStack wrap>" }
        return ""
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
        // A role is a size, so it lands on the same property — and two
        // names on one property is what makes the last one written win.
        if name == "font_role" { return host.P_FONT_SIZE }
        if name == "step" { return host.P_STEP }
        if name == "selected" { return host.P_SELECTED }
        if name == "indeterminate" { return host.P_INDETERMINATE }
        if name == "opacity" { return host.P_OPACITY }
        if name == "lines" { return host.P_LINES }
        if name == "day" { return host.P_DATE }
        if name == "color" { return host.P_COLOR }
        if name == "open" { return host.P_EXPANDED }
        if name == "animating" { return host.P_ANIMATING }
        if name == "background" { return host.P_BG_COLOR }
        if name == "corner_radius" { return host.P_CORNER_RADIUS }
        if name == "border_width" { return host.P_BORDER_WIDTH }
        if name == "border_color" { return host.P_BORDER_COLOR }
        if name == "text_color" { return host.P_FG_COLOR }
        return -1
    }

    /// Whether a control of `kind` carries the attribute `name`.
    ///
    /// Asked of the host, so there is one answer rather than a copy above the
    /// ABI. A name that is not a property answers `true`: layout names belong
    /// to no control, and an unknown name is refused before this is reached.
    pub static fn carries(kind: widgets.WidgetKind, name: string) -> bool {
        let property: int = Vocabulary.property_of(name)
        if property < 0 { return true }
        var answer: int = 0
        unsafe {
            answer = host.ctd_kind_carries(kind.code() as i32,
                                           host.KEY_PROPERTY as i32,
                                           property as i32) as int
        }
        return answer == 1
    }

    /// One column of a track list: `160` points, `1fr` a share of what is
    /// left, `auto` the widest child in it.
    pub static fn track_of(word: string) -> Option<layout.Track> {
        if word == "auto" { return some(layout.Track.auto()) }
        if word.ends_with("fr") {
            match word.slice(0, word.len() - 2).to_float() {
                err(problem) => { return none }
                ok(weight) => {
                    if weight <= 0.0 { return none }
                    return some(layout.Track.fraction(weight))
                }
            }
        }
        match word.to_float() {
            err(problem) => { return none }
            ok(points) => {
                if points < 0.0 { return none }
                return some(layout.Track.fixed(points))
            }
        }
    }

    /// The system font role a word names, or `none`. `mono` is deliberately
    /// absent: it is body's size in another family, and a family is not a
    /// property a control carries.
    pub static fn font_role_of(word: string) -> Option<platform.SystemFont> {
        if word == "body" { return some(platform.SystemFont.body) }
        if word == "heading" { return some(platform.SystemFont.heading) }
        if word == "caption" { return some(platform.SystemFont.caption) }
        return none
    }

    /// Whether this attribute's value is a colour, written `#rgb`, `#rrggbb`
    /// or `#rrggbbaa`. Mirrors `bx.is_colour_attribute`.
    pub static fn is_colour(name: string) -> bool {
        return name == "color" || name == "background" ||
               name == "border_color" || name == "text_color"
    }

    /// Which controls carry `name`, for a refusal that says where it belongs.
    pub static fn who_carries(name: string) -> string {
        var carried: List<string> = []
        for kind: widgets.WidgetKind in widgets.WidgetKind.all() {
            if Vocabulary.carries(kind, name) { carried.push(kind.name()) }
        }
        if carried.len() == 0 { return "no control carries it" }
        return "{name} is carried by {carried.join(", ")}"
    }

    /// How a property's value travels.
    pub static fn kind_of_property(name: string) -> AttributeKind {
        if name == "min" || name == "max" || name == "value" ||
           name == "font_size" || name == "step" || name == "opacity" ||
           name == "day" || name == "corner_radius" || name == "border_width" {
            return AttributeKind.real
        }
        // A colour travels as a whole number, packed 0xRRGGBBAA — the same
        // integer the ABI carries and the same one a value_changed event
        // hands back. It is written in markup as `#rrggbbaa`, and `Builder`
        // is what turns the one into the other.
        if name == "checked" || name == "alignment" || name == "selected" ||
           name == "lines" || Vocabulary.is_colour(name) {
            return AttributeKind.whole
        }
        if name == "open" || name == "animating" { return AttributeKind.flag }
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
    ///
    /// The per-edge insets are written out one by one because
    /// `tools/check_vocabulary.sh` reads this list and holds `bx/widgets.b` to it.
    pub static fn is_layout_name(name: string) -> bool {
        return name == "spacing" || name == "line_spacing" || name == "padding" || name == "justify" ||
               name == "align" || name == "grow" || name == "shrink" ||
               name == "basis" || name == "flex" || name == "wrap" ||
               name == "margin" || name == "width" ||
               name == "height" || name == "x" || name == "y" ||
               name == "padding_x" || name == "padding_y" ||
               name == "padding_top" || name == "padding_right" ||
               name == "padding_bottom" || name == "padding_left" ||
               name == "margin_x" || name == "margin_y" ||
               name == "margin_top" || name == "margin_right" ||
               name == "margin_bottom" || name == "margin_left" ||
               name == "min_width" || name == "max_width" ||
               name == "min_height" || name == "max_height" ||
               name == "width_percent" || name == "height_percent" ||
               name == "aspect_ratio" ||
               name == "hide_below" || name == "hide_above" ||
               name == "right" || name == "bottom" || name == "align_self" ||
               name == "columns" || name == "min_column" || name == "max_column" ||
               name == "column_gap" || name == "row_gap"
    }

    /// Whether a component tag may carry `name`: what the component's root asks
    /// of the run around it, written by the parent that places it.
    pub static fn is_placement_name(name: string) -> bool {
        return name == "margin" || name == "margin_x" || name == "margin_y" ||
               name == "margin_top" || name == "margin_right" ||
               name == "margin_bottom" || name == "margin_left" ||
               name == "grow" || name == "shrink" || name == "basis" || name == "flex" ||
               name == "width" || name == "height" ||
               name == "min_width" || name == "max_width" ||
               name == "min_height" || name == "max_height" ||
               name == "width_percent" || name == "height_percent" ||
               name == "aspect_ratio" ||
               name == "hide_below" || name == "hide_above" ||
               name == "x" || name == "y" || name == "right" || name == "bottom" ||
               name == "align" || name == "align_self"
    }

    /// The edge a padding name writes: `top`, `right`, `bottom`, `left`, `x` for
    /// both sides or `y` for top and bottom. `""` for anything else, `padding` included.
    pub static fn padding_edge(name: string) -> string {
        if name == "padding_x" { return "x" }
        if name == "padding_y" { return "y" }
        if name == "padding_top" { return "top" }
        if name == "padding_right" { return "right" }
        if name == "padding_bottom" { return "bottom" }
        if name == "padding_left" { return "left" }
        return ""
    }

    /// The same for margin: `margin_left` writes `left`, `margin_y` writes
    /// top and bottom, and `margin` itself answers `""`.
    pub static fn margin_edge(name: string) -> string {
        if name == "margin_x" { return "x" }
        if name == "margin_y" { return "y" }
        if name == "margin_top" { return "top" }
        if name == "margin_right" { return "right" }
        if name == "margin_bottom" { return "bottom" }
        if name == "margin_left" { return "left" }
        return ""
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
