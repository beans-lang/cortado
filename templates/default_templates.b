package templates

import cortado.component
import cortado.render
import {ButtonTemplate, TextFieldTemplate, CheckBoxTemplate, RadioButtonTemplate, SwitchTemplate,
        SliderTemplate, StepperTemplate, ProgressBarTemplate, LevelIndicatorTemplate,
        SeparatorTemplate, GroupBoxTemplate, DisclosureTemplate, ComboBoxTemplate,
        ComboBoxPopupTemplate, SegmentedTemplate, TabViewTemplate, SplitViewTemplate,
        TableTemplate} from cortado.generated.templates

pub class DefaultTemplates implements component.PopupTemplateFactory {
    pub fn init() {}
    pub fn create(control: render.RenderObject) -> Option<component.ControlTemplate> {
        match control as? render.ButtonRender {
            some(_) => { return some(new ButtonTemplate()) }
            none => {}
        }
        match control as? render.TextFieldRender {
            some(_) => { return some(new TextFieldTemplate()) }
            none => {}
        }
        match control as? render.CheckBoxRender { some(_) => { return some(new CheckBoxTemplate()) } none => {} }
        match control as? render.RadioButtonRender { some(_) => { return some(new RadioButtonTemplate()) } none => {} }
        match control as? render.SwitchRender { some(_) => { return some(new SwitchTemplate()) } none => {} }
        match control as? render.SliderRender { some(_) => { return some(new SliderTemplate()) } none => {} }
        match control as? render.StepperRender { some(_) => { return some(new StepperTemplate()) } none => {} }
        match control as? render.ProgressBarRender { some(_) => { return some(new ProgressBarTemplate()) } none => {} }
        match control as? render.LevelIndicatorRender { some(_) => { return some(new LevelIndicatorTemplate()) } none => {} }
        match control as? render.SeparatorRender { some(_) => { return some(new SeparatorTemplate()) } none => {} }
        match control as? render.GroupBoxRender { some(_) => { return some(new GroupBoxTemplate()) } none => {} }
        match control as? render.DisclosureRender { some(_) => { return some(new DisclosureTemplate()) } none => {} }
        match control as? render.ComboBoxRender { some(_) => { return some(new ComboBoxTemplate()) } none => {} }
        match control as? render.SegmentedRender { some(_) => { return some(new SegmentedTemplate()) } none => {} }
        match control as? render.TabViewRender { some(_) => { return some(new TabViewTemplate()) } none => {} }
        match control as? render.SplitViewRender { some(_) => { return some(new SplitViewTemplate()) } none => {} }
        match control as? render.TableRender { some(_) => { return some(new TableTemplate()) } none => {} }
        return none
    }
    pub fn create_popup(control: render.RenderObject) -> Option<component.ControlTemplate> {
        match control as? render.ComboBoxRender { some(_) => { return some(new ComboBoxPopupTemplate()) } none => {} }
        return none
    }
}
