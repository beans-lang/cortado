// One thing that happened, decoded.
package events

import cortado.host
import cortado.geometry

/// An event, in Beans terms.
///
/// The host delivers a flat record of numbers; this is what cortado hands a
/// handler. It is a plain value with no reference back to the widget, which
/// is what lets a handler be an ordinary function rather than a closure that
/// captures the control it belongs to — and that, in turn, is what keeps
/// widgets and handlers from forming a cycle the collector cannot see.
pub class UiEvent {
    pub kind: EventKind = EventKind.unknown
    pub target: host.Handle = host.Handle.none()
    pub modifiers: int = 0
    /// Row, tab, selected index or key code, depending on `kind`.
    pub index: int = 0
    /// Echoes the word passed to `Application.post`, for `post` events.
    pub token: int = 0
    pub position: geometry.Point = geometry.Point.zero()
    pub size: geometry.Size = geometry.Size.zero()

    /// What the control said, for the events where that is the news: a value
    /// that changed, a field that committed. Empty for every other kind.
    ///
    /// Copied out of the host's buffer here and not later. The bytes belong to
    /// the platform and are valid only while it is raising the event; a
    /// handler that runs afterwards — and every handler does — would be
    /// reading memory the platform has moved on from.
    pub text: string = ""

    pub fn init(record: host.CtdEvent) {
        self.kind = EventKind.of(record.kind as int)
        self.target = host.Handle.of(record.target)
        self.modifiers = record.modifiers as int
        self.index = record.index as int
        self.token = record.token as int
        self.position = geometry.Point.at(record.x, record.y)
        self.size = geometry.Size.of(record.width, record.height)
        self.text = host.HostText.copy_in(record.text, record.text_len as int)
    }

    /// An event cortado raised itself, rather than one the platform sent.
    ///
    /// The component layer needs this to deliver a change it made on the
    /// Beans side — a parameter that moved, a value the framework set — down
    /// the same path a real click takes, so a handler has one shape whatever
    /// woke it. It is also what lets the differ and the router be tested with
    /// no platform at all.
    pub static fn of(kind: EventKind, target: host.Handle) -> UiEvent {
        var record: host.CtdEvent = host.CtdEvent {
            kind: kind.name_code() as u32, modifiers: 0, target: target.raw,
            index: 0, token: 0, x: 0.0, y: 0.0, width: 0.0, height: 0.0,
            text: RawPtr.null(), text_len: 0
        }
        return new UiEvent(record)
    }

    pub fn has_modifier(bit: int) -> bool {
        return (self.modifiers & bit) != 0
    }

    /// The line the event goldens carry. Only the fields a given kind actually
    /// uses appear, so adding a field to the record does not churn every
    /// golden in the suite.
    pub fn show() -> string {
        match self.kind {
            post => { return "post token={self.token}" }
            surface_resized => { return "surface_resized {self.size.show()}" }
            pointer_down => { return "pointer_down {self.target.show()} {self.position.show()}" }
            pointer_up => { return "pointer_up {self.target.show()} {self.position.show()}" }
            pointer_move => { return "pointer_move {self.target.show()} {self.position.show()}" }
            selection => { return "selection {self.target.show()} index={self.index}" }
            key_down => { return "key_down {self.target.show()} key={self.index}" }
            key_up => { return "key_up {self.target.show()} key={self.index}" }
            _ => { return "{self.kind.name()} {self.target.show()}" }
        }
    }
}
