// Generated from examples/markup/site/checkout.bx by cortado-bx. Do not edit.
//
// The <beans> block below is checkout.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change checkout.bx and regenerate:
//
//     cortado-bx build examples/markup/site/checkout.bx
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
        b.open("Label")  // checkout.bx:3
        b.text("{self.shots} × {self.drink}")
        b.close()
        b.child<Price>("c1", fn(_cortado_c: Price) {  // checkout.bx:5
            _cortado_c.drink = self.drink
        })
        b.open("CheckBox")  // checkout.bx:7
        b.flag("checked", self.rush)
        b.on("change", fn(e: UiEvent) { self.toggle_rush() })
        b.text("Rush it")
        b.close()
        if self.shots > 2 {  // checkout.bx:11
            b.open("Label")  // checkout.bx:12
            b.text("That is a lot of caffeine")
            b.close()
        }
        b.open("HStack")  // checkout.bx:15
        b.number("spacing", (10) as f64)
        b.word("justify", "end")
        b.open("Button")  // checkout.bx:16
        b.flag("enabled", self.shots < 4)
        b.on("click", fn(e: UiEvent) { self.add_shot() })
        b.text("Another shot")
        b.close()
        b.open("Button")  // checkout.bx:19
        b.on("click", fn(e: UiEvent) { self.change_drink() })
        b.text("Change drink")
        b.close()
        b.close()
        b.close()
    }
}
