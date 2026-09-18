// Generated from templates/disclosure_template.bx by cortado. Do not edit.
//
// The <beans> block below is disclosure_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change disclosure_template.bx and regenerate:
//
//     cortado generate templates/disclosure_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class DisclosureTemplate extends component.DisclosureControlTemplate {
    pub fn init() { super.init() }
}

partial class DisclosureTemplate {
    pub override fn render(b: Builder) {
        b.open("VStack")  // disclosure_template.bx:1
        b.word("background", self.fill)
        b.number("corner_radius", (self.radius) as f64)
        b.word("align", "stretch")
        b.open("HStack")  // disclosure_template.bx:2
        b.number("spacing", (7) as f64)
        b.number("padding", (7) as f64)
        b.word("align", "center")
        b.open("Label")  // disclosure_template.bx:3
        b.text("{self.glyph}")
        b.word("text_color", self.accent)
        b.number("font_size", (self.font_size) as f64)
        b.close()
        b.open("Label")  // disclosure_template.bx:4
        b.text("{self.title}")
        b.word("text_color", self.ink)
        b.number("font_size", (self.font_size) as f64)
        b.close()
        b.close()
        b.close()
    }
}
