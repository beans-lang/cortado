// The control every other control extends.
package widgets

import cortado.host
import cortado.geometry

/// A control's text with its line breaks and tabs escaped, so one widget
/// occupies exactly one line of a dump.
fn one_line(text: string) -> string {
    return text.replace("\\", "\\\\")
               .replace("\n", "\\n")
               .replace("\r", "\\r")
               .replace("\t", "\\t")
}

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

    /// The pixels this control painted.
    ///
    /// Two calls, the same shape every reader in this ABI uses: the first
    /// learns the size, the second fills a buffer that size. A control that is
    /// hidden or has no size paints nothing and says so.
    ///
    /// `CTD_ERR_UNSUPPORTED` where the platform has no way to read a widget
    /// back — ask `Application.can(Capability.snapshot)` first rather than
    /// finding out here.
    pub fn snapshot() -> Result<Snapshot> {
        let slot: host.Handle = self.slot
        return Snapshot.read("snapshot a {self.kind_value.name()}",
                             fn(size: RawPtr<f64>, out: RawPtr<i8>, cap: i32) -> i32 {
            unsafe {
                return host.ctd_snapshot(slot.raw, size, out, cap)
            }
        })
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

    /// How opaque this control is, 0.0 to 1.0.
    ///
    /// Every kind has one, containers included: unlike `enabled` this really is
    /// a property of any view, and fading a box fades everything in it, which
    /// is what a caller means by it and what all four platforms already do.
    ///
    /// Out of range is a refusal rather than a clamp. A caller that computed
    /// 1.5 has a bug, and quietly showing them 1.0 hides it.
    pub fn set_opacity(value: f64) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_set_real(self.slot.raw, host.P_OPACITY as i32, value) as int,
                "set the opacity of a {self.kind_value.name()}")
        }
    }

    pub fn opacity() -> Result<f64> {
        return self.read_real(host.P_OPACITY,
                              "read the opacity of a {self.kind_value.name()}")
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

    /// Reads one real-valued property by its `host.P_*` id.
    ///
    /// Package-private: the subclass that has the property exposes it under a
    /// name that says what it is — a slider's `value`, a progress bar's — and
    /// the generic form is for them and for the applier.
    fn read_real(key: int, attempt: string) -> Result<f64> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_get_real(self.slot.raw, key as i32, scratch.reals) as int,
                       attempt)?
        }
        return ok(scratch.real(0))
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
        let buffer: Bytes = host.HostText.encode(text, "set the text of a {self.kind_value.name()}")?
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

    // ---- the platform's own child list ----
    //
    // Two controls hold children — a `Container` and a `ScrollView` — and both
    // keep a Beans list beside the platform's. The three calls that keep the
    // two in step live here rather than being written twice, because a fix to
    // one copy and not the other is exactly the drift the tree dump exists to
    // catch.

    fn attach_child(child: Widget, index: int) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_view_add_child(self.slot.raw,
                                                      child.handle().raw,
                                                      index as i32) as int,
                              "add a {child.kind().name()} to a {self.kind_value.name()}")
        }
    }

    fn detach_child(child: Widget) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_view_remove_child(self.slot.raw,
                                                         child.handle().raw) as int,
                              "remove a {child.kind().name()} from a {self.kind_value.name()}")
        }
    }

    fn reorder_child(from: int, to: int) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_view_move_child(self.slot.raw,
                                                       from as i32, to as i32) as int,
                              "reorder the children of a {self.kind_value.name()}")
        }
    }

    // ---- generic property access ----
    //
    // The component layer applies a render's result by property id, because
    // the differ compares integers and a translation back to method names
    // would put a string table in the hot path of every frame. Application
    // code should reach for the named methods above and the ones each subclass
    // adds — `set_enabled`, `Button.set_title` — which say what they do.

    /// Writes the text this control shows, whatever the control calls it.
    pub fn set_display_text(text: string) -> Result<bool> {
        return self.set_text_raw(text)
    }

    /// Writes one integer property by its `host.P_*` id.
    pub fn set_property(property: int, value: int) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_set_int(self.slot.raw, property as i32, value as i64) as int,
                "set property {property} of a {self.kind_value.name()}")
        }
    }

    /// Reads one integer property back by its `host.P_*` id.
    ///
    /// The counterpart of `set_property`, and public for the same reason: the
    /// applier writes attributes by id, and a test that asks what a *kind*
    /// answers has no named accessor to reach for — a `Label` has no
    /// `is_checked()` and should not grow one just to be refused.
    ///
    /// Application code wants the named accessor. `check_box.state()` says
    /// what it reads and returns a `CheckState`; this returns an integer whose
    /// meaning is in a C header.
    pub fn read_property(property: int) -> Result<int> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_get_int(self.slot.raw, property as i32, scratch.ints) as int,
                       "read property {property} of a {self.kind_value.name()}")?
        }
        return ok(scratch.integer() as int)
    }

    /// Reads one real-valued property back by its `host.P_*` id.
    ///
    /// Public for the same reason `read_property` is: a test that asks what a
    /// *kind* answers has no named accessor to reach for. Application code
    /// wants `slider.value()`, which says what it reads.
    pub fn read_property_real(property: int) -> Result<f64> {
        return self.read_real(property, "read property {property} of a {self.kind_value.name()}")
    }

    /// Writes one real-valued property by its `host.P_*` id.
    pub fn set_property_real(property: int, value: f64) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_set_real(self.slot.raw, property as i32, value) as int,
                "set property {property} of a {self.kind_value.name()}")
        }
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
        // Escaped, because a text area's text has newlines in it and one
        // widget has to be one line: a dump whose rows depend on the content
        // of a control cannot be read down a column, and a diff of it points
        // at the wrong row.
        let text: string = one_line(self.display_text()?)
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
    ///
    /// Not usable on every control, and the reason is worth knowing: clicking
    /// a combo box opens its menu and runs a modal tracking loop, so this
    /// never returns for one. Use `set_value_as_user` for anything that
    /// carries a value.
    pub fn activate() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_widget_activate(self.slot.raw) as int,
                              "activate a {self.kind_value.name()}")
        }
    }

    /// Moves this control's value the way a user would, and raises the event
    /// that follows.
    ///
    /// The setters above change a control **silently**, and that is
    /// deliberate: a program that writes a value should not hear about its own
    /// write, or a render would feed itself and never settle. This is the
    /// other half — what a test uses to drive a control, and what an
    /// application uses to replay input.
    ///
    /// `index` chooses for a control with a list and is the new state for a
    /// check box; `value` is the position of a slider.
    pub fn set_value_as_user(index: int, value: f64) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_widget_synth_value(self.slot.raw, index as i64, value) as int,
                "drive the value of a {self.kind_value.name()}")
        }
    }

    /// Types text into this control the way a user would, and raises the
    /// commit event that follows.
    pub fn set_text_as_user(text: string) -> Result<bool> {
        let buffer: Bytes = host.HostText.encode(text, "type into a {self.kind_value.name()}")?
        unsafe {
            return host.check(
                host.ctd_widget_synth_text(self.slot.raw, host.HostText.pointer(buffer),
                                           buffer.len() as i32) as int,
                "type into a {self.kind_value.name()}")
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
