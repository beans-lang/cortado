// A widget the GPU draws into.
package gpu

import cortado.host
import cortado.widgets

/// The GPU attached to a `widgets.Canvas`.
///
/// A canvas widget is an area the platform lays out and shows and nothing
/// else; this is what puts something in it. Every frame is three steps — ask
/// for the frame the canvas is about to show, draw into it as into any other
/// target, and present:
///
/// ```
/// var canvas: widgets.Canvas = new widgets.Canvas()
/// var paint: gpu.Canvas = gpu.Canvas.on(canvas.handle(), card)?
///
/// clock.start(1, fn(frame: motion.Frame) {
///     match paint.next() {
///         ok(surface) => {
///             var draw: gpu.Pass = surface.begin(0.0, 0.0, 0.0, 1.0)?
///             draw.pipeline(line)?
///             draw.vertices(shape)?
///             draw.uniform([frame.elapsed])?
///             draw.draw(gpu.Shape.triangles, 0, 6)?
///             draw.present()?
///         }
///         err(problem) => {}
///     }
/// })?
/// ```
///
/// **Drive it from the frame clock.** A canvas is shown when the display shows
/// it, and drawing outside a frame is drawing the platform will not put on
/// screen. That is the same reason `motion.FrameClock` exists, and the two are
/// meant to be used together.
///
/// **The pipeline must be built for `Pixels.screen`.** A canvas is not the
/// same format as an off-screen target, and a pipeline that says nothing is
/// built for the off-screen one — which the driver refuses at draw time rather
/// than here.
pub class Canvas {
    priv slot: host.Handle = host.Handle.none()

    priv fn init(slot: host.Handle) {
        self.slot = slot
    }

    /// Attaches a GPU to a canvas widget.
    ///
    /// Refused with `unsupported` where the platform has no GPU host — the
    /// widget is still there and still laid out, it simply has nothing drawing
    /// into it. Ask `platform.Capability.gpu.available()` first.
    pub static fn on(widget: host.Handle, card: Device) -> Result<Canvas> {
        unsafe {
            host.check(host.ctd_gpu_canvas_attach(widget.raw, card.handle().raw) as int,
                       "attach a GPU to a canvas")?
        }
        return ok(new Canvas(widget))
    }

    /// The target for the frame this canvas is about to show.
    ///
    /// A `Target` like any other, so the same passes, the same pipelines and
    /// the same `read` all work on it — which is what makes a canvas checkable
    /// rather than something you have to look at.
    ///
    /// It belongs to one frame. Letting it go is what releases it, so a
    /// handler that asks for one each frame and lets it fall out of scope is
    /// doing the right thing with no teardown to remember.
    pub fn next() -> Result<Target> {
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_gpu_canvas_next(self.slot.raw)
        }
        if raw == 0 {
            // A canvas with no width or no height is the common reason, and it
            // is worth its own message: it is a layout mistake several rooms
            // away, and "no frame available" sends somebody to read about
            // compositors instead. It happens to every column whose cross
            // alignment is not `stretch`, because an empty view measures
            // nothing and so gets nothing.
            let scratch: host.HostScratch = host.HostScratch.instance
            unsafe {
                if host.ctd_view_frame(self.slot.raw, scratch.reals) == 0 {
                    let wide: f64 = scratch.real(2)
                    let tall: f64 = scratch.real(3)
                    if wide <= 0.0 || tall <= 0.0 {
                        return err("this canvas is {wide} by {tall}, so there is nothing to draw into — give it a size, or put it in a run that stretches its children",
                                   "no_size")
                    }
                }
            }
            return err("the canvas had no frame to give — nothing is attached to it, or the platform is holding every frame it has",
                       "no_frame")
        }
        return ok(Target.of(host.Handle.of(raw)))
    }
}
