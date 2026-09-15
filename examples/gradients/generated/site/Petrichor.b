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
/// Everything over it is an ordinary native control placed by a run. The title
/// is an NSTextField, the chips are stacks, the toast tabs like a button.
///
/// **Nothing here is a coordinate.** The screen is two full-bleed layers in a
/// `<Box>`, and every size below them is a share of the room, a shape, or what
/// a run hands out — so the same file is the phone layout and the desk one.
///
/// **No Beans code runs per frame.** The gradient redraws off the frame clock;
/// the controls over it are laid out once, because nothing about them changed.
@view
pub partial class Petrichor extends component.Component {
    pub dismissed: bool = false
    pub caption: string = "four colours, blended by distance, drifting"

    pub fn init() { super.init() }

    /// This render reads `viewport()`, so a resize is a reason to run it again.
    pub override fn follows_viewport() -> bool { return true }

    /// Whether there is room beside the title for the colour chips.
    ///
    /// 232 points of chip, 16 of gap and a title that stops reading as a title
    /// under about 380 — the breakpoint is that sum rather than a round number.
    pub fn roomy() -> bool {
        return self.viewport().width >= 660.0
    }

    /// The title, as large as the window can carry: a tenth of the width,
    /// held between what is legible and what the design was drawn at.
    pub fn title_size() -> f64 {
        var size: f64 = self.viewport().width / 10.0
        if size > 64.0 { size = 64.0 }
        if size < 28.0 { size = 28.0 }
        return size
    }

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
        b.open("VFlex")  // Petrichor.bx:4
        b.number("width_percent", (100) as f64)
        b.number("height_percent", (100) as f64)
        b.word("align", "stretch")
        b.child<MeshGradient>("c0", fn(_cortado_c: MeshGradient) {  // Petrichor.bx:5
            _cortado_c.lobe = 2
            _cortado_c.color_1 = "#EAF4FC"
            _cortado_c.reach_1 = 18
            _cortado_c.color_2 = "#1E50A2"
            _cortado_c.reach_2 = 12
            _cortado_c.color_3 = "#F09199"
            _cortado_c.reach_3 = 10
            _cortado_c.color_4 = "#895B8A"
            _cortado_c.reach_4 = 11
        }).number("grow", (1) as f64)
        b.close()
        b.open("VFlex")  // Petrichor.bx:12
        b.number("width_percent", (100) as f64)
        b.number("height_percent", (100) as f64)
        b.number("padding", (16) as f64)
        b.word("align", "stretch")
        if !self.dismissed {  // Petrichor.bx:13
            b.open("HStack")  // Petrichor.bx:14
            b.word("justify", "end")
            b.open("HStack")  // Petrichor.bx:17
            b.number("spacing", (10) as f64)
            b.number("padding", (8) as f64)
            b.word("align", "center")
            b.word("background", "#1c1a22e8")
            b.number("corner_radius", (18) as f64)
            b.number("border_width", (1) as f64)
            b.word("border_color", "#ffffff22")
            b.open("Label")  // Petrichor.bx:20
            b.number("font_size", (12) as f64)
            b.word("text_color", "#f2eef4")
            b.text("Pick up where you left off?")
            b.close()
            b.open("Button")  // Petrichor.bx:21
            b.text("Restore draft")
            b.number("font_size", (12) as f64)
            b.number("corner_radius", (9) as f64)
            b.on("click", fn(e: UiEvent) { self.restore() })
            b.close()
            b.open("Button")  // Petrichor.bx:23
            b.text("✕")
            b.number("font_size", (11) as f64)
            b.number("width", (26) as f64)
            b.number("corner_radius", (9) as f64)
            b.on("click", fn(e: UiEvent) { self.dismiss() })
            b.close()
            b.close()
            b.close()
        }
        b.open("HFlex")  // Petrichor.bx:29
        b.number("grow", (1) as f64)
        b.number("spacing", (16) as f64)
        b.word("align", "stretch")
        b.open("VStack")  // Petrichor.bx:30
        b.number("grow", (1) as f64)
        b.word("justify", "center")
        b.word("align", "stretch")
        b.open("Label")  // Petrichor.bx:31
        b.number("alignment", (1) as f64)
        b.number("font_size", (self.title_size()) as f64)
        b.word("text_color", "#241c22")
        b.text("Petrichor")
        b.close()
        b.open("Label")  // Petrichor.bx:33
        b.number("margin_top", (10) as f64)
        b.number("alignment", (1) as f64)
        b.number("font_size", (12) as f64)
        b.word("text_color", "#463c46")
        b.text("{self.caption}")
        b.close()
        b.close()
        if self.roomy() {  // Petrichor.bx:39
            b.open("VStack")  // Petrichor.bx:40
            b.number("width", (232) as f64)
            b.number("spacing", (22) as f64)
            b.word("justify", "center")
            b.child<Swatch>("c1", fn(_cortado_c: Swatch) {  // Petrichor.bx:41
                _cortado_c.name = "MOON WHITE"
                _cortado_c.hex = "#EAF4FC"
                _cortado_c.tint = "#EAF4FC"
            })
            b.child<Swatch>("c2", fn(_cortado_c: Swatch) {  // Petrichor.bx:42
                _cortado_c.name = "LAPIS"
                _cortado_c.hex = "#1E50A2"
                _cortado_c.tint = "#1E50A2"
            })
            b.child<Swatch>("c3", fn(_cortado_c: Swatch) {  // Petrichor.bx:43
                _cortado_c.name = "PEACH PINK"
                _cortado_c.hex = "#F09199"
                _cortado_c.tint = "#F09199"
            })
            b.child<Swatch>("c4", fn(_cortado_c: Swatch) {  // Petrichor.bx:44
                _cortado_c.name = "ANCIENT PURPLE"
                _cortado_c.hex = "#895B8A"
                _cortado_c.tint = "#895B8A"
            })
            b.close()
        }
        b.close()
        b.open("HWrap")  // Petrichor.bx:51
        b.number("spacing", (10) as f64)
        b.number("line_spacing", (10) as f64)
        b.word("justify", "center")
        b.number("margin_top", (12) as f64)
        b.open("VStack")  // Petrichor.bx:52
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<AuroraGradient>("c5", fn(_cortado_c: AuroraGradient) {  // Petrichor.bx:53
        }).number("width", (160) as f64).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:54
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("AURORA")
        b.close()
        b.close()
        b.open("VStack")  // Petrichor.bx:56
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<FlowGradient>("c6", fn(_cortado_c: FlowGradient) {  // Petrichor.bx:57
        }).number("width", (160) as f64).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:58
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("FLOW")
        b.close()
        b.close()
        b.open("VStack")  // Petrichor.bx:60
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<PrismGradient>("c7", fn(_cortado_c: PrismGradient) {  // Petrichor.bx:61
        }).number("width", (160) as f64).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:62
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("PRISM")
        b.close()
        b.close()
        b.open("VStack")  // Petrichor.bx:64
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<GlowGradient>("c8", fn(_cortado_c: GlowGradient) {  // Petrichor.bx:65
        }).number("width", (160) as f64).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:66
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("GLOW")
        b.close()
        b.close()
        b.open("VStack")  // Petrichor.bx:68
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<SkyGradient>("c9", fn(_cortado_c: SkyGradient) {  // Petrichor.bx:69
        }).number("width", (160) as f64).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:70
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("SKY")
        b.close()
        b.close()
        b.close()
        b.close()
        b.close()
    }
}
