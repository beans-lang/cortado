// A movement, described here and run by the platform.
package motion

import cortado.host

/// One property of one widget, moving from one value to another over time.
///
/// It is built up and then handed over. Nothing in Beans runs while it plays:
/// on macOS and iOS the platform's render server drives it on a thread of its
/// own, at the display's rate, and keeps its timing even while the main thread
/// is busy. That is the reason this is a builder rather than something driven
/// from a frame handler, and it is most of the reason to use the platform's
/// own animation at all.
///
/// **The value reads as the destination while it plays.** `start` writes the
/// property to where it is going, and `Widget.opacity()` answers that from
/// then on. The movement is what is *shown*; the property is what is *meant*.
/// The alternative is a number that means "somewhere between two others, and
/// by the time you have acted on it, somewhere else".
///
/// The end arrives as an ordinary event on the widget, so it is registered the
/// way every other handler in cortado is:
///
/// ```
/// app.router.on(button.handle(), events.EventKind.anim_done, fn(event: events.UiEvent) {
///     let end: motion.AnimationEnd = motion.AnimationEnd.of(event)
///     ...
/// })
/// var fade: motion.Animation = motion.Animation.on(button.handle(), motion.Animatable.opacity)?
/// fade.to(0.0)?
/// fade.duration(0.3)?
/// fade.start(7)?
/// ```
///
/// There is no router in here on purpose. A handler belongs to a widget and a
/// kind, which is cortado's one event model; an animation that registered its
/// own would be a second one, and two animations on the same widget would
/// quietly replace each other's handlers.
pub class Animation {
    priv slot: host.Handle = host.Handle.none()
    priv started: bool = false

    priv fn init(slot: host.Handle) {
        self.slot = slot
        self.started = false
    }

    /// Builds an animation for one property of one widget.
    ///
    /// The platform refuses in three cases and they are worth telling apart in
    /// the message, because it answers with no handle rather than a status:
    /// the widget has been released, the property is not one it animates, or
    /// its table is full.
    pub static fn on(widget: host.Handle, property: Animatable) -> Result<Animation> {
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_anim_new(widget.raw, property.code() as i32)
        }
        if raw == 0 {
            return err("the platform would not animate {property.name()} on {widget.show()} — a released widget, or a property this platform does not move",
                       "not_animatable")
        }
        return ok(new Animation(host.Handle.of(raw)))
    }

    /// Where it starts. Without this it starts from wherever the property is
    /// when `start` is called, which is what a movement usually wants.
    pub fn from(value: f64) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_anim_from_real(self.slot.raw, value) as int,
                              "set where an animation starts")
        }
    }

    /// Where it ends. Required — `start` refuses an animation that has not
    /// been told where it is going.
    pub fn to(value: f64) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_anim_to_real(self.slot.raw, value) as int,
                              "set where an animation ends")
        }
    }

    /// How long it takes, in seconds. A quarter of a second when unsaid.
    pub fn duration(seconds: f64) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_anim_duration(self.slot.raw, seconds) as int,
                              "set how long an animation takes")
        }
    }

    /// How long to wait before it starts, in seconds.
    pub fn delay(seconds: f64) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_anim_delay(self.slot.raw, seconds) as int,
                              "set an animation's delay")
        }
    }

    pub fn curve(shape: Curve) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_anim_curve(self.slot.raw, shape.code() as i32) as int,
                              "set an animation's curve")
        }
    }

    /// Hands it to the platform. `token` comes back on the event that says it
    /// ended, and is what tells two animations on one widget apart.
    ///
    /// Starting one on a property that is already animating replaces the
    /// animation there, which ends as cancelled.
    pub fn start(token: int) -> Result<bool> {
        unsafe {
            host.check(host.ctd_anim_start(self.slot.raw, token as i64) as int,
                       "start an animation")?
        }
        self.started = true
        return ok(true)
    }

    /// Stops it where it is: the property keeps the value it was showing, not
    /// the one it was going to.
    ///
    /// On one that was built and never started this is how it is thrown away —
    /// nothing was running, so nothing is reported.
    pub fn cancel() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_anim_cancel(self.slot.raw) as int,
                              "cancel an animation")
        }
    }

    /// Throws away an animation nobody started.
    ///
    /// Only that one. An animation that *was* started belongs to the platform,
    /// and its handle went stale the moment it ended — collecting the Beans
    /// object that described it must not reach across and stop a movement that
    /// is still playing.
    fn deinit() {
        if !self.started {
            self.cancel()
        }
    }
}
