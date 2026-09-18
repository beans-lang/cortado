package render

/// Per-window design resources. No process-wide mutable theme.
pub class Theme {
    background_value: int = 0xf7f7f9ff
    foreground_value: int = 0x202128ff
    accent_value: int = 0x365eeaff
    surface_value: int = 0xe8eaf0ff
    font_value: f64 = 14.0
    revision: int = 0
    pub fn init() {}
    pub fn background() -> int { return self.background_value }
    pub fn foreground() -> int { return self.foreground_value }
    pub fn accent() -> int { return self.accent_value }
    pub fn surface() -> int { return self.surface_value }
    pub fn font_size() -> f64 { return self.font_value }
    pub fn version() -> int { return self.revision }
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
