// Generated from templates/level_indicator_template.bx by cortado. Do not edit.
//
// The <beans> block below is level_indicator_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change level_indicator_template.bx and regenerate:
//
//     cortado generate templates/level_indicator_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class LevelIndicatorTemplate extends component.RangeControlTemplate {
    pub fn init() { super.init() }
}

partial class LevelIndicatorTemplate {
    pub override fn render(b: Builder) {
        b.open("HStack")  // level_indicator_template.bx:1
        b.word("align", "center")
        b.open("Box")  // level_indicator_template.bx:2
        b.number("width_percent", (self.percent) as f64)
        b.number("height", (5) as f64)
        b.word("background", self.accent)
        b.number("corner_radius", (self.radius_small) as f64)
        b.close()
        b.open("Box")  // level_indicator_template.bx:3
        b.number("grow", (1) as f64)
        b.number("height", (5) as f64)
        b.word("background", self.track_off)
        b.number("corner_radius", (self.radius_small) as f64)
        b.close()
        b.close()
    }
}
