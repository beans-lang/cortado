// Generated from examples/markup/site/price.bx by cortado-bx. Do not edit.
//
// The <beans> block below is price.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change price.bx and regenerate:
//
//     cortado-bx build examples/markup/site/price.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view, param, inject} from cortado.annotations

/// What the order costs.
///
/// The menu arrives by injection — nothing above passes it down. `should_render`
/// says no unless the drink actually moved, so the screen re-rendering for its
/// own reasons does not re-run this.
@view
pub partial class Price extends component.Component {
    @param pub drink: string = ""
    @inject pub menu: Menu = new Menu()
    last: string = ""

    pub fn init() { super.init() }

    pub override fn on_params_set() {}

    pub override fn should_render() -> bool {
        if self.last == self.drink { return false }
        self.last = self.drink
        return true
    }
}

partial class Price {
    pub override fn render(b: Builder) {
        b.open("Label")  // price.bx:1
        b.number("font_size", (22) as f64)
        b.text("{self.menu.price(self.drink)}p")
        b.close()
    }
}
