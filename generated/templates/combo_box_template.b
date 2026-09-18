// Generated from templates/combo_box_template.bx by cortado. Do not edit.
//
// The <beans> block below is combo_box_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change combo_box_template.bx and regenerate:
//
//     cortado generate templates/combo_box_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class ComboBoxTemplate extends component.ChoiceControlTemplate {
    pub fn init() { super.init() }
}

partial class ComboBoxTemplate {
    pub override fn render(b: Builder) {
        b.open("HStack")  // combo_box_template.bx:1
        b.word("background", self.fill)
        b.word("border_color", if self.focused { self.accent } else { "#00000000" })
        b.number("border_width", (if self.focused { 2.0 } else { 0.0 }) as f64)
        b.number("corner_radius", (self.radius_medium) as f64)
        b.number("padding", (6) as f64)
        b.word("align", "center")
        b.number("spacing", (8) as f64)
        b.open("Label")  // combo_box_template.bx:4
        b.text("{self.selected_text}")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.number("grow", (1) as f64)
        b.close()
        b.open("Label")  // combo_box_template.bx:5
        b.text("⌄")
        b.word("text_color", self.accent)
        b.number("font_size", (self.font_size) as f64)
        b.close()
        b.close()
    }
}
