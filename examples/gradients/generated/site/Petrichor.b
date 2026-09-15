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
import cortado.motion
import cortado.host
import {MeshGradient, AuroraGradient, FlowGradient,
        PrismGradient, GlowGradient, SkyGradient} from cortado.gpu
import {view} from cortado.annotations

@view
pub partial class Petrichor extends component.Component {
    pub dismissed: bool = false
    pub caption: string = "four colours, blended by distance, drifting"

    /// What the background gradient is actually achieving, in frames a second.
    ///
    /// Counted, never estimated: the number below is frames the canvas *put on
    /// screen* between two readings of the clock, divided by the seconds
    /// between them. A tick that found no drawable free drew nothing and is
    /// not in it, and the display's refresh rate is nowhere in the sum.
    pub rate: string = "measuring"
    /// The same reading as a number, which is what a test can assert on.
    /// Negative until one has been taken.
    pub measured: f64 = 0.0 - 1.0

    /// The gradient behind everything, handed back by `ref=` on its own tag.
    priv mesh: Option<MeshGradient> = none
    /// This screen's own listener on the surface's clock, for the reading.
    priv beat: Option<motion.FrameClock> = none
    priv counted: int = 0
    priv marked: f64 = 0.0

    pub fn init() { super.init() }

    /// A token no control can collide with: `ShaderCanvas` keys its own by the
    /// control's handle, and a handle carries a generation in its high half.
    static fn reading_token() -> int {
        return 1
    }

    pub override fn on_mount(stage: component.Stage) {
        let surface: host.Handle = stage.surface()
        // Nothing to ride: a tree mounted outside a window, which is the
        // headless dump. The reading stays at what it was born with.
        if surface.raw == 0 { return }
        var beat: motion.FrameClock = new motion.FrameClock(surface, stage.router())
        match beat.start(Petrichor.reading_token(), fn(frame: motion.Frame) { self.sample(frame) }) {
            ok(started) => { self.beat = some(beat) }
            err(problem) => { self.rate = "no reading: {problem.kind}" }
        }
    }

    pub override fn on_unmount() {
        match self.beat {
            some(beat) => { beat.stop() }
            none => {}
        }
        self.beat = none
    }

    /// One reading a second, because a label rewritten every frame would be
    /// the thing being measured.
    fn sample(frame: motion.Frame) {
        match self.mesh {
            none => {}
            some(gradient) => {
                let span: f64 = frame.elapsed - self.marked
                if span < 1.0 { return }
                let now: int = gradient.frames()
                // Frames stop while the window is not being shown and the
                // seconds do not, so the window either side of that gap holds
                // no drawing and a rate taken over it would be a true sum and
                // a false answer to what is this achieving now. Re-base.
                if span > 2.0 {
                    self.counted = now
                    self.marked = frame.elapsed
                    return
                }
                let drawn: f64 = (now - self.counted) as f64
                self.counted = now
                self.marked = frame.elapsed
                self.measured = drawn / span
                self.rate = "{self.measured as int} fps"
                self.request_render()
            }
        }
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
fn _cortado_component_Petrichor_Title(value: Title) -> Component { return value }
fn _cortado_component_Petrichor_Swatch(value: Swatch) -> Component { return value }
fn _cortado_component_Petrichor_AuroraGradient(value: AuroraGradient) -> Component { return value }
fn _cortado_component_Petrichor_FlowGradient(value: FlowGradient) -> Component { return value }
fn _cortado_component_Petrichor_PrismGradient(value: PrismGradient) -> Component { return value }
fn _cortado_component_Petrichor_GlowGradient(value: GlowGradient) -> Component { return value }
fn _cortado_component_Petrichor_SkyGradient(value: SkyGradient) -> Component { return value }

partial class Petrichor {
    pub override fn render(b: Builder) {
        b.open("Box")  // Petrichor.bx:1
        b.child<MeshGradient>("c0", fn(_cortado_c: MeshGradient) {  // Petrichor.bx:4
            _cortado_c.lobe = 2
            _cortado_c.color_1 = "#EAF4FC"
            _cortado_c.reach_1 = 18
            _cortado_c.color_2 = "#1E50A2"
            _cortado_c.reach_2 = 12
            _cortado_c.color_3 = "#F09199"
            _cortado_c.reach_3 = 10
            _cortado_c.color_4 = "#895B8A"
            _cortado_c.reach_4 = 11
            self.mesh = some(_cortado_c)
        })
        b.open("ScrollView")  // Petrichor.bx:12
        b.open("VStack")  // Petrichor.bx:13
        b.number("padding", (16) as f64)
        b.word("align", "stretch")
        if !self.dismissed {  // Petrichor.bx:14
            b.open("HStack")  // Petrichor.bx:15
            b.word("justify", "end")
            b.open("HStack")  // Petrichor.bx:19
            b.number("spacing", (10) as f64)
            b.number("padding", (8) as f64)
            b.word("align", "center")
            b.word("background", "#1c1a22e8")
            b.number("corner_radius", (18) as f64)
            b.number("border_width", (1) as f64)
            b.word("border_color", "#ffffff22")
            b.open("Label")  // Petrichor.bx:22
            b.number("font_size", (12) as f64)
            b.word("text_color", "#f2eef4")
            b.text("Pick up where you left off?")
            b.close()
            b.open("Button")  // Petrichor.bx:23
            b.number("shrink", (0) as f64)
            b.text("Restore draft")
            b.number("font_size", (12) as f64)
            b.number("corner_radius", (9) as f64)
            b.on("click", fn(e: UiEvent) { self.restore() })
            b.close()
            b.open("Button")  // Petrichor.bx:25
            b.number("shrink", (0) as f64)
            b.text("✕")
            b.number("font_size", (11) as f64)
            b.number("width", (26) as f64)
            b.number("corner_radius", (9) as f64)
            b.on("click", fn(e: UiEvent) { self.dismiss() })
            b.close()
            b.close()
            b.close()
        }
        b.open("Box")  // Petrichor.bx:34
        b.number("flex", (1) as f64)
        b.child<Title>("c1", fn(_cortado_c: Title) {  // Petrichor.bx:35
            _cortado_c.caption = self.caption
            _cortado_c.rate = self.rate
        })
        b.open("VStack")  // Petrichor.bx:36
        b.number("right", (0) as f64)
        b.number("y", (0) as f64)
        b.number("bottom", (0) as f64)
        b.word("justify", "center")
        b.number("spacing", (22) as f64)
        b.word("align", "stretch")
        b.number("hide_below", (620) as f64)
        b.child<Swatch>("c2", fn(_cortado_c: Swatch) {  // Petrichor.bx:38
            _cortado_c.name = "MOON WHITE"
            _cortado_c.hex = "#EAF4FC"
            _cortado_c.tint = "#EAF4FC"
        })
        b.child<Swatch>("c3", fn(_cortado_c: Swatch) {  // Petrichor.bx:39
            _cortado_c.name = "LAPIS"
            _cortado_c.hex = "#1E50A2"
            _cortado_c.tint = "#1E50A2"
        })
        b.child<Swatch>("c4", fn(_cortado_c: Swatch) {  // Petrichor.bx:40
            _cortado_c.name = "PEACH PINK"
            _cortado_c.hex = "#F09199"
            _cortado_c.tint = "#F09199"
        })
        b.child<Swatch>("c5", fn(_cortado_c: Swatch) {  // Petrichor.bx:41
            _cortado_c.name = "ANCIENT PURPLE"
            _cortado_c.hex = "#895B8A"
            _cortado_c.tint = "#895B8A"
        })
        b.close()
        b.close()
        b.open("Grid")  // Petrichor.bx:48
        b.number("min_column", (160) as f64)
        b.number("max_column", (260) as f64)
        b.word("justify", "center")
        b.number("column_gap", (10) as f64)
        b.number("row_gap", (10) as f64)
        b.number("margin_top", (12) as f64)
        b.word("align", "stretch")
        b.open("VStack")  // Petrichor.bx:50
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<AuroraGradient>("c6", fn(_cortado_c: AuroraGradient) {  // Petrichor.bx:51
        }).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:52
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("AURORA")
        b.close()
        b.close()
        b.open("VStack")  // Petrichor.bx:54
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<FlowGradient>("c7", fn(_cortado_c: FlowGradient) {  // Petrichor.bx:55
        }).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:56
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("FLOW")
        b.close()
        b.close()
        b.open("VStack")  // Petrichor.bx:58
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<PrismGradient>("c8", fn(_cortado_c: PrismGradient) {  // Petrichor.bx:59
        }).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:60
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("PRISM")
        b.close()
        b.close()
        b.open("VStack")  // Petrichor.bx:62
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<GlowGradient>("c9", fn(_cortado_c: GlowGradient) {  // Petrichor.bx:63
        }).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:64
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("GLOW")
        b.close()
        b.close()
        b.open("VStack")  // Petrichor.bx:66
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.child<SkyGradient>("c10", fn(_cortado_c: SkyGradient) {  // Petrichor.bx:67
        }).number("aspect_ratio", (1.95) as f64)
        b.open("Label")  // Petrichor.bx:68
        b.number("alignment", (1) as f64)
        b.number("font_size", (10) as f64)
        b.word("text_color", "#2b2430")
        b.text("SKY")
        b.close()
        b.close()
        b.close()
        b.close()
        b.close()
        b.close()
    }
}
