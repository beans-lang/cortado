// The beat everything that moves runs on.
package motion

import cortado.host
import cortado.events

/// Asks a surface to be told before every frame its display shows.
///
/// A clock rather than a timer, and the difference is the whole point: the
/// platform's display link drives it, so the ticks are the refresh rate the
/// screen really has. A program written against this is already right on a
/// 120 Hz display and already right when the machine slows down, which is not
/// true of anything built on an interval somebody picked.
///
/// It is given its collaborators rather than reaching for them — the surface
/// it belongs to and the router that will carry its frames — so a clock can be
/// pointed at a test's router with no application running at all.
pub class FrameClock {
    priv surface: host.Handle = host.Handle.none()
    priv router: events.EventRouter

    pub fn init(surface: host.Handle, router: events.EventRouter) {
        self.surface = surface
        self.router = router
    }

    /// Starts the clock, calling `handler` before every frame.
    ///
    /// `token` comes back on every frame. Nothing routes by it — the router
    /// already knows which surface a frame belongs to — so it is free for a
    /// caller to say which *run* of the clock a frame came from, which is the
    /// question a program that starts and stops one has.
    ///
    /// The host is asked first and the handler registered only once it agrees.
    /// The other order looks the same until somebody calls this twice: the
    /// second call would replace a running clock's handler and only then be
    /// refused, leaving the frames arriving at a handler nobody meant to
    /// install.
    pub fn start(token: int, handler: fn(Frame)) -> Result<bool> {
        unsafe {
            host.check(host.ctd_clock_start(self.surface.raw, token as i64) as int,
                       "start a frame clock")?
        }
        self.router.on(self.surface, events.EventKind.frame, fn(event: events.UiEvent) {
            handler(Frame.of(event))
        })
        return ok(true)
    }

    /// Stops it, and takes the handler off with it.
    ///
    /// Stopping a clock that is not running succeeds. A teardown path should
    /// not have to ask first, and there is nothing for a caller to do
    /// differently about a clock that had already stopped.
    pub fn stop() -> Result<bool> {
        unsafe {
            host.check(host.ctd_clock_stop(self.surface.raw) as int,
                       "stop a frame clock")?
        }
        self.router.off(self.surface, events.EventKind.frame)
        return ok(true)
    }

    /// What the host says: running or not, how many frames it has delivered,
    /// and where the clock has got to.
    pub fn state() -> Result<ClockState> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_clock_state(self.surface.raw, scratch.reals) as int,
                       "read a frame clock")?
        }
        return ok(ClockState {
            running: scratch.real(0) == 1.0,
            frames: scratch.real(1) as int,
            elapsed: scratch.real(2),
        })
    }

    /// Raises one frame, `seconds` after the previous one, without waiting for
    /// a display.
    ///
    /// The same idea as `Button.activate`: it drives the platform down the
    /// exact path a real frame takes rather than around it. It is how motion
    /// is tested where there is nothing on screen — and that is most places, on
    /// three of the four hosts and on every build machine.
    ///
    /// It refuses a clock that is not running, and a step that is not a
    /// positive number of seconds.
    pub fn step(seconds: f64) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_clock_step(self.surface.raw, seconds) as int,
                              "step a frame clock")
        }
    }
}
