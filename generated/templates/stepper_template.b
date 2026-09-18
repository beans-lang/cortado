// Generated from templates/stepper_template.bx by cortado. Do not edit.
//
// The <beans> block below is stepper_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change stepper_template.bx and regenerate:
//
//     cortado generate templates/stepper_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class StepperTemplate extends component.RangeControlTemplate {
    pub fn init() { super.init() }
}

partial class StepperTemplate {
    pub override fn render(b: Builder) {
        b.open("HStack")  // stepper_template.bx:1
        b.word("background", self.fill)
        b.number("corner_radius", (6) as f64)
        b.word("align", "center")
        b.word("justify", "space_between")
        b.open("Label")  // stepper_template.bx:2
        b.text("−")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.close()
        b.open("Label")  // stepper_template.bx:3
        b.text("{self.number}")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.close()
        b.open("Label")  // stepper_template.bx:4
        b.text("+")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.close()
        b.close()
    }
}
