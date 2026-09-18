package render

/// Per-window design resources. No process-wide mutable theme.
///
/// Every number and colour here was read off real AppKit controls on
/// macOS 26.5 (25F71) by `tools/reference/capture.sh`, in sRGB, at 4x, in both
/// appearances. `build/reference/` holds the captures and the measurements;
/// `tools/reference/README.md` says what is pinned. Nothing here was eyeballed,
/// and nothing here is a guess about a different macOS release.
pub class Theme {
    dark_mode: bool = false
    accent_value: int = -1
    background_value: int = -1
    foreground_value: int = -1
    surface_value: int = -1
    /// 0 mini, 1 small, 2 regular, 3 large. macOS calls these control sizes;
    /// they change height, radius, padding and font together, never one alone.
    size_value: int = 2
    /// macOS drains the accent out of every filled control when its window
    /// stops being the key one. Windows carry this; a standalone scene is key.
    active_value: bool = true
    font_value: f64 = -1.0
    revision: int = 0
    pub fn init() {}

    fn pick(light: int, dark: int) -> int { return if self.dark_mode { dark } else { light } }

    pub fn is_dark() -> bool { return self.dark_mode }
    pub fn is_window_active() -> bool { return self.active_value }
    pub fn set_window_active(active: bool) {
        if self.active_value == active { return }
        self.active_value = active
        self.revision += 1
    }
    pub fn set_dark(dark: bool) {
        if self.dark_mode == dark { return }
        self.dark_mode = dark
        self.revision += 1
    }

    // ------------------------------------------------------- control size
    pub fn control_size() -> int { return self.size_value }
    pub fn set_control_size(size: int) -> Result<bool> {
        if size < 0 || size > 3 { return err("control size is mini, small, regular or large", "out_of_range") }
        if self.size_value == size { return ok(true) }
        self.size_value = size
        self.revision += 1
        return ok(true)
    }
    /// One value per control size, read in the order mini, small, regular, large.
    fn by_size(mini: f64, small: f64, regular: f64, large: f64) -> f64 {
        if self.size_value == 0 { return mini }
        if self.size_value == 1 { return small }
        if self.size_value == 3 { return large }
        return regular
    }

    // ----------------------------------------------------------- backgrounds
    /// NSColor.windowBackgroundColor.
    pub fn background() -> int {
        if self.background_value >= 0 { return self.background_value }
        return self.pick(0xffffffff, 0x1e1e1eff)
    }
    /// NSColor.controlBackgroundColor: what a list or a card sits on.
    pub fn card() -> int { return self.pick(0xffffffff, 0x1e1e1eff) }
    /// NSColor.underPageBackgroundColor, opaque over the window.
    pub fn sunken() -> int { return self.pick(0xf5f5f5ff, 0x282828ff) }
    /// The push-button, popup, segmented and stepper bezel, sampled off a real
    /// control rather than taken from NSColor.control, which is translucent.
    pub fn surface() -> int {
        if self.surface_value >= 0 { return self.surface_value }
        return self.pick(0xebebebff, 0x303030ff)
    }
    pub fn surface_pressed() -> int { return self.pick(0xd4d4d4ff, 0x444444ff) }
    /// AppKit gives a push button no hover fill. Keeping the bezel steady is
    /// what makes a cortado window read as a macOS window.
    pub fn surface_hovered() -> int { return self.surface() }
    pub fn surface_disabled() -> int { return self.pick(0xf5f5f5ff, 0x262626ff) }
    /// NSColor.textBackgroundColor: where text is typed.
    pub fn field() -> int { return self.pick(0xffffffff, 0x1e1e1eff) }
    /// A disabled field keeps its background; AppKit dims the text, not the
    /// paper. Measured: a disabled NSTextField is still white.
    pub fn field_disabled() -> int { return self.field() }
    /// The hairline around a text field. Translucent, so it composites the same
    /// way AppKit's does over whatever is behind it.
    pub fn field_border() -> int { return self.pick(0x00000017, 0xffffff0a) }

    // ---------------------------------------------------------------- labels
    pub fn foreground() -> int {
        if self.foreground_value >= 0 { return self.foreground_value }
        return self.pick(0x000000d8, 0xffffffd8)
    }
    pub fn secondary_label() -> int { return self.pick(0x0000007f, 0xffffff8c) }
    pub fn tertiary_label() -> int { return self.pick(0x00000042, 0xffffff3f) }
    pub fn quaternary_label() -> int { return self.pick(0x00000019, 0xffffff19) }
    pub fn placeholder() -> int { return self.pick(0x0000007f, 0xffffff8c) }
    pub fn disabled_label() -> int { return self.pick(0x0000003f, 0xffffff3f) }
    pub fn header_label() -> int { return self.pick(0x000000d8, 0xffffffff) }
    /// Text and glyphs drawn on top of a filled accent control.
    pub fn on_accent() -> int { return 0xffffffff }
    pub fn on_accent_disabled() -> int { return self.pick(0x0000003f, 0xffffff3f) }

    // ---------------------------------------------------------------- accent
    /// NSColor.controlAccentColor. A default button and a progress fill use it
    /// exactly; the controls below use accent_control().
    pub fn accent() -> int {
        if self.accent_value >= 0 { return self.accent_value }
        return 0x007affff
    }
    /// What a switch, a slider fill and a selected segment actually paint: the
    /// accent under a 2.4% dark wash. Measured, not derived from taste.
    pub fn accent_control() -> int {
        if self.accent_value >= 0 { return Theme.shade(self.accent_value, 0.976) }
        return self.pick(0x0077f9ff, 0x067dffff)
    }
    pub fn accent_pressed() -> int {
        if self.accent_value >= 0 { return Theme.shade(self.accent_value, if self.dark_mode { 1.09 } else { 0.9 }) }
        return self.pick(0x006ee6ff, 0x1987ffff)
    }
    /// What a switch or slider fill becomes in a window that is not key.
    pub fn accent_inactive() -> int { return self.pick(0xdbdbdbff, 0x3e3e3eff) }
    /// The same for a selected segment, which AppKit drains one step further.
    pub fn selection_inactive() -> int { return self.pick(0xcdcdcdff, 0x4a4a4aff) }
    pub fn destructive() -> int { return self.pick(0xff383cff, 0xff4245ff) }
    pub fn success() -> int { return self.pick(0x34c759ff, 0x30d158ff) }
    pub fn warning() -> int { return self.pick(0xff8d28ff, 0xff9230ff) }
    pub fn link() -> int { return self.pick(0x0068daff, 0x419cffff) }

    // ------------------------------------------------- lines and selection
    pub fn separator() -> int { return self.pick(0x00000019, 0xffffff19) }
    pub fn grid() -> int { return self.pick(0xe6e6e6ff, 0x1a1a1aff) }
    pub fn selection() -> int { return self.pick(0x0064e1ff, 0x0059d1ff) }
    /// A selected row in a list that does not have focus.
    pub fn quiet_selection() -> int { return self.pick(0xdcdcdcff, 0x464646ff) }
    pub fn text_selection() -> int { return self.pick(0xb3d7ffff, 0x3f638bff) }
    /// NSColor.keyboardFocusIndicatorColor, the focus ring's own colour.
    pub fn focus_ring() -> int { return self.pick(0x0067f47f, 0x1aa9ff7f) }
    /// How far the ring sits outside the control it belongs to.
    pub fn focus_ring_width() -> f64 { return 3.0 }
    /// The unfilled half of a switch, slider or check box.
    pub fn track() -> int { return self.pick(0xe6e6e6ff, 0x343434ff) }
    pub fn track_disabled() -> int { return self.pick(0xf1f1f1ff, 0x232323ff) }
    /// A progress or level track, which is lighter than a switch track.
    pub fn bar_track() -> int { return self.pick(0xf0f0f0ff, 0x303030ff) }
    pub fn bar_track_border() -> int { return self.pick(0xdfdfdfff, 0x3a3a3aff) }
    /// A switch or slider knob. Dark mode dims it rather than going white.
    pub fn knob() -> int { return self.pick(0xffffffff, 0xe1e1e1ff) }
    /// The knob of a switch that is on, in dark mode a cool tint.
    pub fn knob_on() -> int { return self.pick(0xffffffff, 0xdaecffff) }
    pub fn knob_shadow() -> int { return self.pick(0x00000026, 0x00000040) }
    /// Every other row of a table, so long rows stay trackable.
    pub fn stripe() -> int { return self.pick(0xf4f5f5ff, 0x2a2a2aff) }

    // ------------------------------------------------------------ typography
    /// The control font: NSFont.systemFontSize(for:) — 9, 11, 13, 13.
    pub fn font_size() -> f64 {
        if self.font_value > 0.0 { return self.font_value }
        return self.by_size(9.0, 11.0, 13.0, 13.0)
    }
    /// What AppKit's layout manager gives a line at each size, so a shared line
    /// box is the same height as a native one.
    pub static fn line_height(size: f64) -> f64 {
        if size <= 9.0 { return 11.0 }
        if size <= 10.0 { return 12.0 }
        if size <= 11.0 { return 13.0 }
        if size <= 12.0 { return 15.0 }
        if size <= 13.0 { return 16.0 }
        if size <= 14.0 { return 17.0 }
        if size <= 15.0 { return 18.0 }
        if size <= 16.0 { return 18.0 }
        if size <= 17.0 { return 20.0 }
        if size <= 20.0 { return 23.0 }
        if size <= 22.0 { return 26.0 }
        if size <= 26.0 { return 30.0 }
        return size * 1.18
    }
    /// The named text styles, at the sizes NSFont.preferredFont reports.
    pub fn large_title() -> f64 { return 26.0 }
    pub fn title1() -> f64 { return 22.0 }
    pub fn title2() -> f64 { return 17.0 }
    pub fn title3() -> f64 { return 15.0 }
    pub fn headline() -> f64 { return 13.0 }
    pub fn body() -> f64 { return 13.0 }
    pub fn callout() -> f64 { return 12.0 }
    pub fn subheadline() -> f64 { return 11.0 }
    pub fn footnote() -> f64 { return 10.0 }
    pub fn caption1() -> f64 { return 10.0 }
    pub fn caption2() -> f64 { return 10.0 }
    /// Weights, as the renderer numbers them: 2 regular, 3 medium, 5 bold.
    pub fn headline_weight() -> int { return 5 }
    pub fn caption2_weight() -> int { return 3 }
    /// A selected segment draws its label at medium, the unselected ones regular.
    pub fn selected_weight() -> int { return 3 }
    pub fn regular_weight() -> int { return 2 }
    /// Apple bakes tracking into the optical size, so a UI run adds none.
    pub fn tracking() -> f64 { return 0.0 }

    // ---------------------------------------------------------------- metrics
    /// A push button, popup, segmented or text field: 16, 20, 24, 28.
    pub fn control_height() -> f64 { return self.by_size(16.0, 20.0, 24.0, 28.0) }
    /// Every bezel in the push-button family follows height/4 - 0.5, which is
    /// what the 4x captures give at all four sizes.
    pub fn control_radius() -> f64 { return Theme.radius_for(self.control_height()) }
    pub static fn radius_for(height: f64) -> f64 {
        let radius: f64 = height / 4.0 - 0.5
        return if radius < 1.0 { 1.0 } else { radius }
    }
    /// Left and right of a button title: 8, 10, 12, 14.
    pub fn control_padding() -> f64 { return self.by_size(8.0, 10.0, 12.0, 14.0) }
    /// Where a control's text baseline sits, measured down from its top.
    pub fn control_baseline() -> f64 { return self.by_size(12.0, 14.0, 17.0, 19.0) }
    /// A text field's bezel is drawn one point outside its frame on every edge.
    pub fn field_overhang() -> f64 { return 1.0 }
    pub fn field_height() -> f64 { return self.by_size(22.0, 24.0, 24.0, 24.0) }
    pub fn field_radius() -> f64 { return Theme.radius_for(self.field_height() + 2.0) }
    /// Text inset inside a field, left and right.
    pub fn field_padding() -> f64 { return self.by_size(4.0, 5.0, 6.0, 7.0) }
    pub fn field_border_width() -> f64 { return 1.0 }

    /// A check box or radio button is a square as tall as its row: 12, 14, 16.
    pub fn toggle_size() -> f64 { return self.by_size(12.0, 14.0, 16.0, 18.0) }
    pub fn toggle_radius() -> f64 { return self.by_size(3.0, 3.5, 4.5, 5.0) }
    /// Gap between a check box and its title: title x minus the box.
    pub fn toggle_gap() -> f64 { return self.by_size(4.0, 4.0, 6.0, 6.0) }
    pub fn toggle_row_height() -> f64 { return self.by_size(12.0, 14.0, 16.0, 18.0) }
    pub fn toggle_baseline() -> f64 { return self.by_size(9.5, 11.0, 13.0, 14.0) }

    /// NSSwitch: 36x16, 44x20, 54x24 at mini, small and regular.
    pub fn switch_width() -> f64 { return self.by_size(36.0, 44.0, 54.0, 54.0) }
    pub fn switch_height() -> f64 { return self.by_size(16.0, 20.0, 24.0, 24.0) }
    pub fn switch_knob_inset() -> f64 { return self.by_size(1.5, 2.0, 2.0, 2.0) }
    /// The knob is a wide capsule, not a circle: 21, 26 and 32 points across.
    pub fn switch_knob_width() -> f64 { return self.by_size(21.0, 26.0, 32.0, 32.0) }
    pub fn switch_knob_height() -> f64 { return self.switch_height() - self.switch_knob_inset() * 2.0 }

    /// A slider's knob is a circle half a point taller than the frame, so it
    /// overhangs by that much on each edge — which is what AppKit draws.
    pub fn slider_height() -> f64 { return self.by_size(12.0, 14.0, 16.0, 20.0) }
    pub fn slider_track_thickness() -> f64 { return self.by_size(4.0, 5.0, 6.0, 6.0) }
    pub fn slider_knob_size() -> f64 { return self.by_size(13.0, 15.0, 17.0, 20.0) }
    pub fn slider_overhang() -> f64 { return (self.slider_knob_size() - self.slider_height()) / 2.0 }

    /// A progress bar's frame is taller than its bar, which sits in the middle.
    pub fn bar_control_height() -> f64 { return self.by_size(12.0, 12.0, 20.0, 20.0) }
    pub fn bar_height() -> f64 { return self.by_size(6.0, 6.0, 8.0, 8.0) }
    pub fn bar_radius() -> f64 { return self.by_size(2.9, 2.9, 3.0, 3.0) }
    /// NSLevelIndicator is ten touching cells, 12 by 16, each with a hairline
    /// round it; the filled ones lose the line. The frame is two points taller
    /// than the cells, which sit at its top.
    pub fn level_height() -> f64 { return 18.0 }
    pub fn level_content_height() -> f64 { return 16.25 }
    pub fn level_cells() -> int { return 10 }
    pub fn level_cell_width() -> f64 { return 12.0 }
    pub fn level_cell_height() -> f64 { return 16.0 }
    pub fn level_cell_gap() -> f64 { return 0.0 }
    pub fn level_cell_radius() -> f64 { return 2.0 }
    pub fn level_cell_empty() -> int { return self.pick(0xedededff, 0x2a2a2aff) }
    pub fn level_cell_border() -> int { return self.pick(0xcececeff, 0x3a3a3aff) }

    pub fn stepper_width() -> f64 { return self.by_size(13.0, 17.0, 20.0, 23.0) }
    pub fn stepper_height() -> f64 { return self.by_size(20.0, 22.0, 26.0, 30.0) }
    /// The two chevrons and the rule between them, as one block.
    pub fn stepper_glyph_width() -> f64 { return self.by_size(7.5, 9.0, 11.5, 13.0) }
    pub fn stepper_glyph_height() -> f64 { return self.by_size(14.5, 16.25, 19.5, 22.5) }
    pub fn stepper_glyph_top() -> f64 { return self.by_size(3.0, 3.25, 3.5, 4.0) }
    pub fn stepper_stroke() -> f64 { return self.by_size(1.2, 1.4, 1.6, 1.8) }
    /// The two-chevron glyph on a popup button's trailing edge.
    pub fn chevron_width() -> f64 { return self.by_size(5.5, 6.0, 7.0, 8.0) }
    pub fn chevron_height() -> f64 { return self.by_size(2.6, 3.0, 3.5, 4.0) }

    /// NSTableView's own row height and header, and NSScroller's width.
    pub fn row_height() -> f64 { return self.by_size(18.0, 20.0, 24.0, 28.0) }
    pub fn header_height() -> f64 { return self.by_size(20.0, 24.0, 28.0, 28.0) }
    pub fn scroller_width() -> f64 { return self.by_size(15.0, 15.0, 17.0, 17.0) }

    /// SkRRect scales a corner down to half the box, so an oversized radius is
    /// a capsule at any height.
    pub fn capsule() -> f64 { return 1000.0 }
    pub fn radius_small() -> f64 { return self.by_size(3.0, 3.5, 4.5, 5.0) }
    pub fn radius_medium() -> f64 { return self.control_radius() }
    pub fn radius_large() -> f64 { return self.by_size(5.0, 6.0, 8.0, 9.0) }
    pub fn spacing() -> f64 { return self.by_size(4.0, 6.0, 8.0, 8.0) }
    pub fn margin() -> f64 { return self.by_size(10.0, 14.0, 20.0, 20.0) }
    pub fn hairline() -> f64 { return 1.0 }

    /// The colour as .bx markup spells it, so a view can paint itself with
    /// the same tokens its controls use: #rrggbbaa.
    pub static fn hex(value: int) -> string {
        let digits: string = "0123456789abcdef"
        var result: string = "#"
        for index: int in 0..8 {
            let shift: int = (7 - index) * 4
            let digit: int = (value >> shift) & 15
            result = "{result}{digits.slice(digit, digit + 1)}"
        }
        return result
    }

    /// Scales the three colour channels and keeps the alpha, for the one place
    /// a custom accent has to stand in for a measured pair.
    pub static fn shade(value: int, factor: f64) -> int {
        var out: int = value & 255
        for index: int in 0..3 {
            let shift: int = 8 + index * 8
            let channel: f64 = ((value >> shift) & 255) as f64 * factor
            var scaled: int = (channel + 0.5) as int
            if scaled > 255 { scaled = 255 }
            if scaled < 0 { scaled = 0 }
            out = out | (scaled << shift)
        }
        return out
    }

    pub fn version() -> int { return self.revision }
    /// Tints one role. set_colors would pin the other three to today's
    /// appearance, so an accent change alone goes through here.
    pub fn set_accent(color: int) {
        if self.accent_value == color { return }
        self.accent_value = color
        self.revision += 1
    }
    pub fn clear_accent() {
        if self.accent_value < 0 { return }
        self.accent_value = -1
        self.revision += 1
    }
    pub fn set_colors(background: int, foreground: int, accent: int, surface: int) {
        self.background_value = background
        self.foreground_value = foreground
        self.accent_value = accent
        self.surface_value = surface
        self.revision += 1
    }
    pub fn set_font_size(size: f64) -> Result<bool> {
        if !(size > 0.0 && size < 4096.0) { return err("invalid theme font size", "out_of_range") }
        self.font_value = size
        self.revision += 1
        return ok(true)
    }
}
