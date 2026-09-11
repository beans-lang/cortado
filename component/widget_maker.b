// Turning a description into a real control.
package component

import cortado.widgets
import cortado.host

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
    pub static fn make(element: Element) -> Result<widgets.Widget> {
        var control: widgets.Widget = WidgetMaker.bare(element)?
        WidgetMaker.write_all(control, element)?
        if element.count() == 0 {
            return ok(control)
        }
        match control as? widgets.Container {
            some(box) => {
                for child: Element in element.children() {
                    box.add(WidgetMaker.make(child)?)?
                }
                return ok(control)
            }
            none => {}
        }
        match control as? widgets.ScrollView {
            some(scroller) => {
                for child: Element in element.children() {
                    scroller.add(WidgetMaker.make(child)?)?
                }
                return ok(control)
            }
            none => {}
        }
        return err("<{element.tag}> was given {element.count()} children but a {element.kind.name()} cannot hold any",
                   "not_a_container")
    }

    /// An empty control of the right kind.
    pub static fn bare(element: Element) -> Result<widgets.Widget> {
        match element.kind {
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
        }
    }

    /// Writes every attribute an element carries onto a control.
    pub static fn write_all(control: widgets.Widget, element: Element) -> Result<bool> {
        var index: int = 0
        for index: int in 0..element.attribute_count() {
            WidgetMaker.write(control, element.attribute_at(index))?
        }
        return ok(true)
    }

    /// Writes one attribute.
    pub static fn write(control: widgets.Widget, attribute: Attribute) -> Result<bool> {
        match attribute.kind {
            text => { return control.set_display_text(attribute.text) }
            real => { return control.set_property_real(attribute.property, attribute.number) }
            whole => { return control.set_property(attribute.property, attribute.whole) }
            flag => { return control.set_property(attribute.property, attribute.whole) }
        }
    }
}
