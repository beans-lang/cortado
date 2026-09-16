// What the system itself says: appearance, scale, and its own fonts.

#include "internal.h"

int32_t ctd_appearance(void) {
    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) return 0;
    gboolean dark = FALSE;
    g_object_get(settings, "gtk-application-prefer-dark-theme", &dark, NULL);
    return dark ? 1 : 0;
}

ctd_status ctd_surface_scale(ctd_handle surface, double *out) {
    // Headless has no display, so it has no device pixel grid. Answering the
    // main screen's scale here would put the attached monitor in a golden.
    if (g_role == CTD_ROLE_HEADLESS) {
        if (out) *out = 1.0;
        return CTD_OK;
    }
    double scale = 1.0;
    if (surface) {
        gpointer object = ctd_resolve(surface);
        if (!object) return CTD_ERR_STALE;
        if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
        scale = (double)gtk_widget_get_scale_factor(GTK_WIDGET(object));
    }
    if (scale <= 0.0) scale = 1.0;
    if (out) *out = scale;
    return CTD_OK;
}


// GTK's font comes from the theme as one description string — "Cantarell 11" —
// so the family and the size are pulled out of the same place.
static void ctd_theme_font(char *family, size_t cap, double *size) {
    g_strlcpy(family, "Sans", cap);
    *size = 11.0;
    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) return;
    char *description = NULL;
    g_object_get(settings, "gtk-font-name", &description, NULL);
    if (!description) return;
    PangoFontDescription *font = pango_font_description_from_string(description);
    if (font) {
        const char *name = pango_font_description_get_family(font);
        if (name) g_strlcpy(family, name, cap);
        int points = pango_font_description_get_size(font);
        if (points > 0) *size = (double)points / PANGO_SCALE;
        pango_font_description_free(font);
    }
    g_free(description);
}

int32_t ctd_font_family(int32_t role, char *out, int32_t cap) {
    if (role < CTD_FONT_BODY || role > CTD_FONT_MONO) return CTD_ERR_RANGE;
    if (role == CTD_FONT_MONO) return ctd_copy_out("Monospace", out, cap);
    char family[128];
    double size = 0.0;
    ctd_theme_font(family, sizeof family, &size);
    return ctd_copy_out(family, out, cap);
}

ctd_status ctd_font_size(int32_t role, double *out) {
    if (role < CTD_FONT_BODY || role > CTD_FONT_MONO) return CTD_ERR_RANGE;
    char family[128];
    double size = 0.0;
    ctd_theme_font(family, sizeof family, &size);
    if (role == CTD_FONT_HEADING) size += 4.0;
    if (role == CTD_FONT_CAPTION) size -= 2.0;
    if (out) *out = size;
    return CTD_OK;
}
