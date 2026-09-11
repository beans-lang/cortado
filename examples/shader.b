// Drawing with the GPU: a shader, a render target, and a file you can open.
//
//     beansc build examples/shader.b -o build/shader && ./build/shader
//
// Everything else in cortado asks the platform for a control and lets the
// platform paint it. This is the other door. There are no widgets in this
// program at all — it opens the machine's graphics processor, compiles a
// fragment shader, draws one rectangle covering the whole image, and reads the
// pixels back.
//
// The shape is worth naming because it is the shape of every GPU program:
//
//   1. a device, and a target to draw into
//   2. a shader, compiled from source at run time
//   3. a pipeline — which shader functions, what a vertex looks like
//   4. a buffer of vertices
//   5. a pass: clear, set, draw, finish
//   6. read the pixels back
//
// The picture is a Mandelbrot set, because the fragment shader is where the
// work belongs: every one of the 640x480 pixels runs that loop, in parallel,
// on hardware built for it. The same loop in Beans would be a third of a
// million iterations of an inner loop on one core.
package main

import cortado.platform
import cortado.gpu
import cortado.widgets
import std.fs
import std.io

const WIDE: int = 640
const TALL: int = 480

// Two triangles covering the whole of clip space, carrying the corner
// coordinates along so the fragment shader knows where it is.
fn corners() -> List<f64> {
    var at: List<f64> = [
    -1.0, -1.0,   -2.2, -1.2,
     1.0, -1.0,    1.0, -1.2,
    -1.0,  1.0,   -2.2,  1.2,
     1.0, -1.0,    1.0, -1.2,
     1.0,  1.0,    1.0,  1.2,
    -1.0,  1.0,   -2.2,  1.2
    ]
    return move at
}

// A raw string, because a shader is full of `{` and an ordinary Beans string
// reads that as the start of an interpolation.
const SHADER: string = r"
#include <metal_stdlib>
using namespace metal;

struct In  { float2 at [[attribute(0)]]; float2 plane [[attribute(1)]]; };
struct Out { float4 at [[position]]; float2 plane; };
struct Uniform { float limit; };

vertex Out v_main(In v [[stage_in]]) {
    Out out;
    out.at = float4(v.at, 0.0, 1.0);
    out.plane = v.plane;
    return out;
}

fragment float4 f_main(Out v [[stage_in]], constant Uniform &u [[buffer(1)]]) {
    float2 c = v.plane;
    float2 z = float2(0.0, 0.0);
    float steps = 0.0;
    for (int i = 0; i < 256; i++) {
        if (float(i) >= u.limit) { break; }
        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        if (dot(z, z) > 4.0) { break; }
        steps += 1.0;
    }
    if (steps >= u.limit) { return float4(0.0, 0.0, 0.0, 1.0); }
    // A smooth colour from how quickly the point escaped.
    float t = steps / u.limit;
    return float4(t, t * t * 0.8 + 0.15, 0.55 - t * 0.35, 1.0);
}
"

// A Windows bitmap, which is the shortest image format that opens with a
// double click on every desktop.
//
// This is file-format code and not cortado: fourteen bytes of file header,
// forty of image header, then the pixels **bottom row first** and as blue,
// green, red — both of which are the format's conventions and neither of which
// is what the GPU handed back.
fn bitmap(shot: widgets.Snapshot) -> Result<Bytes> {
    let rows: int = shot.height
    let columns: int = shot.width
    // Every row is padded out to a multiple of four bytes.
    let stride: int = ((columns * 3) + 3) / 4 * 4
    let body: int = stride * rows
    var out: Bytes = Bytes.filled(54 + body, 0)

    out.set(0, 66)                      // "BM"
    out.set(1, 77)
    put32(out, 2, 54 + body)            // the whole file
    put32(out, 10, 54)                  // where the pixels start
    put32(out, 14, 40)                  // the size of this header
    put32(out, 18, columns)
    put32(out, 22, rows)
    out.set(26, 1)                      // one colour plane
    out.set(28, 24)                     // bits per pixel
    put32(out, 34, body)

    for y: int in 0..rows {
        for x: int in 0..columns {
            let pixel: widgets.Rgba = shot.pixel(x, y)?
            let at: int = 54 + (rows - 1 - y) * stride + x * 3
            out.set(at, pixel.blue)
            out.set(at + 1, pixel.green)
            out.set(at + 2, pixel.red)
        }
    }
    return ok(move out)
}

fn put32(out: Bytes, at: int, value: int) {
    out.set(at, value % 256)
    out.set(at + 1, value / 256 % 256)
    out.set(at + 2, value / 65536 % 256)
    out.set(at + 3, value / 16777216 % 256)
}

fn run() -> Result<bool> {
    // Ask once. A platform with no GPU host refuses every call below, and
    // finding that out one call at a time is exactly what the capability
    // exists to prevent.
    if !platform.Capability.gpu.available() {
        io.println("this platform has no GPU host — cortado draws with Metal on macOS and iOS")
        return ok(false)
    }

    var card: gpu.Device = gpu.Device.open()?
    io.println("drawing on {card.name()?}")
    io.println("  shares memory with the CPU: {card.shares_memory()?}")

    var shader: gpu.Shader = card.shader(gpu.ShaderLanguage.msl, SHADER)?
    var line: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
    line.attr(0, 2, 0)?          // where the vertex is, two numbers, at 0
    line.attr(1, 2, 2)?          // where it is on the plane, two numbers, at 2
    line.stride(4)?              // so a vertex is four numbers
    line.build()?

    var quad: gpu.Buffer = card.buffer(corners())?
    var canvas: gpu.Target = card.target(WIDE, TALL)?

    var draw: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    draw.pipeline(line)?
    draw.vertices(quad)?
    draw.uniform([120.0])?        // how long to keep looking before calling it black
    draw.draw(gpu.Shape.triangles, 0, 6)?
    draw.finish()?

    let picture: widgets.Snapshot = canvas.read()?
    io.println("  rendered {picture.width}x{picture.height}, {picture.byte_count()} bytes")

    let file: string = "build/mandelbrot.bmp"
    fs.write_bytes(file, bitmap(picture)?)?
    io.println("wrote {file} — open it")
    return ok(true)
}

fn main() {
    match run() {
        ok(drew) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
