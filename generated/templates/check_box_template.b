// Generated from templates/check_box_template.bx by cortado. Do not edit.
//
// The <beans> block below is check_box_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change check_box_template.bx and regenerate:
//
//     cortado generate templates/check_box_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class CheckBoxTemplate extends component.ToggleControlTemplate {
    pub fn init() { super.init() }
}

partial class CheckBoxTemplate {
    pub override fn render(b: Builder) {
        b.open("HStack")  // check_box_template.bx:1
        b.number("spacing", (8) as f64)
        b.word("align", "center")
        b.open("Label")  // check_box_template.bx:2
        b.text("{self.mark}")
        b.word("text_color", "#ffffffff")
        b.word("background", self.track)
        b.number("corner_radius", (4) as f64)
        b.number("width", (20) as f64)
        b.number("height", (20) as f64)
        b.close()
        b.open("Label")  // check_box_template.bx:4
        b.text("{self.title}")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.close()
        b.close()
    }
}
