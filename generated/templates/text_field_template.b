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
        b.open("VStack")  // text_field_template.bx:1
        b.word("background", self.card)
        b.number("corner_radius", (self.radius_medium) as f64)
        b.number("border_width", (if self.focused { 2.0 } else { 1.0 }) as f64)
        b.word("border_color", if self.focused { self.accent } else { self.hairline })
        b.close()
    }
}
