// Numbers on their way to the GPU.
package gpu

/// A block of 32-bit floats laid out the way the GPU reads them.
///
/// Beans counts in `f64` and a GPU counts in `f32`, and something has to do
/// the conversion. Doing it here, once, is better than every call site owning
/// a raw pointer: this class allocates the block, narrows each number into it,
/// and frees it when the last reference goes.
///
/// It is `pub` because holding one is the answer to a real cost. Every call
/// that takes numbers — making a buffer, writing into one, setting a uniform —
/// converts a `List<f64>` into one of these, which allocates. For vertex data
/// that happens once. For a uniform that changes every frame it would happen
/// sixty times a second, so a program on that path builds one `Floats` and
/// reuses it with `set`.
pub class Floats {
    priv data: RawPtr<f32> = RawPtr.null()
    priv held: int = 0

    priv fn init(data: RawPtr<f32>, held: int) {
        self.data = data
        self.held = held
    }

    /// Narrows every number in `values` into a new block.
    pub static fn of(values: List<f64>) -> Result<Floats> {
        let count: int = values.len()
        if count <= 0 {
            return err("a block of numbers for the GPU cannot be empty", "out_of_range")
        }
        unsafe {
            var block: RawPtr<f32> = RawPtr.alloc(count)
            var at: int = 0
            for value: f64 in values {
                block.offset(at).write(value as f32)
                at = at + 1
            }
            return ok(new Floats(block, count))
        }
    }

    /// A block of `count` zeroes, to be filled in with `set`.
    pub static fn zeroed(count: int) -> Result<Floats> {
        if count <= 0 {
            return err("a block of numbers for the GPU cannot be empty", "out_of_range")
        }
        unsafe {
            // RawPtr.alloc hands back zeroed storage, so there is nothing to
            // write: a block that was not filled in reads as zeroes rather
            // than as whatever the allocator last had there.
            return ok(new Floats(RawPtr.alloc(count), count))
        }
    }

    pub fn count() -> int {
        return self.held
    }

    /// Replaces one number, without allocating anything.
    pub fn set(at: int, value: f64) -> Result<bool> {
        if at < 0 || at >= self.held {
            return err("{at} is outside a block of {self.held} numbers", "out_of_range")
        }
        unsafe {
            self.data.offset(at).write(value as f32)
        }
        return ok(true)
    }

    pub fn get(at: int) -> Result<f64> {
        if at < 0 || at >= self.held {
            return err("{at} is outside a block of {self.held} numbers", "out_of_range")
        }
        unsafe {
            return ok(self.data.offset(at).read() as f64)
        }
    }

    /// The address the host reads from. Package-visible: a raw pointer into
    /// unmanaged memory this object will free is not something an application
    /// should be handed, and every host call copies before it returns.
    fn pointer() -> RawPtr<f32> {
        return self.data
    }

    fn deinit() {
        unsafe {
            if !self.data.is_null() {
                self.data.free()
                self.data = RawPtr.null()
            }
        }
    }
}
