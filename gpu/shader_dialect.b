// The spellings that differ between shading languages.
package gpu

import cortado.widgets

/// How one shading language spells what a gradient needs.
///
/// This is the seam a second language lands on. A gradient writes its body
/// through a dialect and never names a type or a built-in directly, so adding
/// Windows or Linux is a row in `of` and a wrapper in `ShaderCanvas` — not a
/// change to any gradient, and not a change to any markup that uses one.
pub class ShaderDialect {
    pub language: ShaderLanguage = ShaderLanguage.msl
    /// Vector type names. GLSL says `vec3` where MSL and HLSL say `float3`.
    pub v2: string = "float2"
    pub v3: string = "float3"
    pub v4: string = "float4"
    /// Built-ins whose names differ. HLSL says `frac` where the others say
    /// `fract`, and `lerp` where they say `mix`.
    pub frac: string = "fract"
    pub blend: string = "mix"

    pub fn init(language: ShaderLanguage, v2: string, v3: string, v4: string,
                frac: string, blend: string) {
        self.language = language
        self.v2 = v2
        self.v3 = v3
        self.v4 = v4
        self.frac = frac
        self.blend = blend
    }

    /// A colour as a literal of this language's three-component vector type.
    pub fn rgb(value: widgets.Rgba) -> string {
        let red: f64 = value.red as f64 / 255.0
        let green: f64 = value.green as f64 / 255.0
        let blue: f64 = value.blue as f64 / 255.0
        return "{self.v3}({red}, {green}, {blue})"
    }

    /// A two-component literal.
    pub fn xy(x: f64, y: f64) -> string {
        return "{self.v2}({x}, {y})"
    }

    /// A three-component literal.
    pub fn xyz(x: f64, y: f64, z: f64) -> string {
        return "{self.v3}({x}, {y}, {z})"
    }

    /// A three-component literal of one repeated number.
    pub fn grey(value: f64) -> string {
        return "{self.v3}({value}, {value}, {value})"
    }

    /// The dialect for a language, or none where cortado has none.
    ///
    /// HLSL and GLSL differ from MSL in the names above and in almost nothing
    /// else for this kind of shader. What is missing is not the arithmetic —
    /// it is the whole-program wrapper, which is why `ShaderCanvas.languages`
    /// and not this table is the list a gradient actually picks from.
    pub static fn of(language: ShaderLanguage) -> Option<ShaderDialect> {
        return match language {
            msl => some(new ShaderDialect(language, "float2", "float3", "float4", "fract", "mix")),
            hlsl => none,
            spirv => none,
            glsl => none,
        }
    }
}
