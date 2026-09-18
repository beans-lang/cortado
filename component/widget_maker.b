// Turning a description into a real control.
package component

import cortado.widgets
import cortado.host
import cortado.render
import cortado.visual

/// Builds the native control an `Element` describes, and everything under it.
///
/// The one place in cortado that maps a `WidgetKind` onto a constructor.
/// Adding a widget means adding a case here and a tag to `Vocabulary`, and
/// `tests/roles.out` then carries it on every platform.
///
/// Children are built and attached depth first, so a container is complete
/// before it is handed to its own parent. That ordering is not free: a
/// platform that lays out on every `addSubview` would otherwise do it once per
/// child per level.
pub class WidgetMaker {
    /// The control for one element, with its properties set and its children
    /// built.
    pub static fn make(element: Element, context: Option<render.UiContext> = none) -> Result<widgets.Widget> {
        var control: widgets.Widget = WidgetMaker.bare(element, context)?
        if control.is_rendered() { control.render_object()? }
        WidgetMaker.write_all(control, element)?
        if control.is_rendered() {
            match control.render_object()? as? render.VisualRender {
                some(drawing) => { drawing.arm_transitions() }
                none => {}
            }
        }
        if element.count() == 0 {
            return ok(control)
        }
        match control as? widgets.ChildHolder {
            some(box) => {
                for child: Element in element.children() {
                    let built: widgets.Widget = WidgetMaker.make(child, context)?
                    box.add(built)?
                }
                match control as? widgets.TabView { some(tabs) => { tabs.validate_pages()? } none => {} }
                return ok(control)
            }
            none => {}
        }
        match control as? widgets.ScrollView {
            some(scroller) => {
                for child: Element in element.children() {
                    let built: widgets.Widget = WidgetMaker.make(child, context)?
                    scroller.add(built)?
                }
                return ok(control)
            }
            none => {}
        }
        return err("<{element.tag}> was given {element.count()} children but a {element.kind.name()} cannot hold any",
                   "not_a_container")
    }

    /// An empty control of the right kind.
    pub static fn bare(element: Element, context: Option<render.UiContext> = none) -> Result<widgets.Widget> {
        match visual.kind_of(element.tag) {
            some(shape) => {
                match context {
                    some(owner) => { return ok(new widgets.VisualWidget(shape, owner)) }
                    none => { return err("<{element.tag}> requires the shared renderer", "unsupported") }
                }
            }
            none => {}
        }
        return WidgetMaker.of_kind(element.kind, context)
    }

    /// An empty control of one kind, with no element behind it.
    ///
    /// The one exhaustive `match` over `WidgetKind` in cortado, and the reason
    /// it is public: a kind added to the enum is a **compile error here**, not
    /// a missing line in a golden somewhere. `tests/enabled.b` walks
    /// `WidgetKind.all()` through this, so the suite grows a row for a new
    /// kind whether or not anybody remembered to add one.
    pub static fn of_kind(kind: widgets.WidgetKind, context: Option<render.UiContext> = none) -> Result<widgets.Widget> {
        // Asked before anything is built, so `<Switch />` in markup on a
        // platform with no switch is a refusal naming the control rather than
        // a dead widget whose first attribute write complains about a handle.
        match context {
            some(owner) => {
                match kind {
                    container => { return ok(new widgets.Container(context)) }
                    label => { return ok(new widgets.Label(context)) }
                    button => { return ok(new widgets.Button(context)) }
                    text_field => { return ok(new widgets.TextField(context)) }
                    secure_field => { return ok(new widgets.SecureField(context)) }
                    search_field => { return ok(new widgets.SearchField(context)) }
                    text_area => { return ok(new widgets.TextArea(context)) }
                    scroll_view => { return ok(new widgets.ScrollView(context)) }
                    check_box => { return ok(new widgets.CheckBox(context)) }
                    radio_button => { return ok(new widgets.RadioButton(context)) }
                    switch => { return ok(new widgets.Switch(context)) }
                    slider => { return ok(new widgets.Slider(context)) }
                    stepper => { return ok(new widgets.Stepper(context)) }
                    progress_bar => { return ok(new widgets.ProgressBar(context)) }
                    level_indicator => { return ok(new widgets.LevelIndicator(context)) }
                    separator => { return ok(new widgets.Separator(context)) }
                    group_box => { return ok(new widgets.GroupBox(context)) }
                    disclosure => { return ok(new widgets.Disclosure(context)) }
                    combo_box => { return ok(new widgets.ComboBox(context)) }
                    segmented => { return ok(new widgets.Segmented(context)) }
                    tab_view => { return ok(new widgets.TabView(context)) }
                    split_view => { return ok(new widgets.SplitView(context)) }
                    table => { return ok(new widgets.Table(context)) }
                    _ => { return err("{kind.name()} has not migrated to the shared renderer", "not_migrated") }
                }
            }
            none => {}
        }
        kind.demand()?
        match kind {
            container => { return ok(new widgets.Container()) }
            label => { return ok(new widgets.Label()) }
            button => { return ok(new widgets.Button()) }
            text_field => { return ok(new widgets.TextField()) }
            check_box => { return ok(new widgets.CheckBox()) }
            image_view => { return ok(new widgets.ImageView()) }
            slider => { return ok(new widgets.Slider()) }
            progress_bar => { return ok(new widgets.ProgressBar()) }
            separator => { return ok(new widgets.Separator()) }
            text_area => { return ok(new widgets.TextArea()) }
            combo_box => { return ok(new widgets.ComboBox()) }
            scroll_view => { return ok(new widgets.ScrollView()) }
            radio_button => { return ok(new widgets.RadioButton()) }
            canvas => { return ok(new widgets.Canvas()) }
            switch => { return ok(new widgets.Switch()) }
            secure_field => { return ok(new widgets.SecureField()) }
            stepper => { return ok(new widgets.Stepper()) }
            level_indicator => { return ok(new widgets.LevelIndicator()) }
            table => { return ok(new widgets.Table()) }
            search_field => { return ok(new widgets.SearchField()) }
            spinner => { return ok(new widgets.Spinner()) }
            link => { return ok(new widgets.Link()) }
            segmented => { return ok(new widgets.Segmented()) }
            group_box => { return ok(new widgets.GroupBox()) }
            date_picker => { return ok(new widgets.DatePicker()) }
            color_well => { return ok(new widgets.ColorWell()) }
            disclosure => { return ok(new widgets.Disclosure()) }
            tab_view => { return ok(new widgets.TabView()) }
            split_view => { return ok(new widgets.SplitView()) }
            web_view => { return ok(new widgets.WebView()) }
            outline_view => { return ok(new widgets.OutlineView()) }
        }
    }

    /// Writes every attribute an element carries onto a control.
    ///
    /// A property this platform has not got is stepped over, not fatal: a
    /// screen written with `background="#2f6f4f"` still renders where nothing
    /// can be dressed, the same way a canvas renders where there is no GPU.
    /// Every other refusal stops the render, because it is about the program.
    pub static fn write_all(control: widgets.Widget, element: Element) -> Result<bool> {
        // Items establish the legal selection range. Markup attribute order
        // does not decide whether selected= may be applied.
        for index: int in 0..element.attribute_count() {
            let attribute: Attribute = element.attribute_at(index)
            if attribute.kind == AttributeKind.items { WidgetMaker.write(control, attribute)? }
        }
        for index: int in 0..element.attribute_count() {
            let attribute: Attribute = element.attribute_at(index)
            if attribute.kind == AttributeKind.numbers { WidgetMaker.write(control, attribute)? }
        }
        for index: int in 0..element.attribute_count() {
            let attribute: Attribute = element.attribute_at(index)
            if attribute.kind == AttributeKind.table_source { WidgetMaker.write(control, attribute)? }
        }
        var index: int = 0
        for index: int in 0..element.attribute_count() {
            if element.attribute_at(index).kind == AttributeKind.items ||
               element.attribute_at(index).kind == AttributeKind.numbers ||
               element.attribute_at(index).kind == AttributeKind.table_source { continue }
            match WidgetMaker.write(control, element.attribute_at(index)) {
                ok(done) => {}
                err(problem) => {
                    if control.is_rendered() || problem.kind != "unsupported" { return err(problem.msg, problem.kind) }
                }
            }
        }
        return ok(true)
    }

    /// Writes one attribute.
    pub static fn write(control: widgets.Widget, attribute: Attribute) -> Result<bool> {
        if attribute.reset && control.is_rendered() &&
           (attribute.property == visual.GRADIENT_START || attribute.property == visual.GRADIENT_END) {
            match control.render_object()? as? render.VisualRender {
                some(drawing) => { return drawing.reset_gradient(attribute.property) }
                none => {}
            }
        }
        if attribute.reset && control.is_rendered() && attribute.property == host.P_FG_COLOR {
            return control.render_object()?.clear_text_color()
        }
        match attribute.kind {
            text => {
                if attribute.property == host.S_A11Y_LABEL { return control.set_a11y_label(attribute.text) }
                return control.set_display_text(attribute.text)
            }
            real => { return control.set_property_real(attribute.property, attribute.number) }
            whole => {
                if attribute.property == host.P_SELECTED {
                    match control as? widgets.TabView { some(tabs) => { return tabs.set_page_from_markup(attribute.whole) } none => {} }
                }
                return control.set_property(attribute.property, attribute.whole)
            }
            flag => { return control.set_property(attribute.property, attribute.whole) }
            items => {
                match attribute.items_value {
                    none => { return err("items attribute has no list", "invalid") }
                    some(values) => {
                        if attribute.property == TAB_LABELS_PROPERTY {
                            match control as? widgets.TabView { some(tabs) => { return tabs.set_labels(values.to_list()) } none => {} }
                            return err("labels belongs on TabView", "unsupported")
                        }
                        if attribute.property == TABLE_COLUMNS_PROPERTY {
                            match control as? widgets.Table { some(table) => { return table.set_titles(values.to_list()) } none => {} }
                            return err("columns belongs on Table", "unsupported")
                        }
                        match control as? widgets.ComboBox { some(choice) => { return choice.set_items(values.to_list()) } none => {} }
                        match control as? widgets.Segmented { some(choice) => { return choice.set_items(values.to_list()) } none => {} }
                    }
                }
                return err("items belongs on ComboBox or Segmented", "unsupported")
            }
            numbers => {
                if attribute.property != TABLE_WIDTHS_PROPERTY { return err("unknown number list", "unsupported") }
                match control as? widgets.Table {
                    some(table) => {
                        if attribute.reset { return table.reset_widths() }
                        match attribute.numbers_value {
                            some(values) => { return table.set_widths(values.to_list()) }
                            none => { return err("column widths attribute has no list", "invalid") }
                        }
                    }
                    none => { return err("column widths belongs on Table", "unsupported") }
                }
            }
            table_source => {
                if attribute.property != TABLE_SOURCE_PROPERTY { return err("unknown table source", "unsupported") }
                match control as? widgets.Table {
                    some(table) => {
                        match attribute.source_value { some(rows) => { return table.set_source(rows) } none => { return table.clear_source() } }
                    }
                    none => { return err("source belongs on Table", "unsupported") }
                }
            }
            table_edit_policy => {
                if attribute.property != TABLE_EDIT_POLICY_PROPERTY { return err("unknown table edit policy", "unsupported") }
                match control as? widgets.Table {
                    some(table) => {
                        match attribute.edit_policy_value {
                            some(rule) => { return table.set_editable_when(rule.callback()) }
                            none => { return table.clear_editable() }
                        }
                    }
                    none => { return err("editable_when belongs on Table", "unsupported") }
                }
            }
        }
    }
}
