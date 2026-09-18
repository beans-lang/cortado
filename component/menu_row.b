package component

import cortado.render

/// A button standing in for a menu row: the mark it carries and whether the
/// pointer or keyboard is on it. The row's behaviour stays the button's.
pub abstract class MenuRowControlTemplate extends ControlTemplate {
    pub checked: bool = false
    pub fn init() { super.init() }
    pub override fn update(control: render.RenderObject, theme: render.Theme) {
        super.update(control, theme)
        match control as? render.ButtonRender {
            some(button) => {
                if self.checked == button.checked() { return }
                self.checked = button.checked()
                self.request_render()
            }
            none => {}
        }
    }
}
