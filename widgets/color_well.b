// A colour, and a way to pick another.
package widgets

import cortado.host

/// A colour well.
///
/// `NSColorWell`, `UIColorWell`, `GtkColorDialogButton` — a swatch showing the
/// colour, which opens the platform's own chooser when pressed. **Not on every
/// platform**: the Win32 common controls have none. `ChooseColor` is a dialog
/// a program opens, which is a different control, and an owner-drawn button
/// would be cortado drawing one — so this refuses with `no_such_control`
/// rather than substituting.
///
/// The colour crosses as an `Rgba`, and what is promised is that the bytes
/// that go in come back out. Every platform holds a colour as floats in some
/// colour space, so the hosts name sRGB explicitly and round rather than
/// truncate on the way back; without both, a byte written on a wide-gamut
/// screen would read back as a different byte.
pub class ColorWell extends Widget {
    pub fn init() {
        super.init(WidgetKind.color_well)
    }

    /// A well already showing a colour.
    pub static fn of(shade: Rgba) -> Result<ColorWell> {
        WidgetKind.color_well.demand()?
        var well: ColorWell = new ColorWell()
        well.set_color(shade)?
        return ok(well)
    }

    pub fn set_color(shade: Rgba) -> Result<bool> {
        return self.set_property(host.P_COLOR, ColorWell.pack(shade))
    }

    pub fn color() -> Result<Rgba> {
        let packed: int = self.read_property(host.P_COLOR)?
        return ok(ColorWell.unpack(packed))
    }

    /// 0xRRGGBBAA, the order the header names and the order a CSS colour is
    /// written in.
    ///
    /// Public and static because the packing is the ABI's, not this class's: a
    /// handler reading `event.index` off a `value_changed` gets the same
    /// number this produces, and it needs the same way back.
    pub static fn pack(shade: Rgba) -> int {
        return (shade.red * 16777216) + (shade.green * 65536) +
               (shade.blue * 256) + shade.alpha
    }

    pub static fn unpack(packed: int) -> Rgba {
        return Rgba { red: (packed / 16777216) % 256,
                      green: (packed / 65536) % 256,
                      blue: (packed / 256) % 256,
                      alpha: packed % 256 }
    }
}
