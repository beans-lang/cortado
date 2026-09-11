// Pixels a program computed, asserted exactly.
//
// `tests/pixels.b` reads a control back and can only assert *shape* — an image
// is the size asked for, a control that painted is not uniform — because the
// numbers come out of a font rasterizer that changes with every OS release.
// This one is the opposite. Every quad here lands on a pixel boundary, so
// coverage is arithmetic rather than anti-aliasing, and the colours are exact
// on any conformant GPU: a pixel centre is inside the quad or it is not.
//
// That was checked before it was relied on. The same triangle rendered through
// a bare Metal program on this Mac and in the iOS Simulator gave the same
// checksum and the same orientation, on two different GPUs.
//
// The geometry, once, because every count below follows from it. Clip space
// runs -1 to +1 with **y upward**, and row 0 of the image is the **top**. In an
// 8x8 target a pixel centre sits at 1 - 2*(row + 0.5)/8, so a quad from y=0 to
// y=+1 covers rows 0 to 3 and no others: row 3's centre is at +0.125 and row
// 4's is at -0.125.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.gpu
import std.io

// Position, then colour: two numbers and four, six to a vertex.
const SHADER: string = r"
#include <metal_stdlib>
using namespace metal;
struct In  { float2 at [[attribute(0)]]; float4 tint [[attribute(1)]]; };
struct Out { float4 at [[position]]; float4 tint; };
struct Uniform { float scale; };
vertex Out v_main(In v [[stage_in]], constant Uniform &u [[buffer(1)]]) {
    Out out;
    out.at = float4(v.at * u.scale, 0.0, 1.0);
    out.tint = v.tint;
    return out;
}
fragment float4 f_main(Out v [[stage_in]]) { return v.tint; }
"

const SIDE: int = 8

// Two triangles making a rectangle, with one colour at every corner.
//
// Written out as six vertices rather than four in a triangle strip because a
// strip's vertex order is a thing to get wrong quietly, and this file is about
// being able to read the expected answer off the page. Each row is a vertex:
// where it is, then what colour it is.
fn quad(left: f64, top: f64, right: f64, bottom: f64,
        red: f64, green: f64, blue: f64, alpha: f64) -> List<f64> {
    var at: List<f64> = [
        left,  bottom, red, green, blue, alpha,
        right, bottom, red, green, blue, alpha,
        left,  top,    red, green, blue, alpha,
        right, bottom, red, green, blue, alpha,
        right, top,    red, green, blue, alpha,
        left,  top,    red, green, blue, alpha
    ]
    return move at
}

// How many pixels came out this colour, and whether every pixel is one of the
// two the drawing could have produced. The second half is what catches a GPU
// that anti-aliased an edge cortado said was exact.
class Count {
    pub matched: int = 0
    pub strays: int = 0

    pub fn init() {}
}

fn tally(shot: widgets.Snapshot, red: int, green: int, blue: int,
         other_red: int, other_green: int, other_blue: int) -> Result<Count> {
    var count: Count = new Count()
    for y: int in 0..shot.height {
        for x: int in 0..shot.width {
            let pixel: widgets.Rgba = shot.pixel(x, y)?
            if pixel.red == red && pixel.green == green && pixel.blue == blue {
                count.matched = count.matched + 1
            } else if pixel.red != other_red || pixel.green != other_green ||
                      pixel.blue != other_blue {
                count.strays = count.strays + 1
            }
        }
    }
    return ok(count)
}

// Prints what a refusal was, rather than answering it, so that a call whose
// own arguments are strings does not have to be nested inside one.
fn refused(what: string, outcome: Result<bool>) {
    match outcome {
        ok(done) => { io.println("  {what} was allowed, and should not have been") }
        err(problem) => { io.println("  {what} refused: {problem.kind}") }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var card: gpu.Device = gpu.Device.open()?
    var canvas: gpu.Target = card.target(SIDE, SIDE)?
    var shader: gpu.Shader = card.shader(gpu.ShaderLanguage.msl, SHADER)?

    var line: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
    line.attr(0, 2, 0)?
    line.attr(1, 4, 2)?
    line.stride(6)?
    line.build()?

    io.println("-- nothing drawn --")
    var empty: gpu.Pass = canvas.begin(0.0, 0.0, 1.0, 1.0)?
    empty.finish()?
    let cleared: widgets.Snapshot = canvas.read()?
    io.println("  the target is {cleared.width}x{cleared.height}, {cleared.byte_count()} bytes")
    let blue: Count = tally(cleared, 0, 0, 255, 0, 0, 255)?
    io.println("  every pixel is the clear colour: {blue.matched == SIDE * SIDE}")
    io.println("  and nothing else got drawn: {blue.strays == 0}")

    io.println("-- the whole target --")
    var whole: gpu.Buffer = card.buffer(quad(-1.0, 1.0, 1.0, -1.0, 0.0, 1.0, 0.0, 1.0))?
    io.println("  the vertex buffer holds {whole.count()?} numbers, six to a vertex")
    var all: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    all.pipeline(line)?
    all.vertices(whole)?
    all.uniform([1.0])?
    all.draw(gpu.Shape.triangles, 0, 6)?
    all.finish()?
    let filled: widgets.Snapshot = canvas.read()?
    let green: Count = tally(filled, 0, 255, 0, 0, 0, 0)?
    io.println("  green pixels: {green.matched} of {SIDE * SIDE}")
    io.println("  no pixel is anything but green or the clear colour: {green.strays == 0}")

    io.println("-- the top half, which is where y=+1 lands --")
    var upper: gpu.Buffer = card.buffer(quad(-1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0))?
    var half: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    half.pipeline(line)?
    half.vertices(upper)?
    half.uniform([1.0])?
    half.draw(gpu.Shape.triangles, 0, 6)?
    half.finish()?
    let split: widgets.Snapshot = canvas.read()?
    let upper_green: Count = tally(split, 0, 255, 0, 0, 0, 0)?
    io.println("  green pixels: {upper_green.matched} of {SIDE * SIDE}")
    io.println("  row 0 is green: {split.pixel(0, 0)?.green == 255}")
    io.println("  row {SIDE - 1} is not: {split.pixel(0, SIDE - 1)?.green == 0}")

    io.println("-- a uniform the shader multiplies by --")
    var shrunk: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    shrunk.pipeline(line)?
    shrunk.vertices(whole)?
    // Half the size: clip -0.5 to +0.5, which in eight rows is the middle four
    // in each direction, so sixteen pixels of the sixty-four.
    shrunk.uniform([0.5])?
    shrunk.draw(gpu.Shape.triangles, 0, 6)?
    shrunk.finish()?
    let middle: widgets.Snapshot = canvas.read()?
    let inner: Count = tally(middle, 0, 255, 0, 0, 0, 0)?
    io.println("  green pixels at half scale: {inner.matched} of {SIDE * SIDE}")
    io.println("  the corner is empty: {middle.pixel(0, 0)?.green == 0}")
    io.println("  the centre is not: {middle.pixel(4, 4)?.green == 255}")

    io.println("-- blending --")
    // Two more pipelines off the same shader. The colours are chosen so that
    // every answer is exact in eight bits: a half-and-half mix would land on
    // 127.5 and two GPUs are allowed to round it differently.
    var over: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
    over.attr(0, 2, 0)?
    over.attr(1, 4, 2)?
    over.stride(6)?
    over.blend(gpu.Blend.alpha)?
    over.build()?

    var plus: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
    plus.attr(0, 2, 0)?
    plus.attr(1, 4, 2)?
    plus.stride(6)?
    plus.blend(gpu.Blend.add)?
    plus.build()?

    var red: gpu.Buffer = card.buffer(quad(-1.0, 1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 1.0))?
    var clear_green: gpu.Buffer = card.buffer(quad(-1.0, 1.0, 1.0, -1.0, 0.0, 1.0, 0.0, 0.0))?
    var solid_green: gpu.Buffer = card.buffer(quad(-1.0, 1.0, 1.0, -1.0, 0.0, 1.0, 0.0, 1.0))?

    // Green at no alpha at all, over red. With the blend factors the right way
    // round nothing happens; with them swapped the red disappears — which is
    // the mistake this case exists to catch.
    var invisible: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    invisible.pipeline(line)?
    invisible.vertices(red)?
    invisible.uniform([1.0])?
    invisible.draw(gpu.Shape.triangles, 0, 6)?
    invisible.pipeline(over)?
    invisible.vertices(clear_green)?
    invisible.draw(gpu.Shape.triangles, 0, 6)?
    invisible.finish()?
    let untouched: widgets.Snapshot = canvas.read()?
    io.println("  green at alpha 0 over red leaves red: {untouched.pixel(4, 4)?.show()}")

    var covered: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    covered.pipeline(line)?
    covered.vertices(red)?
    covered.uniform([1.0])?
    covered.draw(gpu.Shape.triangles, 0, 6)?
    covered.pipeline(over)?
    covered.vertices(solid_green)?
    covered.draw(gpu.Shape.triangles, 0, 6)?
    covered.finish()?
    let replaced: widgets.Snapshot = canvas.read()?
    io.println("  green at alpha 1 over red covers it: {replaced.pixel(4, 4)?.show()}")

    var added: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    added.pipeline(line)?
    added.vertices(red)?
    added.uniform([1.0])?
    added.draw(gpu.Shape.triangles, 0, 6)?
    added.pipeline(plus)?
    added.vertices(solid_green)?
    added.draw(gpu.Shape.triangles, 0, 6)?
    added.finish()?
    let summed: widgets.Snapshot = canvas.read()?
    io.println("  green added to red is both: {summed.pixel(4, 4)?.show()}")

    io.println("-- refusals --")
    var unbuilt: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
    unbuilt.attr(0, 2, 0)?
    unbuilt.stride(6)?
    var early: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    refused("drawing with a pipeline nobody built", early.pipeline(unbuilt))
    refused("drawing with no pipeline set", early.draw(gpu.Shape.triangles, 0, 6))
    early.abandon()?

    var no_layout: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
    refused("building a pipeline with no vertex layout", no_layout.build())
    refused("five numbers in one attribute", no_layout.attr(0, 5, 0))
    refused("changing a pipeline after it is built", line.stride(6))

    refused("writing past the end of a buffer", whole.write(34, [1.0, 2.0, 3.0]))
    refused("writing before the start of one", whole.write(-1, [1.0]))

    var spent: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    spent.finish()?
    refused("running a pass twice", spent.finish())
    refused("drawing into a pass that already ran",
                              spent.draw(gpu.Shape.triangles, 0, 6))

    match card.shader(gpu.ShaderLanguage.msl, r"vertex float4 v() { return nope; }") {
        ok(built) => { io.println("  a shader that does not compile was accepted") }
        err(problem) => {
            io.println("  a shader that does not compile: {problem.kind}")
            // The compiler's own words, so they name one toolchain and cannot
            // be goldened. That it says something, with a line in it, is the
            // part worth asserting: a failure with no message is a blank
            // window and a long evening.
            let said: string = card.shader_problem()
            let named_a_problem: bool = said.len() > 0 && said.contains("error")
            io.println("  and it said why: {named_a_problem}")
        }
    }
    match shader.pipeline("v_main", "not_in_the_source") {
        ok(built) => { io.println("  a fragment function that is not there was accepted") }
        err(problem) => { io.println("  a function name that is not in the shader: {problem.kind}") }
    }
    match card.shader(gpu.ShaderLanguage.spirv, SHADER) {
        ok(built) => { io.println("  a language this host does not speak was accepted") }
        err(problem) => { io.println("  a language this host does not speak: {problem.kind}") }
    }

    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
