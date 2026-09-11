// Everything drawn into one target, between a begin and an end.
package gpu

import cortado.host

/// One batch of drawing.
///
/// A pass begins by clearing its target — every backend clears as part of
/// starting one, and a separate "clear" call would be a second pass and a
/// whole extra round trip to the GPU. Then pipelines are set, vertices bound,
/// and draws issued; `finish` hands the lot over and waits.
///
/// **It is synchronous.** When `finish` returns, the pixels are there to read.
/// That is the right trade for an image a program computes and reads back,
/// which is what a `Target` is for. It is the wrong trade for a surface being
/// presented sixty times a second, and that is a different call with a
/// different contract rather than a flag on this one.
///
/// ```
/// var draw: gpu.Pass = target.begin(0.0, 0.0, 0.0, 1.0)?
/// draw.pipeline(line)?
/// draw.vertices(vertices)?
/// draw.uniform([scale])?
/// draw.draw(gpu.Shape.triangles, 0, 3)?
/// draw.finish()?
/// ```
pub class Pass {
    priv slot: host.Handle = host.Handle.none()
    priv done: bool = false

    priv fn init(slot: host.Handle) {
        self.slot = slot
        self.done = false
    }

    static fn of(slot: host.Handle) -> Pass {
        return new Pass(slot)
    }

    /// What to draw with. Refused with `wrong_moment` for a pipeline that has
    /// not been built — a description is not a thing to draw with.
    pub fn pipeline(with: Pipeline) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_pass_pipeline(self.slot.raw, with.handle().raw) as int,
                              "set what a pass draws with")
        }
    }

    /// The vertices to read, bound where the shader declares `[[buffer(0)]]`.
    pub fn vertices(data: Buffer) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_pass_vertices(self.slot.raw, data.handle().raw) as int,
                              "give a pass its vertices")
        }
    }

    /// Constants for the draws that follow, read by the shader at
    /// `[[buffer(1)]]`. Copied as the call is made, so the numbers may be a
    /// local that goes out of scope on the next line.
    pub fn uniform(values: List<f64>) -> Result<bool> {
        let block: Floats = Floats.of(values)?
        return self.uniform_block(block)
    }

    /// The same, from a block that already exists — what a program on a frame
    /// path uses, because it allocates nothing.
    pub fn uniform_block(block: Floats) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_pass_uniform(self.slot.raw, block.pointer(),
                                                        block.count() as i32) as int,
                              "give a pass its constants")
        }
    }

    /// Draws `count` vertices starting at `first`.
    pub fn draw(shape: Shape, first: int, count: int) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_pass_draw(self.slot.raw, shape.code() as i32,
                                                     first as i32, count as i32) as int,
                              "draw {count} vertices as {shape.name()}")
        }
    }

    /// Runs it, and waits. The pass is finished afterwards and every call on it
    /// is refused — the handle went back as it ended, the way an animation's
    /// does, because everything it described has already happened.
    pub fn finish() -> Result<bool> {
        if self.done {
            return err("this pass has already run", "wrong_moment")
        }
        self.done = true
        unsafe {
            return host.check(host.ctd_gpu_pass_end(self.slot.raw) as int, "run a GPU pass")
        }
    }

    /// Ends the pass by putting it on screen, rather than by waiting for it.
    ///
    /// `finish` waits, because the caller is about to read the pixels. A canvas
    /// never reads them; it hands them to the compositor. Waiting there would
    /// stall the thread that has to draw the next frame, sixty times a second,
    /// for nothing.
    ///
    /// Refused with `wrong_moment` on a pass that is not drawing into a canvas
    /// — two calls rather than a flag on one, so a caller who got it the wrong
    /// way round hears about it.
    pub fn present() -> Result<bool> {
        if self.done {
            return err("this pass has already run", "wrong_moment")
        }
        self.done = true
        unsafe {
            return host.check(host.ctd_gpu_pass_present(self.slot.raw) as int,
                              "put a pass on screen")
        }
    }

    /// Throws the drawing away without running it.
    ///
    /// The only reason this exists: a pass that is begun and never finished
    /// holds an open encoder, and the platform complains when one is collected
    /// that way. So a program that gives up half way says so.
    pub fn abandon() -> Result<bool> {
        if self.done {
            return ok(false)
        }
        self.done = true
        unsafe {
            return host.check(host.ctd_gpu_release(self.slot.raw) as int, "abandon a GPU pass")
        }
    }

    fn deinit() {
        if !self.done {
            self.abandon()
        }
    }
}
