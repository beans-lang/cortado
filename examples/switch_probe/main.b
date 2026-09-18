package main

import cortado_skia
import cortado.geometry
import cortado.render
import cortado.visual
import cortado.widgets
import std.io
import std.os

fn main() {
    match run() { ok(_) => {} err(p) => { io.println("failed: {p.msg}"); os.exit(1) } }
}
fn run() -> Result<bool> {
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(200.0, 80.0))
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    for size: int in 0..4 {
        theme.set_control_size(size)?
        let root: widgets.Container = scene.root()
        for root.count() > 0 { root.remove(root.count() - 1)? }
        let toggle: widgets.Switch = new widgets.Switch(some(context))
        toggle.set_on(true)?
        root.add(toggle)?
        scene.resize(geometry.Size.of(200.0, 80.0), 2.0)?
        scene.refresh()?
        let object: render.RenderObject = toggle.render_object()?
        io.println("size {size}: frame {object.frame().width}x{object.frame().height} theme {theme.switch_width()}x{theme.switch_height()} knob {theme.switch_knob_width()}x{theme.switch_knob_height()} travel {theme.switch_travel()}")
        match object.visual() {
            some(visual) => { dump(visual, 1) }
            none => { io.println("   no template") }
        }
    }
    scene.close()
    return ok(true)
}
fn dump(node: render.RenderObject, depth: int) {
    var pad: string = ""
    for step: int in 0..depth { pad = "{pad}  " }
    var extra: string = ""
    match node as? render.VisualRender {
        some(_) => {
            let dx: f64 = node.real(visual.OFFSET_X).or(0.0)
            let dy: f64 = node.real(visual.OFFSET_Y).or(0.0)
            extra = " offset {dx},{dy}"
        }
        none => {}
    }
    io.println("{pad}{node.role()} {node.frame().x},{node.frame().y} {node.frame().width}x{node.frame().height}{extra}")
    for index: int in 0..node.child_count() {
        match node.child_at(index) { some(child) => { dump(child, depth + 1) } none => {} }
    }
}
