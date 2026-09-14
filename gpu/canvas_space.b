// Where a pointer landed, in the coordinates a shader was given.
package gpu

import cortado.host
import cortado.geometry

/// A point on a canvas as the `uv` its shader sees. A division and nothing
/// else: no flip, no scale — both live elsewhere. No size means no answer.
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
