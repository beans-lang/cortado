package component

import cortado.render

pub abstract class ToggleControlTemplate extends ControlTemplate {
    pub checked: bool = false
    pub mixed: bool = false
    pub mark: string = ""
    pub track: string = "#e9e9eaff"

    pub fn init() { super.init() }

    pub override fn update(control: render.RenderObject, theme: render.Theme) {
        super.update(control, theme)
        match control as? render.ToggleRender {
            some(toggle) => {
                let checked: bool = toggle.checked() == 1
                let mixed: bool = toggle.checked() == 2
                let mark: string = if mixed { "−" } else if checked { "✓" } else { "" }
                let track: string = if checked || mixed { self.accent } else { self.track_off }
                if self.checked == checked && self.mixed == mixed && self.mark == mark && self.track == track { return }
                self.checked = checked; self.mixed = mixed; self.mark = mark; self.track = track
                self.request_render()
            }
            none => {}
        }
    }
}
