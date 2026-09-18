// Generated from site/coffee_button.bx by cortado. Do not edit.
//
// The <beans> block below is coffee_button.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change coffee_button.bx and regenerate:
//
//     cortado generate site/coffee_button.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view} from cortado.annotations

@view
pub partial class CoffeeButton extends component.ControlTemplate {
    pub fn init() { super.init() }
}

partial class CoffeeButton {
    pub override fn render(b: Builder) {
        b.open("Box")  // coffee_button.bx:1
        b.open("Rectangle")  // coffee_button.bx:2
        b.word("fill", if self.pressed { "#282119" } else if self.hovered { "#98643c" } else { "#654632" })
        b.number("clip_radius", (14) as f64)
        b.number("transition_seconds", (0.18) as f64)
        b.word("transition_easing", "ease_in_out")
        b.close()
        b.open("HStack")  // coffee_button.bx:4
        b.number("padding", (8) as f64)
        b.number("spacing", (12) as f64)
        b.word("align", "center")
        b.word("justify", "center")
        b.number("border_width", (if self.focused { 2.0 } else { 0.0 }) as f64)
        b.word("border_color", "#d5a665")
        b.open("Label")  // coffee_button.bx:6
        b.text("+")
        b.number("font_size", (18) as f64)
        b.word("text_color", "#d5a665")
        b.close()
        b.open("Label")  // coffee_button.bx:7
        b.text("{self.title}")
        b.number("font_size", (self.font_size) as f64)
        b.word("text_color", "#ffffff")
        b.close()
        b.close()
        b.close()
    }
}
