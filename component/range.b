package component

import cortado.render

pub abstract class RangeControlTemplate extends ControlTemplate {
    pub fraction: f64 = 0.0
    pub percent: f64 = 0.0
    pub number: string = "0"
    pub thumb_leading: f64 = 0.0
    pub indeterminate: bool = false

    pub fn init() { super.init() }

    pub override fn update(control: render.RenderObject, theme: render.Theme) {
        super.update(control, theme)
        match control as? render.RangeRender {
            some(range) => {
                let fraction: f64 = range.fraction()
                let percent: f64 = fraction * 100.0
                let number: string = "{range.value()}"
                let width: f64 = control.frame().width - 14.0
                let thumb_leading: f64 = fraction * (if width > 0.0 { width } else { 0.0 })
                var indeterminate: bool = false
                match range as? render.ProgressBarRender { some(progress) => { indeterminate = progress.indeterminate() } none => {} }
                if self.fraction == fraction && self.percent == percent && self.number == number &&
                   self.thumb_leading == thumb_leading && self.indeterminate == indeterminate { return }
                self.fraction = fraction; self.percent = percent; self.number = number
                self.thumb_leading = thumb_leading; self.indeterminate = indeterminate
                self.request_render()
            }
            none => {}
        }
    }
}
