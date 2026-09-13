// Where events go once they reach Beans.
package events

import cortado.host
import std.time

/// One frame at 120 Hz, in nanoseconds. The default settle window.
pub const FRAME_NANOS: int = 8333333

/// The word cortado posts to itself when a render has been put off.
///
/// Reserved. `EventRouter` takes it back out of the stream rather than handing
/// it to a `post` handler, so a program never sees the framework's own
/// bookkeeping arrive as one of its events. It is the most negative word an
/// `i64` can carry short of the minimum, which is a number no program picks.
pub const SETTLE_TOKEN: int = -9223372036854775807

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
    /// What the framework itself is listening for, kept apart from what the
    /// program is.
    ///
    /// `on` replaces, which is right for a program — a re-render rebinds a
    /// control's handler and there must be exactly one. It is wrong for the
    /// framework: a mount that follows its surface so the layout keeps up with
    /// a resize would be switched off, silently and for good, by an
    /// application that registered a resize handler of its own. The layout
    /// would then freeze at the size the window opened at, which is a bug with
    /// no symptom until somebody drags a corner.
    ///
    /// So the two live in separate tables. A watch is never displaced by an
    /// `on` and never displaces one; both run, and the order is stated rather
    /// than accidental — see `dispatch`.
    watchers: Map<u64, WidgetSubscriptions> = {}
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
    /// The shortest gap between two settles. See `set_settle_window`.
    settle_window: int = FRAME_NANOS
    /// When the last settle ran, on the monotonic clock.
    last_settle: int = 0
    /// Whether a settle has been put off and a wake-up posted for it.
    settle_due: bool = false

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

    /// Registers a framework subscription for one kind of event on one widget.
    ///
    /// The same shape as `on` and a different table: see `watchers`. What uses
    /// it is `component.Mount`, which watches the surface it fills so a resize
    /// or a change of display scale reaches the layout — work that belongs to
    /// the framework and that an application must not be able to switch off by
    /// registering a handler of its own for the same event.
    pub fn watch(target: host.Handle, kind: EventKind, handler: fn(UiEvent)) {
        let code: int = kind.name_code()
        var replaced: bool = false
        match self.watchers.get(target.raw) {
            some(existing) => {
                replaced = existing.has(code)
                existing.set(code, handler)
            }
            none => {
                var fresh: WidgetSubscriptions = new WidgetSubscriptions()
                fresh.set(code, handler)
                self.watchers[target.raw] = fresh
            }
        }
        if !replaced { self.took_up(code) }
    }

    pub fn unwatch(target: host.Handle, kind: EventKind) {
        let code: int = kind.name_code()
        match self.watchers.get(target.raw) {
            some(existing) => {
                if !existing.has(code) { return }
                existing.clear(code)
                self.let_go(code)
                if existing.count() == 0 {
                    self.watchers.remove(target.raw)
                }
            }
            none => {}
        }
    }

    /// Drops every handler and every watch for a widget. Called when the
    /// widget goes, so the maps do not grow for the life of the program.
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
        match self.watchers.get(target.raw) {
            some(existing) => {
                for code: int in existing.kinds() {
                    self.let_go(code)
                }
            }
            none => {}
        }
        self.watchers.remove(target.raw)
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

    /// How many framework watches are registered. The teardown test reads this
    /// beside `registered`: a mount that closed and left its surface watched
    /// keeps the host delivering resizes to nothing.
    pub fn watching() -> int {
        var total: int = 0
        for key: u64 in self.watchers.keys() {
            match self.watchers.get(key) {
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
    ///
    /// **What settles is put off while more input is already waiting.** A
    /// slider being dragged reports on every step and a pointer reports
    /// hundreds of times a second; the platform delivers those one at a time,
    /// so "after the batch" was "after each one" and a framework that
    /// re-rendered there did a screen's worth of work per report. The reports
    /// do not slow down to wait for it, so the queue grows and the window
    /// stops answering — which is what a person calls lag.
    ///
    /// So the host is asked whether anything else is already queued, and if it
    /// is, settling is left to whichever delivery finds the queue empty. The
    /// events themselves are never deferred: every one reaches its handler
    /// immediately, in order, exactly as before. Only the work that follows a
    /// *batch* of them is collapsed into one.
    ///
    /// It cannot be put off for ever, and that is a guarantee rather than a
    /// hope: `settle_by` is a deadline, so input arriving faster than the
    /// screen can be redrawn still redraws the screen — once per frame instead
    /// of once per report. A host that cannot say what is queued answers no,
    /// and renders per event as it always did.
    pub fn deliver(event: UiEvent) {
        // cortado's own wake-up, taken back out of the stream. It carries no
        // news for a program — it exists because a settle was put off and
        // something had to come back for it.
        if event.kind == EventKind.post && event.token == SETTLE_TOKEN {
            self.settle_due = false
            if self.depth == 0 { self.run_settle(time.monotonic_nanos()) }
            return
        }
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
        self.want_settle()
    }

    /// Settles now, or puts it off and posts a wake-up for it.
    ///
    /// **How often a program re-renders should follow the screen, not the
    /// mouse.** A slider being dragged reports on every step and a pointer
    /// reports hundreds of times a second. Settling after each of those does a
    /// screen's worth of work per report, and the reports do not slow down to
    /// wait for it — so the queue grows, the window stops answering, and a
    /// person calls it lag. Two events a millisecond apart cannot both be seen
    /// by anyone.
    ///
    /// So a settle happens at most once per `settle_window`, and the events in
    /// between are handled immediately and collapse into the next one. The
    /// first event after a quiet spell is never delayed: the window has long
    /// since passed, so it settles in the same breath.
    ///
    /// **A settle that is put off is never dropped.** Deferring posts a
    /// wake-up, which the platform delivers whether or not the user does
    /// anything else — so the last event of a drag is drawn even though it is
    /// the one with nothing behind it to trigger a settle. That guarantee is
    /// the whole reason this is a post and not a flag somebody has to
    /// remember to check.
    fn want_settle() {
        match self.settled {
            none => { return }
            some(handler) => {}
        }
        let now: int = time.monotonic_nanos()
        if now - self.last_settle >= self.settle_window {
            self.run_settle(now)
            return
        }
        if self.settle_due { return }
        self.settle_due = true
        unsafe {
            host.ctd_post(SETTLE_TOKEN as i64)
        }
    }

    fn run_settle(now: int) {
        self.last_settle = now
        self.settle_due = false
        match self.settled {
            none => {}
            some(handler) => { handler() }
        }
    }

    /// The shortest gap between two settles, in nanoseconds.
    ///
    /// One frame at 120 Hz by default. Zero settles after every batch, which
    /// is what cortado did before this existed and what a program that must
    /// not collapse two inputs into one render wants.
    pub fn set_settle_window(nanos: int) {
        var wanted: int = nanos
        if wanted < 0 { wanted = 0 }
        self.settle_window = wanted
    }

    /// Whether a settle has been put off and not yet run. The input gate reads
    /// it: a deferral that no wake-up ever collected is a render that never
    /// happened.
    pub fn settle_waiting() -> bool {
        return self.settle_due
    }

    /// The framework's watch first, then the program's handler.
    ///
    /// That order is the one a program can reason about: a mount watching its
    /// surface has re-laid the tree out by the time an application's own
    /// resize handler runs, so a handler that reads a control's frame reads
    /// the frame it has now rather than the one it had before the window
    /// changed size. The other order would hand the program a tree it is about
    /// to move.
    fn dispatch(event: UiEvent) {
        let code: int = event.kind.name_code()
        match self.watchers.get(event.target.raw) {
            some(subscriptions) => {
                match subscriptions.handler(code) {
                    some(watcher) => { watcher(event) }
                    none => {}
                }
            }
            none => {}
        }
        match self.handlers.get(event.target.raw) {
            some(subscriptions) => {
                match subscriptions.handler(code) {
                    some(handler) => { handler(event) }
                    none => {}
                }
            }
            none => {}
        }
    }
}
