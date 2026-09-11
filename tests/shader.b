// The easy road: a rectangle with a shader in it.
//
// `tests/canvas.b` checks the machinery a program drives itself — device,
// pipeline, buffer, pass, present. This checks the one call that does all of
// it, because the common case for a GPU in an interface is not "place my own
// vertices", it is "fill this rectangle with a shader", and a library that
// only offered the first would make everyone write the same forty lines.
//
// What it asserts is that a *body* — three lines about colour, with no Metal
// boilerplate in it — becomes pixels. The wrapper around it is cortado's, and
// getting it wrong would show up here as a shader that does not compile.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.geometry
import cortado.gpu
import std.io

/// A screen with one shader canvas on it, written the way markup writes one.
class Screen extends component.Component {
    pub effect: gpu.ShaderCanvas = new gpu.ShaderCanvas()

    pub fn init() { super.init() }

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.number("spacing", 8.0)
        // Without this the canvas is as wide as it measures, which for a
        // control that paints nothing of its own is nothing at all. It is the
        // first thing anybody gets wrong, so `Canvas.next` says so by name.
        into.word("align", "stretch")
        into.show("effect", self.effect)
        into.close()
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(160.0, 120.0, "Shader")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var screen: Screen = new Screen()
    // Flat red, everywhere. Chosen because it is exact in eight bits and
    // because it uses `uv`, `seconds` and `size` — so a wrapper that forgot to
    // declare one of them fails to compile rather than quietly drawing black.
    screen.effect.shader = r"
    float ignore = uv.x * 0.0 + seconds * 0.0 + size.x * 0.0;
    return float4(1.0 + ignore, 0.0, 0.0, 1.0);
"
    screen.effect.height = 32.0

    var mount: component.Mount = new component.Mount(root, app.router)
    mount.set_bounds(geometry.Size.of(160.0, 120.0))
    mount.show(screen)?

    let promised: bool = platform.Capability.gpu.available()

    io.println("-- what the component made --")
    io.println("  the screen mounted: true")
    io.println("  a canvas is in the tree: {has_canvas(root)}")
    io.println("  it says why it is empty exactly when there is no GPU: {promised == (screen.effect.problem() == "")}")

    // Driven by hand. There is no display in a gate, so no frame clock runs —
    // the same reason `tests/clock.b` steps the clock rather than waiting for
    // one. What is being checked is the drawing, not the beat.
    var drew: bool = false
    for tick: int in 0..3 {
        drew = screen.effect.draw(tick as f64 * 0.25)
    }
    io.println("-- drawing --")
    io.println("  a frame was drawn exactly where there is a GPU: {promised == drew}")
    io.println("  and it counted them: {promised == (screen.effect.frames() > 0)}")

    // A canvas with no width is the mistake every column makes whose cross
    // alignment is not `stretch`, and it used to be a silent empty rectangle.
    // Now it has a name.
    var narrow: Screen = new Screen()
    narrow.effect.shader = screen.effect.shader
    narrow.effect.height = 32.0
    var thin: widgets.Container = new widgets.Container()
    var side: surface.Window = app.window(160.0, 120.0, "Thin")?
    side.set_root(thin)?
    var second: component.Mount = new component.Mount(thin, app.router)
    second.set_bounds(geometry.Size.of(0.0, 120.0))
    second.show(narrow)?
    narrow.effect.draw(0.0)
    io.println("-- a canvas with no size --")
    io.println("  says so by name rather than drawing nothing: {promised == narrow.effect.problem().contains("nothing to draw into")}")
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
