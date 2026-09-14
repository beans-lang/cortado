// Generated from site/Swatch.bx by cortado. Do not edit.
//
// The <beans> block below is Swatch.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change Swatch.bx and regenerate:
//
//     cortado generate site/Swatch.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view, param} from cortado.annotations

/// One colour of the mesh, named and pinned where the screen wants it.
///
/// It carries `x` and `y` itself rather than being wrapped in a placed
/// container: a chip is a thing that sits somewhere, so the coordinate belongs
/// to the chip.
@view
pub partial class Swatch extends component.Component {
    @param pub name: string = ""
    @param pub hex: string = ""
    @param pub tint: string = "#888888"
    @param pub x: f64 = 0.0
    @param pub y: f64 = 0.0

    /// Pinned rather than measured, so four chips line up on both edges.
    @param pub across: f64 = 232.0

    pub fn init() { super.init() }
}

partial class Swatch {
    pub override fn render(b: Builder) {
        b.open("HFlex")  // Swatch.bx:1
        b.number("x", (self.x) as f64)
        b.number("y", (self.y) as f64)
        b.number("width", (self.across) as f64)
        b.number("spacing", (8) as f64)
        b.number("padding", (9) as f64)
        b.word("align", "center")
        b.word("background", "#ffffffe8")
        b.number("corner_radius", (15) as f64)
        b.number("border_width", (1) as f64)
        b.word("border_color", "#00000016")
        b.open("Label")  // Swatch.bx:4
        b.text("")
        b.number("width", (14) as f64)
        b.number("height", (14) as f64)
        b.word("background", self.tint)
        b.number("corner_radius", (7) as f64)
        b.number("border_width", (1) as f64)
        b.word("border_color", "#00000022")
        b.close()
        b.open("Label")  // Swatch.bx:6
        b.text("{self.name}")
        b.number("font_size", (11) as f64)
        b.word("text_color", "#1b1b20")
        b.close()
        b.open("Label")  // Swatch.bx:9
        b.text("")
        b.number("grow", (1) as f64)
        b.close()
        b.open("Label")  // Swatch.bx:10
        b.text("{self.hex}")
        b.number("font_size", (11) as f64)
        b.word("text_color", "#6b6b74")
        b.close()
        b.close()
    }
}
