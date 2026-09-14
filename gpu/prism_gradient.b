// A spectrum thrown across the frame, bent as it goes.
package gpu

import std.fmt

/// A straight sweep through the spectrum, bent by two slow waves — light
/// through moving glass rather than a colour wheel, which has a centre that
/// nobody asked for and every eye finds.
///
/// ```
/// <PrismGradient grow={1} angle={35} spread={0.62} saturation={0.8} />
/// ```
pub class PrismGradient extends Gradient {
    /// Which way the spectrum runs, in degrees.
    pub angle: f64 = 35.0
    /// How much of the spectrum crosses the frame. Above one repeats it.
    pub spread: f64 = 0.62
    /// How hard the sweep is bent, and how far it rocks, on its way across.
    /// Zero only slides it, and a sliding repeating spectrum looks still.
    pub warp: f64 = 1.0
    /// Above one deepens the colours; zero is a flat grey the shape of the
    /// sweep, which is a useful thing to see when placing one.
    pub saturation: f64 = 1.0

    pub fn init() { super.init() }

    pub override fn write(d: ShaderDialect) -> Result<string> {
        let rate: f64 = 0.14 * self.speed
        let radians: f64 = self.angle * 3.14159265358979 / 180.0
        let sway: f64 = 0.30 * self.warp
        let bend: f64 = 0.34 * self.warp
        let ripple: f64 = 0.22 * self.warp
        let red: f64 = 0.258 * self.saturation
        let green: f64 = 0.242 * self.saturation
        let blue: f64 = 0.278 * self.saturation

        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float t = seconds * {rate};\n")
        out.push("    {d.v2} p = uv - 0.5;\n")
        out.push("    p.x = p.x * 1.35;\n\n")
        out.push("    // The sweep rocks as well as slides. Sliding alone returns a repeating\n")
        out.push("    // ramp to itself — the colours cycle and the picture never changes.\n")
        out.push("    float lean = {radians} + {sway} * sin(t * 0.70);\n")
        out.push("    {d.v2} dir = {d.v2}(cos(lean), sin(lean));\n")
        out.push("    float axis = dot(p, dir) + {bend} * sin(p.y * 2.60 + t * 1.30) + {ripple} * sin(p.x * 3.40 - t * 0.90) + t;\n\n")
        out.push("    // Pastel rather than full saturation: a narrow band of the spectrum held\n")
        out.push("    // above a light base is what a prism actually throws on a wall.\n")
        out.push("    {d.v3} col = {d.xyz(0.672, 0.660, 0.692)} +\n")
        out.push("                 {d.xyz(red, green, blue)} * cos(6.2831853 * (axis * {self.spread} + {d.xyz(0.00, 0.28, 0.58)}));\n\n")
        out.push(self.speckle(d, 0.022))
        out.push("    return {d.v4}(clamp(col, {d.grey(0.0)}, {d.grey(1.0)}), 1.0);\n")
        return ok(out.to_string())
    }
}
