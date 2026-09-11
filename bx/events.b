// events.b — what `on:` may name.
//
// One table, and one reason for it: **an event the Builder cannot deliver must
// be refused here.** Generating a subscription for an event cortado does not
// raise would produce a control that silently never fires, which is the worst
// possible failure for a handler — it looks exactly like a handler whose
// condition was never met.
//
// Unlike latte's, this table has one event *family*. Every cortado handler
// receives a `UiEvent`, because the platform delivers one flat record and the
// fields a given kind fills are documented on the kind rather than split
// across five classes. So the generated closure's parameter type is always the
// same, and an author copying a handler from one control to another never has
// to change it.

package bx

/// Whether `on:<event>` names something cortado raises.
pub fn is_event(event: string) -> bool {
    return event_family(event) != ""
}

/// The event class an `on:<event>` handler receives, or `""` when the event is
/// not one cortado raises.
pub fn event_family(event: string) -> string {
    if event == "click" { return "UiEvent" }
    if event == "activate" { return "UiEvent" }
    if event == "change" { return "UiEvent" }
    if event == "commit" { return "UiEvent" }
    if event == "select" { return "UiEvent" }
    if event == "focus" { return "UiEvent" }
    if event == "blur" { return "UiEvent" }
    if event == "pointer_down" { return "UiEvent" }
    if event == "pointer_up" { return "UiEvent" }
    if event == "pointer_move" { return "UiEvent" }
    if event == "key_down" { return "UiEvent" }
    if event == "key_up" { return "UiEvent" }
    return ""
}

/// Every event name, in order, for a diagnostic that can list them.
pub fn event_names() -> List<string> {
    return ["activate", "blur", "change", "click", "commit", "focus",
            "key_down", "key_up", "pointer_down", "pointer_move",
            "pointer_up", "select"]
}

/// The events, comma-separated, for the body of a diagnostic.
pub fn event_list() -> string {
    return event_names().join(", ")
}

/// The nearest event to `event` by edit distance, or `""` when nothing is
/// close enough to be worth suggesting.
///
/// Only within two edits, so `on:clcik` says "did you mean click?" and
/// `on:wheel` does not say "did you mean key_up?". A wrong suggestion is worse
/// than none: it sends the reader to fix the wrong thing.
pub fn nearest_event(event: string) -> string {
    return nearest_of(event, event_names())
}
