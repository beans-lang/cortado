// What a control actually painted.
package widgets

import cortado.host

/// The pixels of a widget, read back off the platform.
///
/// This is the only thing in cortado that answers a question the program did
/// not already know the answer to. Every other query reads back a property the
/// program itself set — text, enabled, frame — so a host that stored the value
/// and never told the platform would pass all of them. Pixels come from the
/// platform's own drawing, so they are the one check that something was really
/// there.
///
/// It is deliberately *not* a golden. Goldening pixels means goldening a font
/// rasterizer, which changes on every OS point release and teaches a team to
/// re-record the file instead of reading it. The useful assertions are the
/// ones that hold across releases: an image is the size that was asked for, a
/// control that painted is not uniform, and a hidden one leaves nothing
/// behind.
///
/// Rows run top to bottom with no padding, so a pixel is at
/// `(y * width + x) * 4` — the layout the ABI promises.
///
/// It is also what a GPU render target reads back into, through the same
/// `read` below. An RGBA image is an RGBA image; the two differ in who painted
/// it, not in what came back. What a GPU target *does* let you golden is the
/// pixels themselves — a quad on a pixel boundary is exact arithmetic, not a
/// font rasterizer — which is why `tests/triangle.b` asserts colours where
/// `tests/pixels.b` can only assert shape.
pub class Snapshot {
    pub width: int = 0
    pub height: int = 0
    pixels: Bytes = Bytes.filled(0, 0)

    /// An empty image of the right size, for the host to fill.
    ///
    /// The buffer is made here rather than handed in because a `Bytes` cannot
    /// be moved into a field from a parameter, and copying sixteen thousand
    /// bytes one at a time to get around that would be a strange thing to find
    /// in a library.
    pub fn init(width: int, height: int, size: int) {
        self.width = width
        self.height = height
        self.pixels = Bytes.filled(size, 0)
    }

    /// The buffer as the host's `char *`. Package-visible: `Widget.snapshot`
    /// is the only caller, and a raw pointer into a live object's field is not
    /// something an application should be handed.
    fn buffer() -> RawPtr<i8> {
        unsafe {
            return RawPtr.from_address(self.pixels.as_ptr().address())
        }
    }

    pub fn byte_count() -> int {
        return self.pixels.len()
    }

    /// Reads an image out of the host with the two-call shape.
    ///
    /// `probe` is called first with a null buffer and a capacity of zero to
    /// learn the byte count and the dimensions, then again with a buffer that
    /// size. It is written once here, and not in each caller, because the
    /// interesting part is the check at the end: a host that answers a bigger
    /// image the second time has resized between the two calls, and the buffer
    /// then holds part of one picture and part of another.
    ///
    /// A closure rather than a handle, because the two callers reach different
    /// entry points — `ctd_snapshot` for a control that painted, and
    /// `ctd_gpu_target_read` for an image a program computed on the GPU — and
    /// what they share is the shape, not the symbol. `buffer()` stays
    /// package-visible: a raw pointer into a live object's field is not
    /// something an application should be handed, and this is how a caller in
    /// another package fills one without being given one.
    pub static fn read(attempt: string,
                       probe: fn(RawPtr<f64>, RawPtr<i8>, i32) -> i32) -> Result<Snapshot> {
        let scratch: host.HostScratch = host.HostScratch.instance
        let needed: int = probe(scratch.reals, RawPtr.null(), 0) as int
        host.check(needed, "measure {attempt}")?
        let width: int = scratch.real(0) as int
        let height: int = scratch.real(1) as int
        var shot: Snapshot = new Snapshot(width, height, needed)
        if needed == 0 {
            return ok(shot)
        }
        let wrote: int = probe(scratch.reals, shot.buffer(), needed as i32) as int
        host.check(wrote, attempt)?
        if wrote != needed {
            return err("could not {attempt}: it changed size while it was being read",
                       "host_raced")
        }
        return ok(shot)
    }

    /// The pixel at `x`, `y`, with the top-left at 0, 0.
    pub fn pixel(x: int, y: int) -> Result<Rgba> {
        if x < 0 || y < 0 || x >= self.width || y >= self.height {
            return err("({x}, {y}) is outside a {self.width}x{self.height} snapshot",
                       "out_of_range")
        }
        let at: int = (y * self.width + x) * 4
        return ok(Rgba {
            red: self.pixels.get(at),
            green: self.pixels.get(at + 1),
            blue: self.pixels.get(at + 2),
            alpha: self.pixels.get(at + 3),
        })
    }

    /// Whether every pixel is the same colour.
    ///
    /// The assertion that survives an OS update: an empty box is uniform and a
    /// box with a control in it is not, whatever the theme decided the control
    /// should look like.
    pub fn is_uniform() -> Result<bool> {
        if self.width <= 0 || self.height <= 0 { return ok(true) }
        let first: Rgba = self.pixel(0, 0)?
        for y: int in 0..self.height {
            for x: int in 0..self.width {
                if !self.pixel(x, y)?.same_as(first) { return ok(false) }
            }
        }
        return ok(true)
    }

    /// How many pixels differ between two snapshots of the same size.
    ///
    /// Counted rather than compared, because a count says *how much* changed
    /// and a bool only says that something did — and a one-pixel difference
    /// from an antialiasing change is a different fact from a control
    /// appearing.
    pub fn differences(other: Snapshot) -> Result<int> {
        if self.width != other.width || self.height != other.height {
            return err("a {self.width}x{self.height} snapshot cannot be compared with a {other.width}x{other.height} one",
                       "size_mismatch")
        }
        var differ: int = 0
        for y: int in 0..self.height {
            for x: int in 0..self.width {
                if !self.pixel(x, y)?.same_as(other.pixel(x, y)?) {
                    differ = differ + 1
                }
            }
        }
        return ok(differ)
    }
}
