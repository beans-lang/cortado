// Where a pointer landed, in the coordinates a shader was given.
package gpu

import cortado.host
import cortado.geometry

/// A point on a canvas, as the `uv` its shader sees: 0 to 1 across, 0 to 1
/// down, `(0,0)` at the top left.
///
/// **The conversion is a division and nothing else**, and that is worth a
/// function rather than a comment because it is the one place a flip could be
/// introduced by accident. The ABI's pointer space is already the control's
/// own: top-left, y down, in points — `ctd_raise_pointer` converts into the
/// view and `CortadoView` is flipped. A canvas's `uv` is 0 to 1, y down, from
/// the top left, because `ShaderCanvas.quad_corners` maps clip `y = -1` to
/// `v = 1` and does the flip once, in the vertex data.
///
/// The backing scale never enters. A pointer arrives in points and
/// `ctd_view_frame` answers in points; the 2× on a Retina display lives only
/// inside `size`, which the shader gets in real pixels — which is exactly why
/// a `ShapeCanvas` is handed the scale as its fourth uniform.
///
/// A control with no width has no answer rather than a division by zero.
pub fn uv_of(control: host.Handle, at: geometry.Point) -> Result<geometry.Point> {
    let scratch: host.HostScratch = host.HostScratch.instance
    unsafe {
        host.check(host.ctd_view_frame(control.raw, scratch.reals) as int,
                   "read where a canvas is")?
    }
    let wide: f64 = scratch.real(2)
    let tall: f64 = scratch.real(3)
    if wide <= 0.0 || tall <= 0.0 {
        return err("this canvas is {wide} by {tall}, so a point on it is not anywhere — give it a size, or put it in a run that stretches its children",
                   "no_size")
    }
    return ok(geometry.Point.at(at.x / wide, at.y / tall))
}
