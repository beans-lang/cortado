// Generated from site/accessibility_page.bx by cortado. Do not edit.
//
// The <beans> block below is accessibility_page.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change accessibility_page.bx and regenerate:
//
//     cortado generate site/accessibility_page.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view} from cortado.annotations

@view
pub partial class AccessibilityPage extends component.Component {
    pub orders: int = 0
    pub updates: int = 0
    pub drinks: List<string> = ["Tea", "Coffee", "Water"]
    pub drink_index: int = 0
    pub name: string = ""
    pub name_label: string = "Name"
    pub hide_name: bool = false
    pub secret: string = ""
    pub fn init() { super.init() }
    pub fn place_order() { self.orders += 1; self.request_render() }
    pub fn set_updates(value: int) { self.updates = value; self.request_render() }
    pub fn choose_drink(index: int) { self.drink_index = index; self.request_render() }
}

partial class AccessibilityPage {
    pub override fn render(b: Builder) {
        b.open("VStack")  // accessibility_page.bx:1
        b.number("padding", (20) as f64)
        b.number("spacing", (12) as f64)
        b.word("align", "stretch")
        b.open("Label")  // accessibility_page.bx:2
        b.text("Accessibility")
        b.number("font_size", (23) as f64)
        b.close()
        b.open("Label")  // accessibility_page.bx:3
        b.text("Use a screen reader to inspect labels, states, focus, and actions.")
        b.close()
        b.open("Button")  // accessibility_page.bx:4
        b.key("{"action"}")
        b.text("Place order")
        b.on("click", fn(e: UiEvent) { self.place_order() })
        b.close()
        b.open("Label")  // accessibility_page.bx:5
        b.text("Orders placed: {self.orders}")
        b.close()
        b.open("CheckBox")  // accessibility_page.bx:6
        b.key("{"updates"}")
        b.text("Send updates")
        b.flag("checked", self.updates == 1)
        b.on("change", fn(e: UiEvent) { self.set_updates(e.index) })
        b.close()
        b.open("Label")  // accessibility_page.bx:8
        b.text("Drink")
        b.close()
        b.open("ComboBox")  // accessibility_page.bx:9
        b.key("{"drink"}")
        b.a11y_label("Drink")
        b.number("selected", (self.drink_index) as f64)
        b.items(self.drinks)
        b.on("change", fn(e: UiEvent) { self.choose_drink(e.index) })
        b.close()
        b.open("Label")  // accessibility_page.bx:11
        b.text("Name")
        b.close()
        b.open("TextField")  // accessibility_page.bx:12
        b.key("{"name"}")
        b.a11y_label("{self.name_label}")
        b.flag("hidden", self.hide_name)
        b.on("commit", fn(_e: UiEvent) { self.name = _e.text })
        b.text("{self.name}")
        b.close()
        b.open("Label")  // accessibility_page.bx:13
        b.text("Private code")
        b.close()
        b.open("SecureField")  // accessibility_page.bx:14
        b.key("{"secret"}")
        b.a11y_label("Private code")
        b.on("commit", fn(_e: UiEvent) { self.secret = _e.text })
        b.text("{self.secret}")
        b.close()
        b.open("Label")  // accessibility_page.bx:15
        b.text("The private code is never exposed as an accessibility value.")
        b.close()
        b.close()
    }
}
