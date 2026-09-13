// Shapes you can name, as distance rather than as triangles.
package gpu

/// The geometry a `ShapeCanvas` draws.
///
/// Not `Shape` — that name is already the primitive topology in `shape.b`, and
/// two public `Shape` types in one package is a name nobody should have to
/// disambiguate.
///
/// **Four, and not seven.** A rectangle is a rounded rectangle whose radius is
/// zero; a circle is an ellipse whose halves are equal; a border is a stroke.
/// Naming those separately would be four ways to write two things, and the
/// author who wanted a *slightly* rounded rectangle would have to know which
/// of the four names stops being the right one.
///
/// **Why a distance and not a mesh.** Every one of these is one number per
/// pixel — how far that pixel is from the edge, negative inside — and once a
/// shader has that number the fill, the stroke and the shadow all fall out of
/// it by arithmetic. Tessellating a rounded corner into triangles instead
/// would put the corner's smoothness in the vertex count, where a resize
/// makes it wrong.
pub enum(u8) Figure {
    /// A rectangle, with `radius` rounding every corner. Zero is square, and
    /// a radius past half the shorter side is clamped to it — which is a
    /// capsule, and drawing one is better than refusing a number somebody
    /// arrived at by binding it to a slider.
    rounded_rect
    /// A circle, or the ellipse inscribed in a canvas that is not square.
    ellipse
    /// An `ellipse` with its middle taken out. `thickness` is how wide the
    /// band is, measured **inward** from the edge, for the reason a stroke is
    /// measured inward: outward needs room the layout never gave it.
    ring
    /// A rectangle with its ends fully rounded, whichever way round it is.
    /// The same as `rounded_rect` with the largest radius that fits, named
    /// because that is the shape people mean rather than the radius.
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

    /// The MSL that works out `d` — the signed distance from `p` to this
    /// figure's edge, in pixels, negative inside.
    ///
    /// Written as an ordinary interpolated string, and it works for the one
    /// reason `Effect.body` names: **none of these contains a `{`**. Every
    /// line is an expression, so the braces a function needs are supplied by
    /// the raw string in `ShapeCanvas.wrap` instead. The moment a figure needs
    /// a block, it needs a builder too.
    ///
    /// The names it may read are the ones `wrap` puts in scope: `p`,
    /// `half_extent`, `radius` and `thickness`, all already in pixels.
    pub fn distance_body() -> string {
        return match self {
            // The standard rounded-box distance. `q` is how far outside the
            // straight part of each edge the point is; the `length(max(q,0))`
            // term rounds the corners and the `min(max(...),0)` term carries
            // the inside, where both are negative.
            rounded_rect => "    float r = min(radius, min(half_extent.x, half_extent.y));\n    float2 q = abs(p) - (half_extent - r);\n    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;",
            // Exact for a circle, and the usual first-order approximation when
            // the halves differ — an exact ellipse distance needs iteration,
            // which is a cost per pixel for an error no eye finds at the one
            // pixel where the coverage ramp is not already 0 or 1.
            ellipse => "    float d = (length(p / half_extent) - 1.0) * min(half_extent.x, half_extent.y);",
            // The band just inside the edge: `outer` is the ellipse's own
            // distance, and the band is where it lies between -thickness and
            // 0, which is what folding it about -thickness/2 says.
            ring => "    float outer = (length(p / half_extent) - 1.0) * min(half_extent.x, half_extent.y);\n    float d = abs(outer + thickness * 0.5) - thickness * 0.5;",
            // The largest radius that fits, which is what a capsule is.
            capsule => "    float r = min(half_extent.x, half_extent.y);\n    float2 q = abs(p) - (half_extent - r);\n    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;",
        }
    }
}
