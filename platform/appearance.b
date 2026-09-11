// Light or dark, and how sharp the display is.
package platform

import cortado.host

/// Whether the system is showing light or dark.
///
/// Native controls follow this on their own — that is most of the argument for
/// using them — so a program only needs to ask when it draws something
/// itself: a chart, a custom cell, a colour it chose. Changes arrive as an
/// `appearance` event, so nothing has to poll.
pub enum Appearance {
    light
    dark

    pub fn name() -> string {
        return match self {
            light => "light",
            dark => "dark",
        }
    }

    /// What the system is showing right now.
    pub static fn current() -> Appearance {
        unsafe {
            if host.ctd_appearance() == 1 {
                return Appearance.dark
            }
            return Appearance.light
        }
    }

    pub static fn of(code: int) -> Appearance {
        if code == 1 { return Appearance.dark }
        return Appearance.light
    }
}
