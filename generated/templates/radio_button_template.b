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
        b.number("spacing", (self.toggle_gap) as f64)
        b.word("align", "start")
        b.open("Box")  // radio_button_template.bx:2
        b.number("width", (self.toggle_size) as f64)
        b.number("height", (self.toggle_size) as f64)
        b.word("background", if self.checked { self.accent_fill } else { self.track_off })
        b.number("corner_radius", (self.capsule) as f64)
        if self.checked {  // radio_button_template.bx:5
            b.open("Ellipse")  // radio_button_template.bx:6
            b.number("x", (self.toggle_size * 0.34375) as f64)
            b.number("y", (self.toggle_size * 0.34375) as f64)
            b.number("width", (self.toggle_size * 0.3125) as f64)
            b.number("height", (self.toggle_size * 0.3125) as f64)
            b.word("fill", self.on_accent)
            b.close()
        }
        b.close()
        b.open("Label")  // radio_button_template.bx:11
        b.text("{self.title}")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.number("baseline", (self.toggle_baseline) as f64)
        b.number("grow", (1) as f64)
        b.number("height", (self.toggle_size) as f64)
        b.close()
        b.close()
    }
}
