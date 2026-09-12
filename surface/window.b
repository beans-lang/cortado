// A desktop window.
package surface

import cortado.host
import cortado.geometry
import cortado.events

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

    // ---- the four things that happen to a surface ----

    /// Makes one of them happen, for a test and for a program replaying a
    /// session.
    ///
    /// **Two take the real road and two cannot.** A resize really resizes the
    /// window and a close really asks it to close, so the platform's own
    /// notification is what arrives. But no program can change the system's
    /// appearance or a display's scale — those belong to the system, and a
    /// call that really did it would be a call reaching outside the program —
    /// so for those two the event is raised directly. What that proves is
    /// everything above the platform; what it cannot prove is that the
    /// platform calls cortado when a person moves the slider in System
    /// Settings.
    ///
    /// `a` and `b` are the new width and height for a resize, `a` is the new
    /// appearance or scale for those two, and both are ignored for a close.
    pub fn happen(what: events.EventKind, a: f64, b: f64) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_surface_synth(self.handle().raw, what.name_code() as i32,
                                       a, b) as int,
                "drive a window")
        }
    }

    /// The user dragged the corner.
    pub fn resize_as_user(size: geometry.Size) -> Result<bool> {
        return self.happen(events.EventKind.surface_resized, size.width, size.height)
    }

    /// The user pressed the close button.
    ///
    /// What follows is the rule the header states: a program with a
    /// `surface_close` handler keeps its window and decides, and one without
    /// gets the window closed. A handler cannot answer back — there is one
    /// callback edge and it returns nothing — so the question is settled by
    /// the only thing the host already knows.
    ///
    /// Refused as `unsupported` on a phone, where there is no window to close:
    /// no title bar, no close button and no gesture that means it. Leaving an
    /// application is `app_background`, and a different thing entirely.
    pub fn close_as_user() -> Result<bool> {
        return self.happen(events.EventKind.surface_close, 0.0, 0.0)
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
