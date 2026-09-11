// A program that runs on the GPU.
package gpu

import cortado.host

/// Compiled shader source.
///
/// Compiled at run time, not as a build step, because there is no build step
/// to put it in: a Beans package declares C sources and frameworks and nothing
/// that would run a shader compiler. It costs about two milliseconds the first
/// time and nothing after, which is cheaper than the machinery would be.
///
/// **Write the source as a raw string.** A shader is full of `{`, and an
/// ordinary Beans string reads that as the start of an interpolation:
///
/// ```
/// let source: string = r"
/// #include <metal_stdlib>
/// using namespace metal;
/// struct In { float2 at [[attribute(0)]]; };
/// vertex float4 v_main(In v [[stage_in]]) { return float4(v.at, 0.0, 1.0); }
/// fragment float4 f_main() { return float4(1.0, 0.0, 0.0, 1.0); }
/// "
/// var shader: gpu.Shader = card.shader(gpu.ShaderLanguage.msl, source)?
/// ```
pub class Shader {
    priv slot: host.Handle = host.Handle.none()
    priv closed: bool = false

    priv fn init(slot: host.Handle) {
        self.slot = slot
        self.closed = false
    }

    static fn of(slot: host.Handle) -> Shader {
        return new Shader(slot)
    }

    pub fn handle() -> host.Handle {
        return self.slot
    }

    /// A way of drawing with this shader: which function runs per vertex,
    /// which per pixel. A name that is not in the source is refused here
    /// rather than at draw time, where it would be a blank image and nothing
    /// to go on.
    pub fn pipeline(vertex: string, fragment: string) -> Result<Pipeline> {
        let first: Bytes = host.HostText.encode(vertex, "name a vertex function")?
        let second: Bytes = host.HostText.encode(fragment, "name a fragment function")?
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_gpu_pipeline_new(self.slot.raw,
                                            host.HostText.pointer(first), first.len() as i32,
                                            host.HostText.pointer(second), second.len() as i32)
        }
        if raw == 0 {
            return err("the shader has no pair of functions called {vertex} and {fragment}",
                       "no_such_function")
        }
        return ok(Pipeline.of(host.Handle.of(raw)))
    }

    pub fn close() -> Result<bool> {
        if self.closed {
            return ok(false)
        }
        self.closed = true
        unsafe {
            return host.check(host.ctd_gpu_release(self.slot.raw) as int, "close a shader")
        }
    }

    fn deinit() {
        if !self.closed {
            self.close()
        }
    }
}
