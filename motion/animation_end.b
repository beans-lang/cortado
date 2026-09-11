// How an animation ended.
package motion

import cortado.events

/// The news an animation delivers when it stops: which one, whether it got
/// where it was going, and where it ended up.
///
/// A value, like `Frame`. It is read inside the handler and nothing outlives
/// the call.
pub struct AnimationEnd {
    /// The word `Animation.start` was given. This is what tells two animations
    /// on one widget apart, because both report against the widget.
    pub token: int = 0

    /// False when it was cancelled, or replaced by another animation of the
    /// same property. A caller that does something *after* a movement has to
    /// know the difference; one that was cancelled half way usually should not
    /// run whatever came next.
    pub finished: bool = false

    /// What the property reads now.
    pub value: f64 = 0.0

    pub static fn of(event: events.UiEvent) -> AnimationEnd {
        return AnimationEnd {
            token: event.token,
            finished: event.index == 1,
            value: event.position.x,
        }
    }

    pub fn show() -> string {
        return "token={self.token} finished={self.finished}"
    }
}
