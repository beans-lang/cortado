// The top-level thing a widget tree lives in.
package surface

import cortado.host
import cortado.geometry
import cortado.widgets

/// A place to put a widget tree.
///
/// On a desktop this is a window. On iOS it is a scene, on Android the content
/// view of an activity. The name avoids "window" on purpose: a phone has no
/// window to move, resize or close, and an API that assumed one would have to
/// be unlearned at the first mobile port rather than merely extended.
///
/// What is common to all five is what lives here: a title, a root widget, a
/// content size. What is not — showing, closing, being one of several — sits
/// on `Window`, behind `platform.Capability`.
pub abstract class Surface {
    slot: host.Handle = host.Handle.none()
    root: Option<widgets.Widget> = none
    closed: bool = false

    fn init(size: geometry.Size) {
        self.closed = false
        unsafe {
            self.slot = host.Handle.of(host.ctd_surface_new(size.width, size.height))
        }
    }

    pub fn handle() -> host.Handle {
        return self.slot
    }

    pub fn set_title(title: string) -> Result<bool> {
        let buffer: Bytes = host.HostText.encode(title, "title a window")?
        unsafe {
            return host.check(
                host.ctd_surface_set_title(self.slot.raw,
                                           host.HostText.pointer(buffer),
                                           buffer.len() as i32) as int,
                "set a surface title")
        }
    }

    pub fn title() -> Result<string> {
        let raw: u64 = self.slot.raw
        return host.HostText.read("read a surface title",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_surface_title(raw, out, cap) }
            })
    }

    /// Puts `widget` in the surface, replacing whatever was there.
    ///
    /// The surface keeps a reference, so the tree outlives the call. The root
    /// is sized to the content area; everything below it is positioned by the
    /// layout pass.
    pub fn set_root(widget: widgets.Widget) -> Result<bool> {
        unsafe {
            host.check(host.ctd_surface_set_root(self.slot.raw,
                                                 widget.handle().raw) as int,
                       "put a widget tree in a surface")?
        }
        self.root = some(widget)
        match self.native_root() {
            some(installed) => {
                if installed.raw != widget.handle().raw {
                    return err("the surface accepted a root widget and kept a different one",
                               "tree_drift")
                }
            }
            none => {
                return err("the surface accepted a root widget and kept none",
                           "tree_drift")
            }
        }
        return ok(true)
    }

    pub fn root_widget() -> Option<widgets.Widget> {
        return self.root
    }

    /// The root as the platform has it. `set_root` is checked against this, so
    /// a surface that accepted a tree and then dropped it cannot pass quietly.
    pub fn native_root() -> Option<host.Handle> {
        unsafe {
            let found: u64 = host.ctd_surface_root(self.slot.raw)
            if found == 0 {
                return none
            }
            return some(host.Handle.of(found))
        }
    }

    /// The area a widget tree may use, in points. Never includes a title bar.
    /// The backing-store scale of the display this surface is on — 1 on a
    /// standard display, 2 on a Retina one.
    ///
    /// Hand it to `layout.Solver.set_scale` so frames land on whole device
    /// pixels. A surface that has not been shown answers the main display's
    /// scale, which is what it will get when it appears.
    pub fn scale() -> Result<f64> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_surface_scale(self.slot.raw, scratch.reals) as int,
                       "read a surface's scale")?
        }
        return ok(scratch.real(0))
    }

    pub fn content_size() -> Result<geometry.Size> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_surface_content_size(self.slot.raw, scratch.reals) as int,
                       "read a surface content size")?
        }
        return ok(geometry.Size.of(scratch.real(0), scratch.real(1)))
    }

    /// Attaches a row of commands to this surface, described by a `Menu`.
    ///
    /// The same handle and the same tokens as the menu bar, which is the whole
    /// point: a command that is in both places is one command, and disabling
    /// it through `Menu.set_enabled` disables it in both. Choosing it from
    /// either raises `EventKind.command` carrying the token.
    ///
    /// Where the row goes is the platform's business and differs — AppKit puts
    /// it in the title bar, GTK a header bar in place of one, Windows a strip
    /// inside the frame. The last one takes room from the window, and says so
    /// through `content_size`, so a layout never has to know.
    ///
    /// Refused with `unsupported` where `Capability.toolbar` answers no.
    pub fn set_toolbar(bar: Menu) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_toolbar_set(self.handle().raw, bar.handle().raw) as int,
                "attach a toolbar")
        }
    }

    pub fn clear_toolbar() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_toolbar_clear(self.handle().raw) as int,
                              "take a toolbar away")
        }
    }

    /// How many items the toolbar ended up showing.
    ///
    /// Not always the menu's count: a submenu is not a toolbar item on any
    /// platform here, and a separator is one on some and not others. A caller
    /// that wanted the menu's count should ask the menu.
    pub fn toolbar_count() -> Result<int> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var count: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_toolbar_count(self.handle().raw, slot) as int,
                       "count a toolbar's items")?
            count = slot.read()
        }
        return ok(count as int)
    }
}
