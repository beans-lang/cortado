// What the system itself says: appearance, backing scale, and its own fonts.

#import "internal.h"

// ----------------------------------------------------------------- appearance

int32_t ctd_appearance(void) {
    NSAppearance *current = [NSApp effectiveAppearance];
    NSAppearanceName best =
        [current bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,
                                                     NSAppearanceNameDarkAqua]];
    return [best isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
}

ctd_status ctd_surface_scale(ctd_handle surface, double *out) {
    double scale = [[NSScreen mainScreen] backingScaleFactor];
    if (surface) {
        id object = ctd_resolve(surface);
        if (!object) return CTD_ERR_STALE;
        if (![object isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
        scale = [(NSWindow *)object backingScaleFactor];
        // A window that has not been shown has no screen yet, and AppKit
        // answers 0 for one. The main display's scale is the honest guess and
        // the one the window will get when it appears.
        if (scale <= 0.0) scale = [[NSScreen mainScreen] backingScaleFactor];
    }
    if (scale <= 0.0) scale = 1.0;
    if (out) *out = scale;
    return CTD_OK;
}

// ---------------------------------------------------------------------- fonts

static NSFont *ctd_font_for(int32_t role) {
    switch (role) {
        case CTD_FONT_HEADING:
            return [NSFont systemFontOfSize:[NSFont systemFontSize] + 4.0
                                     weight:NSFontWeightSemibold];
        case CTD_FONT_CAPTION:
            return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        case CTD_FONT_MONO:
            return [NSFont monospacedSystemFontOfSize:[NSFont systemFontSize]
                                               weight:NSFontWeightRegular];
        case CTD_FONT_BODY:
            return [NSFont systemFontOfSize:[NSFont systemFontSize]];
        default:
            return nil;
    }
}

int32_t ctd_font_family(int32_t role, char *out, int32_t cap) {
    NSFont *font = ctd_font_for(role);
    if (!font) return CTD_ERR_RANGE;
    return ctd_copy_out([font familyName], out, cap);
}

ctd_status ctd_font_size(int32_t role, double *out) {
    NSFont *font = ctd_font_for(role);
    if (!font) return CTD_ERR_RANGE;
    if (out) *out = (double)[font pointSize];
    return CTD_OK;
}
