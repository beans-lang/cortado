package component

import cortado.render

pub abstract class TabControlTemplate extends ControlTemplate {
    pub labels: List<string> = []
    pub selected: int = 0
    pub borderless: bool = false
    version: int = -1
    pub fn init() { super.init() }
    pub override fn update(control: render.RenderObject, theme: render.Theme) {
        super.update(control, theme)
        match control as? render.TabViewRender {
            some(tabs) => {
                if self.version == tabs.labels_version() && self.selected == tabs.selected() && self.borderless == tabs.borderless() { return }
                self.version = tabs.labels_version()
                self.selected = tabs.selected()
                self.borderless = tabs.borderless()
                self.labels = tabs.labels()
                self.request_render()
            }
            none => {}
        }
    }
}
