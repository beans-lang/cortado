// The easy road: a rectangle with a shader in it, named rather than written.
//
// `tests/canvas.b` checks the machinery a program drives itself — device,
// pipeline, buffer, pass, present. This checks the two ways above it, because
// the common case for a GPU in an interface is not "place my own vertices":
//
//   <ShaderCanvas effect="ripple" color="#4088bf" detail={26} />   named
//   <ShaderCanvas shader={self.body} />                            written
//
// A shader is a program in another language, and there is no honest way to
// spell an arbitrary one in markup — a shading language in angle brackets
// would be harder to write than the shading language. So cortado names the
// ones worth naming and says plainly that `shader` is the way out. Both roads
// are here, and so is every refusal that keeps them apart.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import cortado.gpu
import std.io

/// A screen with one shader canvas on it, the way markup writes one.
class Screen extends component.Component {
    pub effect: gpu.ShaderCanvas = new gpu.ShaderCanvas()
    /// How tall the effect is placed; zero lets the column decide.
    pub height: f64 = 0.0

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.number("spacing", 8.0)
        // Without this the canvas is as wide as it measures, which for a
        // control that paints nothing of its own is nothing at all. It is the
        // first thing anybody gets wrong, so `Canvas.next` says so by name.
        into.word("align", "stretch")
        var placed: component.Placement = into.show("effect", self.effect)
        if self.height > 0.0 { placed.number("height", self.height) }
        into.close()
    }
}

fn say(what: string, outcome: Result<string>) {
    match outcome {
        ok(body) => { io.println("  {what} was allowed, and should not have been") }
        err(problem) => { io.println("  {what} refused: {problem.kind}") }
    }
}

/// Whether a refusal *names the right mistake*, not merely that it refused.
///
/// Three different things can be wrong with a colour and all three are
/// `not_a_colour`, so a test that printed the kind alone would pass with one
/// check doing the work of three. What tells them apart is the message, which
/// is the half a reader actually uses.
fn explains(what: string, outcome: Result<string>, clue: string) {
    match outcome {
        ok(body) => { io.println("  {what} was allowed, and should not have been") }
        err(problem) => {
            io.println("  {what} refused, saying so: {problem.msg.contains(clue)}")
        }
    }
}

/// Mounts one named effect and draws a frame with it.
fn draws_with(app: surface.Application, name: string) -> Result<bool> {
    var window: surface.Window = app.window(64.0, 32.0, "Effect")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    var screen: Screen = new Screen()
    screen.effect.effect = name
    screen.height = 32.0
    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(64.0, 32.0))
    mount.show(screen)?
    let drew: bool = screen.effect.draw(0.5)
    mount.close()?
    return ok(drew)
}

/// Draws `effect="solid"` of one colour off-screen and reads it back.
///
/// Through the low-level API rather than through a canvas, because a canvas
/// frame belongs to the compositor and this is about the colour, not the
/// screen. What it checks is the whole chain a markup attribute goes down: the
/// text parsed, turned into MSL, wrapped in the program cortado generates,
/// compiled, and drawn.
fn solid_lands(card: gpu.Device, want: widgets.Rgba) -> Result<bool> {
    let source: string = gpu.ShaderCanvas.wrap(
        gpu.Effect.solid.body(want, want, 0.0, 0.0, 0.0))
    var shader: gpu.Shader = card.shader(gpu.ShaderLanguage.msl, source)?
    var line: gpu.Pipeline = shader.pipeline("cortado_vertex", "cortado_fragment")?
    line.attr(0, 2, 0)?
    line.attr(1, 2, 2)?
    line.stride(4)?
    line.build()?
    var quad: gpu.Buffer = card.buffer(gpu.ShaderCanvas.quad_corners())?
    var canvas: gpu.Target = card.target(4, 4)?
    var pass: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?
    pass.pipeline(line)?
    pass.vertices(quad)?
    pass.uniform([0.0, 4.0, 4.0, 0.0])?
    pass.draw(gpu.Shape.triangles, 0, 6)?
    pass.finish()?
    let shown: widgets.Snapshot = canvas.read()?
    return ok(shown.pixel(2, 2)?.same_as(want))
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(160.0, 120.0, "Shader")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var screen: Screen = new Screen()
    // A shader written by hand, which is the escape hatch. Flat red, because
    // it is exact in eight bits; it touches `uv`, `seconds` and `size` so that
    // a wrapper which forgot to declare one of them fails to compile rather
    // than quietly drawing black.
    screen.effect.shader = r"
    float ignore = uv.x * 0.0 + seconds * 0.0 + size.x * 0.0;
    return float4(1.0 + ignore, 0.0, 0.0, 1.0);
"
    screen.height = 32.0

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(160.0, 120.0))
    mount.show(screen)?

    let promised: bool = platform.Capability.gpu.available()

    io.println("-- what the component made --")
    io.println("  a canvas is in the tree: {has_canvas(root)}")
    io.println("  it says why it is empty exactly when there is no GPU: {promised == (screen.effect.problem() == "")}")

    // Driven by hand. There is no display in a gate, so no frame clock runs —
    // the same reason `tests/clock.b` steps the clock rather than waiting for
    // one. What is being checked is the drawing, not the beat.
    var drew: bool = false
    for tick: int in 0..3 {
        drew = screen.effect.draw(tick as f64 * 0.25)
    }
    io.println("-- a shader written by hand --")
    io.println("  a frame was drawn exactly where there is a GPU: {promised == drew}")
    io.println("  and it counted them: {promised == (screen.effect.frames() > 0)}")

    io.println("-- every effect cortado names --")
    let names: List<string> = gpu.Effect.names()
    var working: int = 0
    for name: string in names {
        if draws_with(app, name)? { working = working + 1 }
    }
    io.println("  cortado names this many effects: {names.len()}")
    io.println("  every one compiles and draws, where there is a GPU: {promised == (working == names.len())}")

    io.println("-- the colour you name is the colour that lands --")
    let asked: widgets.Rgba = widgets.Rgba.of_hex("#4088bf")?
    io.println("  #4088bf reads as {asked.show()}")
    let brief: widgets.Rgba = widgets.Rgba.of_hex("#48b")?
    let spelt: widgets.Rgba = widgets.Rgba.of_hex("#4488bb")?
    io.println("  #48b means the same as #4488bb: {brief.same_as(spelt)}")
    let clear: widgets.Rgba = widgets.Rgba.of_hex("#00000000")?
    io.println("  eight digits carry alpha: {clear.alpha == 0}")
    var landed: bool = false
    match gpu.Device.open() {
        ok(card) => {
            var device: gpu.Device = card
            landed = solid_lands(device, asked)?
        }
        err(problem) => {}
    }
    io.println("  a solid canvas of it comes back exactly that: {promised == landed}")

    io.println("-- refusals --")
    var both: gpu.ShaderCanvas = new gpu.ShaderCanvas()
    both.effect = "ripple"
    both.shader = "return float4(1.0, 0.0, 0.0, 1.0);"
    say("naming an effect and writing a shader", both.body())
    say("naming neither", new gpu.ShaderCanvas().body())
    var unknown: gpu.ShaderCanvas = new gpu.ShaderCanvas()
    unknown.effect = "kaleidoscope"
    explains("an effect nobody wrote", unknown.body(), "the ones there are")
    var missing: gpu.ShaderCanvas = new gpu.ShaderCanvas()
    missing.effect = "solid"
    missing.color = "4088bf"
    explains("a colour with no #", missing.body(), "has no #")
    var short: gpu.ShaderCanvas = new gpu.ShaderCanvas()
    short.effect = "solid"
    short.color = "#12345"
    explains("a colour of five digits", short.body(), "has 5 digits")
    var odd: gpu.ShaderCanvas = new gpu.ShaderCanvas()
    odd.effect = "solid"
    odd.color = "#gg0000"
    explains("a colour with a digit that is not one", odd.body(), "0-9 and a-f")

    // A canvas with no width is the mistake every column makes whose cross
    // alignment is not `stretch`, and it used to be a silent empty rectangle.
    var narrow: Screen = new Screen()
    narrow.effect.effect = "solid"
    narrow.height = 32.0
    var thin: widgets.Container = new widgets.Container()
    var side: surface.Window = app.window(160.0, 120.0, "Thin")?
    side.set_root(thin)?
    var second: component.Mount = new component.Mount(thin, app.router)
    second.set_bounds(geometry.Size.of(0.0, 120.0))
    second.show(narrow)?
    narrow.effect.draw(0.0)
    io.println("  a canvas with no size says so rather than drawing nothing: {promised == narrow.effect.problem().contains("nothing to draw into")}")

    // And stops saying it once it has one. `problem()` is the only thing this
    // class can say, so a message kept after the frame it complained about
    // arrived is a report that is no longer true — and the one shape that
    // reaches it is the common one: a canvas laid out at no width on the pass
    // before its parent stretched it.
    second.resized(geometry.Size.of(160.0, 120.0))?
    narrow.effect.draw(0.0)
    io.println("  and stops saying so once it has one: {promised == (narrow.effect.problem() == "")}")
    second.close()?

    mount.close()?
    io.println("-- after it goes --")
    io.println("  drawing stops once the component is unmounted: {!screen.effect.draw(1.0)}")
    return ok(true)
}

fn has_canvas(root: widgets.Widget) -> bool {
    for child: widgets.Widget in root.children() {
        if child.kind() == widgets.WidgetKind.canvas { return true }
        if has_canvas(child) { return true }
    }
    return false
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
