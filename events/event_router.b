// Where events go once they reach Beans.
package events

import cortado.host

/// Routes events to the code that cares about them.
///
/// There is exactly one callback registered with the platform for the whole
/// process, and it lands here. Per-widget handlers are entries in this map,
/// not separate platform callbacks, for a reason worth stating plainly: a
/// stored callback holds a strong reference to its closure that the cycle
/// collector cannot see through, so a closure capturing the widget it is
/// attached to would leak with nothing able to reclaim it. A handler here is
/// an ordinary function that takes the event as an argument and captures
/// nothing it is attached to.
///
/// Handlers are keyed by the full handle, generation included, so a recycled
/// slot never inherits the previous widget's handlers.
pub class EventRouter {
    handlers: Map<u64, WidgetSubscriptions> = {}
    /// How many widgets have a handler for each kind.
    ///
    /// The host is told when a count leaves zero and when it reaches it again,
    /// and that is not bookkeeping for its own sake: AppKit generates no
    /// mouse-moved events for a window until it is told to want them, and a
    /// pointer that reports a thousand times a second is a thousand crossings
    /// per second into a program that was not listening. Everything else in
    /// cortado is told what to do; this is the one place it says what it
    /// *wants*, so a host can decline to do work nobody reads.
    listeners: Map<int, int> = {}
    /// Events that arrived while a handler was already running. Delivering one
    /// immediately would re-enter Beans from inside a platform callback, which
    /// is how a resize provoked by a click handler becomes a recursion with no
    /// bottom.
    pending: List<UiEvent> = []
    depth: int = 0

    /// Run once after each batch of events, if anything registered.
    settled: Option<fn()> = none

    pub fn init() {}

    /// Registers `handler` for one kind of event on one widget, replacing any
    /// handler already registered for that pair.
    pub fn on(target: host.Handle, kind: EventKind, handler: fn(UiEvent)) {
        let code: int = kind.name_code()
        var replaced: bool = false
        match self.handlers.get(target.raw) {
            some(existing) => {
                // Replacing rather than adding, which the count must not see:
                // one that rose on every `on` would never fall back to zero
                // and the host would be told to keep working forever.
                replaced = existing.has(code)
                existing.set(code, handler)
            }
            none => {
                var fresh: WidgetSubscriptions = new WidgetSubscriptions()
                fresh.set(code, handler)
                self.handlers[target.raw] = fresh
            }
        }
        if !replaced { self.took_up(code) }
    }

    pub fn off(target: host.Handle, kind: EventKind) {
        let code: int = kind.name_code()
        match self.handlers.get(target.raw) {
            some(existing) => {
                if !existing.has(code) { return }
                existing.clear(code)
                self.let_go(code)
                if existing.count() == 0 {
                    self.handlers.remove(target.raw)
                }
            }
            none => {}
        }
    }

    /// Drops every handler for a widget. Called when the widget goes, so the
    /// map does not grow for the life of the program.
    pub fn forget(target: host.Handle) {
        match self.handlers.get(target.raw) {
            some(existing) => {
                for code: int in existing.kinds() {
                    self.let_go(code)
                }
            }
            none => {}
        }
        self.handlers.remove(target.raw)
    }

    /// One more widget wants this kind. The host hears about the first.
    fn took_up(code: int) {
        let before: int = self.listeners.get(code).or(0)
        self.listeners[code] = before + 1
        if before == 0 { self.tell_host(code, true) }
    }

    /// One fewer. The host hears about the last.
    fn let_go(code: int) {
        let before: int = self.listeners.get(code).or(0)
        if before <= 1 {
            self.listeners.remove(code)
            self.tell_host(code, false)
            return
        }
        self.listeners[code] = before - 1
    }

    /// The answer is deliberately thrown away. The header calls this advice
    /// rather than permission: a host that cannot turn a kind off says so and
    /// keeps delivering, and this map drops what nobody wants. There is
    /// nothing a program could usefully do about either answer.
    fn tell_host(code: int, on: bool) {
        var flag: int = 0
        if on { flag = 1 }
        unsafe {
            host.ctd_listen(code as i32, flag as i32)
        }
    }

    /// How many kinds the host has been asked for. The input suite reads it:
    /// a count that never falls is the bug this bookkeeping exists to avoid.
    pub fn listening() -> int {
        return self.listeners.len()
    }

    /// How many handlers are registered, across every widget. The teardown
    /// test reads this: after a window closes it must be zero, which is what
    /// proves handlers are not the thing that keeps a widget alive.
    pub fn registered() -> int {
        var total: int = 0
        for key: u64 in self.handlers.keys() {
            match self.handlers.get(key) {
                some(subscriptions) => { total = total + subscriptions.count() }
                none => {}
            }
        }
        return total
    }

    /// Runs after a batch of events has been handled, once.
    ///
    /// This is the seam a component framework needs and nothing else does: a
    /// handler changes some state, and something has to notice and re-render.
    /// It runs **after the whole batch drains**, not after each event, so a
    /// handler that triggers three more does not cause four renders — and so a
    /// render that is itself observable cannot be re-entered from inside one.
    ///
    /// A plain callback and not a list of them. One mount owns one surface,
    /// and a framework that let several things register here would make the
    /// order they run in matter without giving anyone a way to say what it
    /// should be.
    pub fn after(handler: fn()) {
        self.settled = some(handler)
    }

    /// Hands one event to its handler, then drains anything that arrived while
    /// that handler was running.
    pub fn deliver(event: UiEvent) {
        if self.depth > 0 {
            self.pending.push(event)
            return
        }
        self.depth = self.depth + 1
        self.dispatch(event)
        for self.pending.len() > 0 {
            let next: UiEvent = self.pending[0]
            self.pending.remove(0)
            self.dispatch(next)
        }
        self.depth = self.depth - 1
        match self.settled {
            none => {}
            some(handler) => { handler() }
        }
    }

    fn dispatch(event: UiEvent) {
        match self.handlers.get(event.target.raw) {
            some(subscriptions) => {
                match subscriptions.handler(event.kind.name_code()) {
                    some(handler) => { handler(event) }
                    none => {}
                }
            }
            none => {}
        }
    }
}
