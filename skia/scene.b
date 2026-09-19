package cortado_skia

import cortado.component
import cortado.geometry
import cortado.render
import cortado.templates
import cortado.widgets
import cortado.events
import cortado.host

/// Composition root for the opt-in shared renderer. Existing .bx components
/// use the same Mount, differ and layout solver as native Cortado.
pub class Scene {
    renderer_value: SkiaRenderer
    context_value: render.UiContext
    root_value: widgets.Container
    mount: component.Mount
    templates: component.TemplateSet
    size_value: geometry.Size
    scale_value: f64 = 1.0
    closed: bool = false
    layout_version: int = -1
    theme_version: int = -1
    renderer_revision: int = -1

    pub fn init(size: geometry.Size, namespace: int = 1) {
        self.size_value = size
        self.renderer_value = new SkiaRenderer()
        self.context_value = new render.UiContext(self.renderer_value, namespace)
        self.root_value = new widgets.Container(some(self.context_value))
        self.mount = new component.Mount(self.root_value, self.context_value.router())
        self.templates = new component.TemplateSet(self.context_value, new templates.DefaultTemplates())
        // Read the accessibility setting once, where the window is made. Every
        // motion token answers zero while it is on.
        self.context_value.theme().set_reduced_motion(host.NativeServices.reduce_motion())
    }
    pub fn context() -> render.UiContext { return self.context_value }
    pub fn renderer() -> SkiaRenderer { return self.renderer_value }
    pub fn has_active_animations() -> bool { return self.context_value.has_active_animations() }
    pub fn advance(seconds: f64) -> Result<bool> {
        self.context_value.advance(seconds)?
        return self.refresh()
    }
    pub fn root() -> widgets.Container { return self.root_value }
    pub fn focused_object() -> Option<render.RenderObject> { return self.context_value.focused_object() }
    pub fn global_frame(object: render.RenderObject) -> Result<geometry.Rect> { return self.context_value.global_frame(object) }
    pub fn global_visual_frame(object: render.RenderObject) -> Result<geometry.Rect> { return self.context_value.global_visual_frame(object) }
    pub fn semantics() -> List<render.SemanticsNode> {
        var nodes: List<render.SemanticsNode> = []
        match self.root_value.render_object() { ok(root) => { self.collect_semantics(root, nodes, true) } err(_) => {} }
        match self.context_value.popups().root() { some(popup) => { self.collect_semantics(popup, nodes, true) } none => {} }
        return move nodes
    }
    fn collect_semantics(object: render.RenderObject, nodes: List<render.SemanticsNode>, enabled: bool) {
        if !object.is_alive() || object.is_hidden() { return }
        let node: render.SemanticsNode = object.semantics()
        match self.global_visual_frame(object) {
            ok(bounds) => { nodes.push(new render.SemanticsNode(node.id(), node.role(), node.label(), node.value(), bounds, enabled && node.enabled())) }
            err(_) => { return }
        }
        if object.interactive_visual() {
            match object.visual() { some(visual) => { self.collect_semantics(visual, nodes, enabled && node.enabled()) } none => {} }
        }
        if !object.shows_children() { return }
        for index: int in 0..object.child_count() {
            if !object.shows_child(index) { continue }
            match object.child_at(index) { some(child) => { self.collect_semantics(child, nodes, enabled && node.enabled()) } none => {} }
        }
    }
    pub fn use_templates(factory: component.TemplateFactory) {
        self.templates.close()
        self.templates = new component.TemplateSet(self.context_value, factory)
    }
    pub fn show(view: component.Component) -> Result<bool> {
        if self.closed { return err("scene is closed", "stale") }
        self.root_value.set_frame(geometry.Rect.at(geometry.Point.zero(), self.size_value))?
        self.mount.set_bounds(self.size_value)
        self.mount.show(view)?
        return self.refresh()
    }
    pub fn resize(size: geometry.Size, scale: f64) -> Result<bool> {
        if self.closed { return err("scene is closed", "stale") }
        if !(size.width > 0.0 && size.width < 10000000.0 && size.height > 0.0 && size.height < 10000000.0 && scale > 0.0 && scale < 16.0) {
            return err("invalid scene size or scale", "out_of_range")
        }
        self.size_value = size; self.scale_value = scale
        self.root_value.set_frame(geometry.Rect.at(geometry.Point.zero(), size))?
        self.mount.rescaled(scale)?
        self.mount.resized(size)?
        self.context_value.invalidation().paint()
        return self.refresh()
    }
    /// Settle retained geometry before input hit testing, without painting.
    pub fn prepare_input() -> Result<bool> {
        if self.closed { return err("scene is closed", "stale") }
        self.mount.refresh_if_needed()?
        if self.theme_version != self.context_value.theme().version() ||
           self.layout_version != self.context_value.invalidation().layout_version() {
            self.mount.remeasure()?
            self.theme_version = self.context_value.theme().version()
        }
        self.context_value.validate_input()
        self.templates.refresh(self.root_value)?
        self.layout_version = self.context_value.invalidation().layout_version()
        return ok(true)
    }
    pub fn refresh() -> Result<bool> {
        self.prepare_input()?
        if self.renderer_revision != self.renderer_value.revision() { self.context_value.invalidation().paint() }
        let before: Backend = self.renderer_value.backend()
        var painted: bool = false
        match self.context_value.draw(self.root_value.render_object()?, self.size_value, self.scale_value) {
            ok(changed) => { painted = changed }
            err(problem) => {
                if before == Backend.software || self.renderer_value.backend() != Backend.software {
                    return err(problem.msg, problem.kind)
                }
                // The engine discarded a failed GPU surface. Replay the same
                // retained tree once on its replacement software surface.
                self.context_value.invalidation().paint()
                painted = self.context_value.draw(self.root_value.render_object()?, self.size_value, self.scale_value)?
            }
        }
        self.renderer_revision = self.renderer_value.revision()
        self.layout_version = self.context_value.invalidation().layout_version()
        return ok(painted)
    }
    pub fn snapshot() -> Result<widgets.Snapshot> {
        if self.closed { return err("scene is closed", "stale") }
        let before: Backend = self.renderer_value.backend()
        match self.renderer_value.snapshot() {
            ok(pixels) => { return ok(pixels) }
            err(problem) => {
                if before == Backend.software || self.renderer_value.backend() != Backend.software {
                    return err(problem.msg, problem.kind)
                }
                self.context_value.invalidation().paint()
                self.refresh()?
                return self.renderer_value.snapshot()
            }
        }
    }
    /// Present a frame, recovering once if GPU readback falls back to software.
    pub fn present_to(canvas: widgets.Canvas) -> Result<bool> {
        if self.closed { return err("scene is closed", "stale") }
        let before: Backend = self.renderer_value.backend()
        match self.renderer_value.present_to(canvas) {
            ok(done) => { return ok(done) }
            err(problem) => {
                if before == Backend.software || self.renderer_value.backend() != Backend.software {
                    return err(problem.msg, problem.kind)
                }
                self.context_value.invalidation().paint()
                self.refresh()?
                return self.renderer_value.present_to(canvas)
            }
        }
    }
    pub fn pointer(kind: events.EventKind, point: geometry.Point, button: int = 1, clicks: int = 1, modifiers: int = 0) -> Result<bool> {
        self.context_value.pointer(self.root_value.render_object()?, kind, point, button, clicks, modifiers)?
        return self.refresh()
    }
    pub fn key(kind: events.EventKind, key: events.Key, text: string = "", modifiers: int = 0) -> Result<bool> {
        self.context_value.key(self.root_value.render_object()?, kind, key, text, modifiers)?
        return self.refresh()
    }
    pub fn scroll(point: geometry.Point, dx: f64, dy: f64) -> Result<bool> {
        self.apply_scroll(point, dx, dy)?
        return self.refresh()
    }
    /// Apply queued wheel input without drawing; the host draws at its next frame.
    pub fn apply_scroll(point: geometry.Point, dx: f64, dy: f64) -> Result<bool> {
        if self.closed { return err("scene is closed", "stale") }
        return self.context_value.scroll(self.root_value.render_object()?, point, dx, dy)
    }
    pub fn text_input(kind: events.EventKind, text: string, index: int = -1, token: int = -1) -> Result<bool> {
        match self.focused_object() {
            some(object) => {
                let event: events.UiEvent = events.UiEvent.of(kind, host.Handle.of(object.handle()))
                event.text = text; event.index = index; event.token = token
                self.context_value.dispatch(event)?
            }
            none => {}
        }
        return self.refresh()
    }
    pub fn semantics_action(handle: u64, action: int) -> Result<bool> {
        if self.closed { return err("scene is closed", "stale") }
        if action == 1 {
            self.context_value.dispatch(events.UiEvent.of(events.EventKind.activate, host.Handle.of(handle)))?
        } else if action == 2 {
            self.context_value.focus(handle)?
        } else { return err("unknown accessibility action", "unsupported") }
        return self.refresh()
    }
    pub fn close() {
        if self.closed { return }
        self.closed = true
        self.templates.close()
        self.mount.close()
        self.root_value.release()
        self.context_value.close()
        self.renderer_value.close()
    }
    fn deinit() { self.close() }
}
