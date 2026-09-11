// What a GPU can be asked about itself.
package gpu

import cortado.host

/// A number a device answers about its own capacity.
///
/// Three, and each one is a number every backend can really answer — Metal
/// from the device, Direct3D from `D3D12_FEATURE_DATA_ARCHITECTURE` and
/// `QueryVideoMemoryInfo`, Vulkan from its memory heaps and physical-device
/// limits — and each one is a number a program branches on. A tier or a
/// feature-set name would be neither: it means something on one backend and
/// has to be invented on the others.
pub enum(u8) GpuLimit {
    /// Whether the CPU and the GPU share the same memory. On a machine where
    /// they do, a buffer written by the program is already visible to the GPU
    /// and there is nothing to copy; where they do not, every upload crosses a
    /// bus and a program that cared would batch its writes.
    ///
    /// It reads as a number because it is a limit like the others, and
    /// `Device.shares_memory` is the yes-or-no shape of the same question.
    unified_memory
    /// The largest single buffer this device will make.
    max_buffer_bytes
    /// What the driver asks a program to stay under, counting every texture
    /// and buffer alive at once. **Zero means the driver did not say** — the
    /// iOS Simulator's device answers exactly that — and zero is an answer,
    /// not a failure.
    memory_bytes

    pub fn name() -> string {
        return match self {
            unified_memory => "unified_memory",
            max_buffer_bytes => "max_buffer_bytes",
            memory_bytes => "memory_bytes",
        }
    }

    pub fn code() -> int {
        return match self {
            unified_memory => host.GPU_UNIFIED_MEMORY,
            max_buffer_bytes => host.GPU_MAX_BUFFER_BYTES,
            memory_bytes => host.GPU_MEMORY_BYTES,
        }
    }

    pub static fn all() -> List<GpuLimit> {
        var every: List<GpuLimit> = []
        every.push(GpuLimit.unified_memory)
        every.push(GpuLimit.max_buffer_bytes)
        every.push(GpuLimit.memory_bytes)
        return move every
    }
}
