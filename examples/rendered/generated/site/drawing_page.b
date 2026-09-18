// Generated from site/drawing_page.bx by cortado. Do not edit.
//
// The <beans> block below is drawing_page.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change drawing_page.bx and regenerate:
//
//     cortado generate site/drawing_page.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view, param} from cortado.annotations

@view
pub partial class DrawingPage extends component.Component {
    @param pub active: bool = false
    pub fn init() { super.init() }
    pub fn toggle() { self.active = !self.active; self.request_render() }
}

partial class DrawingPage {
    pub override fn render(b: Builder) {
        b.open("VStack")  // drawing_page.bx:1
        b.number("padding", (24) as f64)
        b.number("spacing", (14) as f64)
        b.word("align", "stretch")
        b.open("HStack")  // drawing_page.bx:2
        b.number("spacing", (12) as f64)
        b.word("align", "center")
        b.open("Label")  // drawing_page.bx:3
        b.text("Drawing in .bx")
        b.number("font_size", (24) as f64)
        b.close()
        b.open("Button")  // drawing_page.bx:4
        b.text("Animate")
        b.on("click", fn(e: UiEvent) { self.toggle() })
        b.close()
        b.close()
        b.open("Label")  // drawing_page.bx:6
        b.text("Shapes, gradients, shadows, clips, images, and transforms come from markup.")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("Box")  // drawing_page.bx:7
        b.number("height", (220) as f64)
        b.word("background", "#ffffff")
        b.open("Rectangle")  // drawing_page.bx:8
        b.number("x", (24) as f64)
        b.number("y", (40) as f64)
        b.number("width", (140) as f64)
        b.number("height", (100) as f64)
        b.word("gradient_start", if self.active { "#ed8054" } else { "#365eea" })
        b.word("gradient_end", "#365eea00")
        b.word("stroke", "#172b66")
        b.number("stroke_width", (4) as f64)
        b.number("rotation", (if self.active { 8.0 } else { -8.0 }) as f64)
        b.number("transition_seconds", (0.4) as f64)
        b.word("transition_easing", "ease_in_out")
        b.close()
        b.open("Ellipse")  // drawing_page.bx:9
        b.number("x", (210) as f64)
        b.number("y", (35) as f64)
        b.number("width", (140) as f64)
        b.number("height", (110) as f64)
        b.word("fill", "#ec854d")
        b.word("stroke", "#95401a")
        b.number("stroke_width", (5) as f64)
        b.number("scale_x", (1.1) as f64)
        b.word("shadow_color", "#37224a88")
        b.number("shadow_blur", (6) as f64)
        b.number("shadow_dx", (8) as f64)
        b.number("shadow_dy", (8) as f64)
        b.close()
        b.open("Path")  // drawing_page.bx:10
        b.number("x", (410) as f64)
        b.number("y", (20) as f64)
        b.number("width", (160) as f64)
        b.number("height", (150) as f64)
        b.text("M 10 120 L 75 10 L 140 120 Z")
        b.word("fill", "#48b8a0")
        b.word("stroke", "#176b60")
        b.number("stroke_width", (5) as f64)
        b.number("rotation", (8) as f64)
        b.close()
        b.open("ResourceImage")  // drawing_page.bx:11
        b.number("x", (580) as f64)
        b.number("y", (35) as f64)
        b.number("width", (64) as f64)
        b.number("height", (100) as f64)
        b.text("examples/rendered/assets/tiles.png")
        b.number("clip_radius", (12) as f64)
        b.close()
        b.close()
        b.open("Label")  // drawing_page.bx:13
        b.text("Every shape above comes from this page's markup.")
        b.close()
        b.close()
    }
}
