// A small window anchored to a control.
package surface

import cortado.host
import cortado.widgets
import cortado.platform

/// A popover.
///
/// `NSPopover` and `GtkPopover` are real controls. **Not on every platform**:
/// Windows has none — every application that has one makes a layered window,
/// gives it a shadow and captures the mouse to dismiss it, which is cortado
/// drawing a control — and UIKit's is a presentation that turns into a
/// full-screen sheet on a phone, which is a different control with a different
/// dismissal. Ask `platform.Capability.popover`, or let `of` refuse with
/// `unsupported`.
///
/// **It is not a widget.** A popover is its own window on every platform that
/// has one, which is what lets it draw outside the window that spawned it and
/// take the keyboard while it is up. It holds a widget subtree and owns where
/// that subtree goes; it has no frame the solver sets and it is nobody's
/// child.
///
/// **The caller lays the content out.** A popover has no layout of its own and
/// no platform here will size one to fit a subtree, so `of` takes the size it
/// should be and the caller solves into it. Guessing would mean measuring a
/// tree the host cannot see.
///
/// Dismissing raises `EventKind.dismiss` with the popover as the target,
/// whether the program closed it or the user clicked away — because the
/// program cannot tell those apart from outside either, and a state that only
/// updates on one of the two paths is a popover that is shut and thinks it is
/// open.
pub class Popover {
    slot: host.Handle = host.Handle.none()
    released: bool = false

    fn init(slot: host.Handle) {
        self.slot = slot
    }

    /// A popover holding `content`, at the size it should be.
    pub static fn of(content: widgets.Widget, width: f64, height: f64) -> Result<Popover> {
        if !platform.Capability.popover.available() {
            return err("this platform has no popover", "unsupported")
        }
        if width <= 0.0 || height <= 0.0 {
            return err("a popover needs a positive size, got {width} by {height}",
                       "out_of_range")
        }
        var raw: u64 = 0
        unsafe {
            raw = host.ctd_popover_new(content.handle().raw, width, height)
        }
        if raw == 0 {
            return err("this platform would not make a popover", "platform")
        }
        return ok(new Popover(host.Handle.of(raw)))
    }

    pub fn handle() -> host.Handle {
        return self.slot
    }

    /// Shows it against `anchor`, on the given edge.
    pub fn show(anchor: widgets.Widget, edge: Edge) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_popover_show(self.slot.raw, anchor.handle().raw,
                                      edge.code() as i32) as int,
                "show a popover")
        }
    }

    pub fn close() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_popover_close(self.slot.raw) as int,
                              "close a popover")
        }
    }

    pub fn is_shown() -> Result<bool> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var up: i32 = 0
        unsafe {
            let where: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_popover_shown(self.slot.raw, where) as int,
                       "read whether a popover is showing")?
            up = where.read()
        }
        return ok(up != 0)
    }

    /// Lets the popover go.
    ///
    /// The content widget is **not** released with it: the caller built that
    /// tree and may show it again, so it goes back to being an ordinary
    /// unparented widget with its own handle.
    pub fn release() -> Result<bool> {
        if self.released {
            return ok(true)
        }
        self.released = true
        unsafe {
            return host.check(host.ctd_popover_release(self.slot.raw) as int,
                              "let a popover go")
        }
    }

    fn deinit() {
        self.release()
    }
}

/// Which side of the anchor a popover appears on.
pub enum Edge {
    leading
    above
    trailing
    below

    fn code() -> int {
        return match self {
            leading => host.EDGE_MIN_X,
            above => host.EDGE_MIN_Y,
            trailing => host.EDGE_MAX_X,
            below => host.EDGE_MAX_Y,
        }
    }

    pub fn name() -> string {
        return match self {
            leading => "leading",
            above => "above",
            trailing => "trailing",
            below => "below",
        }
    }
}
