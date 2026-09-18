package render

/// Per-window design resources. No process-wide mutable theme.
/// The macOS system colours and the *small* control size — 20pt rows, 11pt
/// text — so a window fits a lot. tools/read_apple_tokens.swift prints these
/// straight from AppKit; nothing here was eyeballed.
pub class Theme {
    dark_mode: bool = false
    background_value: int = -1
    foreground_value: int = -1
    accent_value: int = -1
    surface_value: int = -1
    font_value: f64 = 11.0
    revision: int = 0
    pub fn init() {}

    fn pick(light: int, dark: int) -> int { return if self.dark_mode { dark } else { light } }

    pub fn is_dark() -> bool { return self.dark_mode }
    pub fn set_dark(dark: bool) {
        if self.dark_mode == dark { return }
        self.dark_mode = dark
        self.revision += 1
    }

    // ----------------------------------------------------------- backgrounds
    /// The window itself. macOS keeps content flat and lets hairlines do the
    /// structural work, which is also what makes a dense window readable.
    pub fn background() -> int {
        if self.background_value >= 0 { return self.background_value }
        return self.pick(0xffffffff, 0x1e1e1eff)
    }
    pub fn card() -> int { return self.pick(0xffffffff, 0x1e1e1eff) }
    /// Behind a sidebar or a grouped panel: one step off the window.
    pub fn sunken() -> int { return self.pick(0xf4f4f4ff, 0x282828ff) }
    /// A push button or popup bezel, sampled off a real small NSButton.
    pub fn surface() -> int {
        if self.surface_value >= 0 { return self.surface_value }
        return self.pick(0xefefefff, 0x363636ff)
    }
    pub fn surface_pressed() -> int { return self.pick(0xdedeedff, 0x4a4a4aff) }
    pub fn surface_hovered() -> int { return self.pick(0xe5e5e5ff, 0x3e3e3eff) }
    /// Where text is typed. Always the text background, never the bezel.
    pub fn field() -> int { return self.pick(0xffffffff, 0x1e1e1eff) }

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
    /// Text and glyphs drawn on top of accent().
    pub fn on_accent() -> int { return 0xffffffff }

    // ---------------------------------------------------------------- accent
    pub fn accent() -> int {
        if self.accent_value >= 0 { return self.accent_value }
        return self.pick(0x007affff, 0x007affff)
    }
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
    /// The unfilled half of a switch, slider or progress track.
    pub fn track() -> int { return self.pick(0xd8d8d8ff, 0x4a4a4aff) }
    /// A switch or slider knob stays white in both appearances, as AppKit's does.
    pub fn knob() -> int { return 0xffffffff }
    /// Every other row of a table, so long rows stay trackable.
    pub fn stripe() -> int { return self.pick(0xf5f5f5ff, 0x232323ff) }

    // ------------------------------------------------------------ typography
    /// The default control font is smallSystemFontSize: 11pt, 13pt line.
    pub fn font_size() -> f64 { return self.font_value }
    pub fn large_title() -> f64 { return 22.0 }
    pub fn title1() -> f64 { return 17.0 }
    pub fn title2() -> f64 { return 15.0 }
    pub fn title3() -> f64 { return 13.0 }
    pub fn headline() -> f64 { return 11.0 }
    pub fn body() -> f64 { return 11.0 }
    pub fn callout() -> f64 { return 11.0 }
    pub fn subheadline() -> f64 { return 10.0 }
    pub fn footnote() -> f64 { return 10.0 }
    pub fn caption1() -> f64 { return 9.0 }
    pub fn caption2() -> f64 { return 9.0 }

    // ---------------------------------------------------------------- metrics
    /// SkRRect scales a corner down to half the box, so an oversized radius is
    /// a capsule at any height. Only a switch knob and a slider thumb use it.
    pub fn capsule() -> f64 { return 1000.0 }
    pub fn radius_small() -> f64 { return 3.0 }
    /// Measured off a 20pt small NSButton: 5pt.
    pub fn radius_medium() -> f64 { return 5.0 }
    pub fn radius_large() -> f64 { return 6.0 }
    pub fn control_height() -> f64 { return 20.0 }
    pub fn row_height() -> f64 { return 18.0 }
    /// AppKit ships one NSSwitch size, 54x24. Scaled to the 20pt row so it
    /// does not tower over everything beside it.
    pub fn switch_width() -> f64 { return 45.0 }
    pub fn switch_height() -> f64 { return 20.0 }
    pub fn toggle_size() -> f64 { return 14.0 }
    pub fn track_thickness() -> f64 { return 4.0 }
    pub fn thumb_size() -> f64 { return 14.0 }
    pub fn spacing() -> f64 { return 6.0 }
    pub fn margin() -> f64 { return 10.0 }
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
