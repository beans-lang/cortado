// How to draw: which shader, what a vertex looks like, how it mixes.
package gpu

import cortado.host

/// A description of one way of drawing, built up and then frozen.
///
/// A builder, because a pipeline is genuinely a list of decisions rather than
/// four arguments, and because no struct crosses cortado's C boundary by
/// value. `build` is the line between the two halves of its life: before it,
/// every setter works and nothing can draw; after it, nothing changes and it
/// is what a pass draws with. Every setter refuses once it is built, rather
/// than accepting a change that would silently not apply.
///
/// ```
/// var line: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
/// line.attr(0, 2, 0)?          // attribute 0: two floats, at float 0
/// line.attr(1, 4, 2)?          // attribute 1: four floats, at float 2
/// line.stride(6)?              // a vertex is six floats
/// line.blend(gpu.Blend.alpha)?
/// line.build()?
/// ```
pub class Pipeline {
    priv slot: host.Handle = host.Handle.none()
    priv built: bool = false
    priv closed: bool = false

    priv fn init(slot: host.Handle) {
        self.slot = slot
        self.built = false
        self.closed = false
    }

    static fn of(slot: host.Handle) -> Pipeline {
        return new Pipeline(slot)
    }

    pub fn handle() -> host.Handle {
        return self.slot
    }

    /// One field of a vertex: which `[[attribute(index)]]` in the shader it
    /// feeds, how many numbers it is (1 to 4), and how many numbers into the
    /// vertex it starts.
    pub fn attr(index: int, floats: int, offset: int) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_pipeline_attr(self.slot.raw, index as i32,
                                                         floats as i32, offset as i32) as int,
                              "describe attribute {index} of a vertex")
        }
    }

    /// How many numbers one vertex takes, including any padding between them.
    pub fn stride(floats: int) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_pipeline_stride(self.slot.raw, floats as i32) as int,
                              "set how wide a vertex is")
        }
    }

    pub fn blend(how: Blend) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_pipeline_blend(self.slot.raw, how.code() as i32) as int,
                              "set how a pipeline blends")
        }
    }

    /// Which kind of place this pipeline draws into.
    ///
    /// `Pixels.offscreen` when nothing is said, because that is what
    /// `Device.target` makes. A pipeline for a canvas has to say so, and one
    /// that does not is refused by the driver at draw time rather than here —
    /// which is exactly why this call exists.
    pub fn pixels(kind: Pixels) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_pipeline_pixels(self.slot.raw, kind.code() as i32) as int,
                              "set which pixels a pipeline writes")
        }
    }

    /// Freezes it. Refused with `wrong_moment` when no attribute or no stride
    /// was given: a pipeline with no vertex layout could only be driven by a
    /// shader that indexes a raw buffer itself, which is a second way to write
    /// every shader and a second thing for cortado to describe.
    pub fn build() -> Result<bool> {
        unsafe {
            host.check(host.ctd_gpu_pipeline_build(self.slot.raw) as int,
                       "build a GPU pipeline")?
        }
        self.built = true
        return ok(true)
    }

    pub fn is_built() -> bool {
        return self.built
    }

    pub fn close() -> Result<bool> {
        if self.closed {
            return ok(false)
        }
        self.closed = true
        unsafe {
            return host.check(host.ctd_gpu_release(self.slot.raw) as int, "close a GPU pipeline")
        }
    }

    fn deinit() {
        if !self.closed {
            self.close()
        }
    }
}
