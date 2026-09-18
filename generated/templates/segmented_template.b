// Generated from templates/segmented_template.bx by cortado. Do not edit.
//
// The <beans> block below is segmented_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change segmented_template.bx and regenerate:
//
//     cortado generate templates/segmented_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class SegmentedTemplate extends component.ChoiceControlTemplate {
    pub fn init() { super.init() }
}

partial class SegmentedTemplate {
    pub override fn render(b: Builder) {
        b.open("HStack")  // segmented_template.bx:1
        b.word("background", "#d6d8df")
        b.number("corner_radius", (self.radius) as f64)
        b.number("padding", (2) as f64)
        b.word("align", "stretch")
        b.number("spacing", (2) as f64)
        var _cortado_row_0: int = 0
        for index in 0..self.choices.len() {  // segmented_template.bx:2
            b.open("Label")  // segmented_template.bx:3
            b.key("{"segment-{index}"}")
            b.text("{self.choices[index]}")
            b.word("text_color", if self.selected == index { "#ffffffff" } else { self.ink })
            b.word("background", if self.selected == index { self.accent } else { "#d6d8df" })
            b.number("corner_radius", (4) as f64)
            b.number("font_size", (self.font_size) as f64)
            b.number("grow", (1) as f64)
            b.close()
            _cortado_row_0 += 1
        }
        b.close()
    }
}
