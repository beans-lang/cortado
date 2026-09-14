// Generated from site/FancyButton.bx by cortado. Do not edit.
//
// The <beans> block below is FancyButton.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change FancyButton.bx and regenerate:
//
//     cortado generate site/FancyButton.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view, param} from cortado.annotations

/// A push button with a colour, named once so a screen can place it anywhere.
///
/// **This is what "extend Button" means here.** A `widgets.Button` owns a
/// native handle and is not a `Component`, so a subclass of it cannot be a tag.
///
/// A component that *renders* a `<Button>` can, and costs no registration —
/// any capitalised tag cortado does not own compiles to `Builder.child<T>`.
@view
pub partial class FancyButton extends component.Component {
    @param pub title: string = ""

    /// The colour behind the bezel. macOS draws it; the other three hosts
    /// answer `unsupported` and the applier steps over it.
    @param pub tint: string = "#2f6f4f"
    @param pub radius: f64 = 6.0
    @param pub font_size: f64 = 13.0
    @param pub enabled: bool = true

    /// What to run when it is pressed. A parameter, not an `on:` handler: the
    /// press lands on this component's button, not on the tag the screen wrote.
    pub on_press: fn(UiEvent) = fn(_e: UiEvent) {}

    pub fn init() { super.init() }

    /// Through a local binding, the way `Listener.fire` does it: a `fn` field
    /// cannot be called in place.
    fn fire(event: UiEvent) {
        let action: fn(UiEvent) = self.on_press
        action(event)
    }
}

partial class FancyButton {
    pub override fn render(b: Builder) {
        b.open("Button")  // FancyButton.bx:1
        b.text("{self.title}")
        b.word("background", self.tint)
        b.number("corner_radius", (self.radius) as f64)
        b.number("border_width", (1) as f64)
        b.word("border_color", "#00000040")
        b.number("font_size", (self.font_size) as f64)
        b.flag("enabled", self.enabled)
        b.on("click", fn(e: UiEvent) { self.fire(e) })
        b.close()
    }
}
