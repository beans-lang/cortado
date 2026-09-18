// Generated from site/composition_page.bx by cortado. Do not edit.
//
// The <beans> block below is composition_page.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change composition_page.bx and regenerate:
//
//     cortado generate site/composition_page.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          
import cortado.component
import cortado.render
import {view, param} from cortado.annotations
@view
pub partial class CompositionPage extends component.Component {
    @param pub theme: Option<render.Theme> = none
    pub rating: int = 0
    pub fn init() { super.init() }
    pub fn rate(value: int) { self.rating = value; self.request_render() }
    pub fn accent(color: int) {
        match self.theme {
            some(theme) => { theme.set_colors(theme.background(), theme.foreground(), color, theme.surface()) }
            none => {}
        }
        self.request_render()
    }
}

// Every component tag in composition_page.bx, checked by beansc rather than by cortado-bx:
// a tag whose type is not a Component is a type error naming the type,
// instead of a blank subtree and a fault at run time. Unused, and an
// unused free function is not an error.
fn _cortado_component_composition_page_RatingControl(value: RatingControl) -> Component { return value }

partial class CompositionPage {
    pub override fn render(b: Builder) {
        b.open("VStack")  // composition_page.bx:1
        b.number("padding", (24) as f64)
        b.number("spacing", (18) as f64)
        b.word("align", "stretch")
        b.word("background", "#f7f7f9")
        b.open("Label")  // composition_page.bx:2
        b.text("Build a control with markup")
        b.number("font_size", (24) as f64)
        b.close()
        b.open("Label")  // composition_page.bx:3
        b.text("This rating control adds no renderer or platform code.")
        b.close()
        b.open("VStack")  // composition_page.bx:4
        b.number("padding", (18) as f64)
        b.number("spacing", (12) as f64)
        b.word("align", "stretch")
        b.word("background", "#e8eaf0")
        b.number("corner_radius", (12) as f64)
        b.child<RatingControl>("c0", fn(_cortado_c: RatingControl) {  // composition_page.bx:5
            _cortado_c.value = self.rating
            _cortado_c.on_change = fn(value: int) { self.rate(value) }
        })
        b.open("Label")  // composition_page.bx:6
        b.text("{if self.rating == 0 { "Choose a rating with a pointer or the keyboard." } else { "You chose {self.rating} of 5." }}")
        b.close()
        b.close()
        b.open("Label")  // composition_page.bx:8
        b.text("Change the window's theme")
        b.number("font_size", (20) as f64)
        b.close()
        b.open("HStack")  // composition_page.bx:9
        b.number("spacing", (10) as f64)
        b.flag("wrap", true)
        b.open("Button")  // composition_page.bx:10
        b.text("Cortado blue")
        b.on("click", fn(e: UiEvent) { self.accent(0x365eeaff) })
        b.close()
        b.open("Button")  // composition_page.bx:11
        b.text("Coffee brown")
        b.on("click", fn(e: UiEvent) { self.accent(0x87582fff) })
        b.close()
        b.open("Button")  // composition_page.bx:12
        b.text("Leaf green")
        b.on("click", fn(e: UiEvent) { self.accent(0x26734dff) })
        b.close()
        b.close()
        b.open("CheckBox")  // composition_page.bx:14
        b.text("Theme preview")
        b.flag("checked", true)
        b.close()
        b.open("ProgressBar")  // composition_page.bx:15
        b.number("value", (65.0) as f64)
        b.close()
        b.close()
    }
}
