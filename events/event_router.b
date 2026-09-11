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
    /// Events that arrived while a handler was already running. Delivering one
    /// immediately would re-enter Beans from inside a platform callback, which
    /// is how a resize provoked by a click handler becomes a recursion with no
    /// bottom.
    pending: List<UiEvent> = []
    depth: int = 0

    pub fn init() {}

    /// Registers `handler` for one kind of event on one widget, replacing any
    /// handler already registered for that pair.
    pub fn on(target: host.Handle, kind: EventKind, handler: fn(UiEvent)) {
        match self.handlers.get(target.raw) {
            some(existing) => { existing.set(kind.name_code(), handler) }
            none => {
                var fresh: WidgetSubscriptions = new WidgetSubscriptions()
                fresh.set(kind.name_code(), handler)
                self.handlers[target.raw] = fresh
            }
        }
    }

    pub fn off(target: host.Handle, kind: EventKind) {
        match self.handlers.get(target.raw) {
            some(existing) => {
                existing.clear(kind.name_code())
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
        self.handlers.remove(target.raw)
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
