// Generated from templates/button_template.bx by cortado. Do not edit.
//
// The <beans> block below is button_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change button_template.bx and regenerate:
//
//     cortado generate templates/button_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               

import cortado.component
import {view} from cortado.annotations

@view
pub partial class ButtonTemplate extends component.ControlTemplate {
    pub fn init() { super.init() }
}

partial class ButtonTemplate {
    pub override fn render(b: Builder) {
        b.open("VStack")  // button_template.bx:1
        b.word("background", self.fill)
        b.number("corner_radius", (self.radius) as f64)
        b.number("padding", (3) as f64)
        b.number("border_width", (1) as f64)
        b.word("border_color", if self.focused { self.accent } else { self.separator })
        b.word("align", "center")
        b.word("justify", "center")
        b.open("Label")  // button_template.bx:4
        b.text("{self.title}")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.number("alignment", (1) as f64)
        b.close()
        b.close()
    }
}
