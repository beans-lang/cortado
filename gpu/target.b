// Somewhere to draw that is not the screen.
package gpu

import cortado.host
import cortado.widgets
import cortado.geometry

/// An off-screen image the GPU draws into, 8-bit RGBA.
///
/// One pixel format. A format argument would be the first thing a caller had
/// to decide and the last thing they could check, and every extra one
/// multiplies what a test has to assert. Wider colour is a real want and a
/// later decision with a capability of its own.
///
/// Width and height are in **pixels, not points**: this is an image the
/// program computes, and there is no display involved to have a scale. That is
/// the one place cortado's usual rule does not apply, and it is why
/// `tests/triangle.b` can assert an exact pixel on any machine.
pub class Target {
    priv slot: host.Handle = host.Handle.none()
    priv closed: bool = false

    priv fn init(slot: host.Handle) {
        self.slot = slot
        self.closed = false
    }

    static fn of(slot: host.Handle) -> Target {
        return new Target(slot)
    }

    pub fn handle() -> host.Handle {
        return self.slot
    }

    /// How big it is, in pixels.
    ///
    /// The first half of the two-call read, on its own: asking for zero bytes
    /// fills in the size and copies nothing. A canvas frame is the reason this
    /// is worth having — its size is the view's, in real pixels, and a shader
    /// that wants to know the aspect ratio has no other way to ask.
    pub fn size() -> Result<geometry.Size> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_gpu_target_read(self.slot.raw, scratch.reals,
                                                RawPtr.null(), 0) as int,
                       "measure a GPU target")?
        }
        return ok(geometry.Size.of(scratch.real(0), scratch.real(1)))
    }

    /// Reads the pixels back, top row first.
    ///
    /// Into the same `widgets.Snapshot` a control's pixels come back in: an
    /// RGBA image is an RGBA image, and the two differ in who painted it. What
    /// this one adds is that the numbers are worth asserting — a quad on a
    /// pixel boundary is exact arithmetic, where a control's pixels are a font
    /// rasterizer that changes with the OS.
    pub fn read() -> Result<widgets.Snapshot> {
        let slot: host.Handle = self.slot
        return widgets.Snapshot.read("read a GPU target back",
                                     fn(size: RawPtr<f64>, out: RawPtr<i8>, cap: i32) -> i32 {
            unsafe {
                return host.ctd_gpu_target_read(slot.raw, size, out, cap)
            }
        })
    }

    /// Starts drawing into it, clearing it to this colour first. Components
    /// run 0 to 1.
    pub fn begin(red: f64, green: f64, blue: f64, alpha: f64) -> Result<Pass> {
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_gpu_pass_begin(self.slot.raw, red, green, blue, alpha)
        }
        if raw == 0 {
            return err("the GPU would not start a pass on this target — a closed target, or no room in the handle table",
                       "no_gpu_pass")
        }
        return ok(Pass.of(host.Handle.of(raw)))
    }

    pub fn close() -> Result<bool> {
        if self.closed {
            return ok(false)
        }
        self.closed = true
        unsafe {
            return host.check(host.ctd_gpu_release(self.slot.raw) as int, "close a GPU target")
        }
    }

    fn deinit() {
        if !self.closed {
            self.close()
        }
    }
}
