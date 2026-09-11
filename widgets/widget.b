// The control every other control extends.
package widgets

import cortado.host
import cortado.geometry

/// A native control.
///
/// Every `Widget` owns exactly one native object — an `NSButton`, an `HWND`, a
/// `GtkButton` — and releases it in `deinit`. Ownership runs one way: a
/// container holds its children as Beans references, so the Beans tree *is*
/// the lifetime tree, and a subtree dies when the last reference to its root
/// does. The platform's own view hierarchy follows along; it never owns
/// anything cortado does not.
///
/// Everything here answers `Result`. A host call can fail for reasons the
/// caller cannot see coming — the widget was released, the platform refused,
/// the property does not apply to this kind — and a method that swallowed
/// those would leave a control silently not doing what the code says.
pub abstract class Widget {
    slot: host.Handle = host.Handle.none()
    kind_value: WidgetKind = WidgetKind.container
    released: bool = false

    fn init(kind: WidgetKind) {
        self.kind_value = kind
        self.released = false
        unsafe {
            self.slot = host.Handle.of(host.ctd_widget_new(kind.code() as i32))
        }
    }

    /// The handle the host knows this widget by.
    ///
    /// Public because `cortado.surface` and `cortado.component` are separate
    /// packages and Beans has no `protected`. It is safe to hand out: a handle
    /// is an integer with no dereference, and one that has gone stale is a
    /// checked error rather than a crash.
    pub fn handle() -> host.Handle {
        return self.slot
    }

    pub fn kind() -> WidgetKind {
        return self.kind_value
    }

    /// Whether the host still has this widget. False after `release()`, and
    /// false if construction failed.
    pub fn is_alive() -> bool {
        if !self.slot.is_set() { return false }
        unsafe {
            return host.ctd_widget_alive(self.slot.raw) == 1
        }
    }

    // ---- geometry ----

    pub fn set_frame(frame: geometry.Rect) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_view_set_frame(self.slot.raw, frame.x, frame.y,
                                        frame.width, frame.height) as int,
                "position a {self.kind_value.name()}")
        }
    }

    pub fn frame() -> Result<geometry.Rect> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_view_frame(self.slot.raw, scratch.reals) as int,
                       "read the frame of a {self.kind_value.name()}")?
        }
        return ok(geometry.Rect.of(scratch.real(0), scratch.real(1),
                                   scratch.real(2), scratch.real(3)))
    }

    /// How big this control wants to be inside `available`.
    ///
    /// A negative component of `available` means unbounded in that direction.
    /// This is the layout engine's one call into the platform: text metrics
    /// are the only thing cortado cannot compute for itself.
    pub fn measure(available: geometry.Size) -> Result<geometry.Size> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_view_measure(self.slot.raw, available.width,
                                             available.height, scratch.reals) as int,
                       "measure a {self.kind_value.name()}")?
        }
        return ok(geometry.Size.of(scratch.real(0), scratch.real(1)))
    }

    // ---- state ----

    pub fn set_enabled(on: bool) -> Result<bool> {
        return self.set_flag(host.P_ENABLED, on, "enable a {self.kind_value.name()}")
    }

    pub fn is_enabled() -> Result<bool> {
        return self.read_flag(host.P_ENABLED, "read whether a {self.kind_value.name()} is enabled")
    }

    pub fn set_hidden(on: bool) -> Result<bool> {
        return self.set_flag(host.P_HIDDEN, on, "hide a {self.kind_value.name()}")
    }

    pub fn is_hidden() -> Result<bool> {
        return self.read_flag(host.P_HIDDEN, "read whether a {self.kind_value.name()} is hidden")
    }

    fn set_flag(key: int, on: bool, attempt: string) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_set_int(self.slot.raw, key as i32,
                                 if on { 1 } else { 0 }) as int,
                attempt)
        }
    }

    fn read_flag(key: int, attempt: string) -> Result<bool> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_get_int(self.slot.raw, key as i32, scratch.ints) as int,
                       attempt)?
        }
        return ok(scratch.integer() != 0)
    }

    // Text lives on the base because three kinds carry it and the host keys it
    // by widget, not by class. Subclasses expose it under the name their
    // control actually uses: a button has a title, a field has a value.
    fn set_text_raw(text: string) -> Result<bool> {
        let buffer: Bytes = host.HostText.encode(text)
        unsafe {
            return host.check(
                host.ctd_set_text(self.slot.raw, host.HostText.pointer(buffer),
                                  buffer.len() as i32) as int,
                "set the text of a {self.kind_value.name()}")
        }
    }

    fn text_raw() -> Result<string> {
        let raw: u64 = self.slot.raw
        return host.HostText.read(
            "read the text of a {self.kind_value.name()}",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_get_text(raw, out, cap) }
            })
    }

    // ---- introspection ----

    /// The platform's own class name for this control — `NSButton`, `Button`,
    /// `GtkButton`. The test suite golden-files it, because it is the only
    /// answer that proves a real native control was built and not a stand-in.
    pub fn native_class() -> Result<string> {
        let raw: u64 = self.slot.raw
        return host.HostText.read(
            "read the native class of a {self.kind_value.name()}",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_native_class(raw, out, cap) }
            })
    }

    /// The accessibility role, in one vocabulary shared by every platform.
    pub fn a11y_role() -> Result<string> {
        let raw: u64 = self.slot.raw
        return host.HostText.read(
            "read the accessibility role of a {self.kind_value.name()}",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_a11y_role(raw, out, cap) }
            })
    }

    /// How many children the platform says this widget has.
    ///
    /// cortado keeps its own child list, and these two numbers must agree.
    /// They are read separately and compared on purpose: the Beans list is
    /// bookkeeping, and bookkeeping that is never checked against the thing it
    /// describes is how a tree ends up correct on paper and wrong on screen.
    pub fn native_child_count() -> Result<int> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var count: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_view_child_count(self.slot.raw, slot) as int,
                       "count the children of a {self.kind_value.name()}")?
            count = slot.read()
        }
        return ok(count as int)
    }

    /// The n-th child, as the platform has it. Answers `none` past the end.
    pub fn native_child_at(index: int) -> Option<host.Handle> {
        unsafe {
            let found: u64 = host.ctd_view_child_at(self.slot.raw, index as i32)
            if found == 0 {
                return none
            }
            return some(host.Handle.of(found))
        }
    }

    /// The widget this one sits inside, as the platform has it.
    pub fn native_parent() -> Option<host.Handle> {
        unsafe {
            let found: u64 = host.ctd_view_parent(self.slot.raw)
            if found == 0 {
                return none
            }
            return some(host.Handle.of(found))
        }
    }

    /// What kind the platform thinks this widget is.
    ///
    /// cortado already knows — it asked for the kind when it built the widget.
    /// Asking again and comparing is what turns "the handle table is correct"
    /// from an assumption into something the test suite checks.
    pub fn native_kind() -> Option<WidgetKind> {
        unsafe {
            return WidgetKind.of(host.ctd_widget_kind(self.slot.raw) as int)
        }
    }

    pub fn set_font_size(points: f64) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_set_real(self.slot.raw, host.P_FONT_SIZE as i32, points) as int,
                "set the font size of a {self.kind_value.name()}")
        }
    }

    pub fn font_size() -> Result<f64> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_get_real(self.slot.raw, host.P_FONT_SIZE as i32,
                                         scratch.reals) as int,
                       "read the font size of a {self.kind_value.name()}")?
        }
        return ok(scratch.real(0))
    }

    /// The children this widget contains. Empty for everything that is not a
    /// container, so a tree walk needs no downcast and no kind check.
    pub fn children() -> List<Widget> {
        return []
    }

    /// The text this control shows, or "" for one that shows none.
    ///
    /// Overridden rather than downcast to: a dump that asked "is this a
    /// Button?" would need editing every time a kind was added, and would
    /// silently print nothing for the one somebody forgot.
    pub fn display_text() -> Result<string> {
        return ok("")
    }

    /// One line describing this widget: what cortado calls it, what the
    /// platform calls it, how assistive technology sees it, its text, its
    /// frame, and whatever state is not at its default.
    ///
    /// This is the line the test goldens carry, and it is deliberately built
    /// here in Beans rather than in the host. If the host formatted it, the
    /// interpreter and a native build would call the same compiled function
    /// and print identical bytes even with the whole foreign-function layer
    /// broken — the comparison would prove nothing. Built here, matching
    /// output means both backends classified every signature, read every
    /// out-pointer and marshalled every string the same way.
    pub fn describe() -> Result<string> {
        let native: string = self.native_class()?
        let role: string = self.a11y_role()?
        let text: string = self.display_text()?
        let frame: geometry.Rect = self.frame()?
        var line: string = "{self.kind_value.name()} {native} role={role} \"{text}\" frame={frame.show()}"
        // Only a widget that actually has the state reports it. A container
        // has no enabled flag at all, and printing a default for it would say
        // something false about every container in every golden file.
        match self.is_enabled() {
            ok(enabled) => { if !enabled { line = "{line} disabled" } }
            err(absent) => {}
        }
        match self.is_hidden() {
            ok(hidden) => { if hidden { line = "{line} hidden" } }
            err(absent) => {}
        }
        return ok(line)
    }

    /// Sends this control's action the way a real click does — through the
    /// platform's own target/action dispatch, not by calling a handler
    /// directly. Public API, and how every event test drives the framework.
    pub fn activate() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_widget_activate(self.slot.raw) as int,
                              "activate a {self.kind_value.name()}")
        }
    }

    // ---- teardown ----

    /// Releases the native control now, rather than when the last reference
    /// goes. Safe to call twice.
    pub fn release() {
        if self.released || !self.slot.is_set() {
            return
        }
        self.released = true
        unsafe {
            host.ctd_widget_release(self.slot.raw)
        }
    }

    fn deinit() {
        self.release()
    }
}
