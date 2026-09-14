// The control every other control extends.
package widgets

import cortado.host
import cortado.geometry
import cortado.events

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

    // ---- how a control is dressed ----
    // Which controls refuse a background is `ctd_kind_has_background`, read off
    // a screen. Corners and borders have no rule: every control takes both.

    /// The colour behind this control's own drawing.
    ///
    /// Refused by name on the four bezelled text controls: the only way to
    /// show a colour there is to remove the bezel, and then it is not the
    /// platform's text field. See `ctd_kind_has_background`.
    pub fn set_background(shade: Rgba) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_set_int(self.slot.raw, host.P_BG_COLOR as i32,
                                 ColorWell.pack(shade) as i64) as int,
                "give a {self.kind_value.name()} a background")
        }
    }

    pub fn background() -> Result<Rgba> {
        let packed: int = self.read_property(host.P_BG_COLOR)?
        return ok(ColorWell.unpack(packed))
    }

    /// The colour of this control's own text.
    ///
    /// Carried by a label and the four controls you type into, and refused by
    /// name on everything else. A button, a check box and a radio button draw
    /// their words as a title inside the platform's bezel — three mechanisms
    /// with one name — and a link's colour is the system's. See
    /// `ctd_kind_has_fg_color`.
    ///
    /// Without this `set_background` was half a property: a pale background
    /// behind a label and no way to stop the system drawing white on it.
    pub fn set_text_color(shade: Rgba) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_set_int(self.slot.raw, host.P_FG_COLOR as i32,
                                 ColorWell.pack(shade) as i64) as int,
                "give a {self.kind_value.name()} a text colour")
        }
    }

    pub fn text_color() -> Result<Rgba> {
        let packed: int = self.read_property(host.P_FG_COLOR)?
        return ok(ColorWell.unpack(packed))
    }

    /// Corner rounding in points. Zero is square.
    pub fn set_corner_radius(points: f64) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_set_real(self.slot.raw, host.P_CORNER_RADIUS as i32, points) as int,
                "round the corners of a {self.kind_value.name()}")
        }
    }

    pub fn corner_radius() -> Result<f64> {
        return self.read_real(host.P_CORNER_RADIUS,
                              "read the corner radius of a {self.kind_value.name()}")
    }

    /// An outline drawn inside the bounds, like CALayer and CSS: an outside
    /// one needs room the layout never gave it.
    pub fn set_border(points: f64, shade: Rgba) -> Result<bool> {
        self.set_property(host.P_BORDER_COLOR, ColorWell.pack(shade))?
        unsafe {
            return host.check(
                host.ctd_set_real(self.slot.raw, host.P_BORDER_WIDTH as i32, points) as int,
                "put a border on a {self.kind_value.name()}")
        }
    }

    pub fn border_width() -> Result<f64> {
        return self.read_real(host.P_BORDER_WIDTH,
                              "read the border width of a {self.kind_value.name()}")
    }

    // ---- a control a program draws itself ----

    /// Whether this control can take the keyboard.
    ///
    /// A canvas and nothing else: every other control's answer is the
    /// platform's. Off by default, so a decorative canvas stays out of the way.
    pub fn set_focusable(on: bool) -> Result<bool> {
        return self.set_flag(host.P_FOCUSABLE, on,
                             "let a {self.kind_value.name()} take the keyboard")
    }

    pub fn is_focusable() -> Result<bool> {
        return self.read_flag(host.P_FOCUSABLE,
                              "read whether a {self.kind_value.name()} takes the keyboard")
    }

    /// What a screen reader calls this control when its own text is not it —
    /// an icon-only button, or a canvas, which draws no text cortado wrote.
    ///
    /// Carried by every kind. Reading it back answers **what a screen reader
    /// will say** — the label when one was set, and the control's own text
    /// when none was — so `""` means genuinely silent rather than merely
    /// unnamed.
    pub fn set_a11y_label(said: string) -> Result<bool> {
        return self.set_string(host.S_A11Y_LABEL, said,
                               "name a {self.kind_value.name()} for a screen reader")
    }

    pub fn a11y_label() -> Result<string> {
        return self.string_at(host.S_A11Y_LABEL,
                              "read what a {self.kind_value.name()} is called")
    }

    /// What kind of thing a canvas is, to a screen reader. See `A11yRole`.
    pub fn set_a11y_role(role: A11yRole) -> Result<bool> {
        return self.set_property(host.P_A11Y_ROLE, role.code())
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

    /// Writes one of a control's other strings by its `host.S_*` id.
    ///
    /// Public for the reason `set_property` is: a test that asks what a *kind*
    /// answers has no named accessor to reach for, and the applier writes by
    /// id. Application code wants the named one — `field.set_hint(...)` says
    /// what it means.
    pub fn set_string_at(key: int, text: string) -> Result<bool> {
        return self.set_string(key, text, "set string {key} of a {self.kind_value.name()}")
    }

    pub fn string_at_key(key: int) -> Result<string> {
        return self.string_at(key, "read string {key} of a {self.kind_value.name()}")
    }

    /// Writes one of a control's *other* strings by its `host.S_*` id.
    ///
    /// `set_text_raw` is the text a control **is** — a button's title, a
    /// field's value. A control can carry more than one: a field has words it
    /// shows while it is empty. Those are keyed, for the same reason the
    /// scalar properties are, and each subclass exposes the ones it has under
    /// a name that says what they mean.
    fn set_string(key: int, text: string, attempt: string) -> Result<bool> {
        let buffer: Bytes = host.HostText.encode(text, attempt)?
        unsafe {
            return host.check(
                host.ctd_set_string(self.slot.raw, key as i32,
                                    host.HostText.pointer(buffer),
                                    buffer.len() as i32) as int,
                attempt)
        }
    }

    fn string_at(key: int, attempt: string) -> Result<string> {
        let raw: u64 = self.slot.raw
        return host.HostText.read(attempt, fn(out: RawPtr<i8>, cap: i32) -> i32 {
            unsafe { return host.ctd_get_string(raw, key as i32, out, cap) }
        })
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
    /// How much of this control's frame the platform keeps for itself.
    ///
    /// Four zeros for almost everything. The exceptions are the containers a
    /// platform draws chrome for — a group box's border and title band, a
    /// disclosure's header — whose children live inside a view the platform
    /// positions. What the chrome takes from the caller is *room*: the
    /// children's own coordinates already start at that view's corner, so
    /// nothing here moves them.
    ///
    /// `WidgetLayout.group` asks this once per container when the tree is
    /// built. A caller building frames by hand wants it too, and that is why
    /// it is public.
    pub fn content_inset() -> Result<geometry.EdgeInsets> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_view_content_inset(self.slot.raw, scratch.reals) as int,
                       "read what {self.kind_value.name()} keeps for its own chrome")?
        }
        return ok(geometry.EdgeInsets { left: scratch.real(0), top: scratch.real(1),
                                        right: scratch.real(2), bottom: scratch.real(3) })
    }

    /// How big the area this control scrolls over is.
    ///
    /// A scroll view's frame is its viewport; this is the thing behind it.
    /// Refused on any other control, which scrolls nothing cortado laid out.
    pub fn set_content_size(size: geometry.Size) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_view_set_content_size(self.slot.raw, size.width, size.height) as int,
                "set the scrolled size of a {self.kind_value.name()}")
        }
    }

    pub fn content_size() -> Result<geometry.Size> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_view_content_size(self.slot.raw, scratch.reals) as int,
                       "read the scrolled size of a {self.kind_value.name()}")?
        }
        return ok(geometry.Size.of(scratch.real(0), scratch.real(1)))
    }

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

    // ---- the keyboard ----

    /// Points the keyboard at this control.
    ///
    /// Unlike every other write in cortado this one is **not silent**, and the
    /// reason is that focus is not a control's private state: it is one thing
    /// the whole window shares, so a program that moved it has by definition
    /// changed what every other control shows. Whatever had it hears `blur`
    /// and this one hears `focus`.
    ///
    /// Refused as `unsupported` by a control that cannot take the keyboard at
    /// all, and **which controls those are is a real platform difference, not
    /// a gap**: a label refuses everywhere, and a button takes it on a desktop
    /// and refuses on a phone, where there is no Tab key to reach it with and
    /// no focus ring to show it. A program asks rather than assuming.
    pub fn focus() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_widget_focus(self.slot.raw) as int,
                              "point the keyboard at a {self.kind_value.name()}")
        }
    }

    /// Whether this is the control its window would type into.
    ///
    /// Not "the control the user is typing into": the second needs the window
    /// to be on screen and in front, which makes it a fact about the desktop
    /// rather than about the program — and unanswerable in a headless run.
    pub fn focused() -> bool {
        unsafe {
            return host.ctd_widget_focused(self.slot.raw) != 0
        }
    }

    // ---- driving it the way a user would ----

    /// Clicks, releases or moves the pointer over this control.
    ///
    /// `where` is in the control's own space — the same space `set_frame` uses
    /// — so a caller that knows where a control is knows where to click it.
    ///
    /// **What this proves differs by platform, and the difference is worth
    /// knowing before writing a test around it.** On macOS and Windows it is a
    /// real event through the platform's own dispatch, the same road a mouse
    /// travels. GTK4 and UIKit have no public way to build an event at all, so
    /// there it runs cortado's own handler — one step short of the platform.
    pub fn point_as_user(kind: events.EventKind, where: geometry.Point,
                         button: events.PointerButton) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_widget_synth_pointer(self.slot.raw, kind.name_code() as i32,
                                              where.x, where.y,
                                              button.code() as i32) as int,
                "drive the pointer over a {self.kind_value.name()}")
        }
    }

    /// A press and a release in the same place, which is what a click is.
    pub fn click_as_user(where: geometry.Point) -> Result<bool> {
        self.point_as_user(events.EventKind.pointer_down, where,
                           events.PointerButton.left)?
        return self.point_as_user(events.EventKind.pointer_up, where,
                                  events.PointerButton.left)
    }

    /// Presses or releases a key at this control.
    ///
    /// The control is given the keyboard first if it does not have it, and the
    /// call is refused the same way `focus` would be if it cannot take it —
    /// because driving a key at a control the keyboard is not pointing at is
    /// testing something a user could not do.
    ///
    /// `typed` is what the key produced, which is empty for every key that
    /// produces nothing and is the whole news for `Key.character`.
    pub fn key_as_user(kind: events.EventKind, key: events.Key, typed: string,
                       modifiers: int) -> Result<bool> {
        let buffer: Bytes = host.HostText.encode(typed, "type at a {self.kind_value.name()}")?
        unsafe {
            return host.check(
                host.ctd_widget_synth_key(self.slot.raw, kind.name_code() as i32,
                                          key.code() as i32,
                                          host.HostText.pointer(buffer),
                                          buffer.len() as i32,
                                          modifiers as u32) as int,
                "type at a {self.kind_value.name()}")
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
