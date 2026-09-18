// Generated from templates/slider_template.bx by cortado. Do not edit.
//
// The <beans> block below is slider_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change slider_template.bx and regenerate:
//
//     cortado generate templates/slider_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class SliderTemplate extends component.RangeControlTemplate {
    pub fn init() { super.init() }
}

partial class SliderTemplate {
    pub override fn render(b: Builder) {
        b.open("HStack")  // slider_template.bx:1
        b.word("background", "#d6d8df")
        b.number("corner_radius", (8) as f64)
        b.word("align", "center")
        b.open("Box")  // slider_template.bx:2
        b.number("width", (self.thumb_leading) as f64)
        b.number("height", (8) as f64)
        b.word("background", self.accent)
        b.number("corner_radius", (4) as f64)
        b.close()
        b.open("Box")  // slider_template.bx:3
        b.number("width", (14) as f64)
        b.number("height", (14) as f64)
        b.word("background", "#ffffffff")
        b.word("border_color", self.accent)
        b.number("border_width", (2) as f64)
        b.number("corner_radius", (7) as f64)
        b.close()
        b.open("Box")  // slider_template.bx:5
        b.number("grow", (1) as f64)
        b.close()
        b.close()
    }
}
