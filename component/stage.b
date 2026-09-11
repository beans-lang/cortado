// What a component is handed once its controls are real.
package component

import cortado.host
import cortado.events
import cortado.widgets

/// The platform, as it looks to one component at the moment it is mounted.
///
/// `render` describes controls; it does not have any. By the time `on_mount`
/// runs the controls exist, and this is how a component reaches the ones it
/// asked for — by the `key` it gave them.
///
/// ```
/// pub fn on_mount(stage: component.Stage) {
///     match stage.control("plot") {
///         some(canvas) => { ... }
///         none => {}
///     }
/// }
/// ```
///
/// **Nothing here is a reference to the mount, and that is deliberate.** A
/// component holding its mount would be a cycle — the mount holds the
/// component, the component holds the mount — and a cycle whose members hold
/// platform resources is exactly the shape that never runs `deinit`. So this
/// carries copies: the handles as they were, the router, and the surface. It
/// is made for one call and means nothing after it; a component that keeps one
/// keeps stale handles, which the generation in each one turns into a typed
/// refusal rather than a crash.
pub class Stage {
    priv controls: Map<string, host.Handle> = {}
    priv router_ref: events.EventRouter = new events.EventRouter()
    priv surface_handle: host.Handle = host.Handle.none()

    pub fn init(controls: Map<string, host.Handle>, router: events.EventRouter,
                surface: host.Handle) {
        // Copied rather than moved: a parameter is borrowed, and a stage that
        // took its caller's map would leave the mount without one.
        for key: string in controls.keys() {
            match controls.get(key) {
                some(handle) => { self.controls[key] = handle }
                none => {}
            }
        }
        self.router_ref = router
        self.surface_handle = surface
    }

    /// The control an element with this key became.
    ///
    /// `none` when nothing in this component's own render carried that key.
    /// Keys are per component, so two components may both use "plot" without
    /// finding each other's.
    pub fn control(key: string) -> Option<host.Handle> {
        return self.controls.get(key)
    }

    /// Where handlers are registered. The same router the application made,
    /// because there is one per process and an event is dispatched by handle.
    pub fn router() -> events.EventRouter {
        return self.router_ref
    }

    /// The surface these controls are in, for the things that belong to a
    /// window rather than to a control — a frame clock, above all.
    ///
    /// Zero before anything is on screen, which is the case a headless test
    /// hits and a real application does not.
    pub fn surface() -> host.Handle {
        return self.surface_handle
    }

    /// How many controls this stage knows about, so a component can tell
    /// "no control by that name" from "no controls at all".
    pub fn count() -> int {
        return self.controls.len()
    }
}
