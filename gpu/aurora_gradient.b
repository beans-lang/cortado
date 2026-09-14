// Curtains of light hanging from a wavy edge.
package gpu

import cortado.widgets
import std.fmt

/// Northern lights: up to three curtains, each hanging from its own drifting
/// edge and cut into flutes, added over a dark sky.
///
/// ```
/// <AuroraGradient grow={1} bands={3} color_1="#2EE08F" />
/// ```
pub class AuroraGradient extends Gradient {
    pub background: string = "#090e1e"
    pub color_1: string = "#2ee08f"
    pub color_2: string = "#4d8afa"
    pub color_3: string = "#c757c2"

    /// How many curtains, 1 to 3. Each one costs a handful of instructions.
    pub bands: int = 3
    /// How far a curtain falls below its edge. Above one hangs further down.
    pub drop: f64 = 1.0

    pub fn init() { super.init() }

    pub override fn write(d: ShaderDialect) -> Result<string> {
        let sky: widgets.Rgba = self.colour("background", self.background)?
        let one: widgets.Rgba = self.colour("color_1", self.color_1)?
        let two: widgets.Rgba = self.colour("color_2", self.color_2)?
        let three: widgets.Rgba = self.colour("color_3", self.color_3)?
        if self.bands < 1 || self.bands > 3 {
            return err("bands={self.bands} is not a number of curtains — it is 1 to 3", "no_such_band")
        }
        if self.drop <= 0.0 {
            return err("drop={self.drop} would give a curtain no height — it is above zero", "no_drop")
        }
        let rate: f64 = 0.18 * self.speed

        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float t = seconds * {rate};\n")
        out.push("    {d.v2} p = uv;\n\n")
        out.push("    {d.v3} col = {d.rgb(sky)};\n")
        out.push("    col = col + {d.xyz(0.030, 0.040, 0.090)} * (1.0 - p.y);\n\n")
        out.push("    // A curtain hangs from a wavy top edge, bright along the edge and fading\n")
        out.push("    // down. The flutes are one phase-modulated sine, never zero, so no edge.\n")
        out.push(self.curtain(d, 1, one, 0.20, 3.10, 1.10, 0.09, 7.30, 0.70, 0.04, 3.10, 0.16, 0.07, 19.0, 1.30, 1.3, 4.0, 0.50, 0.95, 0.0))
        if self.bands >= 2 {
            out.push(self.curtain(d, 2, two, 0.30, 2.10, -0.90, 0.11, 5.90, -1.20, 0.05, 2.40, 0.18, 0.08, 14.0, -1.70, 1.1, 3.0, -0.80, 0.70, 1.7))
        }
        if self.bands >= 3 {
            out.push(self.curtain(d, 3, three, 0.44, 1.70, 0.70, 0.08, 9.10, 1.40, 0.04, 3.80, 0.14, 0.06, 26.0, 2.10, 1.4, 6.0, 0.60, 0.55, 3.4))
        }
        out.push(self.speckle(d, 0.020))
        out.push("    return {d.v4}(clamp(col, {d.grey(0.0)}, {d.grey(1.0)}), 1.0);\n")
        return ok(out.to_string())
    }

    /// One curtain. Every number that makes this one unlike its neighbours is
    /// a parameter, so three calls read as three curtains and not as one blur.
    fn curtain(d: ShaderDialect, n: int, tint: widgets.Rgba, base: f64,
               wave: f64, wave_rate: f64, wave_size: f64,
               ripple: f64, ripple_rate: f64, ripple_size: f64,
               fall: f64, above: f64, below: f64,
               flute: f64, flute_rate: f64, bend: f64, bend_wave: f64, bend_rate: f64,
               gain: f64, phase: f64) -> string {
        let drops: f64 = fall / self.drop
        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float top{n} = {base} + {wave_size} * sin(p.x * {wave} + t * {wave_rate} + {phase}) + {ripple_size} * sin(p.x * {ripple} - t * {ripple_rate});\n")
        out.push("    float d{n} = p.y - top{n};\n")
        out.push("    float f{n} = exp(-max(d{n}, 0.0) * {drops}) * smoothstep(-{above}, {below}, d{n});\n")
        out.push("    f{n} = f{n} * (0.55 + 0.45 * sin(p.x * {flute} + t * {flute_rate} + {bend} * sin(p.x * {bend_wave} - t * {bend_rate})));\n")
        out.push("    col = col + {d.rgb(tint)} * f{n} * {gain};\n\n")
        return out.to_string()
    }
}
