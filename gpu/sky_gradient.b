// A sky: a ramp, a sun, and weather.
package gpu

import cortado.widgets
import std.fmt

/// A vertical ramp from zenith to horizon, a sun that tracks across it, and
/// cloud banding that drifts. The one gradient here that is a picture of
/// something rather than an abstraction.
///
/// ```
/// <SkyGradient grow={1} zenith="#2D5FC6" horizon="#F2D1B4" sun_height={0.3} />
/// ```
pub class SkyGradient extends Gradient {
    pub zenith: string = "#2d5fc6"
    pub horizon: string = "#f2d1b4"
    pub sun: string = "#ffe3a6"

    /// Where the sun rides, 0 at the top of the frame and 1 at the bottom.
    pub sun_height: f64 = 0.32
    /// How much cloud. Zero is a clear sky.
    pub clouds: f64 = 1.0

    pub fn init() { super.init() }

    pub override fn write(d: ShaderDialect) -> Result<string> {
        let high: widgets.Rgba = self.colour("zenith", self.zenith)?
        let low: widgets.Rgba = self.colour("horizon", self.horizon)?
        let star: widgets.Rgba = self.colour("sun", self.sun)?
        let rate: f64 = 0.25 * self.speed
        let drift: f64 = 0.55 * self.speed
        var cloud: f64 = 0.42 * self.clouds
        if cloud > 1.0 { cloud = 1.0 }

        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float t = seconds * {rate};\n")
        out.push("    // The cloud runs at twice the sun, which is the ratio a real sky has.\n")
        out.push("    // One clock could not hold both.\n")
        out.push("    float ct = seconds * {drift};\n\n")
        out.push("    // The ramp is the sky. Everything below it is weather, painted on top.\n")
        out.push("    float h = clamp(uv.y, 0.0, 1.0);\n")
        out.push("    {d.v3} col = {d.blend}({d.rgb(high)}, {d.rgb(low)}, smoothstep(0.0, 1.0, h));\n\n")
        out.push("    {d.v2} sun = {d.v2}(0.50 + 0.30 * sin(t * 0.60), {self.sun_height} + 0.07 * cos(t * 0.40));\n")
        out.push("    {d.v2} ds = (uv - sun) / {d.xy(0.62, 0.52)};\n")
        out.push("    col = col + {d.rgb(star)} * exp(-dot(ds, ds) * 9.00) * 0.34;\n")
        out.push("    {d.v2} dc = (uv - sun) / {d.xy(0.055, 0.047)};\n")
        out.push("    col = col + {d.xyz(1.000, 0.973, 0.886)} * exp(-dot(dc, dc) * 2.40) * 0.30;\n\n")
        if cloud > 0.0 {
            out.push("    // Cloud banding: a band in y whose height is pushed around by x and time.\n")
            out.push("    float band = 0.5 + 0.5 * sin(uv.y * 7.0 + 1.60 * sin(uv.x * 2.40 + ct * 1.70) + ct * 0.90);\n")
            out.push("    band = band * band * smoothstep(0.10, 0.46, uv.y) * smoothstep(1.0, 0.60, uv.y);\n")
            out.push("    col = {d.blend}(col, {d.xyz(0.996, 0.976, 0.953)}, band * {cloud});\n\n")
        }
        out.push(self.speckle(d, 0.018))
        out.push("    return {d.v4}(clamp(col, {d.grey(0.0)}, {d.grey(1.0)}), 1.0);\n")
        return ok(out.to_string())
    }
}
