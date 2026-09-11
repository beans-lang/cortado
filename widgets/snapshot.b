// What a control actually painted.
package widgets

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
