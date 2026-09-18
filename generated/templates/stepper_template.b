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
        b.open("Box")  // stepper_template.bx:1
        b.word("background", self.surface)
        b.number("corner_radius", (self.radius) as f64)
        b.number("width_percent", (100.0) as f64)
        b.number("height_percent", (100.0) as f64)
        b.open("Path")  // stepper_template.bx:3
        b.number("x", ((self.stepper_width - self.stepper_glyph_width) / 2.0) as f64)
        b.number("y", (self.stepper_glyph_top) as f64)
        b.number("width", (self.stepper_glyph_width) as f64)
        b.number("height", (self.stepper_glyph_height * 0.34) as f64)
        b.text("M0 {self.stepper_glyph_height * 0.34} L{self.stepper_glyph_width / 2.0} 0 L{self.stepper_glyph_width} {self.stepper_glyph_height * 0.34}")
        b.word("stroke", self.ink)
        b.number("stroke_width", (self.stepper_stroke) as f64)
        b.word("stroke_cap", "round")
        b.word("stroke_join", "round")
        b.word("fill", "#00000000")
        b.close()
        b.open("Box")  // stepper_template.bx:8
        b.number("x", ((self.stepper_width - self.stepper_glyph_width) / 2.0) as f64)
        b.number("y", (self.stepper_glyph_top + self.stepper_glyph_height / 2.0) as f64)
        b.number("width", (self.stepper_glyph_width) as f64)
        b.number("height", (self.hairline_width) as f64)
        b.word("background", self.separator)
        b.close()
        b.open("Path")  // stepper_template.bx:12
        b.number("x", ((self.stepper_width - self.stepper_glyph_width) / 2.0) as f64)
        b.number("y", (self.stepper_glyph_top + self.stepper_glyph_height * 0.66) as f64)
        b.number("width", (self.stepper_glyph_width) as f64)
        b.number("height", (self.stepper_glyph_height * 0.34) as f64)
        b.text("M0 0 L{self.stepper_glyph_width / 2.0} {self.stepper_glyph_height * 0.34} L{self.stepper_glyph_width} 0")
        b.word("stroke", self.ink)
        b.number("stroke_width", (self.stepper_stroke) as f64)
        b.word("stroke_cap", "round")
        b.word("stroke_join", "round")
        b.word("fill", "#00000000")
        b.close()
        b.close()
    }
}
