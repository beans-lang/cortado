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
        b.word("border_color", self.separator)
        b.number("border_width", (self.hairline_width) as f64)
        b.number("corner_radius", (self.radius) as f64)
        b.word("align", "stretch")
        if !self.borderless {  // tab_view_template.bx:3
            b.open("HStack")  // tab_view_template.bx:6
            b.number("height", (self.control_height + self.spacing) as f64)
            b.word("align", "center")
            b.word("justify", "center")
            b.open("HStack")  // tab_view_template.bx:7
            b.word("background", self.surface)
            b.number("corner_radius", (self.radius) as f64)
            b.number("height", (self.control_height) as f64)
            b.word("align", "stretch")
            b.number("shrink", (0) as f64)
            var _cortado_row_0: int = 0
            for index in 0..self.labels.len() {  // tab_view_template.bx:9
                b.open("Box")  // tab_view_template.bx:10
                b.key("{"tab-{index}"}")
                b.number("padding_x", (self.segment_padding / 2.0) as f64)
                b.word("background", if self.selected == index { self.selection_fill } else { self.clear })
                b.number("corner_radius", (self.radius) as f64)
                b.open("Label")  // tab_view_template.bx:13
                b.text("{self.labels[index]}")
                b.word("text_color", if self.selected == index && self.active { self.on_accent } else { self.ink })
                b.number("font_weight", (if self.selected == index { self.selected_weight } else { 0 }) as f64)
                b.word("background", self.clear)
                b.number("font_size", (self.font_size) as f64)
                b.number("baseline", (self.baseline) as f64)
                b.number("alignment", (1) as f64)
                b.number("width_percent", (100.0) as f64)
                b.number("height_percent", (100.0) as f64)
                b.close()
                b.close()
                _cortado_row_0 += 1
            }
            b.close()
            b.close()
        }
        b.close()
    }
}
