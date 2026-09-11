// A block of numbers the GPU can read.
package gpu

import cortado.host

/// Vertex data, on the GPU.
///
/// Floats, and only floats. That is narrower than any of the three backends,
/// and it is narrow on purpose — the alternative is an API where a caller
/// computes byte offsets for data they wrote as numbers, and gets one of them
/// wrong. Packed colours and 16-bit indices are the reason this will grow, and
/// they arrive as their own call with byte offsets of their own rather than by
/// changing what these arguments mean.
pub class Buffer {
    priv slot: host.Handle = host.Handle.none()
    priv closed: bool = false

    priv fn init(slot: host.Handle) {
        self.slot = slot
        self.closed = false
    }

    /// Made by `Device.buffer`; this is how that reaches the constructor.
    static fn of(slot: host.Handle) -> Buffer {
        return new Buffer(slot)
    }

    pub fn handle() -> host.Handle {
        return self.slot
    }

    /// How many numbers it holds.
    pub fn count() -> Result<int> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            let ints: RawPtr<i32> = RawPtr.from_address(scratch.reals.address())
            host.check(host.ctd_gpu_buffer_count(self.slot.raw, ints) as int,
                       "count what a GPU buffer holds")?
            return ok(ints.read() as int)
        }
    }

    /// Overwrites `values.len()` numbers starting at `first`.
    ///
    /// This is how per-frame data gets to the GPU: a buffer made once and
    /// written into, rather than a new buffer every frame. Writing past the end
    /// is refused and never truncated — a GPU buffer is memory the driver owns,
    /// and a clamped write there is a corruption nobody sees until a frame
    /// looks wrong.
    pub fn write(first: int, values: List<f64>) -> Result<bool> {
        let block: Floats = Floats.of(values)?
        return self.write_block(first, block)
    }

    /// The same, from a block that already exists. What a program on a frame
    /// path uses, because it allocates nothing.
    pub fn write_block(first: int, block: Floats) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_gpu_buffer_write(self.slot.raw, first as i32,
                                                        block.pointer(),
                                                        block.count() as i32) as int,
                              "write into a GPU buffer")
        }
    }

    pub fn close() -> Result<bool> {
        if self.closed {
            return ok(false)
        }
        self.closed = true
        unsafe {
            return host.check(host.ctd_gpu_release(self.slot.raw) as int, "close a GPU buffer")
        }
    }

    fn deinit() {
        if !self.closed {
            self.close()
        }
    }
}
