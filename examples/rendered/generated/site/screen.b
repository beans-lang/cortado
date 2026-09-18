// Generated from site/screen.bx by cortado. Do not edit.
//
// The <beans> block below is screen.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change screen.bx and regenerate:
//
//     cortado generate site/screen.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view} from cortado.annotations

@view
pub partial class Screen extends component.Component {
    pub name: string = ""
    pub orders: int = 0
    pub fn init() { super.init() }
    pub fn order() { self.orders += 1; self.request_render() }
}

partial class Screen {
    pub override fn render(b: Builder) {
        b.open("VStack")  // screen.bx:1
        b.number("padding", (24) as f64)
        b.number("spacing", (14) as f64)
        b.word("align", "stretch")
        b.open("Label")  // screen.bx:2
        b.text("Cortado, drawn by Beans")
        b.number("font_size", (26) as f64)
        b.close()
        b.open("Label")  // screen.bx:3
        b.text("This entire screen is .bx markup.")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("TextField")  // screen.bx:4
        b.key("{"name"}")
        b.on("commit", fn(_e: UiEvent) { self.name = _e.text })
        b.text("{self.name}")
        b.close()
        b.open("Button")  // screen.bx:5
        b.key("{"order"}")
        b.text("Order coffee")
        b.on("click", fn(e: UiEvent) { self.order() })
        b.close()
        b.open("Label")  // screen.bx:6
        b.key("{"count"}")
        b.text("Orders: {self.orders}")
        b.close()
        b.open("ScrollView")  // screen.bx:7
        b.number("height", (160) as f64)
        b.open("VStack")  // screen.bx:8
        b.number("spacing", (10) as f64)
        b.word("align", "stretch")
        var _cortado_row_0: int = 0
        for row in 0..20 {  // screen.bx:9
            b.open("HStack")  // screen.bx:10
            b.key("{"row-{row}"}")
            b.number("padding", (10) as f64)
            b.number("spacing", (12) as f64)
            b.word("background", "#ffffffff")
            b.number("corner_radius", (8) as f64)
            b.open("Label")  // screen.bx:11
            b.text("Coffee {row}")
            b.number("grow", (1) as f64)
            b.close()
            b.open("Label")  // screen.bx:12
            b.text("Ready")
            b.word("text_color", "#0088ffff")
            b.close()
            b.close()
            _cortado_row_0 += 1
        }
        b.close()
        b.close()
        b.close()
    }
}
