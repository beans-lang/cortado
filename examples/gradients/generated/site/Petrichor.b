// Generated from site/Petrichor.bx by cortado. Do not edit.
//
// The <beans> block below is Petrichor.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change Petrichor.bx and regenerate:
//
//     cortado generate site/Petrichor.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import cortado.events
import {MeshGradient, AuroraGradient, FlowGradient,
        PrismGradient, GlowGradient, SkyGradient} from cortado.gpu
import {view} from cortado.annotations

/// Four colours blended by distance, drifting, with a screen of real controls
/// on top of them.
///
/// **What is drawn here and what is placed.** Six tags are drawn — the
/// `<MeshGradient>` behind everything and the five on the shelf below it. Not
/// one of them carries a line of shader: they are named attributes.
///
/// Everything over it is an ordinary native control placed by `<Box>`. The
/// title is an NSTextField, the chips are stacks, the toast tabs like a button.
///
/// That split is the point. A web page draws the whole screen and then
/// reimplements focus; this draws only the part that has to be drawn.
///
/// **No Beans code runs per frame.** The gradient redraws off the frame clock;
/// the controls over it are laid out once, because nothing about them changed.
@view
pub partial class Petrichor extends component.Component {
    /// The screen's own size. Set by `main.b` from the window, because a
    /// window is whatever was asked for and a phone's is the screen.
    pub wide: f64 = 900.0
    pub tall: f64 = 640.0

    pub dismissed: bool = false
    pub caption: string = "four colours, blended by distance, drifting"


    pub fn init() { super.init() }

    // Both of these end in `request_render`, and that is not a formality.
    // The mount asks rather than being told, so a handler that changes a field
    // and stops leaves the screen showing the old answer for ever.
    fn restore() {
        self.caption = "draft restored"
        self.dismissed = true
        self.request_render()
    }

    fn dismiss() {
        self.dismissed = true
        self.request_render()
    }
}

// Every component tag in Petrichor.bx, checked by beansc rather than by cortado-bx:
// a tag whose type is not a Component is a type error naming the type,
// instead of a blank subtree and a fault at run time. Unused, and an
// unused free function is not an error.
fn _cortado_component_Petrichor_MeshGradient(value: MeshGradient) -> Component { return value }
fn _cortado_component_Petrichor_Swatch(value: Swatch) -> Component { return value }
fn _cortado_component_Petrichor_AuroraGradient(value: AuroraGradient) -> Component { return value }
fn _cortado_component_Petrichor_FlowGradient(value: FlowGradient) -> Component { return value }
fn _cortado_component_Petrichor_PrismGradient(value: PrismGradient) -> Component { return value }
fn _cortado_component_Petrichor_GlowGradient(value: GlowGradient) -> Component { return value }
fn _cortado_component_Petrichor_SkyGradient(value: SkyGradient) -> Component { return value }

partial class Petrichor {
    pub override fn render(b: Builder) {
        b.open("Box")  // Petrichor.bx:1
        b.number("width", (self.wide) as f64)
        b.number("height", (self.tall) as f64)
        b.open("VFlex")  // Petrichor.bx:4
        b.number("x", (0) as f64)
        b.number("y", (0) as f64)
        b.number("width", (self.wide) as f64)
        b.number("height", (self.tall) as f64)
        b.word("align", "stretch")
        b.child<MeshGradient>("c0", fn(_cortado_c: MeshGradient) {  // Petrichor.bx:5
            _cortado_c.grow = 1
            _cortado_c.lobe = 2
            _cortado_c.color_1 = "#EAF4FC"
            _cortado_c.reach_1 = 18
            _cortado_c.color_2 = "#1E50A2"
            _cortado_c.reach_2 = 12
            _cortado_c.color_3 = "#F09199"
            _cortado_c.reach_3 = 10
            _cortado_c.color_4 = "#895B8A"
            _cortado_c.reach_4 = 11
        })
        b.close()
        b.open("Label")  // Petrichor.bx:12
        b.number("x", (0) as f64)
        b.number("y", (264) as f64)
        b.number("width", (self.wide) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (64) as f64)
        b.word("text_color", "#241c22")
        b.text("Petrichor")
        b.close()
        b.open("Label")  // Petrichor.bx:14
        b.number("x", (0) as f64)
        b.number("y", (344) as f64)
        b.number("width", (self.wide) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (12) as f64)
        b.word("text_color", "#463c46")
        b.text("{self.caption}")
        b.close()
        if !self.dismissed {  // Petrichor.bx:17
            b.open("HStack")  // Petrichor.bx:20
            b.number("x", (266) as f64)
            b.number("y", (16) as f64)
            b.number("spacing", (10) as f64)
            b.number("padding", (8) as f64)
            b.word("align", "center")
            b.word("background", "#1c1a22e8")
            b.number("corner_radius", (18) as f64)
            b.number("border_width", (1) as f64)
            b.word("border_color", "#ffffff22")
            b.open("Label")  // Petrichor.bx:23
            b.number("font_size", (12) as f64)
            b.word("text_color", "#f2eef4")
            b.text("Pick up where you left off?")
            b.close()
            b.open("Button")  // Petrichor.bx:24
            b.text("Restore draft")
            b.number("font_size", (12) as f64)
            b.number("corner_radius", (9) as f64)
            b.on("click", fn(e: UiEvent) { self.restore() })
            b.close()
            b.open("Button")  // Petrichor.bx:26
            b.text("✕")
            b.number("font_size", (11) as f64)
            b.number("width", (26) as f64)
            b.number("corner_radius", (9) as f64)
            b.on("click", fn(e: UiEvent) { self.dismiss() })
            b.close()
            b.close()
        }
        b.child<Swatch>("c1", fn(_cortado_c: Swatch) {  // Petrichor.bx:31
            _cortado_c.x = 640
            _cortado_c.y = 96
            _cortado_c.name = "MOON WHITE"
            _cortado_c.hex = "#EAF4FC"
            _cortado_c.tint = "#EAF4FC"
        })
        b.child<Swatch>("c2", fn(_cortado_c: Swatch) {  // Petrichor.bx:32
            _cortado_c.x = 640
            _cortado_c.y = 220
            _cortado_c.name = "LAPIS"
            _cortado_c.hex = "#1E50A2"
            _cortado_c.tint = "#1E50A2"
        })
        b.child<Swatch>("c3", fn(_cortado_c: Swatch) {  // Petrichor.bx:33
            _cortado_c.x = 640
            _cortado_c.y = 344
            _cortado_c.name = "PEACH PINK"
            _cortado_c.hex = "#F09199"
            _cortado_c.tint = "#F09199"
        })
        b.child<Swatch>("c4", fn(_cortado_c: Swatch) {  // Petrichor.bx:34
            _cortado_c.x = 640
            _cortado_c.y = 468
            _cortado_c.name = "ANCIENT PURPLE"
            _cortado_c.hex = "#895B8A"
            _cortado_c.tint = "#895B8A"
        })
        b.open("VFlex")  // Petrichor.bx:37
        b.number("x", (12) as f64)
        b.number("y", (510) as f64)
        b.number("width", (168) as f64)
        b.number("height", (86) as f64)
        b.word("align", "stretch")
        b.child<AuroraGradient>("c5", fn(_cortado_c: AuroraGradient) {
            _cortado_c.grow = 1
        })
        b.close()
        b.open("VFlex")  // Petrichor.bx:38
        b.number("x", (190) as f64)
        b.number("y", (510) as f64)
        b.number("width", (168) as f64)
        b.number("height", (86) as f64)
        b.word("align", "stretch")
        b.child<FlowGradient>("c6", fn(_cortado_c: FlowGradient) {
            _cortado_c.grow = 1
        })
        b.close()
        b.open("VFlex")  // Petrichor.bx:39
        b.number("x", (368) as f64)
        b.number("y", (510) as f64)
        b.number("width", (168) as f64)
        b.number("height", (86) as f64)
        b.word("align", "stretch")
        b.child<PrismGradient>("c7", fn(_cortado_c: PrismGradient) {
            _cortado_c.grow = 1
        })
        b.close()
        b.open("VFlex")  // Petrichor.bx:40
        b.number("x", (546) as f64)
        b.number("y", (510) as f64)
        b.number("width", (168) as f64)
        b.number("height", (86) as f64)
        b.word("align", "stretch")
        b.child<GlowGradient>("c8", fn(_cortado_c: GlowGradient) {
            _cortado_c.grow = 1
        })
        b.close()
        b.open("VFlex")  // Petrichor.bx:41
        b.number("x", (724) as f64)
        b.number("y", (510) as f64)
        b.number("width", (168) as f64)
        b.number("height", (86) as f64)
        b.word("align", "stretch")
        b.child<SkyGradient>("c9", fn(_cortado_c: SkyGradient) {
            _cortado_c.grow = 1
        })
        b.close()
        b.open("Label")  // Petrichor.bx:43
        b.number("x", (12) as f64)
        b.number("y", (601) as f64)
        b.number("width", (168) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("AURORA")
        b.close()
        b.open("Label")  // Petrichor.bx:44
        b.number("x", (190) as f64)
        b.number("y", (601) as f64)
        b.number("width", (168) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("FLOW")
        b.close()
        b.open("Label")  // Petrichor.bx:45
        b.number("x", (368) as f64)
        b.number("y", (601) as f64)
        b.number("width", (168) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("PRISM")
        b.close()
        b.open("Label")  // Petrichor.bx:46
        b.number("x", (546) as f64)
        b.number("y", (601) as f64)
        b.number("width", (168) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("GLOW")
        b.close()
        b.open("Label")  // Petrichor.bx:47
        b.number("x", (724) as f64)
        b.number("y", (601) as f64)
        b.number("width", (168) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("SKY")
        b.close()
        b.close()
    }
}
