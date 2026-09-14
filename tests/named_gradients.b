// The named gradients: that each one draws, that each one moves, and that the
// seam a second shading language lands on is still the shape it has to be.
//
// `tests/shader.b` covers the escape hatch — a body somebody typed. This covers
// the road most screens take, where cortado writes the body instead.
package main

import cortado.platform
import cortado.widgets
import cortado.gpu
import std.io

fn gap(a: int, b: int) -> int {
    if a > b { return a - b }
    return b - a
}

/// How far apart two frames are, over a grid of samples, 0 to 255.
fn apart(first: widgets.Snapshot, second: widgets.Snapshot) -> Result<f64> {
    var total: int = 0
    for y: int in 0..12 {
        for x: int in 0..16 {
            let a: widgets.Rgba = first.pixel(x * 4, y * 4)?
            let b: widgets.Rgba = second.pixel(x * 4, y * 4)?
            total = total + gap(a.red, b.red) + gap(a.green, b.green) + gap(a.blue, b.blue)
        }
    }
    return ok(total as f64 / 576.0)
}

/// What it costs to lay the second frame over the first at one offset.
fn offset_cost(first: widgets.Snapshot, second: widgets.Snapshot, dx: int, dy: int) -> Result<f64> {
    var total: int = 0
    for j: int in 0..6 {
        for i: int in 0..8 {
            let x: int = 12 + i * 4
            let y: int = 12 + j * 3
            let a: widgets.Rgba = first.pixel(x, y)?
            let b: widgets.Rgba = second.pixel(x + dx, y + dy)?
            total = total + gap(a.red, b.red) + gap(a.green, b.green) + gap(a.blue, b.blue)
        }
    }
    return ok(total as f64 / 48.0)
}

/// How much better the second frame fits the first somewhere else than where it
/// sits. High means a slide: every pixel changed and the picture did not.
fn sliding(first: widgets.Snapshot, second: widgets.Snapshot) -> Result<f64> {
    let held: f64 = offset_cost(first, second, 0, 0)?
    var best: f64 = held
    for j: int in 0..9 {
        for i: int in 0..9 {
            let cost: f64 = offset_cost(first, second, -12 + i * 3, -12 + j * 3)?
            if cost < best { best = cost }
        }
    }
    // A frame that matches itself perfectly somewhere would divide by nothing.
    if best < 0.01 { return ok(held / 0.01) }
    return ok(held / best)
}

fn frame_at(card: gpu.Device, line: gpu.Pipeline, quad: gpu.Buffer, seconds: f64) -> Result<widgets.Snapshot> {
    var canvas: gpu.Target = card.target(64, 48)?
    var pass: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    pass.pipeline(line)?
    pass.vertices(quad)?
    pass.uniform([seconds, 64.0, 48.0, 0.0])?
    pass.draw(gpu.Shape.triangles, 0, 6)?
    pass.finish()?
    return canvas.read()
}

/// Draws one gradient off-screen at four instants and scores the three things
/// worth knowing: that it moves, that it still moves later, and that a frame
/// asked for twice is the same frame.
fn scores(what: gpu.Gradient) -> Result<List<f64>> {
    let body: string = what.source()?
    let dialect: gpu.ShaderDialect = gpu.Gradient.dialect()?
    var card: gpu.Device = gpu.Device.open()?
    var shader: gpu.Shader = card.shader(dialect.language, gpu.ShaderCanvas.wrap_in(dialect.language, body)?)?
    var line: gpu.Pipeline = shader.pipeline("cortado_vertex", "cortado_fragment")?
    line.attr(0, 2, 0)?
    line.attr(1, 2, 2)?
    line.stride(4)?
    line.build()?
    var quad: gpu.Buffer = card.buffer(gpu.ShaderCanvas.quad_corners())?

    var out: List<f64> = []
    out.push(apart(frame_at(card, line, quad, 0.0)?, frame_at(card, line, quad, 4.0)?)?)
    out.push(apart(frame_at(card, line, quad, 3600.0)?, frame_at(card, line, quad, 3604.0)?)?)
    out.push(apart(frame_at(card, line, quad, 1.0)?, frame_at(card, line, quad, 1.0)?)?)
    out.push(sliding(frame_at(card, line, quad, 0.0)?, frame_at(card, line, quad, 4.0)?)?)
    return ok(move out)
}

/// One line per gradient, over four seconds — long enough that a background
/// nobody can see moving fails, which is the regression worth catching.
///
/// The threshold is measured, not guessed. These six score 6 to 65 over that
/// interval and the near-static mesh they replaced scores 2.85.
///
/// `more than a slide` is measured the same way: these six score 1.05 to 3.31,
/// and the prism that only translated its spectrum — top scorer here — 9.1.
fn moves(name: string, what: gpu.Gradient, promised: bool) {
    var now: f64 = 0.0
    var later: f64 = 0.0
    var still: f64 = 0.0
    var slide: f64 = 0.0
    match scores(what) {
        ok(found) => {
            now = found[0]
            later = found[1]
            still = found[2]
            slide = found[3]
        }
        // Expected where there is no GPU, and the line below says so against
        // `promised`. Anywhere else it is real, and the reader is told which.
        err(problem) => {
            if promised { io.println("  {name}: {problem.kind}: {problem.msg}") }
        }
    }
    io.println("  {name} moves: {promised == (now > 4.0)}, an hour in: {promised == (later > 4.0)}, holds still: {still == 0.0}, more than a slide: {promised == (slide > 0.0 && slide < 6.0)}")
}

/// Whether a refusal names the right mistake, not merely that it refused.
fn explains(what: string, outcome: Result<string>, clue: string) {
    match outcome {
        ok(body) => { io.println("  {what} was allowed, and should not have been") }
        err(problem) => { io.println("  {what} refused, saying so: {problem.msg.contains(clue)}") }
    }
}

fn drive() {
    let promised: bool = platform.Capability.gpu.available()

    io.println("-- every named gradient --")
    moves("mesh  ", new gpu.MeshGradient(), promised)
    moves("aurora", new gpu.AuroraGradient(), promised)
    moves("flow  ", new gpu.FlowGradient(), promised)
    moves("prism ", new gpu.PrismGradient(), promised)
    moves("glow  ", new gpu.GlowGradient(), promised)
    moves("sky   ", new gpu.SkyGradient(), promised)

    io.println("-- the knobs that can be wrong --")
    var bad_hex: gpu.MeshGradient = new gpu.MeshGradient()
    bad_hex.color_2 = "1E50A2"
    explains("a colour with no #", bad_hex.source(), "color_2")
    var bad_lobe: gpu.MeshGradient = new gpu.MeshGradient()
    bad_lobe.lobe = 7
    explains("a lobe that names no colour", bad_lobe.source(), "1 to 4")
    var bad_bands: gpu.AuroraGradient = new gpu.AuroraGradient()
    bad_bands.bands = 0
    explains("no curtains at all", bad_bands.source(), "1 to 3")
    var bad_drop: gpu.AuroraGradient = new gpu.AuroraGradient()
    bad_drop.drop = 0.0
    explains("a curtain with no height", bad_drop.source(), "above zero")
    var bad_orbs: gpu.GlowGradient = new gpu.GlowGradient()
    bad_orbs.orbs = 9
    explains("more orbs than there are", bad_orbs.source(), "1 to 3")
    var bad_radius: gpu.GlowGradient = new gpu.GlowGradient()
    bad_radius.radius = 0.0
    explains("an orb with no size", bad_radius.source(), "above zero")

    // The seam. These three lines are what keeps a second shading language a
    // background job: adding one flips them, and changes no gradient's markup.
    io.println("-- the seam a second language lands on --")
    let written: List<gpu.ShaderLanguage> = gpu.ShaderCanvas.languages()
    io.println("  cortado writes a whole program in: {gpu.ShaderCanvas.written_names()}")
    var dialects: int = 0
    var wrappers: int = 0
    for language: gpu.ShaderLanguage in written {
        match gpu.ShaderDialect.of(language) {
            some(found) => { dialects = dialects + 1 }
            none => {}
        }
        match gpu.ShaderCanvas.wrap_in(language, "    return float4(1.0, 0.0, 0.0, 1.0);\n") {
            ok(source) => { wrappers = wrappers + 1 }
            err(problem) => {}
        }
    }
    io.println("  every one of them has a dialect: {dialects == written.len()}")
    io.println("  and a whole-program wrapper: {wrappers == written.len()}")
    explains("a language cortado cannot write",
             gpu.ShaderCanvas.wrap_in(gpu.ShaderLanguage.glsl, "return;"), "glsl")
    io.println("  and no gradient ever picks one: {picks_only_written()}")
}

/// A gradient chooses from what cortado can write a whole program in, never
/// from what it merely knows how to spell.
fn picks_only_written() -> bool {
    match gpu.Gradient.dialect() {
        ok(chosen) => {
            for language: gpu.ShaderLanguage in gpu.ShaderCanvas.languages() {
                if language.name() == chosen.language.name() { return true }
            }
            return false
        }
        // No GPU here, so nothing was picked — which is the rule holding, not
        // breaking. The refusal names both sides and `-- every named gradient --`
        // above has already reported that nothing drew.
        err(problem) => { return problem.kind == "no_language" }
    }
}

fn main() {
    drive()
}
