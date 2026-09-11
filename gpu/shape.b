// What a draw call makes out of its vertices.
package gpu

import cortado.host

/// How the vertices in a draw are joined up.
///
/// The same five every graphics API has had since the nineteen-nineties, and
/// they are the same five because they are what hardware rasterizes directly.
/// Anything else — a circle, a rounded rectangle, a thick line with joins — is
/// built out of these, by the program or by a library above cortado, and not
/// by a mode here that only one backend would have.
pub enum(u8) Shape {
    /// Every three vertices are one triangle. The one to reach for: it costs a
    /// few more vertices than a strip and it never joins two shapes that were
    /// meant to be apart.
    triangles
    /// Each vertex after the second makes a triangle with the two before it.
    triangle_strip
    lines
    line_strip
    points

    pub fn name() -> string {
        return match self {
            triangles => "triangles",
            triangle_strip => "triangle_strip",
            lines => "lines",
            line_strip => "line_strip",
            points => "points",
        }
    }

    pub fn code() -> int {
        return match self {
            triangles => host.SHAPE_TRIANGLES,
            triangle_strip => host.SHAPE_TRIANGLE_STRIP,
            lines => host.SHAPE_LINES,
            line_strip => host.SHAPE_LINE_STRIP,
            points => host.SHAPE_POINTS,
        }
    }
}
