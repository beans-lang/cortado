// A shader in a rectangle, with everything else done for you.
package gpu

import cortado.host
import cortado.events
import cortado.motion
import cortado.component
import cortado.platform
import cortado.widgets
import cortado.geometry
import std.fmt

/// A canvas that runs one fragment shader, every frame, at the display's rate.
///
/// This is the easy road. `gpu.Device`, `Shader`, `Pipeline`, `Buffer`,
/// `Target` and `Pass` are all still there for a program that wants to place
/// its own vertices; this is for the far more common case, which is *a
/// rectangle with a shader in it*. Everything below is done for you: the
/// device, the vertex shader, a quad covering the area, the pipeline, the
/// frame clock, and taking it all down again when the component goes away.
///
/// In markup it is one line:
///
/// ```
/// <ShaderCanvas shader={self.plasma} height={200} />
/// ```
///
/// and the shader is a function body, not a whole Metal program:
///
/// ```beans
/// pub plasma: string = r"
///     float d = length(uv - 0.5);
///     return float4(0.5 + 0.5 * sin(d * 30.0 - seconds * 3.0), 0.2, 0.6, 1.0);
/// "
/// ```
///
/// **What the body gets**, and it is deliberately three things rather than
/// thirty:
///
/// | name | what it is |
/// |---|---|
/// | `uv` | `float2`, 0 to 1 across the canvas, 0,0 at the top left |
/// | `seconds` | `float`, since the canvas started drawing |
/// | `size` | `float2`, the canvas in pixels |
///
/// and it returns a `float4` of red, green, blue, alpha, each 0 to 1. A
/// program that needs more than that has outgrown this class and should build
/// its own pipeline, which is what the rest of this package is.
///
/// **Where there is no GPU** the component still renders its canvas — an empty
/// area of the right size, in the right place — and `problem()` says why
/// nothing is in it. A markup screen does not fall apart on a platform cortado
/// cannot draw on; it has a blank rectangle where the effect would be.
pub class ShaderCanvas extends component.Component {
    /// A shader by name — `"solid"`, `"gradient"`, `"radial"`, `"ripple"`,
    /// `"noise"` or `"checker"` — parameterised by the attributes below.
    ///
    /// This is the markup road, and it is the one to reach for first:
    ///
    /// ```
    /// <ShaderCanvas height={44} effect="ripple" color="#4088bf" detail={26} />
    /// ```
    ///
    /// There is no way to express an *arbitrary* shader in markup — a shading
    /// language spelled in angle brackets would be harder to write than the
    /// shading language — so cortado names the ones worth naming and is honest
    /// that `shader` is the way out. See `Effect`.
    pub effect: string = ""

    /// The main colour, or where a two-colour effect starts. `#rgb`,
    /// `#rrggbb` or `#rrggbbaa`.
    pub color: string = "#3b6ea5"
    /// Where a two-colour effect ends.
    pub color_to: string = "#0d1b2a"
    /// Rings, squares, or the scale of the noise. Zero takes the effect's own
    /// default, so an effect named and nothing else still looks like something.
    pub detail: f64 = 0.0
    /// How fast it moves. Zero holds it still.
    pub speed: f64 = 1.0
    /// The direction of a gradient, in degrees.
    pub angle: f64 = 90.0

    /// A fragment body, written by hand, for anything `effect` cannot name.
    ///
    /// Changing it after mount does nothing: a shader is compiled once, and
    /// recompiling on every render would compile one per keystroke in an
    /// editor.
    pub shader: string = ""
    /// How tall the canvas is, in points. Zero lets the run it sits in decide.
    pub height: f64 = 0.0
    /// How much of the leftover space it takes, in a flex run. Zero means
    /// none, which is right inside a plain stack.
    pub grow: f64 = 0.0

    priv card: Option<Device> = none
    priv paint: Option<Canvas> = none
    priv pipe: Option<Pipeline> = none
    priv quad: Option<Buffer> = none
    priv clock: Option<motion.FrameClock> = none
    priv trouble: string = ""
    priv drawn: int = 0

    pub fn init() { super.init() }

    /// The fragment body this canvas will compile: the one that was written,
    /// or the one the named effect generates.
    ///
    /// Both together is refused rather than one quietly winning. A canvas that
    /// ignored half of what it was told is the kind of thing somebody debugs
    /// for an afternoon before reading the source.
    pub fn body() -> Result<string> {
        if self.shader != "" && self.effect != "" {
            return err("a ShaderCanvas was given both a shader and the effect {self.effect} — one or the other",
                       "two_shaders")
        }
        if self.shader != "" {
            return ok(self.shader)
        }
        if self.effect == "" {
            return err("a ShaderCanvas was given neither a shader nor an effect — name one of {Effect.names().join(", ")}, or write a shader body",
                       "no_shader")
        }
        match Effect.of(self.effect) {
            some(named) => {
                let size: f64 = if self.detail == 0.0 { named.default_detail() } else { self.detail }
                let first: widgets.Rgba = widgets.Rgba.of_hex(self.color)?
                let second: widgets.Rgba = widgets.Rgba.of_hex(self.color_to)?
                return ok(named.body(first, second, size, self.speed, self.angle))
            }
            none => {
                return err("there is no effect called {self.effect} — the ones there are: {Effect.names().join(", ")}",
                           "no_such_effect")
            }
        }
    }

    /// Why nothing is drawing, or "" when something is.
    pub fn problem() -> string {
        return self.trouble
    }

    /// How many frames have been drawn. A test asserts this rather than a
    /// pixel, because a pixel of a moving shader is a different pixel every
    /// time it is asked for.
    pub fn frames() -> int {
        return self.drawn
    }

    pub override fn render(into: component.Builder) {
        into.open("Canvas")
        // The key is how `on_mount` finds this control again. It is scoped to
        // this component, so a screen with three of these does not need three
        // different names.
        into.key("surface")
        if self.height > 0.0 { into.number("height", self.height) }
        if self.grow > 0.0 { into.number("grow", self.grow) }
        into.close()
    }

    pub override fn on_mount(stage: component.Stage) {
        match self.begin(stage) {
            ok(started) => {}
            err(problem) => { self.trouble = problem.msg }
        }
    }

    /// Everything that can fail, in one place, so `on_mount` stays readable
    /// and every failure lands in `problem()` instead of being swallowed.
    priv fn begin(stage: component.Stage) -> Result<bool> {
        let body: string = self.body()?
        if !platform.Capability.gpu.available() {
            return err("this platform has no GPU host, so the canvas stays empty",
                       "unsupported")
        }
        var control: host.Handle = host.Handle.none()
        match stage.control("surface") {
            some(found) => { control = found }
            none => { return err("the canvas this component rendered is not there", "no_control") }
        }

        var device: Device = Device.open()?
        var painter: Canvas = Canvas.on(control, device)?
        var compiled: Shader = device.shader(ShaderLanguage.msl, ShaderCanvas.wrap(body))?
        var line: Pipeline = compiled.pipeline("cortado_vertex", "cortado_fragment")?
        line.attr(0, 2, 0)?
        line.attr(1, 2, 2)?
        line.stride(4)?
        line.pixels(Pixels.screen)?
        line.build()?
        var corners: Buffer = device.buffer(ShaderCanvas.quad_corners())?

        self.card = some(device)
        self.paint = some(painter)
        self.pipe = some(line)
        self.quad = some(corners)

        let surface: host.Handle = stage.surface()
        if surface.raw == 0 {
            // Nothing is on screen, which is a headless test rather than a
            // mistake. The canvas is set up and will draw when it is driven;
            // it simply has no display asking it to.
            return ok(true)
        }
        var beat: motion.FrameClock = new motion.FrameClock(surface, stage.router())
        self.clock = some(beat)
        beat.start(ShaderCanvas.token_of(control), fn(frame: motion.Frame) {
            self.draw(frame.elapsed)
        })?
        return ok(true)
    }

    /// Draws one frame. Public so a program with its own clock — or a test with
    /// no display at all — can drive it.
    pub fn draw(seconds: f64) -> bool {
        match self.paint {
            some(painter) => {
                match painter.next() {
                    ok(surface) => {
                        match self.draw_into(surface, seconds) {
                            ok(drew) => { self.drawn = self.drawn + 1; return true }
                            err(problem) => { self.trouble = problem.msg; return false }
                        }
                    }
                    err(problem) => {
                        // Being told to wait for a drawable is normal — the
                        // platform holds a few frames and hands them back as
                        // the compositor finishes with them. A canvas with no
                        // size is not: it is a layout mistake that would
                        // otherwise show up as a silent empty rectangle, so it
                        // is reported and every later frame stops asking.
                        if problem.kind == "no_size" { self.trouble = problem.msg }
                        return false
                    }
                }
            }
            none => { return false }
        }
    }

    priv fn draw_into(surface: Target, seconds: f64) -> Result<bool> {
        match self.pipe {
            some(line) => {
                match self.quad {
                    some(corners) => {
                        let extent: geometry.Size = surface.size()?
                        var pass: Pass = surface.begin(0.0, 0.0, 0.0, 1.0)?
                        pass.pipeline(line)?
                        pass.vertices(corners)?
                        // seconds, then the canvas in real pixels. The fourth
                        // is spare: Metal wants a constant buffer aligned, and
                        // a named spare is clearer than a comment about
                        // padding somebody will one day remove.
                        pass.uniform([seconds, extent.width, extent.height, 0.0])?
                        pass.draw(Shape.triangles, 0, 6)?
                        return pass.present()
                    }
                    none => { return err("this canvas has no vertices", "not_ready") }
                }
            }
            none => { return err("this canvas has no pipeline", "not_ready") }
        }
    }

    pub override fn on_unmount() {
        // The clock first: a frame that arrived after the device was closed
        // would draw with a handle that is already stale.
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

    // ------------------------------------------------------------ the shader

    /// Wraps a fragment body in the program Metal actually needs.
    ///
    /// Public because what cortado generates should be readable: a program
    /// that has outgrown `effect=` can print this, paste it, and start from
    /// the shader it was already running instead of from a blank file.
    ///
    /// The author writes three lines about colour; this is the thirty they
    /// would otherwise copy, and copying it is how three canvases end up with
    /// three slightly different vertex shaders.
    ///
    /// Built with a `StringBuilder` out of raw strings rather than written as
    /// one interpolated string, for a reason worth knowing: a shader is full
    /// of `{`, and an ordinary Beans string reads that as the start of an
    /// interpolation. A raw string does not — but then it cannot interpolate
    /// the body either. Three pieces and a join is the way out.
    pub static fn wrap(body: string) -> string {
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

fragment float4 cortado_fragment(CortadoOut v [[stage_in]],
                                 constant CortadoFrame &frame [[buffer(1)]]) {
    float2 uv = v.place;
    float seconds = frame.seconds;
    float2 size = float2(frame.width, frame.height);
    (void)uv; (void)seconds; (void)size;
")
        out.push(body)
        out.push(r"
}
")
        return out.to_string()
    }

    /// The vertices `ShaderCanvas` draws with: two triangles covering the
    /// area, carrying a 0-to-1 coordinate for the shader.
    ///
    /// Public for the same reason `wrap` is: a program that has outgrown
    /// `effect=` should be able to start from what cortado was already doing
    /// rather than from a blank file.
    pub static fn quad_corners() -> List<f64> {
        var at: List<f64> = [
            -1.0, -1.0,  0.0, 1.0,
             1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
             1.0, -1.0,  1.0, 1.0,
             1.0,  1.0,  1.0, 0.0,
            -1.0,  1.0,  0.0, 0.0
        ]
        return move at
    }

    /// A token for the frame clock, distinct per canvas so two on one screen
    /// do not answer to each other's frames.
    static fn token_of(control: host.Handle) -> int {
        return control.raw as int
    }
}
