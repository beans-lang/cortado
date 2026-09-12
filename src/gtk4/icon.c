// The system's own icons, named by role.
//
// The freedesktop icon theme, which is what a GTK desktop has and what every
// other application on it draws from. The `-symbolic` variants are the ones a
// toolbar wants: they recolour with the theme, so a dark desktop gets light
// icons without the program knowing which it is on.
//
// Whether a name is *present* is a property of the installed theme rather
// than of GTK, so `ctd_icon_name` asks the theme rather than trusting the
// table below. A machine with a cut-down icon set answers honestly and the
// caller falls back to text.

#include "internal.h"

static const char *const g_names[CTD_ICON_COUNT] = {
    NULL,                               /* CTD_ICON_NONE */
    "view-refresh-symbolic",            /* REFRESH  */
    "list-add-symbolic",                /* ADD      */
    "list-remove-symbolic",             /* REMOVE   */
    "user-trash-symbolic",              /* DELETE   */
    "document-open-symbolic",           /* OPEN     */
    "document-save-symbolic",           /* SAVE     */
    "system-search-symbolic",           /* SEARCH   */
    "media-playback-start-symbolic",    /* RUN      */
    "media-playback-stop-symbolic",     /* STOP     */
    "go-previous-symbolic",             /* BACK     */
    "go-next-symbolic",                 /* FORWARD  */
    "edit-cut-symbolic",                /* CUT      */
    "edit-copy-symbolic",               /* COPY     */
    "edit-paste-symbolic",              /* PASTE    */
    "edit-undo-symbolic",               /* UNDO     */
    "edit-redo-symbolic",               /* REDO     */
    "document-print-symbolic",          /* PRINT    */
    "preferences-system-symbolic",      /* SETTINGS */
    "dialog-information-symbolic",      /* INFO     */
    "dialog-warning-symbolic",          /* WARNING  */
    "dialog-error-symbolic",            /* ERROR    */
    "help-browser-symbolic",            /* HELP     */
    "text-x-generic-symbolic",          /* DOCUMENT */
    "folder-symbolic",                  /* FOLDER   */
    "drive-multidisk-symbolic",         /* DATABASE */
    "view-list-symbolic",               /* TABLE    */
};

// The theme's name for a role, or NULL when this theme does not have it.
const char *ctd_icon_theme_name(int32_t icon) {
    if (icon <= CTD_ICON_NONE || icon >= CTD_ICON_COUNT) return NULL;
    const char *name = g_names[icon];
    if (!name) return NULL;
    GdkDisplay *display = gdk_display_get_default();
    if (!display) return NULL;
    GtkIconTheme *theme = gtk_icon_theme_get_for_display(display);
    if (!theme) return NULL;
    if (!gtk_icon_theme_has_icon(theme, name)) return NULL;
    return name;
}

int32_t ctd_icon_name(int32_t icon, char *out, int32_t cap) {
    if (icon < 0 || icon >= CTD_ICON_COUNT) return CTD_ERR_RANGE;
    if (icon == CTD_ICON_NONE) return ctd_copy_out("", out, cap);
    const char *name = ctd_icon_theme_name(icon);
    if (!name) return CTD_ERR_RANGE;
    return ctd_copy_out(name, out, cap);
}
