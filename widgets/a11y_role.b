// What a control a program draws itself calls itself.
package widgets

import cortado.host

/// The word a screen reader is given for a `Canvas`.
///
/// Four, out of the vocabulary `Widget.a11y_role` already publishes, and no
/// new ones: a canvas is the one control whose contents cortado did not write,
/// so it is the one that has to be told what it is — but inventing a word for
/// "a program draws its own pixels here" would be a word no screen reader
/// knows, which is the argument the canvas's own case in `ctd_a11y_role`
/// already makes.
///
/// Carried by a canvas and nothing else. A program must not be able to tell a
/// screen reader that a text field is an image.
pub enum(u8) A11yRole {
    /// Whatever the kind says — `group` for a canvas. The default, so no
    /// screen that exists today changes what it reports.
    automatic
    /// Something you press.
    button
    /// A picture.
    image
    /// An area with things in it.
    group

    pub fn code() -> int {
        return match self {
            automatic => host.A11Y_AUTO,
            button => host.A11Y_BUTTON,
            image => host.A11Y_IMAGE,
            group => host.A11Y_GROUP,
        }
    }

    pub fn name() -> string {
        return match self {
            automatic => "automatic",
            button => "button",
            image => "image",
            group => "group",
        }
    }

    pub static fn of(code: int) -> Option<A11yRole> {
        if code == host.A11Y_AUTO { return some(A11yRole.automatic) }
        if code == host.A11Y_BUTTON { return some(A11yRole.button) }
        if code == host.A11Y_IMAGE { return some(A11yRole.image) }
        if code == host.A11Y_GROUP { return some(A11yRole.group) }
        return none
    }
}
