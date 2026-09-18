// Generated from templates/switch_template.bx by cortado. Do not edit.
//
// The <beans> block below is switch_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change switch_template.bx and regenerate:
//
//     cortado generate templates/switch_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class SwitchTemplate extends component.ToggleControlTemplate {
    pub fn init() { super.init() }
}

partial class SwitchTemplate {
    pub override fn render(b: Builder) {
        b.open("HStack")  // switch_template.bx:1
        b.word("background", self.track)
        b.number("corner_radius", (14) as f64)
        b.number("padding", (3) as f64)
        b.word("align", "center")
        if self.checked {  // switch_template.bx:2
            b.open("Box")
            b.number("grow", (1) as f64)
            b.close()
        }
        b.open("Box")  // switch_template.bx:3
        b.number("width", (22) as f64)
        b.number("height", (22) as f64)
        b.word("background", "#ffffffff")
        b.number("corner_radius", (11) as f64)
        b.close()
        if !self.checked {  // switch_template.bx:4
            b.open("Box")
            b.number("grow", (1) as f64)
            b.close()
        }
        b.close()
    }
}
