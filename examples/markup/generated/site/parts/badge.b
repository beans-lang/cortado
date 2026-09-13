// Generated from site/parts/badge.bx by cortado. Do not edit.
//
// The <beans> block below is badge.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change badge.bx and regenerate:
//
//     cortado generate site/parts/badge.bx
package parts

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//           

import cortado.component
import {view, param} from cortado.annotations

/// A word for how the order is going.
///
/// **This file is the nested-package case.** It sits in `site/parts/`, so its
/// generated half lands in `generated/site/parts/` and declares `package
/// parts` — a Beans package is its folder, one level deeper than the screen
/// that uses it. `site/checkout.bx` reaches it with
/// `import {Badge} from markup.generated.site.parts` in its own `<beans>`
/// block, which cortado-bx copies through byte for byte.
///
/// Nothing about the tag changes: `<Badge rush={self.rush} />` is the same
/// spelling it would have in a flat tree. What the nesting costs is one import
/// line, and what it buys is that a screen with forty components can be
/// arranged in folders like any other code.
@view
pub partial class Badge extends component.Component {
    @param pub rush: bool = false

    pub fn init() { super.init() }

    pub fn word() -> string {
        if self.rush { return "rushing" }
        return "steady"
    }
}

partial class Badge {
    pub override fn render(b: Builder) {
        b.open("Label")  // badge.bx:1
        b.number("font_size", (12) as f64)
        b.text("{self.word()}")
        b.close()
    }
}
