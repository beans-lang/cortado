// Generated from site/rating_control.bx by cortado. Do not edit.
//
// The <beans> block below is rating_control.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change rating_control.bx and regenerate:
//
//     cortado generate site/rating_control.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          
import cortado.component
import {view, param} from cortado.annotations
@view
pub partial class RatingControl extends component.Component {
    @param pub value: int = 0
    pub on_change: fn(int) = fn(_value: int) {}
    pub fn init() { super.init() }
    pub fn choose(value: int) {
        if value < 1 || value > 5 { return }
        let action: fn(int) = self.on_change
        action(value)
    }
}

partial class RatingControl {
    pub override fn render(b: Builder) {
        b.open("VStack")  // rating_control.bx:1
        b.number("spacing", (8) as f64)
        b.word("align", "stretch")
        b.open("Label")  // rating_control.bx:2
        b.text("Rating: {self.value} of 5")
        b.number("font_size", (18) as f64)
        b.close()
        b.open("HStack")  // rating_control.bx:3
        b.number("spacing", (8) as f64)
        b.flag("wrap", true)
        var _cortado_row_0: int = 0
        for score in 1..6 {  // rating_control.bx:4
            b.open("Button")  // rating_control.bx:5
            b.key("{"rating-{score}"}")
            b.text("{if score <= self.value { "★ {score}" } else { "☆ {score}" }}")
            b.on("click", fn(e: UiEvent) { self.choose(score) })
            b.close()
            _cortado_row_0 += 1
        }
        b.close()
        b.close()
    }
}
