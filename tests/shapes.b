// Shapes asserted as pixels, not as "it compiled". The fixed one-pixel ramp
// makes a boundary-aligned edge exactly 1 or 0, so every count is arithmetic.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import cortado.motion
import cortado.gpu
import std.io
import std.math

const SIDE: int = 8

/// A screen with one shape on it, the way markup writes one.
class Sheet extends component.Component {
    pub shape: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    /// How tall the shape is placed; zero lets the column decide.
    pub height: f64 = 0.0

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        // Without this the canvas is as wide as it measures, which for a
        // control that paints nothing of its own is nothing at all.
        into.word("align", "stretch")
        var placed: component.Placement = into.show("shape", self.shape)
        if self.height > 0.0 { placed.number("height", self.height) }
        into.close()
    }
}

/// Draws a `ShapeCanvas`'s own program off-screen and reads it back. Low-level
/// because a canvas frame belongs to the compositor; it is the same program.
fn drawn(card: gpu.Device, shape: gpu.ShapeCanvas, scale: f64) -> Result<widgets.Snapshot> {
    let source: string = shape.program()?
    var compiled: gpu.Shader = card.shader(gpu.ShaderLanguage.msl, source)?
    var line: gpu.Pipeline = compiled.pipeline("cortado_vertex", "cortado_fragment")?
    line.attr(0, 2, 0)?
    line.attr(1, 2, 2)?
    line.stride(4)?
    line.build()?
    var quad: gpu.Buffer = card.buffer(gpu.ShaderCanvas.quad_corners())?
    var target: gpu.Target = card.target(SIDE, SIDE)?
    var pass: gpu.Pass = target.begin(0.0, 0.0, 0.0, 1.0)?
    pass.pipeline(line)?
    pass.vertices(quad)?
    pass.uniform([0.0, SIDE as f64, SIDE as f64, scale])?
    pass.draw(gpu.Shape.triangles, 0, 6)?
    pass.finish()?
    return target.read()
}

/// How many pixels are exactly this colour.
fn exactly(shot: widgets.Snapshot, want: widgets.Rgba) -> Result<int> {
    var found: int = 0
    for y: int in 0..SIDE {
        for x: int in 0..SIDE {
            if shot.pixel(x, y)?.same_as(want) { found = found + 1 }
        }
    }
    return ok(found)
}

/// How many pixels are neither of two colours — the antialiased band, and
/// anything that went wrong.
fn between(shot: widgets.Snapshot, first: widgets.Rgba, second: widgets.Rgba) -> Result<int> {
    var found: int = 0
    for y: int in 0..SIDE {
        for x: int in 0..SIDE {
            let here: widgets.Rgba = shot.pixel(x, y)?
            if !here.same_as(first) && !here.same_as(second) { found = found + 1 }
        }
    }
    return ok(found)
}

fn absolute(value: f64) -> f64 {
    if value < 0.0 { return 0.0 - value }
    return value
}

/// The rounded-rect distance in Beans — the MSL's arithmetic written twice on
/// purpose, since every term depends on the scale the shader was handed.
fn corner_distance(px: f64, py: f64, half_w: f64, half_h: f64, radius: f64) -> f64 {
    let shorter: f64 = if half_w < half_h { half_w } else { half_h }
    let r: f64 = if radius < shorter { radius } else { shorter }
    let qx: f64 = absolute(px) - (half_w - r)
    let qy: f64 = absolute(py) - (half_h - r)
    let mx: f64 = if qx > 0.0 { qx } else { 0.0 }
    let my: f64 = if qy > 0.0 { qy } else { 0.0 }
    let bigger: f64 = if qx > qy { qx } else { qy }
    let within: f64 = if bigger < 0.0 { bigger } else { 0.0 }
    return math.sqrt(mx * mx + my * my) + within - r
}

/// How many pixels disagree with the shape the canvas says it draws. Only the
/// unambiguous ones: a pixel inside the ramp is part-covered by design.
fn disagreements(shot: widgets.Snapshot, inset: f64, radius: f64, scale: f64,
                 fill: widgets.Rgba, ground: widgets.Rgba) -> Result<int> {
    let half_w: f64 = (shot.width as f64) * 0.5 - inset * scale
    let half_h: f64 = (shot.height as f64) * 0.5 - inset * scale
    var wrong: int = 0
    for y: int in 0..shot.height {
        for x: int in 0..shot.width {
            let px: f64 = ((x as f64) + 0.5) - (shot.width as f64) * 0.5
            let py: f64 = ((y as f64) + 0.5) - (shot.height as f64) * 0.5
            let d: f64 = corner_distance(px, py, half_w, half_h, radius * scale)
            let here: widgets.Rgba = shot.pixel(x, y)?
            if d <= -0.5 && !here.same_as(fill) { wrong = wrong + 1 }
            if d >= 0.5 && !here.same_as(ground) { wrong = wrong + 1 }
        }
    }
    return ok(wrong)
}

fn refusal(what: string, outcome: Result<string>) -> string {
    match outcome {
        ok(body) => { return "{what} was allowed, and should not have been" }
        err(problem) => { return "{what} refused: {problem.kind}" }
    }
}

/// A refusal whose *message* matters, not only its kind — the pattern
/// `tests/shader.b` uses for the ones an author has to act on.
fn saying(what: string, clue: string, outcome: Result<string>) -> string {
    match outcome {
        ok(body) => { return "{what} was allowed, and should not have been" }
        err(problem) => { return "{what} refused, saying so: {problem.msg.contains(clue)}" }
    }
}

fn shapes(app: surface.Application, card: gpu.Device) -> Result<bool> {
    let ground: widgets.Rgba = widgets.Rgba.of_hex("#101010")?
    let inside: widgets.Rgba = widgets.Rgba.of_hex("#40a0c0")?
    let outline: widgets.Rgba = widgets.Rgba.of_hex("#ffffff")?

    io.println("-- a rectangle whose edges land on pixel boundaries --")
    // Edge at |p| = 2, so centres at 1.5 are in and 2.5 are out: four per axis,
    // sixteen pixels, none part-covered.
    var block: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    block.figure = "rounded_rect"
    block.background = "#101010"
    block.color = "#40a0c0"
    block.inset = 2.0
    let square: widgets.Snapshot = drawn(card, block, 1.0)?
    let filled: int = exactly(square, inside)?
    let empty: int = exactly(square, ground)?
    let fringe: int = between(square, inside, ground)?
    io.println("  sixteen pixels are the fill, exactly: {filled == 16}")
    io.println("  forty-eight are the background, exactly: {empty == 48}")
    io.println("  and none is part-covered: {fringe == 0}")

    io.println("-- the same rectangle, stroked --")
    // The band is distance in [-1, 0]: the outer ring of the 4x4 block, twelve
    // pixels, leaving the inner 2x2 as fill.
    var edged: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    edged.figure = "rounded_rect"
    edged.background = "#101010"
    edged.color = "#40a0c0"
    edged.inset = 2.0
    edged.stroke = "#ffffff"
    edged.stroke_width = 1.0
    let ringed: widgets.Snapshot = drawn(card, edged, 1.0)?
    let stroked: int = exactly(ringed, outline)?
    let core: int = exactly(ringed, inside)?
    let outer: int = exactly(ringed, ground)?
    io.println("  twelve pixels are the stroke: {stroked == 12}")
    io.println("  four are still the fill: {core == 4}")
    io.println("  and forty-eight are untouched: {outer == 48}")

    io.println("-- a circle, where the edge does not land on a boundary --")
    // Radius 2 about the middle: four centres at 0.707 are inside, twelve
    // straddle. The case a fixed ramp still antialiases.
    var round: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    round.figure = "ellipse"
    round.background = "#101010"
    round.color = "#40a0c0"
    round.inset = 2.0
    let disc: widgets.Snapshot = drawn(card, round, 1.0)?
    let solid_in: int = exactly(disc, inside)?
    let solid_out: int = exactly(disc, ground)?
    let soft: int = between(disc, inside, ground)?
    io.println("  four pixels are wholly inside: {solid_in == 4}")
    io.println("  twelve straddle the edge: {soft == 12}")
    io.println("  and forty-eight are wholly outside: {solid_out == 48}")

    io.println("-- the colour you name is the colour that lands --")
    let middle: widgets.Rgba = square.pixel(4, 4)?
    io.println("  #40a0c0 reads back as {middle.show()}")

    io.println("-- a radius is in points, so the backing scale moves it --")
    // At scale 2 the corner rounds twice as far, so it covers fewer pixels.
    // A comparison, because what is pinned is that the scale is read at all.
    var soft_corner: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    soft_corner.figure = "rounded_rect"
    soft_corner.background = "#101010"
    soft_corner.color = "#40a0c0"
    soft_corner.inset = 2.0
    soft_corner.radius = 1.0
    let at_one: widgets.Snapshot = drawn(card, soft_corner, 1.0)?
    let at_two: widgets.Snapshot = drawn(card, soft_corner, 2.0)?
    let one_up: int = exactly(at_one, inside)?
    let two_up: int = exactly(at_two, inside)?
    io.println("  a bigger radius covers fewer whole pixels: {two_up < one_up}")
    io.println("  and the two are not the same picture: {at_one.differences(at_two)? > 0}")

    io.println("-- mounted, the canvas reads the scale from its own surface --")
    // Above drives the uniform by hand. This half mounts one on a real window
    // and compares what it recorded against what the surface says.
    var window: surface.Window = app.window(64.0, 64.0, "Shape")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var page: Sheet = new Sheet()
    page.shape.background = "#101010"
    page.shape.color = "#40a0c0"
    page.shape.inset = 2.0
    page.shape.radius = 20.0
    page.height = 64.0
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(64.0, 64.0))
    mount.show(page)?
    let told: f64 = window.scale()?
    io.println("  it is drawing at the surface's own scale: {page.shape.backing_scale() == told}")
    // `on_mount` runs before `lay_out`, so there is no size until the first
    // frame. Driven by hand, standing in for a display this gate has not got.
    io.println("  it wants its first frame: {page.shape.needs_redraw()}")
    let drew: bool = page.shape.draw(0.0)
    io.println("  and draws one when asked: {drew}")
    let quiet: bool = page.shape.problem() == ""
    io.println("  with nothing to complain about: {quiet}")
    // Having drawn at a size that has not changed since, a still shape asks
    // for no more frames — which is what keeps a screen of furniture free.
    io.println("  then asks for no more: {!page.shape.needs_redraw()}")
    // Where the scale actually reaches the shader: the pixels against the shape
    // those numbers describe, every term multiplied by the scale.
    let picture: widgets.Snapshot = page.shape.snapshot(0.0)?
    let off: int = disagreements(picture, 2.0, 20.0, told, inside, ground)?
    io.println("  and the pixels are the shape those numbers describe: {off == 0}")
    // One host clock, however many shapes ride it.
    let riders: int = motion.ClockDesk.instance.listeners_on(window.handle())
    io.println("  and one clock carries it: {riders == 1}")
    mount.close()?

    // A shape laid out at no width says so, and stops saying it once it has
    // one. `problem()` is the only thing this class can say, so a message kept
    // after the frame it complained about arrived is a report that is untrue —
    // and being laid out narrow before a parent stretches it is the way in.
    var thin_root: widgets.Container = new widgets.Container()
    var thin_window: surface.Window = app.window(64.0, 64.0, "Thin")?
    thin_window.set_root(thin_root)?
    var thin_page: Sheet = new Sheet()
    thin_page.shape.figure = "rounded_rect"
    thin_page.height = 32.0
    var thin_mount: component.Mount = new component.Mount(thin_root, app.router)
    thin_mount.set_bounds(geometry.Size.of(0.0, 64.0))
    thin_mount.show(thin_page)?
    thin_page.shape.draw(0.0)
    io.println("  a shape with no width says so: {thin_page.shape.problem().contains("nothing to draw into")}")
    thin_mount.resized(geometry.Size.of(64.0, 64.0))?
    thin_page.shape.draw(0.0)
    io.println("  and stops saying so once it has one: {thin_page.shape.problem() == ""}")
    thin_mount.close()?

    io.println("-- every figure cortado names --")
    var working: int = 0
    let names: List<string> = gpu.Figure.names()
    for name: string in names {
        var each: gpu.ShapeCanvas = new gpu.ShapeCanvas()
        each.figure = name
        each.background = "#101010"
        each.color = "#40a0c0"
        each.inset = 1.0
        if name == "ring" { each.thickness = 1.0 }
        match drawn(card, each, 1.0) {
            ok(shot) => {
                // Something was drawn, and it is not a blank canvas.
                let lit: int = exactly(shot, ground)?
                if lit < SIDE * SIDE { working = working + 1 }
            }
            err(problem) => { io.println("  {name} failed: {problem.msg}") }
        }
    }
    io.println("  cortado names this many figures: {names.len()}")
    io.println("  every one compiles and draws something: {working == names.len()}")

    return ok(true)
}

fn refusals() {
    io.println("-- refusals --")
    var unknown: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    unknown.figure = "rounded_rect_ish"
    io.println(saying("a figure cortado does not draw", "rounded_rect", unknown.body()))

    var bad_fill: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    bad_fill.fill = "gradiant"
    io.println(saying("a fill cortado does not have", "gradient", bad_fill.body()))

    // A radius on a shape with no corners would draw exactly the same picture,
    // which is the kind of silence this refuses.
    var pointless: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    pointless.figure = "ellipse"
    pointless.radius = 4.0
    io.println(saying("a radius on an ellipse", "no corners", pointless.body()))

    var thick: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    thick.figure = "capsule"
    thick.thickness = 2.0
    io.println(saying("a thickness on a capsule", "solid", thick.body()))

    var bare_ring: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    bare_ring.figure = "ring"
    io.println(saying("a ring with no thickness", "needs a thickness", bare_ring.body()))

    var half: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    half.stroke_width = 3.0
    io.println(saying("a stroke width with no colour", "give it a stroke", half.body()))

    var flat: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    flat.stroke = "#ffffff"
    flat.stroke_width = 0.0
    io.println(saying("a stroke with no width", "above zero", flat.body()))

    // A shadow with nowhere to fall is cut off at the canvas edge, which looks
    // like a bug in the shadow rather than a missing inset.
    var cramped: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    cramped.shadow = "#00000060"
    cramped.shadow_radius = 6.0
    cramped.shadow_y = 2.0
    io.println(saying("a shadow with no room", "cut off", cramped.body()))

    var roomy: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    roomy.shadow = "#00000060"
    roomy.shadow_radius = 6.0
    roomy.shadow_y = 2.0
    roomy.inset = 8.0
    match roomy.body() {
        ok(body) => { io.println("  the same shadow with room is allowed: true") }
        err(problem) => { io.println("  the same shadow with room is allowed: false ({problem.kind})") }
    }

    var wrong_colour: gpu.ShapeCanvas = new gpu.ShapeCanvas()
    wrong_colour.color = "#gg0000"
    io.println(refusal("a colour that is not one", wrong_colour.body()))
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let promised: bool = platform.Capability.gpu.available()
    io.println("-- what this platform promised --")
    io.println("  it has a GPU: {promised}")

    // The refusals are arithmetic on strings and need no device at all, so
    // they are asserted on every host rather than only where there is a GPU.
    refusals()

    if promised {
        var card: gpu.Device = gpu.Device.open()?
        shapes(app, card)?
        card.close()?
    } else {
        // Said out loud: a run that printed nothing would look the same as one
        // that checked.
        io.println("-- pixels: not checked, this platform has no GPU --")
    }

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
