// A window with a shader running in it.
//
//     beansc build examples/canvas.b -o build/canvas && ./build/canvas
//
// `examples/shader.b` draws on the GPU and writes a file. This is the same
// machinery pointed at the screen: a `Canvas` widget sits in an ordinary
// layout between two ordinary labels, and every frame the display asks for, a
// shader fills it.
//
// Three pieces, and they are the three cortado added in this order on purpose:
//
//   the frame clock   tells you a frame is wanted, at the display's real rate
//   the canvas        is the area the platform lays out and shows
//   the GPU           is what puts something in it
//
// Drawing outside a frame is drawing the platform will not show, which is why
// the pass lives inside the clock's handler and nowhere else.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import cortado.motion
import cortado.gpu
import std.io

// A plasma: cheap, obviously moving, and it needs one uniform, which is what
// makes it a good demonstration rather than a still picture.
const SHADER: string = r"
#include <metal_stdlib>
using namespace metal;

struct In  { float2 at [[attribute(0)]]; float2 uv [[attribute(1)]]; };
struct Out { float4 at [[position]]; float2 uv; };
struct Uniform { float seconds; };

vertex Out v_main(In v [[stage_in]]) {
    Out out;
    out.at = float4(v.at, 0.0, 1.0);
    out.uv = v.uv;
    return out;
}

fragment float4 f_main(Out v [[stage_in]], constant Uniform &u [[buffer(1)]]) {
    float2 p = v.uv * 6.0;
    float t = u.seconds;
    float wave = sin(p.x + t) + sin(p.y + t * 0.7)
               + sin((p.x + p.y) * 0.5 + t * 1.3)
               + sin(length(p - 3.0) * 1.5 - t * 2.0);
    float shade = wave * 0.25 * 0.5 + 0.5;
    return float4(shade, 0.35 + shade * 0.45, 0.85 - shade * 0.35, 1.0);
}
"

// Two triangles covering the canvas, with a 0..1 coordinate for the shader.
fn screen_quad() -> List<f64> {
    var at: List<f64> = [
        -1.0, -1.0,  0.0, 1.0,
         1.0, -1.0,  1.0, 1.0,
        -1.0,  1.0,  0.0, 0.0,
         1.0, -1.0,  1.0, 1.0,
         1.0,  1.0,  1.0, 0.0,
        -1.0,  1.0,  0.0, 0.0
    ]
    return move at
}

// Handlers capture this rather than the controls they belong to: a closure
// that captured its own widget would be a cycle the collector cannot see
// through, because the platform's stored callback holds a reference the tracer
// never walks.
class Drawing {
    pub frames: int = 0
    pub missed: int = 0

    pub fn init() {}
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(480.0, 320.0, "Cortado — a shader in a window")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var heading: widgets.Label = widgets.Label.of("Every pixel below is a fragment shader")?
    var plot: widgets.Canvas = new widgets.Canvas()
    var status: widgets.Label = widgets.Label.of("waiting for the first frame")?
    var quit: widgets.Button = widgets.Button.of("Quit")?

    root.add(heading)?
    root.add(plot)?
    root.add(status)?
    root.add(quit)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    // A flex column, not a stack. Only a flex run hands out the space that is
    // left over, and the canvas is the child that should take it — a stack
    // gives every child the size it measured, and an empty view measures
    // nothing at all.
    var body: layout.FlexLayout = layout.FlexLayout.column(12.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?
    page.add(sheet.leaf("heading", heading))
    // The canvas takes the room left over. It is an ordinary control to the
    // solver and gets no special treatment for being a canvas — `flexible` is
    // the same call any other control would use.
    var area: layout.LayoutNode = sheet.leaf("plot", plot)
    area.spec = layout.LayoutSpec.flexible(1.0)
    page.add(area)
    page.add(sheet.leaf("status", status))

    var row: layout.StackLayout = layout.StackLayout.row(12.0)
    row.set_justify(layout.Justify.end)
    var buttons: layout.LayoutNode = sheet.spacer("buttons", row)
    buttons.add(sheet.leaf("quit", quit))
    page.add(buttons)

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    app.router.on(quit.handle(), events.EventKind.activate, fn(event: events.UiEvent) {
        app.stop()
    })

    // Ask once, and say so plainly rather than showing an empty box.
    if !platform.Capability.gpu.available() {
        status.set_text("this platform has no GPU host — cortado draws with Metal on macOS and iOS")?
        window.show()?
        app.run()
        return ok(false)
    }

    var card: gpu.Device = gpu.Device.open()?
    var paint: gpu.Canvas = gpu.Canvas.on(plot.handle(), card)?
    var shader: gpu.Shader = card.shader(gpu.ShaderLanguage.msl, SHADER)?
    var line: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
    line.attr(0, 2, 0)?
    line.attr(1, 2, 2)?
    line.stride(4)?
    // A canvas is not the same pixels as an off-screen target. Saying so here
    // is the difference between a picture and a driver error at draw time.
    line.pixels(gpu.Pixels.screen)?
    line.build()?
    var quad: gpu.Buffer = card.buffer(screen_quad())?

    let drawing: Drawing = new Drawing()
    var clock: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)

    clock.start(1, fn(frame: motion.Frame) {
        match paint.next() {
            ok(surface) => {
                var canvas: gpu.Target = surface
                match draw_one(canvas, line, quad, frame.elapsed) {
                    ok(drew) => { drawing.frames = drawing.frames + 1 }
                    err(problem) => { status.set_text("{problem.kind}: {problem.msg}") }
                }
            }
            // The platform holds a few frames at a time and hands them back as
            // the compositor is done with them. Being told to wait is normal,
            // and counting it is more useful than treating it as a failure.
            err(problem) => { drawing.missed = drawing.missed + 1 }
        }
        if frame.number % 30 == 0 {
            let rate: f64 = if frame.elapsed > 0.0 { frame.number as f64 / frame.elapsed } else { 0.0 }
            status.set_text("{drawing.frames} frames drawn · {rate as int} per second · {drawing.missed} waited for a drawable")
        }
    })?

    window.show()?
    app.run()
    io.println("drew {drawing.frames} frames, waited {drawing.missed} times")
    return ok(true)
}

// Separate because a `?` inside the frame handler would have to return a
// Result the handler has nowhere to put — a frame handler returns nothing, by
// contract, so the failing path is turned into a message instead.
fn draw_one(canvas: gpu.Target, line: gpu.Pipeline, quad: gpu.Buffer,
            seconds: f64) -> Result<bool> {
    var pass: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    pass.pipeline(line)?
    pass.vertices(quad)?
    pass.uniform([seconds])?
    pass.draw(gpu.Shape.triangles, 0, 6)?
    // Presented, not waited for: the compositor takes it from here and this
    // thread is free to be told about the next frame.
    return pass.present()
}

fn main() {
    match run() {
        ok(drew) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
