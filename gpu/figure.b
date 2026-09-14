// Shapes you can name, as distance rather than as triangles.
package gpu

/// The geometry a `ShapeCanvas` draws. Four, not seven: a rectangle is a
/// rounded rect at radius 0, a circle an equal-halved ellipse, a border a stroke.
pub enum(u8) Figure {
    /// A rectangle, `radius` rounding every corner. Past half the shorter side
    /// it clamps to a capsule rather than refusing a slider-driven number.
    rounded_rect
    /// A circle, or the ellipse inscribed in a canvas that is not square.
    ellipse
    /// An ellipse with its middle out. `thickness` measures inward, like a
    /// stroke: outward needs room the layout never gave it.
    ring
    /// A rectangle with fully rounded ends — `rounded_rect` at the largest
    /// radius that fits, named because that is the shape people mean.
    capsule

    pub fn name() -> string {
        return match self {
            rounded_rect => "rounded_rect",
            ellipse => "ellipse",
            ring => "ring",
            capsule => "capsule",
        }
    }

    /// Every name, for the message a bad one gets.
    pub static fn names() -> List<string> {
        var every: List<string> = []
        every.push("rounded_rect")
        every.push("ellipse")
        every.push("ring")
        every.push("capsule")
        return move every
    }

    pub static fn of(name: string) -> Option<Figure> {
        if name == "rounded_rect" { return some(Figure.rounded_rect) }
        if name == "ellipse" { return some(Figure.ellipse) }
        if name == "ring" { return some(Figure.ring) }
        if name == "capsule" { return some(Figure.capsule) }
        return none
    }

    /// Whether `radius` means anything to this figure, so one that was given a
    /// radius it will ignore can be told rather than quietly ignoring it.
    pub fn reads_radius() -> bool {
        return match self {
            rounded_rect => true,
            ellipse => false,
            ring => false,
            capsule => false,
        }
    }

    /// Whether `thickness` means anything to this figure.
    pub fn reads_thickness() -> bool {
        return match self {
            rounded_rect => false,
            ellipse => false,
            ring => true,
            capsule => false,
        }
    }

    /// The MSL for `d`: signed distance from `p` to the edge, in pixels.
    /// No body contains a `{`, so interpolation works; `wrap` supplies the braces.
    pub fn distance_body() -> string {
        return match self {
            // The standard rounded-box distance: `length(max(q,0))` rounds the
            // corners, `min(max(...),0)` carries the inside.
            rounded_rect => "    float r = min(radius, min(half_extent.x, half_extent.y));\n    float2 q = abs(p) - (half_extent - r);\n    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;",
            // Exact for a circle, first-order otherwise: an exact ellipse
            // distance needs iteration, for an error inside one ramp pixel.
            ellipse => "    float d = (length(p / half_extent) - 1.0) * min(half_extent.x, half_extent.y);",
            // The band just inside the edge, which is `outer` folded about
            // -thickness/2.
            ring => "    float outer = (length(p / half_extent) - 1.0) * min(half_extent.x, half_extent.y);\n    float d = abs(outer + thickness * 0.5) - thickness * 0.5;",
            // The largest radius that fits, which is what a capsule is.
            capsule => "    float r = min(half_extent.x, half_extent.y);\n    float2 q = abs(p) - (half_extent - r);\n    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;",
        }
    }
}
