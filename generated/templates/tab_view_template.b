// Generated from templates/tab_view_template.bx by cortado. Do not edit.
//
// The <beans> block below is tab_view_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change tab_view_template.bx and regenerate:
//
//     cortado generate templates/tab_view_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class TabViewTemplate extends component.TabControlTemplate {
    pub fn init() { super.init() }
}

partial class TabViewTemplate {
    pub override fn render(b: Builder) {
        b.open("VStack")  // tab_view_template.bx:1
        b.word("background", self.card)
        b.word("border_color", self.hairline)
        b.number("border_width", (1) as f64)
        b.number("corner_radius", (self.radius_medium) as f64)
        b.word("align", "stretch")
        if !self.borderless {  // tab_view_template.bx:3
            b.open("HStack")  // tab_view_template.bx:4
            b.number("height", (32) as f64)
            b.word("background", self.track_off)
            b.word("align", "stretch")
            b.number("spacing", (2) as f64)
            b.number("padding", (2) as f64)
            var _cortado_row_0: int = 0
            for index in 0..self.labels.len() {  // tab_view_template.bx:5
                b.open("Label")  // tab_view_template.bx:6
                b.key("{"tab-{index}"}")
                b.text("{self.labels[index]}")
                b.word("text_color", self.ink)
                b.word("background", if self.selected == index { self.background } else { "#00000000" })
                b.number("corner_radius", (self.radius_small) as f64)
                b.number("font_size", (self.font_size) as f64)
                b.number("grow", (1) as f64)
                b.number("alignment", (1) as f64)
                b.close()
                _cortado_row_0 += 1
            }
            b.close()
        }
        b.close()
    }
}
