// Generated from site/tile.bx by cortado. Do not edit.
//
// The <beans> block below is tile.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change tile.bx and regenerate:
//
//     cortado generate site/tile.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view, param} from cortado.annotations
import {Badge} from markup.generated.site.parts

/// A section of a screen: the caption the screen draws for it, how the order
/// is going, and whatever the screen wrote inside the tag.
///
/// **This is the `$slot` component.** A tile decides *where* its content goes;
/// the screen around it decides *what* the content is. The two halves meet in
/// two fields:
///
///   * `body` is the tag's children, as a template. `$slot` places it.
///   * `cap` is the template the screen wrote as `$slot:cap ... { ... }`,
///     handed the tile's own title. `$slot:cap as self.title` places it.
///
/// Both are ordinary `fn(Builder)` fields with a default that draws nothing,
/// so a tile nobody gave a template to is empty rather than broken — the
/// author chooses the default, and cortado does not need a concept for "no
/// template".
///
/// The `<Badge>` between them is not decoration in this example. A template is
/// written in the *screen's* file and run against the *tile's* builder, so a
/// component tag inside the template asks for a key in the tile's render — and
/// cortado-bx restarts key numbering inside a template, so that key can be one
/// the tile has already used for a component of its own. Here it is exactly
/// that: the badge is `c1` in this file and `<Price>` is `c1` in the template
/// `checkout.bx` supplies. `Builder.fragment` is what keeps them apart, and
/// without it this screen tells its author that `<Price> came back as
/// something else`.
@view
pub partial class Tile extends component.Component {
    @param pub title: string = ""
    @param pub rush: bool = false

    /// The screen's children, as a template this component places.
    pub body: fn(Builder) = fn(_b: Builder) {}
    /// How the screen draws a caption, given the title to draw.
    pub cap: fn(Builder, string) = fn(_b: Builder, _t: string) {}

    pub fn init() { super.init() }
}

// Every component tag in tile.bx, checked by beansc rather than by cortado-bx:
// a tag whose type is not a Component is a type error naming the type,
// instead of a blank subtree and a fault at run time. Unused, and an
// unused free function is not an error.
fn _cortado_component_tile_Badge(value: Badge) -> Component { return value }

partial class Tile {
    pub override fn render(b: Builder) {
        b.open("VStack")  // tile.bx:1
        b.number("spacing", (6) as f64)
        b.fragment("0", fn(_cortado_inner: Builder) { self.cap(_cortado_inner, self.title) })  // tile.bx:2
        b.child<Badge>("c1", fn(_cortado_c: Badge) {  // tile.bx:3
            _cortado_c.rush = self.rush
        })
        b.fragment("2", self.body)  // tile.bx:4
        b.close()
    }
}
