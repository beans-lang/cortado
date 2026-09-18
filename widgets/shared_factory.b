package widgets

import cortado.render
import cortado.visual

/// The migration boundary. A kind is either implemented in shared Beans code
/// or refused; it never quietly allocates a native control inside the surface.
pub class SharedFactory {
    pub static fn make(kind: WidgetKind, context: render.UiContext,
                       drawing: Option<visual.Kind> = none) -> Result<render.RenderObject> {
        match drawing {
            some(shape) => {
                if kind != WidgetKind.canvas { return err("drawing kind requires a canvas node", "wrong_kind") }
                return ok(new render.VisualRender(context.renderer(), context.theme(), context.invalidation(), shape))
            }
            none => {}
        }
        match kind {
            container => { return ok(new render.BoxRender(context.renderer(), context.theme(), context.invalidation())) }
            label => { return ok(new render.TextRender(context.renderer(), context.theme(), context.invalidation())) }
            button => { return ok(new render.ButtonRender(context.renderer(), context.theme(), context.invalidation())) }
            text_field => { return ok(new render.TextFieldRender(context.renderer(), context.theme(), context.invalidation())) }
            secure_field => { return ok(new render.SecureFieldRender(context.renderer(), context.theme(), context.invalidation())) }
            search_field => { return ok(new render.SearchFieldRender(context.renderer(), context.theme(), context.invalidation())) }
            text_area => { return ok(new render.TextAreaRender(context.renderer(), context.theme(), context.invalidation())) }
            scroll_view => { return ok(new render.ScrollRender(context.renderer(), context.theme(), context.invalidation())) }
            check_box => { return ok(new render.CheckBoxRender(context.renderer(), context.theme(), context.invalidation())) }
            radio_button => { return ok(new render.RadioButtonRender(context.renderer(), context.theme(), context.invalidation())) }
            switch => { return ok(new render.SwitchRender(context.renderer(), context.theme(), context.invalidation())) }
            slider => { return ok(new render.SliderRender(context.renderer(), context.theme(), context.invalidation())) }
            stepper => { return ok(new render.StepperRender(context.renderer(), context.theme(), context.invalidation())) }
            progress_bar => { return ok(new render.ProgressBarRender(context.renderer(), context.theme(), context.invalidation())) }
            level_indicator => { return ok(new render.LevelIndicatorRender(context.renderer(), context.theme(), context.invalidation())) }
            separator => { return ok(new render.SeparatorRender(context.renderer(), context.theme(), context.invalidation())) }
            group_box => { return ok(new render.GroupBoxRender(context.renderer(), context.theme(), context.invalidation())) }
            disclosure => { return ok(new render.DisclosureRender(context.renderer(), context.theme(), context.invalidation())) }
            combo_box => { return ok(new render.ComboBoxRender(context.renderer(), context.theme(), context.invalidation())) }
            segmented => { return ok(new render.SegmentedRender(context.renderer(), context.theme(), context.invalidation())) }
            tab_view => { return ok(new render.TabViewRender(context.renderer(), context.theme(), context.invalidation())) }
            split_view => { return ok(new render.SplitViewRender(context.renderer(), context.theme(), context.invalidation())) }
            table => { return ok(new render.TableRender(context.renderer(), context.theme(), context.invalidation())) }
            _ => { return err("{kind.name()} has not migrated to the shared renderer", "not_migrated") }
        }
    }
}
