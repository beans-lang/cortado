// Generated from examples/gallery/site/shelf.bx by cortado-bx. Do not edit.
//
// The <beans> block below is shelf.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change shelf.bx and regenerate:
//
//     cortado-bx build examples/gallery/site/shelf.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import cortado.events
import {ShaderCanvas} from cortado.gpu
import {view} from cortado.annotations

/// The order screen, showing one of every control cortado has.
@view
pub partial class Shelf extends component.Component {
    pub drink: string = "flat white"
    pub shots: int = 2
    pub rush: bool = false
    pub note: string = "no sugar"
    pub status: string = "Nothing ordered yet"

    pub fn init() { super.init() }

    pub fn pick(index: int) {
        if index == 1 { self.drink = "espresso" }
        else if index == 2 { self.drink = "cortado" }
        else { self.drink = "flat white" }
        self.request_render()
    }

    pub fn set_shots(event: events.UiEvent) {
        self.shots = event.index
        self.request_render()
    }

    pub fn toggle_rush() {
        self.rush = !self.rush
        self.request_render()
    }

    pub fn order() {
        self.status = "Ordered {self.shots} × {self.drink}"
        self.request_render()
    }
}

// Every component tag in shelf.bx, checked by beansc rather than by cortado-bx:
// a tag whose type is not a Component is a type error naming the type,
// instead of a blank subtree and a fault at run time. Unused, and an
// unused free function is not an error.
fn _cortado_component_shelf_ShaderCanvas(value: ShaderCanvas) -> Component { return value }

partial class Shelf {
    pub override fn render(b: Builder) {
        b.open("VStack")  // shelf.bx:1
        b.number("spacing", (12) as f64)
        b.number("padding", (20) as f64)
        b.word("align", "stretch")
        b.open("Label")  // shelf.bx:2
        b.number("font_size", (18) as f64)
        b.text("Every control")
        b.close()
        b.open("Separator")  // shelf.bx:3
        b.close()
        b.open("HFlex")  // shelf.bx:5
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:6
        b.number("width", (110) as f64)
        b.text("Drink")
        b.close()
        b.open("ComboBox")  // shelf.bx:7
        b.number("grow", (1) as f64)
        b.on("change", fn(e: UiEvent) { self.pick(e.index) })
        b.close()
        b.close()
        b.open("HFlex")  // shelf.bx:10
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:11
        b.number("width", (110) as f64)
        b.text("Shots: {self.shots}")
        b.close()
        b.open("Slider")  // shelf.bx:12
        b.number("grow", (1) as f64)
        b.number("min", (1) as f64)
        b.number("max", (4) as f64)
        b.number("value", (self.shots) as f64)
        b.on("change", fn(e: UiEvent) { self.set_shots(e) })
        b.close()
        b.close()
        b.open("HStack")  // shelf.bx:16
        b.number("spacing", (10) as f64)
        b.open("CheckBox")  // shelf.bx:17
        b.flag("checked", self.rush)
        b.on("change", fn(e: UiEvent) { self.toggle_rush() })
        b.text("Rush it")
        b.close()
        b.open("RadioButton")  // shelf.bx:18
        b.text("Eat in")
        b.close()
        b.open("RadioButton")  // shelf.bx:19
        b.text("Take away")
        b.close()
        b.close()
        b.open("ProgressBar")  // shelf.bx:22
        b.number("height", (12) as f64)
        b.number("min", (0) as f64)
        b.number("max", (4) as f64)
        b.number("value", (self.shots) as f64)
        b.close()
        b.open("Canvas")  // shelf.bx:25
        b.number("height", (24) as f64)
        b.close()
        b.child<ShaderCanvas>("c4", fn(_cortado_c: ShaderCanvas) {  // shelf.bx:30
            _cortado_c.height = 44
            _cortado_c.effect = "ripple"
            _cortado_c.color = "#4088bf"
            _cortado_c.color_to = "#0d1b2a"
            _cortado_c.detail = 26
        })
        b.open("TextArea")  // shelf.bx:32
        b.number("height", (70) as f64)
        b.on("commit", fn(_e: UiEvent) { self.note = _e.text })
        b.text("{self.note}")
        b.close()
        b.open("HStack")  // shelf.bx:34
        b.number("spacing", (10) as f64)
        b.word("justify", "end")
        b.open("Button")  // shelf.bx:35
        b.flag("enabled", self.shots > 0)
        b.on("click", fn(e: UiEvent) { self.order() })
        b.text("Order")
        b.close()
        b.close()
        b.open("Label")  // shelf.bx:38
        b.text("{self.status}")
        b.close()
        b.close()
    }
}
