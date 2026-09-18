package main

import cortado_skia
import cortado.render
import cortado.widgets
import cortado.geometry
import cortado.events
import cortado.host
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn verify() -> Result<bool> {
    let renderer: cortado_skia.SkiaRenderer = new cortado_skia.SkiaRenderer()
    let context: render.UiContext = new render.UiContext(renderer, 10)
    let other: render.UiContext = new render.UiContext(renderer, 11)
    let root: widgets.Container = new widgets.Container(some(context))
    for index: int in 0..3 {
        let child: widgets.Label = new widgets.Label(some(context))
        child.set_text("child {index}")?
        root.add(child)?
    }
    require(root.count() == 3 && root.native_child_count()? == 3, "children lost ownership")
    let foreign: widgets.Label = new widgets.Label(some(other))
    match root.add(foreign) { ok(_) => { panic("cross-window child accepted") } err(_) => {} }
    require(root.count() == 3 && other.registry().count() == 1, "failed insertion changed ownership")
    let old: widgets.Label = new widgets.Label(some(context))
    let stale: host.Handle = old.handle()
    let old_object: render.RenderObject = old.render_object()?
    old.release()
    let replacement: widgets.Label = new widgets.Label(some(context))
    require(replacement.handle().raw != stale.raw, "slot reused without generation")
    require(context.registry().get(stale.raw) == none, "stale handle resolved")
    require(other.registry().get(replacement.handle().raw) == none, "foreign handle resolved")
    match old_object.set_frame(geometry.Rect.of(0.0, 0.0, 1.0, 1.0)) {
        ok(_) => { panic("released node mutated") } err(_) => {}
    }
    match context.dispatch(events.UiEvent.of(events.EventKind.activate, stale)) {
        ok(_) => { panic("stale event delivered") } err(_) => {}
    }
    let field: widgets.TextField = new widgets.TextField(some(context))
    let field_object: render.RenderObject = field.render_object()?
    field.release()
    match field_object.set_string(host.S_HINT, "stale") {
        ok(_) => { panic("released field accepted hint") } err(_) => {}
    }
    match field_object.set_integer(host.P_EDITABLE, 1) {
        ok(_) => { panic("released field accepted editing state") } err(_) => {}
    }
    let branch: widgets.Container = new widgets.Container(some(context))
    root.add(branch)?
    match branch.add(root) { ok(_) => { panic("tree cycle accepted") } err(_) => {} }
    root.release()
    require(context.registry().count() == 1, "subtree release left registered descendants")
    context.close(); other.close()
    require(context.registry().count() == 0 && other.registry().count() == 0, "context close leaked nodes")
    require(!replacement.is_alive(), "closed context left a live widget")
    io.println("ok render ownership, cycles, stale handles, subtree teardown")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
