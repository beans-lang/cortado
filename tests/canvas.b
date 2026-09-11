// A widget a program draws into itself.
//
// Every other control in cortado is the platform's, and what it looks like is
// the operating system's business. A canvas is the opposite: the platform lays
// it out and shows it, and everything inside it is the program's.
//
// **This runs headless, through the real on-screen path**, which is worth
// saying because it sounds impossible. A `CAMetalLayer` on a view in a window
// that was never ordered front still hands back a drawable, still draws, and
// still presents without error — checked with a bare Metal program before any
// of this was written. So the gate is not testing a stand-in.
//
// What it can assert is the whole of it, because a canvas frame is a target
// like any other and reads back the same way. That was the point of shaping it
// so: a canvas you cannot read is a canvas whose test is somebody looking
// at it.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.geometry
import cortado.gpu
import std.io

const SHADER: string = r"
#include <metal_stdlib>
using namespace metal;
struct In  { float2 at [[attribute(0)]]; float4 tint [[attribute(1)]]; };
struct Out { float4 at [[position]]; float4 tint; };
vertex Out v_main(In v [[stage_in]]) { Out o; o.at = float4(v.at, 0.0, 1.0); o.tint = v.tint; return o; }
fragment float4 f_main(Out v [[stage_in]]) { return v.tint; }
"

fn quad(red: f64, green: f64, blue: f64) -> List<f64> {
    var at: List<f64> = [
        -1.0, -1.0, red, green, blue, 1.0,
         1.0, -1.0, red, green, blue, 1.0,
        -1.0,  1.0, red, green, blue, 1.0,
         1.0, -1.0, red, green, blue, 1.0,
         1.0,  1.0, red, green, blue, 1.0,
        -1.0,  1.0, red, green, blue, 1.0
    ]
    return move at
}

fn refused(what: string, outcome: Result<bool>) {
    match outcome {
        ok(done) => { io.println("  {what} was allowed, and should not have been") }
        err(problem) => { io.println("  {what} refused: {problem.kind}") }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(200.0, 100.0, "Canvas")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var area: widgets.Canvas = new widgets.Canvas()
    root.add(area)?
    area.set_frame(geometry.Rect.of(0.0, 0.0, 64.0, 32.0))?

    io.println("-- the control --")
    io.println("  it is a {area.kind().name()} on every host: {area.native_class()?.len() > 0}")
    io.println("  a screen reader calls it a {area.a11y_role()?}")

    let promised: bool = platform.Capability.gpu.available()

    var attached: bool = false
    var framed: bool = false
    var frame_size_right: bool = false
    var drew: bool = false
    var second_frame: bool = false
    var presented_offscreen_refused: bool = false
    var next_before_attach_refused: bool = false

    match gpu.Device.open() {
        ok(card) => {
            var device: gpu.Device = card

            match gpu.Canvas.on(area.handle(), device) {
                ok(painter) => {
                    attached = true
                    var paint: gpu.Canvas = painter

                    var shader: gpu.Shader = device.shader(gpu.ShaderLanguage.msl, SHADER)?
                    var line: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
                    line.attr(0, 2, 0)?
                    line.attr(1, 4, 2)?
                    line.stride(6)?
                    // A canvas is not the same pixels as an off-screen target,
                    // and a pipeline that said nothing would be refused by the
                    // driver at draw time rather than here.
                    line.pixels(gpu.Pixels.screen)?
                    line.build()?

                    var shape: gpu.Buffer = device.buffer(quad(0.0, 0.0, 1.0))?

                    match paint.next() {
                        ok(surface) => {
                            framed = true
                            var frame: gpu.Target = surface
                            var draw: gpu.Pass = frame.begin(1.0, 0.0, 0.0, 1.0)?
                            draw.pipeline(line)?
                            draw.vertices(shape)?
                            draw.draw(gpu.Shape.triangles, 0, 6)?
                            // Read before presenting: after it goes to the
                            // compositor there is nothing here to look at.
                            draw.finish()?
                            let shown: widgets.Snapshot = frame.read()?
                            // 64x32 points on a 2x display is 128x64 pixels —
                            // a canvas is the one thing in cortado measured in
                            // real pixels, because that is what a shader
                            // writes.
                            frame_size_right = shown.width >= 64 && shown.height >= 32
                            let middle: widgets.Rgba = shown.pixel(shown.width / 2, shown.height / 2)?
                            // Blue, and read back as RGBA even though the
                            // compositor's own format is not — which is the
                            // one line of swizzling in the host earning its
                            // keep. Asserted rather than printed, so this
                            // golden is the same bytes on a host with no GPU.
                            drew = middle.blue == 255 && middle.red == 0 &&
                                   middle.green == 0 && shown.byte_count() > 0
                        }
                        err(problem) => {}
                    }

                    // A second frame, because a canvas that could only ever
                    // give one would pass every test above and be useless.
                    match paint.next() {
                        ok(again) => {
                            second_frame = true
                            var frame: gpu.Target = again
                            var draw: gpu.Pass = frame.begin(0.0, 1.0, 0.0, 1.0)?
                            draw.present()?
                        }
                        err(problem) => {}
                    }

                    // An off-screen target has nothing to put on screen.
                    var offscreen: gpu.Target = device.target(8, 8)?
                    var wrong: gpu.Pass = offscreen.begin(0.0, 0.0, 0.0, 1.0)?
                    match wrong.present() {
                        ok(done) => { presented_offscreen_refused = false }
                        err(problem) => { presented_offscreen_refused = problem.kind == "wrong_moment" }
                    }
                    wrong.abandon()?
                }
                err(problem) => {}
            }
        }
        err(problem) => {}
    }

    io.println("-- what happened, against what the capability promised --")
    io.println("  a GPU attaches to a canvas: {promised == attached}")
    io.println("  it hands back a frame: {promised == framed}")
    io.println("  the frame is at least the size of the control: {promised == frame_size_right}")
    io.println("  what the shader wrote is what reads back: {promised == drew}")
    io.println("  and again the next frame: {promised == second_frame}")
    io.println("  presenting an off-screen pass is refused: {promised == presented_offscreen_refused}")

    io.println("-- refusals --")
    var button: widgets.Button = widgets.Button.of("not a canvas")?
    root.add(button)?
    var button_refused: bool = false
    var said_wrong_widget: bool = false
    match gpu.Device.open() {
        ok(card) => {
            var device: gpu.Device = card
            match gpu.Canvas.on(button.handle(), device) {
                ok(painter) => {}
                err(problem) => {
                    button_refused = true
                    said_wrong_widget = problem.kind == "wrong_widget"
                }
            }
        }
        // No GPU here, so there was never a device to attach. Still refused,
        // and that is what the first line below claims.
        err(problem) => { button_refused = true }
    }
    io.println("  a GPU never gets attached to a button: {button_refused}")
    // The second half is the part only a host with a GPU can reach, and it is
    // the one that matters: "this is not a canvas" is the caller's bug and
    // "this platform has no GPU" is not, so a host must not answer the second
    // to both. The hosts without one check the kind before they refuse — the
    // header says they must — but nothing in Beans can reach that check while
    // `Canvas.on` needs a `Device` those hosts cannot open. It is the four
    // hosts' shared contract, checked on the two that can run it.
    io.println("  and where there is one, it says which widget is wrong: {promised == said_wrong_widget}")

    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
