// The process, as cortado sees it.
package surface

import cortado.host
import cortado.platform
import cortado.events
import cortado.geometry

/// The root of a cortado program.
///
/// It does three things: it brings the platform up on the main thread, it owns
/// the one callback the platform delivers events through, and it runs the
/// event loop.
///
/// **One callback, for the whole process.** Registering one per widget would
/// mean one stored callback per widget, and a stored callback holds a strong
/// reference to its closure that Beans' cycle collector cannot trace — so a
/// closure capturing the widget it is attached to would leak with nothing able
/// to reclaim it. There is a single edge instead, owned by this object, whose
/// lifetime is the program's. Per-widget handlers live in `router`, as
/// ordinary functions in a map.
///
/// That choice also makes a safety property real rather than aspirational: the
/// callback records the thread it was registered on, and an event delivered
/// from any other thread is a checked abort instead of a data race inside the
/// interpreter. Work that belongs on another thread goes there with
/// `std.thread` and comes back through `post`, which carries an integer and
/// nothing else.
pub class Application {
    pub router: events.EventRouter
    sink: LocalStoredCallback<fn(RawPtr<u8>, RawPtr<host.CtdEvent>)>
    running: bool = false

    /// Brings the platform up. Must be called from `main`, which Beans
    /// guarantees runs on the real process main thread under both the
    /// interpreter and a native build — the promise every desktop UI toolkit
    /// stands on.
    pub fn init(role: platform.AppRole) {
        self.running = false
        var router: events.EventRouter = new events.EventRouter()
        self.router = router
        // Built here, not in a field initializer: a field initializer cannot
        // name `self`, and this closure has to reach the router.
        self.sink = LocalStoredCallback.create(0, fn(record: RawPtr<host.CtdEvent>) {
            if record.is_null() {
                return
            }
            unsafe {
                router.deliver(new events.UiEvent(record.read()))
            }
        })
        unsafe {
            host.ctd_init(host.ABI_VERSION as u32)
            host.ctd_app_set_role(role.code() as i32)
            host.ctd_set_event_sink(self.sink.function(), self.sink.context())
        }
    }

    /// Checks that the host library was built from the same header this
    /// binding was generated from. A mismatch here is a stale `.dylib` or a
    /// half-finished rebuild, and it is much easier to read as a message than
    /// as a field that silently holds the wrong number.
    pub fn check_abi() -> Result<bool> {
        var found: int = 0
        unsafe {
            found = host.ctd_abi_version() as int
        }
        if found != host.ABI_VERSION {
            return err("this build speaks cortado ABI {host.ABI_VERSION} but the platform host speaks {found}",
                       "abi_mismatch")
        }
        return ok(true)
    }

    pub fn set_role(role: platform.AppRole) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_app_set_role(role.code() as i32) as int,
                              "set the application role")
        }
    }

    /// A new window, sized in points.
    pub fn window(width: f64, height: f64, title: string) -> Result<Window> {
        return Window.of(width, height, title)
    }

    /// Runs the event loop until `stop`.
    ///
    /// On a desktop this returns. On iOS the platform's loop never gives
    /// control back, and on Android there is no loop to start because the
    /// activity already owns one — so a program that may also run on a phone
    /// does its work in event handlers rather than after this call.
    pub fn run() {
        self.running = true
        unsafe {
            host.ctd_app_run()
        }
        self.running = false
    }

    pub fn stop() {
        unsafe {
            host.ctd_app_stop()
        }
    }

    /// Wakes the UI thread and delivers a `post` event carrying `token`.
    ///
    /// The only entry point in cortado that is safe to call from another
    /// thread, and it takes an integer for exactly that reason — nothing else
    /// can be smuggled across a thread boundary through it.
    pub fn post(token: int) {
        unsafe {
            host.ctd_post(token as i64)
        }
    }

    /// Unregisters the platform callback so nothing can reach Beans through
    /// it again.
    ///
    /// It deliberately does not `close()` the callback. Closing wants a named
    /// local — Beans refuses `move self.sink`, because moving out of a field
    /// would leave the object half-built — and the callback is a field here
    /// precisely because it has to outlive every call that registers a
    /// handler. Unregistering is the half that matters: after this returns the
    /// platform holds no pointer into Beans, which is the property `close`
    /// exists to guarantee. What is left unreclaimed is one closure per
    /// process, released when the process exits.
    ///
    /// The alternative — owning the callback as a local inside `run()` — would
    /// close cleanly and break the headless case, where a test builds and
    /// measures a whole widget tree and never starts an event loop at all.
    pub fn shutdown() {
        unsafe {
            host.ctd_set_event_sink(fn(context: RawPtr<u8>, record: RawPtr<host.CtdEvent>) {},
                                    RawPtr.null())
            host.ctd_shutdown()
        }
    }
}
