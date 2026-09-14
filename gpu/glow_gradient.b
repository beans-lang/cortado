// Soft orbs of light, breathing.
package gpu

import cortado.widgets
import std.fmt

/// Up to three soft orbs drifting over a dark ground, each breathing at its
/// own rate. The quietest of these gradients, and the one that sits under text.
///
/// ```
/// <GlowGradient grow={1} orbs={2} radius={1.2} pulse={0.5} />
/// ```
pub class GlowGradient extends Gradient {
    pub background: string = "#0e101a"
    pub color_1: string = "#6582fa"
    pub color_2: string = "#eb73ad"
    pub color_3: string = "#8ae9e7"

    /// How many orbs, 1 to 3.
    pub orbs: int = 3
    /// How wide they are. Above one and they overlap into a single wash.
    pub radius: f64 = 1.0
    /// How much they brighten and dim. Zero holds them at full.
    pub pulse: f64 = 1.0

    pub fn init() { super.init() }

    pub override fn write(d: ShaderDialect) -> Result<string> {
        let ground: widgets.Rgba = self.colour("background", self.background)?
        let one: widgets.Rgba = self.colour("color_1", self.color_1)?
        let two: widgets.Rgba = self.colour("color_2", self.color_2)?
        let three: widgets.Rgba = self.colour("color_3", self.color_3)?
        if self.orbs < 1 || self.orbs > 3 {
            return err("orbs={self.orbs} is not a number of orbs — it is 1 to 3", "no_such_orb")
        }
        if self.radius <= 0.0 {
            return err("radius={self.radius} would give an orb no size — it is above zero", "no_radius")
        }
        let rate: f64 = 0.55 * self.speed

        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float t = seconds * {rate};\n")
        out.push("    {d.v3} col = {d.rgb(ground)};\n\n")
        out.push(self.orb(d, 1, one, 0.38, 0.26, 0.70, 0.44, 0.20, 0.90, 0.50, 0.44, 1.80, 1.00, 0.26, 1.60, 0.0))
        if self.orbs >= 2 {
            out.push(self.orb(d, 2, two, 0.66, 0.24, 0.53, 0.60, 0.21, 0.81, 0.44, 0.40, 2.05, 0.95, 0.30, 1.10, 2.1))
        }
        if self.orbs >= 3 {
            out.push(self.orb(d, 3, three, 0.52, 0.28, 0.41, 0.34, 0.23, 0.63, 0.34, 0.31, 2.45, 0.88, 0.34, 1.90, 4.2))
        }
        out.push(self.speckle(d, 0.022))
        out.push("    return {d.v4}(clamp(col, {d.grey(0.0)}, {d.grey(1.0)}), 1.0);\n")
        return ok(out.to_string())
    }

    /// One orb: where it sits, how it drifts, how wide it is, how it breathes.
    fn orb(d: ShaderDialect, n: int, tint: widgets.Rgba,
           home_x: f64, swing_x: f64, rate_x: f64,
           home_y: f64, swing_y: f64, rate_y: f64,
           wide: f64, tall: f64, edge: f64,
           gain: f64, breath: f64, breath_rate: f64, phase: f64) -> string {
        // Held at one so a bigger pulse cannot drive the mix past the colour
        // and back out the other side, which reads as a hole rather than a dim.
        var beat: f64 = breath * self.pulse
        if beat > 1.0 { beat = 1.0 }
        let still: f64 = 1.0 - beat
        let w: f64 = wide * self.radius
        let h: f64 = tall * self.radius
        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    {d.v2} c{n} = {d.v2}({home_x} + {swing_x} * sin(t * {rate_x} + {phase}), {home_y} + {swing_y} * cos(t * {rate_y} + {phase}));\n")
        out.push("    {d.v2} e{n} = (uv - c{n}) / {d.xy(w, h)};\n")
        out.push("    col = {d.blend}(col, {d.rgb(tint)}, {gain} * exp(-dot(e{n}, e{n}) * {edge}) * ({still} + {beat} * sin(t * {breath_rate} + {phase})));\n\n")
        return out.to_string()
    }
}
