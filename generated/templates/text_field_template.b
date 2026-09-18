// Generated from templates/text_field_template.bx by cortado. Do not edit.
//
// The <beans> block below is text_field_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change text_field_template.bx and regenerate:
//
//     cortado generate templates/text_field_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               

import cortado.component
import {view} from cortado.annotations

@view
pub partial class TextFieldTemplate extends component.ControlTemplate {
    pub fn init() { super.init() }
}

partial class TextFieldTemplate {
    pub override fn render(b: Builder) {
        b.open("Box")  // text_field_template.bx:1
        b.number("overhang", (self.field_overhang) as f64)
        b.number("width_percent", (100.0) as f64)
        b.number("height_percent", (100.0) as f64)
        b.word("background", self.field)
        b.number("corner_radius", (self.field_radius) as f64)
        b.number("border_width", (self.field_border_width) as f64)
        b.word("border_color", self.field_border)
        if self.focused {  // text_field_template.bx:4
            b.open("Rectangle")  // text_field_template.bx:5
            b.number("x", (0) as f64)
            b.number("y", (0) as f64)
            b.number("width_percent", (100.0) as f64)
            b.number("height_percent", (100.0) as f64)
            b.number("overhang", (self.field_overhang + self.focus_width / 2.0) as f64)
            b.number("corner_radius", (self.field_radius + self.focus_width / 2.0) as f64)
            b.word("fill", "#00000000")
            b.word("stroke", self.focus_ring)
            b.number("stroke_width", (self.focus_width) as f64)
            b.close()
        }
        b.close()
    }
}
