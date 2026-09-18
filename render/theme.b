package render

/// Per-window design resources. No process-wide mutable theme.
/// Colours and metrics are the iOS 26 system values, read off UIKit rather
/// than copied from a description; tools/read_apple_tokens.swift regenerates them.
pub class Theme {
    dark_mode: bool = false
    background_value: int = -1
    foreground_value: int = -1
    accent_value: int = -1
    surface_value: int = -1
    font_value: f64 = 17.0
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
    pub fn background() -> int {
        if self.background_value >= 0 { return self.background_value }
        return self.pick(0xffffffff, 0x000000ff)
    }
    pub fn secondary_background() -> int { return self.pick(0xf2f2f7ff, 0x1c1c1eff) }
    pub fn tertiary_background() -> int { return self.pick(0xffffffff, 0x2c2c2eff) }
    pub fn grouped_background() -> int { return self.pick(0xf2f2f7ff, 0x000000ff) }
    /// The resting fill of a control bezel. Opaque so a template can nest it.
    pub fn surface() -> int {
        if self.surface_value >= 0 { return self.surface_value }
        return self.pick(0xe9e9ebff, 0x2c2c2eff)
    }
    pub fn surface_pressed() -> int { return self.pick(0xd1d1d6ff, 0x3a3a3cff) }
    pub fn surface_hovered() -> int { return self.pick(0xf2f2f7ff, 0x3a3a3cff) }

    // ---------------------------------------------------------------- labels
    pub fn foreground() -> int {
        if self.foreground_value >= 0 { return self.foreground_value }
        return self.pick(0x000000ff, 0xffffffff)
    }
    pub fn secondary_label() -> int { return self.pick(0x3c3c4399, 0xebebf599) }
    pub fn tertiary_label() -> int { return self.pick(0x3c3c434c, 0xebebf54c) }
    pub fn quaternary_label() -> int { return self.pick(0x3c3c432d, 0xebebf528) }
    pub fn placeholder() -> int { return self.tertiary_label() }
    /// Text and glyphs drawn on top of accent().
    pub fn on_accent() -> int { return 0xffffffff }

    // ---------------------------------------------------------------- accent
    pub fn accent() -> int {
        if self.accent_value >= 0 { return self.accent_value }
        return self.pick(0x0088ffff, 0x0091ffff)
    }
    pub fn destructive() -> int { return self.pick(0xff383cff, 0xff4245ff) }
    pub fn success() -> int { return self.pick(0x34c759ff, 0x30d158ff) }
    pub fn warning() -> int { return self.pick(0xff8d28ff, 0xff9230ff) }

    // ------------------------------------------------------ separators, fills
    pub fn separator() -> int { return self.pick(0x3c3c431f, 0x54545880) }
    pub fn opaque_separator() -> int { return self.pick(0xc6c6c8ff, 0x38383aff) }
    pub fn fill() -> int { return self.pick(0x78788033, 0x7878805c) }
    pub fn secondary_fill() -> int { return self.pick(0x78788029, 0x78788052) }
    pub fn tertiary_fill() -> int { return self.pick(0x7676801f, 0x7676803d) }
    pub fn quaternary_fill() -> int { return self.pick(0x74748014, 0x7676802e) }
    /// The unfilled half of a switch, slider or progress track. Opaque.
    pub fn track() -> int { return self.pick(0xe9e9eaff, 0x39393dff) }
    /// A switch or slider knob stays white in both appearances, as UIKit's does.
    pub fn knob() -> int { return 0xffffffff }
    /// A card raised off grouped_background(): secondarySystemGroupedBackground.
    pub fn card() -> int { return self.pick(0xffffffff, 0x1c1c1eff) }

    // ------------------------------------------------------------------ grays
    pub fn gray() -> int { return self.pick(0x8e8e93ff, 0x8e8e93ff) }
    pub fn gray2() -> int { return self.pick(0xaeaeb2ff, 0x636366ff) }
    pub fn gray3() -> int { return self.pick(0xc7c7ccff, 0x48484aff) }
    pub fn gray4() -> int { return self.pick(0xd1d1d6ff, 0x3a3a3cff) }
    pub fn gray5() -> int { return self.pick(0xe5e5eaff, 0x2c2c2eff) }
    pub fn gray6() -> int { return self.pick(0xf2f2f7ff, 0x1c1c1eff) }

    // ------------------------------------------------------------ typography
    pub fn font_size() -> f64 { return self.font_value }
    pub fn large_title() -> f64 { return 34.0 }
    pub fn title1() -> f64 { return 28.0 }
    pub fn title2() -> f64 { return 22.0 }
    pub fn title3() -> f64 { return 20.0 }
    pub fn headline() -> f64 { return 17.0 }
    pub fn body() -> f64 { return 17.0 }
    pub fn callout() -> f64 { return 16.0 }
    pub fn subheadline() -> f64 { return 15.0 }
    pub fn footnote() -> f64 { return 13.0 }
    pub fn caption1() -> f64 { return 12.0 }
    pub fn caption2() -> f64 { return 11.0 }

    // ---------------------------------------------------------------- metrics
    /// iOS 26 draws buttons and switches as capsules. SkRRect scales a corner
    /// down to half the box, so an oversized radius is a capsule at any height.
    pub fn capsule() -> f64 { return 1000.0 }
    pub fn radius_small() -> f64 { return 6.0 }
    pub fn radius_medium() -> f64 { return 10.0 }
    pub fn radius_large() -> f64 { return 14.0 }
    pub fn control_height() -> f64 { return 34.0 }
    pub fn switch_width() -> f64 { return 61.0 }
    pub fn switch_height() -> f64 { return 28.0 }
    pub fn toggle_size() -> f64 { return 22.0 }
    pub fn track_thickness() -> f64 { return 4.0 }
    pub fn thumb_size() -> f64 { return 28.0 }
    pub fn spacing() -> f64 { return 8.0 }
    pub fn margin() -> f64 { return 16.0 }
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
