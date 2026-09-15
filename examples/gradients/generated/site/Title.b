// Generated from site/Title.bx by cortado. Do not edit.
//
// The <beans> block below is Title.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change Title.bx and regenerate:
//
//     cortado generate site/Title.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view, param} from cortado.annotations

/// The title, as large as its own column can carry.
///
/// It is a component rather than three tags on the screen for one reason:
/// `cw` is a share of the box a component is laid out in, and a component is
/// the smallest thing that has one. Written on the screen it would have been a
/// share of the window — which is 45% wider than the column the title lands
/// in, once the padding and the colour chips beside it are taken off.
@view
pub partial class Title extends component.Component {
    @param pub caption: string = ""
    @param pub rate: string = ""

    pub fn init() { super.init() }
}

partial class Title {
    pub override fn render(b: Builder) {
        b.open("VStack")  // Title.bx:1
        b.word("justify", "center")
        b.word("align", "stretch")
        b.open("Label")  // Title.bx:4
        b.number("alignment", (1) as f64)
        b.number("font_size", (self.cw(10, 28, 64)) as f64)
        b.word("text_color", "#241c22")
        b.text("Petrichor")
        b.close()
        b.open("Label")  // Title.bx:6
        b.number("margin_top", (10) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (12) as f64)
        b.word("text_color", "#463c46")
        b.text("{self.caption}")
        b.close()
        b.open("Label")  // Title.bx:8
        b.number("margin_top", (6) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (11) as f64)
        b.word("text_color", "#6b6b74")
        b.text("{self.rate}")
        b.close()
        b.close()
    }
}
