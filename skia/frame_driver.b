package cortado_skia

import cortado.host
import cortado.events
import cortado.motion

/// Owns the shared window's native frame subscription. It starts only while
/// Beans has active animations, and never uses the legacy global ClockDesk.
pub class FrameDriver {
    surface: host.Handle
    router: events.EventRouter
    handler: Option<fn(f64)>
    running: bool = false
    closed: bool = false
    pub fn init(surface: host.Handle, router: events.EventRouter, handler: fn(f64)) {
        self.surface = surface; self.router = router; self.handler = some(handler)
    }
    pub fn is_running() -> bool { return self.running }
    pub fn request(active: bool) -> Result<bool> {
        if self.closed { return err("frame driver is closed", "stale") }
        if active == self.running { return ok(false) }
        if !active {
            self.running = false
            self.router.unwatch(self.surface, events.EventKind.frame)
            unsafe { host.check(host.ctd_clock_stop(self.surface.raw) as int, "stop shared frame clock")? }
            return ok(true)
        }
        let owner: FrameDriver = self
        self.router.watch(self.surface, events.EventKind.frame, fn(event: events.UiEvent) {
            if !owner.running || owner.closed { return }
            match owner.handler { some(tick) => { tick(motion.Frame.of(event).delta) } none => {} }
        })
        self.running = true
        var status: int = 0
        unsafe { status = host.ctd_clock_start(self.surface.raw, 0) as int }
        match host.check(status, "start shared frame clock") {
            ok(_) => { return ok(true) }
            err(problem) => {
                self.running = false
                self.router.unwatch(self.surface, events.EventKind.frame)
                return err(problem.msg, problem.kind)
            }
        }
    }
    /// Uses the same native delivery path as a display tick for bounded tests.
    pub fn step(seconds: f64) -> Result<bool> {
        if self.closed { return err("frame driver is closed", "stale") }
        unsafe { return host.check(host.ctd_clock_step(self.surface.raw, seconds) as int, "step shared frame clock") }
    }
    pub fn close() {
        if self.closed { return }
        self.request(false)
        self.closed = true
        self.handler = none
    }
    fn deinit() { self.close() }
}
