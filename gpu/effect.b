// Shaders you can name instead of write.
package gpu

import cortado.widgets

/// A shader described by a name and a few numbers.
///
/// **What this is for, and where it stops.** A shader is a program in another
/// language, and there is no honest way to express an arbitrary one in markup:
/// a shading language spelled in angle brackets would be harder to write than
/// the shading language, and harder to read. So cortado does the thing it does
/// everywhere else — a small set that is real and declarative, and an escape
/// hatch that is honest about being one.
///
/// ```
/// <ShaderCanvas height={44} effect="ripple" color="#4088bf" detail={26} />
/// ```
///
/// covers the decorative case, which is most of them. Anything else is
/// `shader={...}`, a fragment body, and the moment you need one you were
/// always going to be writing a shader.
///
/// Every effect takes the same six attributes and ignores the ones it has no
/// use for, which is deliberate: an author who changes `effect="ripple"` to
/// `effect="noise"` should not have to rename anything around it.
///
/// | attribute | what it means |
/// |---|---|
/// | `color` | the main colour, or where a two-colour effect starts |
/// | `color_to` | where a two-colour effect ends |
/// | `detail` | rings, squares, or the scale of the noise |
/// | `speed` | how fast it moves; `0` holds it still |
/// | `angle` | the direction of a gradient, in degrees |
pub enum(u8) Effect {
    /// One colour, everywhere. The only way cortado has to fill a rectangle
    /// with a colour at all, which is why it is worth having even though it
    /// uses no shading.
    solid
    /// `color` to `color_to` in a straight line, along `angle`.
    gradient
    /// `color` at the middle to `color_to` at the corners.
    radial
    /// Rings running outward. `detail` is how many, `speed` how fast.
    ripple
    /// Animated value noise between the two colours. `detail` is the scale.
    noise
    /// A checkerboard, `detail` squares across. Still by default; `speed`
    /// scrolls it.
    checker

    pub fn name() -> string {
        return match self {
            solid => "solid",
            gradient => "gradient",
            radial => "radial",
            ripple => "ripple",
            noise => "noise",
            checker => "checker",
        }
    }

    /// Every name, for an error message that can list them.
    pub static fn names() -> List<string> {
        var all: List<string> = []
        all.push("solid")
        all.push("gradient")
        all.push("radial")
        all.push("ripple")
        all.push("noise")
        all.push("checker")
        return move all
    }

    pub static fn of(name: string) -> Option<Effect> {
        if name == "solid" { return some(Effect.solid) }
        if name == "gradient" { return some(Effect.gradient) }
        if name == "radial" { return some(Effect.radial) }
        if name == "ripple" { return some(Effect.ripple) }
        if name == "noise" { return some(Effect.noise) }
        if name == "checker" { return some(Effect.checker) }
        return none
    }

    /// What `detail` means here when nobody said, so that an effect named and
    /// nothing else still looks like something.
    pub fn default_detail() -> f64 {
        return match self {
            solid => 0.0,
            gradient => 0.0,
            radial => 0.0,
            ripple => 22.0,
            noise => 6.0,
            checker => 8.0,
        }
    }

    /// The fragment body for this effect.
    ///
    /// Written as ordinary interpolated strings rather than raw ones, which is
    /// the opposite of everywhere else a shader appears in cortado — and it
    /// works for one reason worth checking before adding an effect: none of
    /// these bodies contains a `{`. The moment one needs a block, it needs a
    /// raw string and a builder, the way `ShaderCanvas.wrap` does it.
    pub fn body(color: widgets.Rgba, to: widgets.Rgba, detail: f64,
                speed: f64, angle: f64) -> string {
        let first: string = Effect.msl_color(color)
        let second: string = Effect.msl_color(to)
        return match self {
            solid => "    return {first};",
            gradient => "    float a = {angle} * 3.14159265 / 180.0;\n    float2 dir = float2(cos(a), sin(a));\n    float t = clamp(dot(uv - 0.5, dir) + 0.5, 0.0, 1.0);\n    return mix({first}, {second}, t);",
            radial => "    float t = clamp(length(uv - 0.5) * 1.4142136, 0.0, 1.0);\n    return mix({first}, {second}, t);",
            ripple => "    float rings = sin(length(uv - 0.5) * {detail} - seconds * {speed} * 3.0);\n    return mix({first}, {second}, 0.5 + 0.5 * rings);",
            noise => "    float2 p = uv * {detail} + float2(seconds * {speed} * 0.3, seconds * {speed} * 0.2);\n    float2 cell = floor(p);\n    float2 part = fract(p);\n    part = part * part * (3.0 - 2.0 * part);\n    float n00 = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);\n    float n10 = fract(sin(dot(cell + float2(1.0, 0.0), float2(12.9898, 78.233))) * 43758.5453);\n    float n01 = fract(sin(dot(cell + float2(0.0, 1.0), float2(12.9898, 78.233))) * 43758.5453);\n    float n11 = fract(sin(dot(cell + float2(1.0, 1.0), float2(12.9898, 78.233))) * 43758.5453);\n    float n = mix(mix(n00, n10, part.x), mix(n01, n11, part.x), part.y);\n    return mix({first}, {second}, n);",
            checker => "    float2 cell = floor((uv + float2(seconds * {speed} * 0.1, 0.0)) * {detail});\n    float on = fmod(cell.x + cell.y + 2048.0, 2.0);\n    return mix({first}, {second}, on);",
        }
    }

    /// A colour as MSL. Written out in full rather than passed as a uniform,
    /// because a colour that never changes belongs in the program the compiler
    /// sees — and because a uniform per effect would be a uniform layout the
    /// author of a `shader={...}` body would then have to match.
    static fn msl_color(value: widgets.Rgba) -> string {
        let red: f64 = value.red as f64 / 255.0
        let green: f64 = value.green as f64 / 255.0
        let blue: f64 = value.blue as f64 / 255.0
        let alpha: f64 = value.alpha as f64 / 255.0
        return "float4({red}, {green}, {blue}, {alpha})"
    }
}
