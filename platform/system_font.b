// The fonts the system itself uses.
package platform

import cortado.host

/// A font by the job it does, rather than by name.
///
/// Naming a family is how an interface ends up looking foreign: the right
/// choice is "San Francisco" here, "Segoe UI" there and whatever the desktop
/// theme says on Linux, and a program that hard-codes one is wrong on three
/// platforms out of four. Asking for the *role* gets the platform's own answer,
/// at the platform's own size — which also follows the user's text-size
/// setting, something a hard-coded number cannot.
pub enum SystemFont {
    body
    heading
    caption
    /// Fixed width, for code and for numbers that should line up in a column.
    mono

    pub fn code() -> int {
        return match self {
            body => host.FONT_BODY,
            heading => host.FONT_HEADING,
            caption => host.FONT_CAPTION,
            mono => host.FONT_MONO,
        }
    }

    pub fn name() -> string {
        return match self {
            body => "body",
            heading => "heading",
            caption => "caption",
            mono => "mono",
        }
    }

    /// The family the platform uses for this role.
    pub fn family() -> Result<string> {
        let role: i32 = self.code() as i32
        return host.HostText.read(
            "read the {self.name()} font family",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_font_family(role, out, cap) }
            })
    }

    /// The size in points the platform uses for this role.
    pub fn size() -> Result<f64> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_font_size(self.code() as i32, scratch.reals) as int,
                       "read the {self.name()} font size")?
        }
        return ok(scratch.real(0))
    }
}
