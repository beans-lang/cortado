// One host clock per surface, and everything that rides it.
package motion

import cortado.host
import cortado.events

/// The listeners on one surface's frame clock. A class, not a nested `Map`:
/// a map inside a map is move-only. Join order is kept so a golden can assert it.
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

/// Every listener on every surface's clock, so one window can hold several
/// moving things. The host keeps one clock per surface; the fan-out is here.
pub singleton class ClockDesk {
    desks: Map<u64, SurfaceListeners> = {}

    fn init() {}

    /// Adds `handler` under `token`, starting the host clock for the first to
    /// join. The host is asked first, or a refusal strands a listener.
    pub fn join(surface: host.Handle, router: events.EventRouter,
                token: int, handler: fn(Frame)) -> Result<bool> {
        var listeners: SurfaceListeners = self.listeners_for(surface)
        if listeners.has(token) {
            return err("this surface already has a frame listener under token {token} — give each one a token of its own",
                       "token_taken")
        }
        if listeners.count() == 0 {
            unsafe {
                // Zero: each listener is told its own token, so echoing one
                // of them here would be arbitrary.
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

    /// Takes one listener off; stops the host clock when the last goes. An
    /// empty surface still asks the host — that is what reports a released widget.
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
                // A token that never joined leaves the others alone; the
                // surface demonstrably resolves, so the host has nothing to say.
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
                // Copied before the walk, so a handler that leaves mid-delivery
                // does not change the list underneath it.
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
