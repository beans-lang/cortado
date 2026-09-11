// One event a described widget wants to hear about.
package component

import cortado.events

/// An event kind and what to do when it happens.
///
/// A class rather than a struct because it holds a closure, and because the
/// differ needs to compare *which events are listened for* without ever
/// comparing the closures themselves — two closures are never equal in any
/// useful sense, so a differ that tried would rebuild a handler on every
/// render.
///
/// So the rule is: the set of event kinds is diffed, and the action is
/// refreshed for every element the differ visits. Those are exactly the
/// elements whose component re-rendered, which are exactly the ones whose
/// closures may have changed — a component that `should_render` skipped is
/// left holding the closure it already had, correctly.
pub class Listener {
    pub kind: events.EventKind = events.EventKind.activate
    action: fn(events.UiEvent)

    pub fn init(kind: events.EventKind, action: fn(events.UiEvent)) {
        self.kind = kind
        self.action = action
    }

    pub fn fire(event: events.UiEvent) {
        let action: fn(events.UiEvent) = self.action
        action(event)
    }
}
