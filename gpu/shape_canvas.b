// A shape in a rectangle, with everything else done for you.
package gpu

import cortado.host
import cortado.events
import cortado.motion
import cortado.component
import cortado.platform
import cortado.widgets
import cortado.geometry
import std.fmt

/// A rounded rectangle, an ellipse, a ring or a capsule — filled, stroked and
/// shadowed, drawn by the GPU.
///
/// ```
/// <ShapeCanvas figure="rounded_rect" radius={12} height={64}
///              fill="gradient" color="#3b6ea5" color_to="#0d1b2a"
///              stroke="#ffffff" stroke_width={2}
///              shadow="#00000060" shadow_radius={8} shadow_y={2} inset={10} />
/// ```
///
/// A shape is a mask and an `Effect` is a material, so they multiply: all six
/// fills work with all four figures and `gpu/effect.b` did not change.
///
/// The edge is a fixed one-pixel ramp, not `fwidth`: a screen-space derivative
/// would make a boundary pixel the GPU's business rather than this program's.
///
/// Compositing is `mix(under, over, coverage * over.a)` — exact where the
/// colours are opaque, the usual approximation where they are not.
pub class ShapeCanvas extends component.Component {
    /// Which shape: `"rounded_rect"`, `"ellipse"`, `"ring"` or `"capsule"`.
    pub figure: string = "rounded_rect"
    /// Corner radius in **points**, for `rounded_rect`. Past half the shorter
    /// side it is clamped, which is a capsule.
    pub radius: f64 = 0.0
    /// How wide a `ring`'s band is, in points, measured inward from the edge.
    pub thickness: f64 = 0.0

    /// The material inside the shape — an `Effect` name. `"solid"` is one
    /// colour, which is what most shapes want.
    pub fill: string = "solid"
    /// The main colour, or where a two-colour fill starts.
    pub color: string = "#3b6ea5"
    /// Where a two-colour fill ends.
    pub color_to: string = "#0d1b2a"
    /// Rings, squares, or the scale of the noise, for the fills that have one.
    pub detail: f64 = 0.0
    /// How fast the fill moves. Zero by default, unlike `ShaderCanvas`:
    /// furniture that animates costs a frame clock for ever.
    pub speed: f64 = 0.0
    /// The direction of a gradient fill, in degrees.
    pub angle: f64 = 90.0

    /// The outline's colour. `""` is no outline.
    pub stroke: string = ""
    /// Outline thickness in points, drawn inward like `CALayer.borderWidth`:
    /// an outward one needs room the layout never gave it.
    pub stroke_width: f64 = 1.0

    /// The shadow's colour, alpha included. `""` is no shadow.
    pub shadow: string = ""
    /// How far the shadow is blurred, in points.
    pub shadow_radius: f64 = 0.0
    /// How far the shadow is moved, in points. `shadow_y` is **downward**,
    /// which is this project's y everywhere above the GPU.
    pub shadow_x: f64 = 0.0
    pub shadow_y: f64 = 0.0

    /// What is behind the shape, inside this canvas. Transparent by default.
    pub background: string = "#00000000"
    /// Points kept clear around the figure, inside the canvas — the room a
    /// stroke or a shadow needs.
    pub inset: f64 = 0.0


    priv card: Option<Device> = none
    priv paint: Option<Canvas> = none
    priv pipe: Option<Pipeline> = none
    priv quad: Option<Buffer> = none
    priv clock: Option<motion.FrameClock> = none
    priv trouble: string = ""
    priv drawn: int = 0
    priv scale: f64 = 1.0
    priv control: host.Handle = host.Handle.none()
    /// The control's size the last time this canvas drew, so a still shape can
    /// tell "nothing has changed" from "I have never drawn".
    priv last_width: f64 = 0.0
    priv last_height: f64 = 0.0

    pub fn init() { super.init() }

    /// Why nothing is drawing, or "" when something is.
    pub fn problem() -> string {
        return self.trouble
    }

    /// How many frames have been drawn.
    pub fn frames() -> int {
        return self.drawn
    }

    /// The backing scale this canvas draws at, 1 before it is mounted. Public
    /// because everything it is given is points and everything it draws is pixels.
    pub fn backing_scale() -> f64 {
        return self.scale
    }

    /// Whether the fill moves. A still shape draws on its first size and on
    /// each change, and nothing between — see `needs_redraw`.
    pub fn animates() -> bool {
        if self.speed == 0.0 { return false }
        match Effect.of(self.fill) {
            some(named) => { return named.default_detail() > 0.0 }
            none => { return false }
        }
    }

    // -------------------------------------------------------------- refusals

    /// The figure this canvas will draw, or why it cannot.
    pub fn chosen() -> Result<Figure> {
        match Figure.of(self.figure) {
            some(found) => { return ok(found) }
            none => {
                return err("a ShapeCanvas was given figure=\"{self.figure}\", which is not one cortado draws — name one of {Figure.names().join(", ")}",
                           "no_such_figure")
            }
        }
    }

    /// The fill, or why it cannot be one.
    pub fn material() -> Result<Effect> {
        match Effect.of(self.fill) {
            some(found) => { return ok(found) }
            none => {
                return err("a ShapeCanvas was given fill=\"{self.fill}\", which is not a fill cortado has — name one of {Effect.names().join(", ")}",
                           "no_such_effect")
            }
        }
    }

    /// Everything this canvas is asked to draw, checked together — each of
    /// these would otherwise draw something and ignore the rest.
    priv fn settled() -> Result<bool> {
        let shape: Figure = self.chosen()?
        let paint: Effect = self.material()?

        if self.radius != 0.0 && !shape.reads_radius() {
            return err("a {shape.name()} has no corners, so radius={self.radius} would do nothing — take it off, or use figure=\"rounded_rect\"",
                       "unused_radius")
        }
        if self.thickness != 0.0 && !shape.reads_thickness() {
            return err("a {shape.name()} is solid, so thickness={self.thickness} would do nothing — take it off, or use figure=\"ring\"",
                       "unused_thickness")
        }
        if shape.reads_thickness() && self.thickness <= 0.0 {
            return err("a ring is the band between two edges, so it needs a thickness — give it one in points",
                       "no_thickness")
        }

        // Half a stroke draws nothing. Both are named, so the message is about
        // whichever one is missing.
        if self.stroke == "" && self.stroke_width != 1.0 && self.stroke_width > 0.0 {
            return err("a ShapeCanvas was given stroke_width={self.stroke_width} and no stroke colour — give it a stroke, or take the width off",
                       "no_stroke")
        }
        if self.stroke != "" && self.stroke_width <= 0.0 {
            return err("a ShapeCanvas was given stroke=\"{self.stroke}\" and a width of {self.stroke_width} — a stroke needs a width above zero",
                       "no_stroke_width")
        }

        if self.shadow != "" {
            let reach: f64 = self.shadow_radius + ShapeCanvas.larger(ShapeCanvas.magnitude(self.shadow_x),
                                                                    ShapeCanvas.magnitude(self.shadow_y))
            if self.inset < reach {
                return err("this shadow reaches {reach} points past the figure and the canvas only keeps {self.inset} clear, so it would be cut off at the edge — set inset={reach} or more",
                           "no_room")
            }
        }
        // Every colour is parsed here, including ones only `program` uses:
        // otherwise the same canvas answers two things about one mistake.
        let _ground: widgets.Rgba = widgets.Rgba.of_hex(self.background)?
        let _first: widgets.Rgba = widgets.Rgba.of_hex(self.color)?
        let _second: widgets.Rgba = widgets.Rgba.of_hex(self.color_to)?
        if self.stroke != "" {
            let _edge: widgets.Rgba = widgets.Rgba.of_hex(self.stroke)?
        }
        if self.shadow != "" {
            let _shade: widgets.Rgba = widgets.Rgba.of_hex(self.shadow)?
        }

        // Named so the compiler does not think it is unused; `body` reads it.
        let _: Effect = paint
        return ok(true)
    }

    static fn magnitude(value: f64) -> f64 {
        if value < 0.0 { return 0.0 - value }
        return value
    }

    static fn larger(first: f64, second: f64) -> f64 {
        if first > second { return first }
        return second
    }

    // --------------------------------------------------------------- the MSL

    /// Background, shadow, fill, stroke — the order they sit in depth. An
    /// interpolated string, which works because no line contains a `{`.
    pub fn body() -> Result<string> {
        self.settled()?
        let ground: widgets.Rgba = widgets.Rgba.of_hex(self.background)?

        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float4 paint = {Effect.msl_color(ground)};\n")

        if self.shadow != "" {
            let shade: widgets.Rgba = widgets.Rgba.of_hex(self.shadow)?
            // Widened by subtracting from the distance rather than growing the
            // extent, so the shadow keeps the caster's shape.
            out.push("    float2 cast_at = p - float2({self.shadow_x}, {self.shadow_y}) * scale;\n")
            out.push("    float cast_d = cortado_distance(cast_at, half_extent, radius, thickness) - {self.shadow_radius} * scale;\n")
            out.push("    float4 cast_colour = {Effect.msl_color(shade)};\n")
            out.push("    paint = mix(paint, cast_colour, cortado_cover(cast_d) * cast_colour.a);\n")
        }

        out.push("    float4 inside = cortado_fill(uv, seconds, size);\n")
        out.push("    paint = mix(paint, inside, cortado_cover(d) * inside.a);\n")

        if self.stroke != "" {
            let edge: widgets.Rgba = widgets.Rgba.of_hex(self.stroke)?
            // The band is where the distance lies between -width and 0, which
            // is the difference of two coverages of the same edge.
            out.push("    float4 edge_colour = {Effect.msl_color(edge)};\n")
            out.push("    float edge_a = cortado_cover(d) - cortado_cover(d + {self.stroke_width} * scale);\n")
            out.push("    paint = mix(paint, edge_colour, edge_a * edge_colour.a);\n")
        }

        out.push("    return paint;")
        return ok(out.to_string())
    }

    /// The whole Metal program this canvas runs. Public so a program that has
    /// outgrown `<ShapeCanvas>` starts from this rather than a blank file.
    pub fn program() -> Result<string> {
        let shape: Figure = self.chosen()?
        let paint: Effect = self.material()?
        let first: widgets.Rgba = widgets.Rgba.of_hex(self.color)?
        let second: widgets.Rgba = widgets.Rgba.of_hex(self.color_to)?
        let size: f64 = if self.detail == 0.0 { paint.default_detail() } else { self.detail }
        let shape_body: string = self.body()?
        return ok(ShapeCanvas.wrap(shape,
                                   paint.body(first, second, size, self.speed, self.angle),
                                   self.radius, self.thickness, self.inset,
                                   shape_body))
    }

    /// The program, assembled from raw strings: a shader is full of `{`, which
    /// an ordinary Beans string reads as interpolation.
    pub static fn wrap(shape: Figure, fill_body: string,
                       radius: f64, thickness: f64, inset: f64,
                       shape_body: string) -> string {
        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push(r"#include <metal_stdlib>
using namespace metal;

struct CortadoIn    { float2 at [[attribute(0)]]; float2 place [[attribute(1)]]; };
struct CortadoOut   { float4 at [[position]]; float2 place; };
struct CortadoFrame { float seconds; float width; float height; float spare; };

vertex CortadoOut cortado_vertex(CortadoIn v [[stage_in]]) {
    CortadoOut out;
    out.at = float4(v.at, 0.0, 1.0);
    out.place = v.place;
    return out;
}

/// How much of this pixel the shape covers, as a fixed one-pixel ramp about
/// the edge. Not fwidth: see ShapeCanvas.
static float cortado_cover(float d) {
    return clamp(0.5 - d, 0.0, 1.0);
}

static float cortado_distance(float2 p, float2 half_extent, float radius, float thickness) {
    (void)radius; (void)thickness;
")
        out.push(shape.distance_body())
        out.push(r"
    return d;
}

static float4 cortado_fill(float2 uv, float seconds, float2 size) {
    (void)uv; (void)seconds; (void)size;
")
        out.push(fill_body)
        out.push(r"
}

fragment float4 cortado_fragment(CortadoOut v [[stage_in]],
                                 constant CortadoFrame &frame [[buffer(1)]]) {
    float2 uv = v.place;
    float seconds = frame.seconds;
    float2 size = float2(frame.width, frame.height);
    float scale = max(frame.spare, 1.0);
    float2 p = (uv - 0.5) * size;
")
        out.push("    float2 half_extent = max(size * 0.5 - {inset} * scale, float2(0.0, 0.0));\n")
        out.push("    float radius = {radius} * scale;\n")
        out.push("    float thickness = {thickness} * scale;\n")
        out.push(r"    float d = cortado_distance(p, half_extent, radius, thickness);
")
        out.push(shape_body)
        out.push(r"
}
")
        return out.to_string()
    }

    // ------------------------------------------------------------ the control

    pub override fn render(into: component.Builder) {
        into.open("Canvas")
        into.key("surface")
        into.close()
    }

    pub override fn on_mount(stage: component.Stage) {
        match self.begin(stage) {
            ok(started) => {}
            err(problem) => { self.trouble = problem.msg }
        }
    }

    /// Everything that can fail, in one place, so every failure lands in
    /// `problem()` rather than being swallowed.
    priv fn begin(stage: component.Stage) -> Result<bool> {
        let source: string = self.program()?
        if !platform.Capability.gpu.available() {
            return err("this platform has no GPU host, so the shape stays empty",
                       "unsupported")
        }
        var control: host.Handle = host.Handle.none()
        match stage.control("surface") {
            some(found) => { control = found }
            none => { return err("the canvas this component rendered is not there", "no_control") }
        }

        var device: Device = Device.open()?
        var painter: Canvas = Canvas.on(control, device)?
        var compiled: Shader = device.shader(ShaderLanguage.msl, source)?
        var line: Pipeline = compiled.pipeline("cortado_vertex", "cortado_fragment")?
        line.attr(0, 2, 0)?
        line.attr(1, 2, 2)?
        line.stride(4)?
        line.pixels(Pixels.screen)?
        line.build()?
        var corners: Buffer = device.buffer(ShaderCanvas.quad_corners())?

        self.control = control
        self.card = some(device)
        self.paint = some(painter)
        self.pipe = some(line)
        self.quad = some(corners)

        let surface: host.Handle = stage.surface()
        self.scale = ShapeCanvas.scale_of(surface)
        if surface.raw == 0 {
            // Headless: set up and drawable, with no display asking for it.
            return ok(true)
        }
        // Nothing is drawn here: `on_mount` runs before `lay_out`, so the
        // canvas is still 0 by 0. The first frame is the earliest it has a size.
        var beat: motion.FrameClock = new motion.FrameClock(surface, stage.router())
        self.clock = some(beat)
        beat.start(ShapeCanvas.token_of(control), fn(frame: motion.Frame) {
            if self.needs_redraw() { self.draw(frame.elapsed) }
        })?
        return ok(true)
    }

    pub override fn on_unmount() {
        match self.clock {
            some(beat) => { beat.stop() }
            none => {}
        }
        self.clock = none
        self.paint = none
        self.pipe = none
        self.quad = none
        self.card = none
    }

    /// The backing scale of a surface, or 1 where there is no surface — which
    /// is the headless case and not a mistake.
    static fn scale_of(surface: host.Handle) -> f64 {
        if surface.raw == 0 { return 1.0 }
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            if host.ctd_surface_scale(surface.raw, scratch.reals) as int != 0 {
                return 1.0
            }
        }
        let read: f64 = scratch.real(0)
        if read <= 0.0 { return 1.0 }
        return read
    }

    static fn token_of(control: host.Handle) -> int {
        return control.raw as int
    }

    /// Whether the next frame would differ from the last. It rides the clock
    /// rather than watching resizes because `EventRouter.watch` replaces per
    /// (target, kind) and `Mount` already holds the surface's watcher — taking
    /// it would stop the tree following its window. A per-widget resize event
    /// or a post-layout lifecycle hook would remove this; neither exists.
    pub fn needs_redraw() -> bool {
        if self.animates() { return true }
        if self.drawn == 0 { return true }
        let now: geometry.Size = self.control_size()
        return now.width != self.last_width || now.height != self.last_height
    }

    /// The control's size in points, or zero when there is no control.
    priv fn control_size() -> geometry.Size {
        if self.control.raw == 0 { return geometry.Size.of(0.0, 0.0) }
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            if host.ctd_view_frame(self.control.raw, scratch.reals) != 0 {
                return geometry.Size.of(0.0, 0.0)
            }
        }
        return geometry.Size.of(scratch.real(2), scratch.real(3))
    }

    /// Draws one frame. Public so a program with its own clock — or a test
    /// with no display at all — can drive it.
    pub fn draw(seconds: f64) -> bool {
        match self.paint {
            some(painter) => {
                match painter.next() {
                    ok(surface) => {
                        match self.draw_into(surface, seconds, true) {
                            // Cleared on a frame that landed, for the reason
                            // `ShaderCanvas.draw` gives: a shape laid out at no
                            // width says so and gets a size on the pass after,
                            // and the old message is then no longer true.
                            ok(drew) => {
                                self.trouble = ""
                                self.drawn = self.drawn + 1
                                let now: geometry.Size = self.control_size()
                                self.last_width = now.width
                                self.last_height = now.height
                                return true
                            }
                            err(problem) => { self.trouble = problem.msg; return false }
                        }
                    }
                    err(problem) => {
                        if problem.kind == "no_size" { self.trouble = problem.msg }
                        return false
                    }
                }
            }
            none => { return false }
        }
    }

    /// Draws one frame and reads it back instead of presenting it. The same
    /// path `draw` takes, uniforms and all, or it would prove nothing.
    pub fn snapshot(seconds: f64) -> Result<widgets.Snapshot> {
        match self.paint {
            none => { return err("this shape has no canvas to draw into", "not_ready") }
            some(painter) => {
                var frame: Target = painter.next()?
                self.draw_into(frame, seconds, false)?
                return frame.read()
            }
        }
    }

    priv fn draw_into(surface: Target, seconds: f64, show: bool) -> Result<bool> {
        match self.pipe {
            some(line) => {
                match self.quad {
                    some(corners) => {
                        let extent: geometry.Size = surface.size()?
                        var pass: Pass = surface.begin(0.0, 0.0, 0.0, 0.0)?
                        pass.pipeline(line)?
                        pass.vertices(corners)?
                        // seconds, the canvas in pixels, and the backing scale.
                        // `ShaderCanvas` leaves the fourth spare; a shape cannot.
                        pass.uniform([seconds, extent.width, extent.height, self.scale])?
                        pass.draw(Shape.triangles, 0, 6)?
                        // Finished rather than presented: a frame handed to the
                        // compositor is not ours to read.
                        if !show { return pass.finish() }
                        return pass.present()
                    }
                    none => { return err("this canvas has no vertices", "not_ready") }
                }
            }
            none => { return err("this canvas has no pipeline", "not_ready") }
        }
    }
}
