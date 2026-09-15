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
    /// The token this clock joined under, so `stop` takes off the listener
    /// this object started and not somebody else's.
    priv token: int = 0
    priv started: bool = false

    pub fn init(surface: host.Handle, router: events.EventRouter) {
        self.surface = surface
        self.router = router
    }

    /// Starts the clock, calling `handler` before every frame.
    ///
    /// `token` comes back on every frame and says which listener it is for:
    /// a surface may have several. A repeated token is refused, not replaced.
    ///
    /// The host keeps one clock per surface, which is right — a display link
    /// belongs to a display. `ClockDesk` is what shares it.
    pub fn start(token: int, handler: fn(Frame)) -> Result<bool> {
        // Starting this clock twice is still refused: the object holds one
        // token, so a second start would strand the first listener.
        if self.started {
            return err("this frame clock is already running under token {self.token} — a second thing moving on the same surface is its own FrameClock, not this one started again",
                       "wrong_moment")
        }
        ClockDesk.instance.join(self.surface, self.router, token, handler)?
        self.token = token
        self.started = true
        return ok(true)
    }

    /// Stops it, and takes this clock's handler off with it.
    ///
    /// Stopping a clock that is not running succeeds. A teardown path should
    /// not have to ask first, and there is nothing for a caller to do
    /// differently about a clock that had already stopped.
    ///
    /// The host's clock stops when the *last* listener on the surface leaves,
    /// not when this one does — which is what lets one canvas be taken off a
    /// screen while another keeps moving.
    pub fn stop() -> Result<bool> {
        // Asked unconditionally, even for a clock that never started: the
        // host is what knows whether this handle is still a surface, and a
        // teardown call that answered `ok` about a released widget would be
        // hiding exactly what it exists to report.
        ClockDesk.instance.leave(self.surface, self.router, self.token)?
        self.started = false
        return ok(true)
    }

    /// The rate this surface asks its display for, in frames a second.
    ///
    /// `wanted` is the rate to aim for; `lowest` and `highest` bound where the
    /// system may move when it cannot hold it or has room to spare. Zero for
    /// any of them means the screen's own maximum, which is what a clock asks
    /// for until it is told otherwise — so `prefer(0.0, 0.0, 0.0)` is "as fast
    /// as this display goes" and `prefer(60.0, 60.0, 60.0)` is "sixty, held".
    ///
    /// **A range is permission, not a hint.** Asking for 60 with a floor of 30
    /// was measured holding a steady 42 on a 60 Hz panel: the system took the
    /// room it was given. Pass one number three times for a constant rate.
    ///
    /// Refused as `unsupported` on GTK4, whose frame clock is the display's
    /// and takes no instruction, and as `range` for a negative rate or a range
    /// whose ends are crossed.
    pub fn prefer(lowest: f64, highest: f64, wanted: f64) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_clock_prefer(self.surface.raw, lowest,
                                                    highest, wanted) as int,
                              "ask a display for a frame rate")
        }
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
