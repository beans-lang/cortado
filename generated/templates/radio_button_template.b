// Generated from templates/radio_button_template.bx by cortado. Do not edit.
//
// The <beans> block below is radio_button_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change radio_button_template.bx and regenerate:
//
//     cortado generate templates/radio_button_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class RadioButtonTemplate extends component.ToggleControlTemplate {
    pub fn init() { super.init() }
}

partial class RadioButtonTemplate {
    pub override fn render(b: Builder) {
        b.open("HStack")  // radio_button_template.bx:1
        b.number("spacing", (8) as f64)
        b.word("align", "center")
        b.open("HStack")  // radio_button_template.bx:2
        b.word("background", "#00000000")
        b.word("border_color", self.track)
        b.number("border_width", (2) as f64)
        b.number("corner_radius", (self.capsule) as f64)
        b.number("width", (20) as f64)
        b.number("height", (20) as f64)
        b.word("align", "center")
        b.word("justify", "center")
        if self.checked {  // radio_button_template.bx:4
            b.open("Box")
            b.number("width", (10) as f64)
            b.number("height", (10) as f64)
            b.word("background", self.accent)
            b.number("corner_radius", (self.capsule) as f64)
            b.close()
        }
        b.close()
        b.open("Label")  // radio_button_template.bx:6
        b.text("{self.title}")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.close()
        b.close()
    }
}
