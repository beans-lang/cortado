// How a drawn pixel is mixed with the one already there.
package gpu

import cortado.host

/// What to do with the pixel that is already there.
///
/// Three named modes rather than a pair of blend factors. Every backend has
/// these three and means the same by them; a factor pair is eight enums to
/// combine correctly, unchecked, to arrive at one of these three anyway. Custom
/// factors are a later call of their own and change nothing about this one.
pub enum(u8) Blend {
    /// The new pixel, whatever was there. What you want when the thing being
    /// drawn is opaque, and the fastest of the three because the GPU never has
    /// to read the target.
    replace
    /// Over: the new pixel's alpha decides how much of it shows. What an
    /// interface almost always wants, and what anti-aliased edges need.
    alpha
    /// Added together. Light rather than paint — glows, particles, a heat map
    /// where overlapping samples should get brighter.
    add

    pub fn name() -> string {
        return match self {
            replace => "replace",
            alpha => "alpha",
            add => "add",
        }
    }

    pub fn code() -> int {
        return match self {
            replace => host.BLEND_REPLACE,
            alpha => host.BLEND_ALPHA,
            add => host.BLEND_ADD,
        }
    }
}
