package main

import cortado_skia
import cortado.render
import cortado.geometry
import cortado.events
import cortado.host
import std.io

class InteractiveScroll extends render.ScrollRender {
    pub fn init(context: render.UiContext) { super.init(context.renderer(), context.theme(), context.invalidation()) }
    pub override fn interactive_visual() -> bool { return true }
    pub override fn visual_offset() -> geometry.Point { return geometry.Point.at(self.child_offset().x, 0.0) }
}
class Counter { pub clicks: int = 0; pub fn init() {} }
fn require(value: bool, message: string) { if !value { panic(message) } }
fn verify() -> Result<bool> {
    let renderer: cortado_skia.SkiaRenderer = new cortado_skia.SkiaRenderer()
    let context: render.UiContext = new render.UiContext(renderer, 1)
    let root: render.BoxRender = new render.BoxRender(renderer, context.theme(), context.invalidation())
    let control: InteractiveScroll = new InteractiveScroll(context)
    let visual: render.BoxRender = new render.BoxRender(renderer, context.theme(), context.invalidation())
    let button: render.ButtonRender = new render.ButtonRender(renderer, context.theme(), context.invalidation())
    context.add(root)?; context.add(control)?; context.add(visual)?; context.add(button)?
    root.set_frame(geometry.Rect.of(0.0, 0.0, 300.0, 200.0))?
    control.set_frame(geometry.Rect.of(30.0, 40.0, 100.0, 100.0))?
    control.set_content_size(geometry.Size.of(300.0, 500.0))?
    control.scroll_to(geometry.Point.at(0.0, 60.0))?
    visual.set_frame(geometry.Rect.of(0.0, 0.0, 100.0, 100.0))?
    button.set_frame(geometry.Rect.of(8.0, 10.0, 50.0, 24.0))?
    root.insert(control, 0)?; visual.insert(button, 0)?; control.set_visual(some(visual))?
    let semantics: int = context.invalidation().semantics_version()
    button.set_integer(host.P_BG_COLOR, 0x112233ff)?
    button.set_integer(host.P_FG_COLOR, 0x556677ff)?
    button.set_integer(host.P_BORDER_COLOR, 0x8899aaff)?
    require(context.invalidation().semantics_version() == semantics, "paint colors rebuilt accessibility")
    context.pointer(root, events.EventKind.pointer_move, geometry.Point.at(40.0, 60.0), 0)?
    require(button.hovered() && control.hovered() && root.hovered(), "hover path missed visual ancestors")
    require(context.invalidation().semantics_version() == semantics, "hover rebuilt accessibility")
    let bounds: geometry.Rect = context.global_frame(button)?
    require(bounds.x == 38.0 && bounds.y == 50.0, "template part applied owner scroll offset twice")
    let seen: Counter = new Counter()
    context.router().watch(host.Handle.of(button.handle()), events.EventKind.activate,
        fn(event: events.UiEvent) { seen.clicks += 1 })
    context.pointer(root, events.EventKind.pointer_down, geometry.Point.at(40.0, 60.0), host.BTN_LEFT)?
    context.pointer(root, events.EventKind.pointer_move, geometry.Point.at(200.0, 150.0), 0)?
    require(!button.hovered() && root.hovered(), "pointer capture trapped hover")
    context.pointer(root, events.EventKind.pointer_move, geometry.Point.at(40.0, 60.0), 0)?
    context.pointer(root, events.EventKind.pointer_up, geometry.Point.at(40.0, 60.0), host.BTN_LEFT)?
    require(seen.clicks == 1 && button.focused(), "interactive template part lost pointer or focus")
    control.scroll_to(geometry.Point.at(12.0, 60.0))?
    require(context.global_frame(button)?.x == 26.0, "visual offset missing from global bounds")
    context.pointer(root, events.EventKind.pointer_down, geometry.Point.at(38.0, 60.0), host.BTN_LEFT)?
    context.pointer(root, events.EventKind.pointer_up, geometry.Point.at(38.0, 60.0), host.BTN_LEFT)?
    require(seen.clicks == 2, "visual offset missing from hit testing or local input coordinates")
    context.clear_focus()
    context.key(root, events.EventKind.key_down, events.Key.tab, "", 0)?
    require(button.focused(), "template part is missing from keyboard focus order")
    context.pointer(root, events.EventKind.pointer_move, geometry.Point.at(-1.0, -1.0), 0)?
    require(!button.hovered() && !control.hovered() && !root.hovered(), "pointer leave kept hover")
    context.pointer(root, events.EventKind.pointer_move, geometry.Point.at(38.0, 60.0), 0)?
    control.set_integer(host.P_ENABLED, 0)?
    context.validate_input()
    require(!button.hovered() && !control.hovered(), "disabled ancestor kept hover")
    control.set_integer(host.P_ENABLED, 1)?
    match control.set_visual(some(root)) { ok(_) => { panic("template owner cycle allowed") } err(_) => {} }
    context.release(control.handle())
    require(!context.dispatch(events.UiEvent.of(events.EventKind.activate, host.Handle.of(button.handle())))?,
            "detached template part still accepts events")
    require(seen.clicks == 2 && context.router().watching() == 0, "released owner retained template callbacks")
    context.close(); renderer.close()
    require(context.registry().count() == 0, "visual parts leaked registry entries")
    io.println("ok interactive .bx template part coordinates, input, focus, ownership, teardown")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
