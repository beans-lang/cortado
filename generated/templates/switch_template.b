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
        b.open("Box")  // switch_template.bx:1
        b.word("background", if self.checked { self.accent_fill } else { self.track_off })
        b.number("corner_radius", (self.capsule) as f64)
        b.number("width_percent", (100.0) as f64)
        b.number("height_percent", (100.0) as f64)
        b.open("Rectangle")  // switch_template.bx:3
        b.number("x", (if self.checked { self.switch_width - self.switch_inset - self.switch_knob_width } else { self.switch_inset }) as f64)
        b.number("y", (self.switch_inset) as f64)
        b.number("width", (self.switch_knob_width) as f64)
        b.number("height", (self.switch_knob_height) as f64)
        b.number("corner_radius", (self.switch_knob_height / 2.0) as f64)
        b.word("fill", self.knob)
        b.word("shadow_color", self.knob_shadow)
        b.number("shadow_blur", (1.5) as f64)
        b.number("shadow_dy", (0.5) as f64)
        b.close()
        b.close()
    }
}
