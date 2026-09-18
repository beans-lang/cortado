package theme

import cortado.component
import cortado.render
import cortado.templates
import {CoffeeButton} from rendered_demo.generated.site

/// Replace the demo action's appearance while preserving its Button behavior.
pub class GalleryTemplates implements component.PopupTemplateFactory {
    defaults: templates.DefaultTemplates = new templates.DefaultTemplates()
    pub fn init() {}
    pub fn create(control: render.RenderObject) -> Option<component.ControlTemplate> {
        match control as? render.ButtonRender {
            some(_) => { if control.text() == "Order coffee" { return some(new CoffeeButton()) } }
            none => {}
        }
        return self.defaults.create(control)
    }
    pub fn create_popup(control: render.RenderObject) -> Option<component.ControlTemplate> {
        return self.defaults.create_popup(control)
    }
}
