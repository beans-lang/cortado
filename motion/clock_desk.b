// One host clock per surface, and everything that rides it.
package motion

import cortado.host
import cortado.events

/// The listeners on one surface's frame clock.
///
/// A class rather than a `Map` inside a `Map`, for the reason
/// `events.WidgetSubscriptions` gives: a map inside a map is move-only in
/// Beans, so reading the inner one out by index would move it. A class
/// reference copies freely.
///
/// The join order is kept beside the handlers because delivery order is part
/// of what a golden can assert, and a map's iteration order is not something
/// this package gets to promise.
pub class SurfaceListeners {
    by_token: Map<int, fn(Frame)> = {}
    joined: List<int> = []

    pub fn init() {}

    pub fn has(token: int) -> bool {
        return self.by_token.contains_key(token)
    }

    pub fn add(token: int, handler: fn(Frame)) {
        self.by_token[token] = handler
        self.joined.push(token)
    }

    /// Takes one off. Answers whether it was there, so the desk can tell a
    /// token that never joined from the last one leaving.
    pub fn remove(token: int) -> bool {
        if !self.by_token.contains_key(token) {
            return false
        }
        self.by_token.remove(token)
        var kept: List<int> = []
        for held: int in self.joined {
            if held != token {
                kept.push(held)
            }
        }
        self.joined = move kept
        return true
    }

    pub fn count() -> int {
        return self.by_token.len()
    }

    /// The tokens in the order they joined, copied so a handler that leaves
    /// during delivery cannot change the list being walked.
    pub fn tokens() -> List<int> {
        var every: List<int> = []
        for held: int in self.joined {
            every.push(held)
        }
        return move every
    }

    pub fn handler(token: int) -> Option<fn(Frame)> {
        return self.by_token.get(token)
    }
}

/// Every listener on every surface's frame clock, so a window can have more
/// than one thing moving in it.
///
/// **Why this exists.** The host has one clock per surface and refuses a
/// second (`ctd_clock_start` answers `CTD_ERR_STATE`), and that is the right
/// rule rather than a limitation to route around: a display link belongs to a
/// display, so two canvases in one window should share one link instead of
/// opening two. What was missing was the layer that shares it. Before this,
/// the second `ShaderCanvas` on a screen got its refusal stored in `problem()`
/// and simply never moved — and nothing said so, because every test that
/// draws puts each canvas in a window of its own.
///
/// So the fan-out lives here, above the ABI, and no host changes.
///
/// **The token is the key.** `FrameClock.start` already took a token and the
/// host already echoed it back; now it also says *which listener* a frame is
/// for. A token already joined to a surface is refused rather than replacing
/// what is there — a canvas that silently took another's frames is exactly the
/// bug this class exists to remove, and `events.EventRouter.on` replacing by
/// design is what makes saying so here necessary.
pub singleton class ClockDesk {
    desks: Map<u64, SurfaceListeners> = {}

    fn init() {}

    /// Adds `handler` to this surface's clock under `token`, starting the host
    /// clock if it is the first to join.
    ///
    /// The host is asked before anything is recorded, for the reason
    /// `FrameClock.start` documents: the other order leaves a listener
    /// registered against a clock that was refused.
    pub fn join(surface: host.Handle, router: events.EventRouter,
                token: int, handler: fn(Frame)) -> Result<bool> {
        var listeners: SurfaceListeners = self.listeners_for(surface)
        if listeners.has(token) {
            return err("this surface already has a frame listener under token {token} — give each one a token of its own",
                       "token_taken")
        }
        if listeners.count() == 0 {
            unsafe {
                // Zero, because the host's token is bookkeeping now: every
                // frame is handed to several listeners and each is told its
                // own. Echoing one of them would be arbitrary.
                host.check(host.ctd_clock_start(surface.raw, 0 as i64) as int,
                           "start a frame clock")?
            }
            router.on(surface, events.EventKind.frame, fn(event: events.UiEvent) {
                ClockDesk.instance.deliver(surface, event)
            })
        }
        listeners.add(token, handler)
        self.desks[surface.raw] = listeners
        return ok(true)
    }

    /// Takes one listener off, stopping the host clock and unregistering the
    /// router handler only when the last one goes.
    ///
    /// Leaving a surface with no listeners still asks the host to stop, and
    /// that is deliberate rather than a wasted call: the host is what knows
    /// whether the handle is a surface at all. Answering `ok` from here
    /// without asking would make `stop()` on a released widget succeed, and
    /// the whole point of a teardown call is that it tells you when the thing
    /// you are tearing down is already gone. A live surface with no clock
    /// running answers `CTD_OK`, which is why stopping one that never started
    /// still succeeds.
    pub fn leave(surface: host.Handle, router: events.EventRouter,
                 token: int) -> Result<bool> {
        match self.desks.get(surface.raw) {
            none => {
                unsafe {
                    return host.check(host.ctd_clock_stop(surface.raw) as int,
                                      "stop a frame clock")
                }
            }
            some(listeners) => {
                // A token that never joined leaves the others alone. The
                // surface demonstrably resolves — something is listening on
                // it — so there is nothing for the host to tell us.
                if !listeners.remove(token) {
                    return ok(true)
                }
                if listeners.count() > 0 {
                    return ok(true)
                }
                self.desks.remove(surface.raw)
                router.off(surface, events.EventKind.frame)
                unsafe {
                    return host.check(host.ctd_clock_stop(surface.raw) as int,
                                      "stop a frame clock")
                }
            }
        }
    }

    /// How many listeners a surface has. A test asserts this; a program should
    /// not need it.
    pub fn listeners_on(surface: host.Handle) -> int {
        match self.desks.get(surface.raw) {
            some(listeners) => { return listeners.count() }
            none => { return 0 }
        }
    }

    /// Hands one host frame to every listener, in the order they joined, each
    /// told its own token rather than the host's.
    fn deliver(surface: host.Handle, event: events.UiEvent) {
        match self.desks.get(surface.raw) {
            none => {}
            some(listeners) => {
                // The token list is copied before the walk, so a handler that
                // leaves the clock while it is being delivered to does not
                // change the list underneath it.
                for token: int in listeners.tokens() {
                    match listeners.handler(token) {
                        none => {}
                        some(handler) => {
                            var frame: Frame = Frame.of(event)
                            frame.token = token
                            handler(frame)
                        }
                    }
                }
            }
        }
    }

    fn listeners_for(surface: host.Handle) -> SurfaceListeners {
        match self.desks.get(surface.raw) {
            some(found) => { return found }
            none => { return new SurfaceListeners() }
        }
    }
}
