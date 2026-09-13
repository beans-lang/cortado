// Generated from site/checkout.bx by cortado. Do not edit.
//
// The <beans> block below is checkout.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change checkout.bx and regenerate:
//
//     cortado generate site/checkout.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view, param, inject} from cortado.annotations

/// What a drink costs.
pub class Menu {
    pub fn init() {}

    pub fn price(drink: string) -> int {
        if drink == "flat white" { return 380 }
        if drink == "espresso" { return 260 }
        return 300
    }

    pub fn next(drink: string) -> string {
        if drink == "flat white" { return "espresso" }
        if drink == "espresso" { return "cortado" }
        return "flat white"
    }
}

/// The order screen. (`Order` is a builtin interface name in Beans, so the
/// class this file declares is `Checkout`, after the file.)
///
/// Everything above the `<beans>` line is the markup half of this same class.
/// cortado-bx writes a `render` method into the other half of the `partial
/// class`, so the two live in one file and there is one thing to regenerate.
@view
pub partial class Checkout extends component.Component {
    @param pub heading: string = "Order a coffee"
    @inject pub menu: Menu = new Menu()
    pub drink: string = "flat white"
    pub shots: int = 1
    pub rush: bool = false

    pub fn init() { super.init() }

    pub fn add_shot() {
        self.shots = self.shots + 1
        self.request_render()
    }

    pub fn change_drink() {
        self.drink = self.menu.next(self.drink)
        self.shots = 1
        self.request_render()
    }

    pub fn toggle_rush() {
        self.rush = !self.rush
        self.request_render()
    }
}

// Every component tag in checkout.bx, checked by beansc rather than by cortado-bx:
// a tag whose type is not a Component is a type error naming the type,
// instead of a blank subtree and a fault at run time. Unused, and an
// unused free function is not an error.
fn _cortado_component_checkout_Tile(value: Tile) -> Component { return value }
fn _cortado_component_checkout_Price(value: Price) -> Component { return value }

partial class Checkout {
    pub override fn render(b: Builder) {
        b.open("VStack")  // checkout.bx:1
        b.number("spacing", (14) as f64)
        b.number("padding", (24) as f64)
        b.word("align", "stretch")
        b.open("Label")  // checkout.bx:2
        b.number("font_size", (17) as f64)
        b.text("Order a coffee")
        b.close()
        b.child<Tile>("c0", fn(_cortado_c: Tile) {  // checkout.bx:9
            _cortado_c.title = "Your order"
            _cortado_c.rush = self.rush
            _cortado_c.body = fn(_cortado_inner: Builder) {
                _cortado_inner.open("Label")  // checkout.bx:11
                _cortado_inner.text("{self.shots} × {self.drink}")
                _cortado_inner.close()
                _cortado_inner.child<Price>("c1", fn(_cortado_c2: Price) {  // checkout.bx:12
                    _cortado_c2.drink = self.drink
                })
            }
            _cortado_c.cap = fn(_cortado_inner: Builder, t: string) {
                _cortado_inner.open("Label")  // checkout.bx:10
                _cortado_inner.number("font_size", (13) as f64)
                _cortado_inner.text("{t}")
                _cortado_inner.close()
            }
        })
        b.open("CheckBox")  // checkout.bx:15
        b.flag("checked", self.rush)
        b.on("change", fn(e: UiEvent) { self.toggle_rush() })
        b.text("Rush it")
        b.close()
        if self.shots > 2 {  // checkout.bx:19
            b.open("Label")  // checkout.bx:20
            b.text("That is a lot of caffeine")
            b.close()
        }
        b.open("HStack")  // checkout.bx:23
        b.number("spacing", (10) as f64)
        b.word("justify", "end")
        b.open("Button")  // checkout.bx:24
        b.flag("enabled", self.shots < 4)
        b.on("click", fn(e: UiEvent) { self.add_shot() })
        b.text("Another shot")
        b.close()
        b.open("Button")  // checkout.bx:27
        b.on("click", fn(e: UiEvent) { self.change_drink() })
        b.text("Change drink")
        b.close()
        b.close()
        b.close()
    }
}
