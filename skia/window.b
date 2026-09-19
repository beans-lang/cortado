package cortado_skia

import cortado.component
import cortado.surface
import cortado.widgets
import cortado.geometry
import cortado.events
import cortado.render
import cortado.host

/// Capture wheel values when they arrive; router subscribers may still mutate
/// the UiEvent object after Window's watcher returns.
class WheelSample {
    pub point: geometry.Point
    pub dx: f64
    pub dy: f64
    pub fn init(point: geometry.Point, dx: f64, dy: f64) {
        self.point = point; self.dx = dx; self.dy = dy
    }
}

/// A native window with exactly one drawing/input surface. Its controls live
/// in Scene, not in the platform view hierarchy. Close unregisters every watch.
pub class Window {
    scene_value: Scene
    window_value: surface.Window
    canvas: widgets.Canvas
    router: events.EventRouter
    driver: Option<FrameDriver> = none
    problem: string = ""
    closed: bool = false
    semantics_version: int = -1
    scroll_events: List<WheelSample> = []
    scroll_dirty: bool = false

    fn init(scene: Scene, window: surface.Window, canvas: widgets.Canvas, router: events.EventRouter) {
        self.scene_value = scene; self.window_value = window; self.canvas = canvas; self.router = router
    }
    pub static fn open(app: surface.Application, size: geometry.Size, title: string,
                       view: component.Component) -> Result<Window> {
        let scene: Scene = new Scene(size, app.allocate_render_namespace()?)
        let window: surface.Window = app.window(size.width, size.height, title)?
        let canvas: widgets.Canvas = new widgets.Canvas()
        canvas.set_focusable(true)?
        window.set_root(canvas)?
        let client: Window = new Window(scene, window, canvas, app.router)
        scene.show(view)?
        scene.resize(size, window.scale()?)?
        scene.present_to(canvas)?
        client.listen()
        window.show()?
        canvas.focus()?
        client.sync_services()
        return ok(client)
    }
    pub fn scene() -> Scene { return self.scene_value }
    pub fn native_window() -> surface.Window { return self.window_value }
    pub fn last_error() -> string { return self.problem }
    /// Refresh after an app changes its component tree outside an input event.
    pub fn refresh() -> Result<bool> {
        let scrolled: bool = self.take_scroll_dirty()?
        let changed: bool = self.scene_value.refresh()? || scrolled
        if changed { self.present() } else { self.sync_services() }
        return ok(changed)
    }
    /// Replay wheel input in order. A child scroller can reach its edge between
    /// two reports, so merging deltas would lose the next report's parent scroll.
    /// Only the costly draw and native present are coalesced per frame.
    fn apply_pending_scroll() -> Result<bool> {
        var changed: bool = false
        var pending: List<WheelSample> = []
        for item: WheelSample in self.scroll_events { pending.push(item) }
        self.scroll_events.clear()
        for index: int in 0..pending.len() {
            let item: WheelSample = pending[index]
            match self.scene_value.apply_scroll(item.point, item.dx, item.dy) {
                ok(moved) => { if moved { changed = true; self.scroll_dirty = true } }
                err(problem) => {
                    // Keep this report and all later ones for an explicit retry.
                    var later: List<WheelSample> = []
                    for queued: WheelSample in self.scroll_events { later.push(queued) }
                    self.scroll_events.clear()
                    for remaining: int in index..pending.len() { self.scroll_events.push(pending[remaining]) }
                    for queued: WheelSample in later { self.scroll_events.push(queued) }
                    return err(problem.msg, problem.kind)
                }
            }
        }
        return ok(changed)
    }
    fn take_scroll_dirty() -> Result<bool> {
        self.apply_pending_scroll()?
        let changed: bool = self.scroll_dirty
        self.scroll_dirty = false
        return ok(changed)
    }
    /// Settle virtual rows before a following click/key asks them to hit-test.
    /// This does not draw pixels; the input handler paints its final state.
    fn flush_before_input() -> Result<bool> {
        let changed: bool = self.take_scroll_dirty()?
        if changed { self.scene_value.prepare_input()? }
        return ok(changed)
    }
    fn queue_scroll(event: events.UiEvent) {
        self.scroll_events.push(new WheelSample(event.position, event.size.width, event.size.height))
        // Bound queued memory under a stalled native clock. Applying input
        // here does not build rows, draw, snapshot, or update native services.
        if self.scroll_events.len() >= 256 {
            match self.apply_pending_scroll() {
                ok(_) => {}
                err(problem) => { self.problem = problem.msg; return }
            }
        }
        match self.driver {
            some(driver) => { match driver.request(true) {
                ok(_) => {}
                err(problem) => { self.problem = problem.msg }
            } }
            none => {}
        }
    }
    fn sync_services() {
        match self.driver {
            some(driver) => { match driver.request(self.scene_value.has_active_animations() || self.scroll_events.len() > 0 || self.scroll_dirty) {
                ok(_) => {}
                err(problem) => { self.problem = problem.msg }
            } }
            none => {}
        }
        var mode: int = 0
        var words: string = ""
        var anchor: int = 0
        var caret: int = 0
        var frame: geometry.Rect = geometry.Rect.of(0.0, 0.0, 1.0, 16.0)
        match self.scene_value.focused_object() {
            some(object) => { match object as? render.TextFieldRender {
                some(field) => {
                    mode = if field.is_secure() { 2 } else { 1 }
                    words = field.editing_text()
                    anchor = field.selection_anchor()
                    caret = field.selection_caret()
                    match field.caret_rect() {
                        ok(local) => { match self.scene_value.global_frame(field) {
                            ok(global) => { frame = geometry.Rect.of(global.x + local.x, global.y + local.y,
                                                     local.width, local.height) }
                            err(problem) => { self.problem = problem.msg }
                        } }
                        err(problem) => { self.problem = problem.msg }
                    }
                }
                none => {}
            } }
            none => {}
        }
        match host.NativeServices.text_state(self.canvas.handle(), mode, words, anchor, caret,
                                              frame.x, frame.y, frame.width, frame.height) {
            ok(_) => {}
            err(problem) => { if problem.kind != "unsupported" { self.problem = problem.msg } }
        }
        let version: int = self.scene_value.context().invalidation().semantics_version()
        if version == self.semantics_version { return }
        match host.NativeServices.semantics_clear(self.canvas.handle()) {
            err(problem) => {
                if problem.kind != "unsupported" { self.problem = problem.msg }
                return
            }
            ok(_) => {}
        }
        for node: render.SemanticsNode in self.scene_value.semantics() {
            let bounds: geometry.Rect = node.bounds()
            var focused: bool = false
            match self.scene_value.focused_object() {
                some(object) => { focused = object.handle() == node.id() }
                none => {}
            }
            match host.NativeServices.semantics_add(self.canvas.handle(), node.id(), node.role(),
                    node.label(), node.value(), bounds.x, bounds.y, bounds.width, bounds.height,
                    node.enabled(), focused) {
                ok(_) => {}
                err(problem) => { self.problem = problem.msg; return }
            }
        }
        match host.NativeServices.semantics_end(self.canvas.handle()) {
            ok(_) => {}
            err(problem) => { self.problem = problem.msg; return }
        }
        self.semantics_version = version
    }
    fn present() {
        match self.scene_value.present_to(self.canvas) {
            ok(_) => {}
            err(problem) => { self.problem = problem.msg }
        }
        self.sync_services()
    }
    fn resized() -> Result<bool> {
        return self.scene_value.resize(self.window_value.content_size()?, self.window_value.scale()?)
    }
    fn listen() {
        let owner: Window = self
        self.driver = some(new FrameDriver(self.window_value.handle(), self.router, fn(delta: f64) {
            var scrolled: bool = false
            match owner.take_scroll_dirty() {
                ok(changed) => { scrolled = changed }
                err(problem) => { owner.problem = problem.msg; owner.stop_frame_driver(); return }
            }
            match owner.scene_value.advance(delta) {
                ok(changed) => { if changed || scrolled { owner.present() } else { owner.sync_services() } }
                err(problem) => {
                    owner.problem = problem.msg
                    owner.stop_frame_driver()
                }
            }
        }))
        for kind: events.EventKind in [events.EventKind.pointer_down, events.EventKind.pointer_move, events.EventKind.pointer_up] {
            self.router.watch(self.canvas.handle(), kind, fn(event: events.UiEvent) {
                var scrolled: bool = false
                match owner.flush_before_input() {
                    ok(changed) => { scrolled = changed }
                    err(problem) => { owner.problem = problem.msg; return }
                }
                match owner.scene_value.pointer(event.kind, event.position, event.index, event.click_count(), event.modifiers) {
                    ok(changed) => { if changed || scrolled { owner.present() } else { owner.sync_services() } }
                    err(problem) => { owner.problem = problem.msg }
                }
            })
        }
        for kind: events.EventKind in [events.EventKind.key_down, events.EventKind.key_up] {
            self.router.watch(self.canvas.handle(), kind, fn(event: events.UiEvent) {
                var scrolled: bool = false
                match owner.flush_before_input() {
                    ok(changed) => { scrolled = changed }
                    err(problem) => { owner.problem = problem.msg; return }
                }
                match owner.scene_value.key(event.kind, event.key(), event.text, event.modifiers) {
                    ok(changed) => { if changed || scrolled { owner.present() } else { owner.sync_services() } }
                    err(problem) => { owner.problem = problem.msg }
                }
            })
        }
        self.router.watch(self.canvas.handle(), events.EventKind.pointer_scroll, fn(event: events.UiEvent) {
            owner.queue_scroll(event)
        })
        for kind: events.EventKind in [events.EventKind.text_input, events.EventKind.composition_update,
                events.EventKind.composition_cancel] {
            self.router.watch(self.canvas.handle(), kind, fn(event: events.UiEvent) {
                var scrolled: bool = false
                match owner.flush_before_input() {
                    ok(changed) => { scrolled = changed }
                    err(problem) => { owner.problem = problem.msg; return }
                }
                match owner.scene_value.text_input(event.kind, event.text, event.index, event.token) {
                    ok(changed) => { if changed || scrolled { owner.present() } else { owner.sync_services() } }
                    err(problem) => { owner.problem = problem.msg }
                }
            })
        }
        self.router.watch(self.canvas.handle(), events.EventKind.semantics_action, fn(event: events.UiEvent) {
            var scrolled: bool = false
            match owner.flush_before_input() {
                ok(changed) => { scrolled = changed }
                err(problem) => { owner.problem = problem.msg; return }
            }
            match owner.scene_value.semantics_action(event.token as u64, event.index) {
                ok(changed) => { if changed || scrolled { owner.present() } else { owner.sync_services() } }
                err(problem) => { owner.problem = problem.msg }
            }
        })
        for kind: events.EventKind in [events.EventKind.surface_resized, events.EventKind.scale_changed] {
            self.router.watch(self.window_value.handle(), kind, fn(_event: events.UiEvent) {
                match owner.flush_before_input() {
                    ok(_) => {}
                    err(problem) => { owner.problem = problem.msg; return }
                }
                match owner.resized() {
                    ok(_) => { owner.present() }
                    err(problem) => { owner.problem = problem.msg }
                }
            })
        }
        self.router.watch(self.window_value.handle(), events.EventKind.surface_close, fn(_event: events.UiEvent) { owner.close() })
    }
    pub fn close() {
        if self.closed { return }
        self.closed = true
        self.scroll_events.clear(); self.scroll_dirty = false
        match self.driver { some(driver) => { driver.close() } none => {} }
        self.driver = none
        // Stop the OS text session while the canvas handle is still live.
        // macOS secure keyboard input must not wait for a retained view to deallocate.
        match host.NativeServices.text_state(self.canvas.handle(), 0, "", 0, 0,
                                              0.0, 0.0, 0.0, 0.0) {
            ok(_) => {}
            err(problem) => { if problem.kind != "unsupported" { self.problem = problem.msg } }
        }
        for kind: events.EventKind in [events.EventKind.pointer_down, events.EventKind.pointer_move,
                events.EventKind.pointer_up, events.EventKind.key_down, events.EventKind.key_up,
                events.EventKind.pointer_scroll, events.EventKind.text_input,
                events.EventKind.composition_update, events.EventKind.composition_cancel,
                events.EventKind.semantics_action] {
            self.router.unwatch(self.canvas.handle(), kind)
        }
        self.router.unwatch(self.window_value.handle(), events.EventKind.surface_resized)
        self.router.unwatch(self.window_value.handle(), events.EventKind.scale_changed)
        self.router.unwatch(self.window_value.handle(), events.EventKind.surface_close)
        self.scene_value.close()
        self.window_value.close()
        self.canvas.release()
    }
    fn deinit() { self.close() }
    fn stop_frame_driver() {
        match self.driver {
            some(driver) => { match driver.request(false) {
                ok(_) => {}
                err(problem) => { self.problem = "{self.problem}; {problem.msg}" }
            } }
            none => {}
        }
    }
}
