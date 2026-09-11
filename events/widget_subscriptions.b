// The handlers registered against one widget.
package events

/// Every handler for a single widget, keyed by event kind.
///
/// This is a class rather than a nested `Map` because a map inside a map is
/// move-only in Beans — reading the inner one out by index would move it. A
/// class reference copies freely, so the router can reach a widget's handlers
/// in one lookup and still mutate them in place.
pub class WidgetSubscriptions {
    by_kind: Map<int, fn(UiEvent)> = {}

    pub fn init() {}

    pub fn set(kind_code: int, handler: fn(UiEvent)) {
        self.by_kind[kind_code] = handler
    }

    pub fn clear(kind_code: int) {
        self.by_kind.remove(kind_code)
    }

    pub fn count() -> int {
        return self.by_kind.len()
    }

    pub fn handler(kind_code: int) -> Option<fn(UiEvent)> {
        return self.by_kind.get(kind_code)
    }
}
