// Bands of colour, marbled and flowing.
package gpu

import cortado.widgets
import std.fmt

/// Two colours folded through a twice-warped plane, with a third riding the
/// crests — ink stirred into water, never stirred to the bottom.
///
/// ```
/// <FlowGradient grow={1} color="#1B3365" color_to="#53B0C7" highlight="#F5E3C2" />
/// ```
pub class FlowGradient extends Gradient {
    pub color: string = "#1b3365"
    pub color_to: string = "#53b0c7"
    /// What sits on the crests. Set it to `color_to` for two colours only.
    pub highlight: string = "#f5e3c2"

    /// How many bands cross the frame. Above one is a tighter marble.
    pub turns: f64 = 1.0
    /// How hard the plane folds before the bands are measured.
    pub warp: f64 = 1.0

    pub fn init() { super.init() }

    pub override fn write(d: ShaderDialect) -> Result<string> {
        let from: widgets.Rgba = self.colour("color", self.color)?
        let to: widgets.Rgba = self.colour("color_to", self.color_to)?
        let crest: widgets.Rgba = self.colour("highlight", self.highlight)?
        let rate: f64 = 0.20 * self.speed
        let fold: f64 = 0.45 * self.warp
        let curl: f64 = 0.25 * self.warp
        let bands: f64 = 2.20 * self.turns

        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float t = seconds * {rate};\n")
        out.push("    {d.v2} p = uv * {d.xy(1.40, 1.0)};\n")
        out.push("    {d.v2} q = p + {fold} * {d.v2}(sin(p.y * 2.10 + t * 0.90), cos(p.x * 1.70 - t * 0.70));\n")
        out.push("    q = q + {curl} * {d.v2}(cos(q.y * 3.30 - t * 1.20), sin(q.x * 2.90 + t * 1.00));\n\n")
        out.push("    // One scalar field, read as bands. The folding above is what makes the\n")
        out.push("    // bands curl back on themselves instead of running straight.\n")
        out.push("    float f = sin(q.x * 3.00 + q.y * 1.50 + t * 1.10) + 0.5 * sin(q.y * 5.00 - t * 0.80);\n")
        out.push("    float s = 0.5 + 0.5 * sin(f * {bands});\n\n")
        out.push("    {d.v3} col = {d.blend}({d.rgb(from)}, {d.rgb(to)}, s);\n")
        out.push("    col = {d.blend}(col, {d.rgb(crest)}, smoothstep(0.62, 1.0, s) * 0.85);\n\n")
        out.push(self.speckle(d, 0.024))
        out.push("    return {d.v4}(clamp(col, {d.grey(0.0)}, {d.grey(1.0)}), 1.0);\n")
        return ok(out.to_string())
    }
}
