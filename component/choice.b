package component

import cortado.render

pub abstract class ChoiceControlTemplate extends ControlTemplate {
    pub choices: List<string> = []
    pub selected: int = -1
    pub highlighted: int = -1
    pub selected_text: string = ""
    version: int = -1
    pub fn init() { super.init() }
    pub override fn update(control: render.RenderObject, theme: render.Theme) {
        super.update(control, theme)
        match control as? render.ChoiceRender {
            some(choice) => {
                if self.version == choice.version() && self.selected == choice.selected() &&
                   self.highlighted == choice.highlighted() { return }
                self.version = choice.version()
                self.selected = choice.selected()
                self.highlighted = choice.highlighted()
                self.selected_text = choice.selected_text()
                self.choices = choice.choices()
                self.request_render()
            }
            none => {}
        }
    }
}
