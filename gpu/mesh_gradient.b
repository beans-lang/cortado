// Colours blended by distance, drifting.
package gpu

import cortado.widgets
import std.fmt

/// Four colours on a slowly turning ring, blended by distance through a plane
/// that is bent twice — the background that looks hand-painted and moves.
///
/// ```
/// <MeshGradient grow={1} color_1="#EAF4FC" color_2="#1E50A2"
///               color_3="#F09199" color_4="#895B8A" />
/// ```
pub class MeshGradient extends Gradient {
    pub color_1: string = "#f2f6ff"
    pub color_2: string = "#3457d5"
    pub color_3: string = "#ff8fa3"
    pub color_4: string = "#7d5ba6"

    /// How far each colour reaches. Higher is tighter, so a colour with a big
    /// number keeps to itself and one with a small number holds the corners.
    pub reach_1: f64 = 18.0
    pub reach_2: f64 = 12.0
    pub reach_3: f64 = 10.0
    pub reach_4: f64 = 11.0

    /// How hard the plane is bent before anything is measured. Zero is four
    /// plain blobs; one is the drifting ribbons this exists for.
    pub warp: f64 = 1.0
    /// Below one widens the lobes sideways, which is what a wide window wants.
    pub squash: f64 = 0.78
    /// Which colour gets a defined edge and a hook, 1 to 4. Zero is none.
    pub lobe: int = 2

    pub fn init() { super.init() }

    pub override fn write(d: ShaderDialect) -> Result<string> {
        let one: widgets.Rgba = self.colour("color_1", self.color_1)?
        let two: widgets.Rgba = self.colour("color_2", self.color_2)?
        let three: widgets.Rgba = self.colour("color_3", self.color_3)?
        let four: widgets.Rgba = self.colour("color_4", self.color_4)?
        if self.lobe < 0 || self.lobe > 4 {
            return err("lobe={self.lobe} names no colour — it is 1 to 4, or 0 for none", "no_such_lobe")
        }
        let rate: f64 = 0.24 * self.speed
        let bend: f64 = 0.15 * self.warp
        let curl: f64 = 0.10 * self.warp

        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    float t = seconds * {rate};\n\n")
        out.push("    // Warp the plane twice, the second pass reading the first. One pass bends\n")
        out.push("    // a boundary; two curl it, and a curled boundary is what reads as motion.\n")
        out.push("    {d.v2} p = uv;\n")
        out.push("    {d.v2} q = p + {bend} * {d.v2}(sin(p.y * 2.70 + t * 1.10) + 0.5 * cos(p.x * 1.90 + t * 0.70),\n")
        out.push("                                   cos(p.x * 2.30 - t * 0.90) + 0.5 * sin(p.y * 2.10 - t * 0.60));\n")
        out.push("    p = p + {curl} * {d.v2}(cos(q.y * 3.50 - t * 1.40), sin(q.x * 3.10 + t * 1.20));\n\n")
        out.push("    // Four colours a quarter apart on one turning ring, each with its own\n")
        out.push("    // wobble. Both stay inside the frame, so no pixel loses reach of all four.\n")
        out.push("    float spin = t * 0.62;\n")
        out.push("    {d.v2} mid = {d.xy(0.50, 0.50)};\n")
        out.push("    {d.v2} ring = {d.xy(0.34, 0.29)};\n")
        out.push("    {d.v2} pa = mid + ring * {d.v2}(cos(spin + 1.5708), sin(spin + 1.5708)) + 0.07 * {d.v2}(cos(t * 0.90), sin(t * 1.50));\n")
        out.push("    {d.v2} pb = mid + ring * {d.v2}(cos(spin), sin(spin)) + 0.07 * {d.v2}(sin(t * 1.30), cos(t * 1.10));\n")
        out.push("    {d.v2} pc = mid + ring * {d.v2}(cos(spin + 3.1416), sin(spin + 3.1416)) + 0.07 * {d.v2}(sin(t * 1.70), cos(t * 0.80));\n")
        out.push("    {d.v2} pd = mid + ring * {d.v2}(cos(spin + 4.7124), sin(spin + 4.7124)) + 0.07 * {d.v2}(cos(t * 1.20), sin(t * 1.00));\n\n")
        out.push("    // Distance in a squashed space, so a wide window smears the lobes sideways\n")
        out.push("    // rather than letting two of them merge.\n")
        out.push("    {d.v2} squash = {d.xy(self.squash, 1.0)};\n")
        out.push("    {d.v2} da = (p - pa) * squash;\n")
        out.push("    {d.v2} db = (p - pb) * squash;\n")
        out.push("    {d.v2} dc = (p - pc) * squash;\n")
        out.push("    {d.v2} dd = (p - pd) * squash;\n\n")
        out.push("    {d.v3} c1 = {d.rgb(one)};\n")
        out.push("    {d.v3} c2 = {d.rgb(two)};\n")
        out.push("    {d.v3} c3 = {d.rgb(three)};\n")
        out.push("    {d.v3} c4 = {d.rgb(four)};\n\n")
        out.push("    // A gaussian falloff rather than inverse distance: 1/d blows up at a\n")
        out.push("    // control point and prints a hard dot of pure colour there.\n")
        out.push("    float wa = exp(-dot(da, da) * {self.reach_1});\n")
        out.push("    float wb = exp(-dot(db, db) * {self.reach_2});\n")
        out.push("    float wc = exp(-dot(dc, dc) * {self.reach_3});\n")
        out.push("    float wd = exp(-dot(dd, dd) * {self.reach_4});\n")
        out.push("    // Normalised, so every pixel is a blend of all four and no part of the\n")
        out.push("    // frame can fall out of every colour and go flat.\n")
        out.push("    {d.v3} col = (c1 * wa + c2 * wb + c3 * wc + c4 * wd) / (wa + wb + wc + wd);\n\n")
        out.push(self.hook(d, one, two, three, four))
        out.push(self.speckle(d, 0.028))
        out.push("    return {d.v4}(clamp(col, {d.grey(0.0)}, {d.grey(1.0)}), 1.0);\n")
        return ok(out.to_string())
    }

    /// The overlay that gives one colour a defined edge and a curl.
    ///
    /// It rides that colour's own point, so it can only ever sharpen a colour
    /// where the field already put it — never paint it somewhere new.
    fn hook(d: ShaderDialect, one: widgets.Rgba, two: widgets.Rgba,
            three: widgets.Rgba, four: widgets.Rgba) -> string {
        if self.lobe == 0 { return "" }
        var at: string = "pa"
        var tint: widgets.Rgba = one
        if self.lobe == 2 {
            at = "pb"
            tint = two
        }
        if self.lobe == 3 {
            at = "pc"
            tint = three
        }
        if self.lobe == 4 {
            at = "pd"
            tint = four
        }
        var out: fmt.StringBuilder = new fmt.StringBuilder()
        out.push("    // One lobe over the field with an edge and a turn strongest at its middle:\n")
        out.push("    // the hook. It rides its colour's own point, so it sharpens what is there.\n")
        out.push("    {d.v2} rel = p - {at};\n")
        out.push("    float turn = 1.10 * exp(-dot(rel, rel) * 2.6) + t * 0.35;\n")
        out.push("    {d.v2} spun = {d.v2}(rel.x * cos(turn) - rel.y * sin(turn),\n")
        out.push("                         rel.x * sin(turn) + rel.y * cos(turn));\n")
        out.push("    col = {d.blend}(col, {d.rgb(tint)}, 0.55 * smoothstep(0.86, 0.22, length(spun / {d.xy(0.58, 0.49)})));\n\n")
        return out.to_string()
    }
}
