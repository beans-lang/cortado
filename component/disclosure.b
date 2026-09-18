package component

import cortado.render

pub abstract class DisclosureControlTemplate extends ControlTemplate {
    pub open: bool = false
    pub glyph: string = "▸"
    pub fn init() { super.init() }
    pub override fn update(control: render.RenderObject, theme: render.Theme) {
        super.update(control, theme)
        match control as? render.DisclosureRender {
            some(disclosure) => {
                let open: bool = disclosure.is_expanded()
                if self.open == open { return }
                self.open = open
                self.glyph = if open { "▾" } else { "▸" }
                self.request_render()
            }
            none => {}
        }
    }
}
