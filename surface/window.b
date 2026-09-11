// A desktop window.
package surface

import cortado.host
import cortado.geometry

/// A surface the user can move, resize and close.
///
/// Only desktop platforms have these. A program that may also run on a phone
/// asks `platform.Capability.multi_surface` before making a second one, and
/// puts its single root tree in the surface it was handed otherwise.
pub class Window extends Surface {
    pub fn init(size: geometry.Size) {
        super.init(size)
    }

    pub static fn of(width: f64, height: f64, title: string) -> Result<Window> {
        var window: Window = new Window(geometry.Size.of(width, height))
        window.set_title(title)?
        return ok(window)
    }

    /// Puts the window on screen and brings it forward.
    ///
    /// Under `AppRole.headless` this succeeds and shows nothing, so a test can
    /// call it on a machine with no display and still read back a fully built,
    /// fully measured widget tree.
    pub fn show() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_surface_show(self.handle().raw) as int,
                              "show a window")
        }
    }

    pub fn close() -> Result<bool> {
        if self.closed {
            return ok(true)
        }
        self.closed = true
        unsafe {
            return host.check(host.ctd_surface_close(self.handle().raw) as int,
                              "close a window")
        }
    }

    pub fn is_visible() -> bool {
        unsafe {
            return host.ctd_surface_visible(self.handle().raw) == 1
        }
    }

    fn deinit() {
        self.close()
    }
}
