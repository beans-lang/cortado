// Which pixels a pipeline is built to write.
package gpu

import cortado.host

/// The two kinds of place a pipeline can draw.
///
/// Not a format zoo — two answers, because there are two questions. An
/// off-screen target is the 8-bit RGBA that `Target.read` hands back, and
/// every backend can make one. A canvas is whatever the platform's compositor
/// wants, which on Metal is BGRA and on another backend may be something else;
/// the host knows and a caller does not have to.
///
/// It matters because a pipeline carries the format it writes, and drawing
/// with one that disagrees with its target is refused by the driver at draw
/// time — a long way from the line that got it wrong. So a pipeline says which
/// it is for, once.
///
/// **Nothing changes in the shader.** It writes red, green, blue and alpha in
/// that order either way, and the hardware puts them where they go.
pub enum(u8) Pixels {
    /// What `Device.target` makes, and what `Target.read` reads back.
    offscreen
    /// Whatever this platform shows a canvas in.
    screen

    pub fn name() -> string {
        return match self {
            offscreen => "offscreen",
            screen => "screen",
        }
    }

    pub fn code() -> int {
        return match self {
            offscreen => host.PIXELS_RGBA8,
            screen => host.PIXELS_SCREEN,
        }
    }
}
