// What every named gradient shares.
package gpu

import cortado.component
import cortado.widgets
import std.fmt

/// A moving background, named rather than written.
///
/// `ShaderCanvas` is the escape hatch: it takes a body somebody typed, in one
/// language, and compiles it. A `Gradient` is the road most screens want — it
/// *writes* the body from a handful of attributes, through a `ShaderDialect`,
/// so the same markup can reach a second platform without being edited.
///
/// In markup that is one line:
///
/// ```
/// <MeshGradient grow={1} color_1="#EAF4FC" color_2="#1E50A2" />
/// ```
///
/// Subclasses override `write`. Everything below — picking a language the host
/// will actually take, refusing in terms of the screen when there is none, and
/// owning the canvas underneath — is done once, here.
pub abstract class Gradient extends component.Component {
    /// How fast it moves, as a multiple of the gradient's own pace. Zero holds
    /// it still, which is a legitimate thing to ask a background for.
    pub speed: f64 = 1.0
    /// Film grain, as a multiple of the gradient's own. Zero is clean.
    pub grain: f64 = 1.0

    priv paint: ShaderCanvas = new ShaderCanvas()
    priv trouble: string = ""
    priv built: string = ""

    pub fn init() { super.init() }

    /// Write this gradient's fragment body in `dialect`'s language.
    ///
    /// A subclass names no type and no built-in directly; it asks the dialect,
    /// which is what makes one gradient's source portable by construction.
    pub abstract fn write(dialect: ShaderDialect) -> Result<string>

    /// Why nothing is drawing, or "" when something is.
    ///
    /// One answer, not two: a gradient that could not choose a language says
    /// so, and otherwise the canvas underneath speaks for itself.
    /// How many frames this gradient has actually put on screen.
    ///
    /// The canvas's own count, not the clock's: a tick that found no drawable
    /// free drew nothing, and a frame rate built from ticks would not know it.
    pub fn frames() -> int {
        return self.paint.frames()
    }

    pub fn problem() -> string {
        if self.trouble != "" { return self.trouble }
        return self.paint.problem()
    }

    /// The dialect this host will actually take.
    ///
    /// The intersection of what the host accepts and what cortado can write a
    /// whole program in — never one without the other, because half of either
    /// is a shader that fails at the driver instead of here.
    pub static fn dialect() -> Result<ShaderDialect> {
        for language: ShaderLanguage in ShaderCanvas.languages() {
            if language.accepted() {
                match ShaderDialect.of(language) {
                    some(found) => { return ok(found) }
                    none => {}
                }
            }
        }
        return err("no gradient can be drawn here: cortado writes {ShaderCanvas.written_names()} and this host accepts {Gradient.accepted_names()}",
                   "no_language")
    }

    /// What the host said it accepts, for a message. "nothing" where it named
    /// none at all, which is a platform without a GPU rather than a mismatch.
    pub static fn accepted_names() -> string {
        var names: List<string> = []
        for language: ShaderLanguage in ShaderLanguage.all() {
            if language.accepted() { names.push(language.name()) }
        }
        if names.len() == 0 { return "nothing" }
        return names.join(", ")
    }

    /// The dialect a gradient is *checked* against when the host will take
    /// none — the first cortado can write, so there is always one.
    pub static fn reference() -> Option<ShaderDialect> {
        for language: ShaderLanguage in ShaderCanvas.languages() {
            match ShaderDialect.of(language) {
                some(found) => { return some(found) }
                none => {}
            }
        }
        return none
    }

    /// The body this gradient compiles to, for a reader who wants to see it.
    ///
    /// The attributes are checked before the machine is, and that order is the
    /// point: `lobe={7}` is wrong on every host, and a developer whose laptop
    /// has no GPU would otherwise be told only that it has no GPU.
    pub fn source() -> Result<string> {
        match Gradient.dialect() {
            ok(chosen) => { return self.write(chosen) }
            err(missing) => {
                match Gradient.reference() {
                    some(check) => { self.write(check)? }
                    none => {}
                }
                return err(missing.msg, missing.kind)
            }
        }
    }

    /// Built once, when the attributes are in.
    ///
    /// Not in `render`, which is called far more often than a shader is
    /// compiled, and not lazily either — a failure wants to be in `problem()`
    /// before the first frame rather than after it.
    pub override fn on_params_set() {
        match self.source() {
            ok(body) => { self.built = body; self.trouble = "" }
            err(problem) => { self.built = ""; self.trouble = problem.msg }
        }
    }

    pub override fn render(into: component.Builder) {
        self.paint.shader = self.built
        match Gradient.dialect() {
            ok(chosen) => { self.paint.written_in = chosen.language }
            err(problem) => {}
        }
        into.show("paint", self.paint)
    }

    /// A colour attribute, refused by name rather than by position.
    ///
    /// `of_hex` says what is wrong with the text; this says which attribute
    /// the text came from, which is the half a reader needs to fix it.
    fn colour(name: string, text: string) -> Result<widgets.Rgba> {
        match widgets.Rgba.of_hex(text) {
            ok(value) => { return ok(value) }
            err(problem) => {
                return err("{name}=\"{text}\" is not a colour: {problem.msg}", problem.kind)
            }
        }
    }

    /// The grain line every gradient ends with, or nothing at `grain={0}`.
    fn speckle(dialect: ShaderDialect, amount: f64) -> string {
        let scaled: f64 = amount * self.grain
        if scaled <= 0.0 { return "" }
        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float grain = {dialect.frac}(sin(dot(uv * size, {dialect.xy(12.9898, 78.233)})) * 43758.5453);\n")
        out.push("    col = col + (grain - 0.5) * {scaled};\n")
        return out.to_string()
    }
}
