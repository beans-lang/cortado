// The GPU this machine draws with.
package gpu

import cortado.host
import cortado.platform

/// A graphics processor, opened and held.
///
/// Everything else in cortado asks the platform for a control and lets the
/// platform paint it. A `Device` is the other thing: the machine's GPU, opened
/// directly, to draw a rectangle the program paints itself. A chart with fifty
/// thousand points, a waveform, a map — none of those is a tree of controls,
/// and drawing one by making controls is how a program ends up with fifty
/// thousand views.
///
/// **Ask before you open one.** A platform with no GPU host refuses, and
/// `platform.Capability.gpu.available()` is how a program finds out once
/// rather than one call at a time:
///
/// ```
/// if !platform.Capability.gpu.available() {
///     // draw the chart with controls, or say there is no chart
/// }
/// var card: gpu.Device = gpu.Device.open()?
/// let name: string = card.name()?
/// ```
///
/// The device is closed when the last reference to it goes, so a program that
/// opens one and forgets it does not leak the driver's objects. `close` is
/// there for a program that wants the moment to be its own choice.
pub class Device {
    priv slot: host.Handle = host.Handle.none()
    priv closed: bool = false

    priv fn init(slot: host.Handle) {
        self.slot = slot
        self.closed = false
    }

    /// Opens the system's default GPU.
    ///
    /// The default one, and only that one. A Mac with two cards can be asked
    /// for the others and a program that renders for hours on battery would
    /// want to; it is left out because every machine this has run on has
    /// exactly one, and an untested choice between devices is worse than no
    /// choice at all. Adding it later changes nothing here.
    ///
    /// The host answers with no handle rather than a status, so the two
    /// reasons are told apart in the message: this platform has no GPU host at
    /// all, or it has one and the machine has no device for it to open.
    pub static fn open() -> Result<Device> {
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_gpu_device_new()
        }
        if raw == 0 {
            if !platform.Capability.gpu.available() {
                return err("this platform has no GPU host — ask platform.Capability.gpu.available() before opening one",
                           "unsupported")
            }
            return err("the platform has a GPU host but could not open a device on this machine",
                       "no_gpu_device")
        }
        return ok(new Device(host.Handle.of(raw)))
    }

    /// The handle the host knows this device by.
    ///
    /// The same accessor `widgets.Widget` and `surface.Window` carry, and it
    /// is here for the same reason: the handle is what an entry point takes,
    /// and a caller reaching a part of the ABI that has no wrapper yet should
    /// not have to reach inside this class to do it. Passing one where a
    /// widget belongs is a typed refusal, not a crash — which is the whole
    /// point of a handle carrying a generation.
    pub fn handle() -> host.Handle {
        return self.slot
    }

    /// The GPU's own name for itself — "Apple M1 Pro", "NVIDIA GeForce RTX
    /// 4080". It names one machine, so it belongs in a log line and never in
    /// a test's expected output.
    pub fn name() -> Result<string> {
        let slot: host.Handle = self.slot
        return host.HostText.read("read a GPU's name", fn(out: RawPtr<i8>, cap: i32) -> i32 {
            unsafe {
                return host.ctd_gpu_device_name(slot.raw, out, cap)
            }
        })
    }

    /// One number this device answers about its own capacity.
    pub fn limit(which: GpuLimit) -> Result<f64> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_gpu_device_limit(self.slot.raw, which.code() as i32,
                                                 scratch.reals) as int,
                       "read a GPU's {which.name()}")?
        }
        return ok(scratch.real(0))
    }

    /// Whether the CPU and this GPU share memory, which decides whether an
    /// upload is a copy or nothing at all.
    ///
    /// The same question as `GpuLimit.unified_memory`, in the shape the answer
    /// actually has. A caller comparing a float against 1.0 to learn a yes or
    /// no is a caller the library let down.
    pub fn shares_memory() -> Result<bool> {
        let answer: f64 = self.limit(GpuLimit.unified_memory)?
        return ok(answer != 0.0)
    }

    /// A block of numbers on the GPU, filled from `values`.
    pub fn buffer(values: List<f64>) -> Result<Buffer> {
        let block: Floats = Floats.of(values)?
        return self.buffer_block(block)
    }

    /// The same, from a block that already exists.
    pub fn buffer_block(block: Floats) -> Result<Buffer> {
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_gpu_buffer_new(self.slot.raw, block.pointer(), block.count() as i32)
        }
        if raw == 0 {
            return err("the GPU would not make a buffer of {block.count()} numbers — a closed device, or no room left on the card",
                       "no_gpu_buffer")
        }
        return ok(Buffer.of(host.Handle.of(raw)))
    }

    /// An off-screen image to draw into, in pixels.
    pub fn target(width: int, height: int) -> Result<Target> {
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_gpu_target_new(self.slot.raw, width as i32, height as i32)
        }
        if raw == 0 {
            return err("the GPU would not make a {width}x{height} target — a closed device, a size of zero, or one larger than the card allows",
                       "no_gpu_target")
        }
        return ok(Target.of(host.Handle.of(raw)))
    }

    /// Compiles shader source.
    ///
    /// The message on a failure is the platform's own compiler talking — file,
    /// line, column and what it did not understand — because a shader that
    /// failed with no message is a blank window and a long evening.
    pub fn shader(language: ShaderLanguage, source: string) -> Result<Shader> {
        if !language.accepted() {
            return err("this platform does not compile {language.name()} — ask ShaderLanguage.accepted() and ship a shader it takes",
                       "unsupported")
        }
        let bytes: Bytes = host.HostText.encode(source, "compile a shader")?
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_gpu_shader_new(self.slot.raw, language.bit() as i32,
                                          host.HostText.pointer(bytes), bytes.len() as i32)
        }
        if raw == 0 {
            return err("the shader did not compile: {self.shader_problem()}", "shader_refused")
        }
        return ok(Shader.of(host.Handle.of(raw)))
    }

    /// What the compiler said about the last shader that failed on this
    /// device. Empty when the last one compiled.
    ///
    /// On the device rather than on the shader, because the shader that failed
    /// has no handle to ask. That makes it *the last one* — read it at once.
    pub fn shader_problem() -> string {
        let slot: host.Handle = self.slot
        match host.HostText.read("read why a shader failed",
                                 fn(out: RawPtr<i8>, cap: i32) -> i32 {
            unsafe {
                return host.ctd_gpu_shader_problem(slot.raw, out, cap)
            }
        }) {
            ok(text) => { return text }
            err(problem) => { return "the host would not say" }
        }
    }

    /// Lets go of the device.
    ///
    /// Calling it twice is not an error: the second answers that it was
    /// already closed, which is what a teardown path wants to hear rather than
    /// a failure it has to special-case.
    pub fn close() -> Result<bool> {
        if self.closed {
            return ok(false)
        }
        self.closed = true
        unsafe {
            return host.check(host.ctd_gpu_release(self.slot.raw) as int, "close a GPU device")
        }
    }

    /// Closes it when the last reference goes.
    ///
    /// Unlike `motion.Animation`, there is nothing here that belongs to the
    /// platform after this object is gone: an animation that was started is
    /// still playing and must not be stopped by a collection, but a device
    /// nobody holds is a device nobody can draw with.
    fn deinit() {
        if !self.closed {
            self.close()
        }
    }
}
