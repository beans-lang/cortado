// The system's own icons, named by role.
//
// Windows has two sets and neither covers what the other does, which is why
// this file has two columns:
//
//   * the **standard toolbar bitmap** (`IDB_STD_SMALL_COLOR`), fifteen images
//     that have been in the common controls since Windows 95 — cut, copy,
//     paste, undo, redo, delete, new, open, save, print, properties, help,
//     find, replace, print-preview. These are what a real Win32 toolbar
//     draws, and nothing else lines up with them;
//   * the **shell's stock icons** (`SHGetStockIconInfo`), which is where a
//     folder, a document, a warning and an error come from.
//
// Between them they cover most of what cortado names and not all of it.
// There is no standard Windows icon for "run", "refresh", "database" or
// "table", and this host says so: `ctd_icon_name` answers CTD_ERR_RANGE and
// the caller shows a word instead. Inventing one — drawing a triangle,
// shipping a PNG — would be this library deciding what Windows looks like,
// which is the one thing using the system's set is meant to avoid.

#include "internal.h"

// -1 in either column means "not from that set".
typedef struct {
    const char *label;   // what ctd_icon_name answers; NULL for no icon here
    int         std;     // STD_* index into IDB_STD_SMALL_COLOR, or -1
    int         stock;   // SIID_* for SHGetStockIconInfo, or -1
} CtdIconRow;

static const CtdIconRow g_icons[CTD_ICON_COUNT] = {
    { NULL,              -1,             -1 },  /* NONE     */
    { NULL,              -1,             -1 },  /* REFRESH  */
    { NULL,              -1,             -1 },  /* ADD      */
    { NULL,              -1,             -1 },  /* REMOVE   */
    { "STD_DELETE",      STD_DELETE,     -1 },  /* DELETE   */
    { "STD_FILEOPEN",    STD_FILEOPEN,   -1 },  /* OPEN     */
    { "STD_FILESAVE",    STD_FILESAVE,   -1 },  /* SAVE     */
    { "STD_FIND",        STD_FIND,       -1 },  /* SEARCH   */
    { NULL,              -1,             -1 },  /* RUN      */
    { NULL,              -1,             -1 },  /* STOP     */
    { NULL,              -1,             -1 },  /* BACK     */
    { NULL,              -1,             -1 },  /* FORWARD  */
    { "STD_CUT",         STD_CUT,        -1 },  /* CUT      */
    { "STD_COPY",        STD_COPY,       -1 },  /* COPY     */
    { "STD_PASTE",       STD_PASTE,      -1 },  /* PASTE    */
    { "STD_UNDO",        STD_UNDO,       -1 },  /* UNDO     */
    { "STD_REDOW",       STD_REDOW,      -1 },  /* REDO     */
    { "STD_PRINT",       STD_PRINT,      -1 },  /* PRINT    */
    { "STD_PROPERTIES",  STD_PROPERTIES, -1 },  /* SETTINGS */
    { "SIID_INFO",       -1,             SIID_INFO },      /* INFO     */
    { "SIID_WARNING",    -1,             SIID_WARNING },   /* WARNING  */
    { "SIID_ERROR",      -1,             SIID_ERROR },     /* ERROR    */
    { "STD_HELP",        STD_HELP,       -1 },  /* HELP     */
    { "SIID_DOCNOASSOC", -1,             SIID_DOCNOASSOC },/* DOCUMENT */
    { "SIID_FOLDER",     -1,             SIID_FOLDER },    /* FOLDER   */
    { NULL,              -1,             -1 },  /* DATABASE */
    { NULL,              -1,             -1 },  /* TABLE    */
};

int ctd_icon_std_index(int32_t icon) {
    if (icon <= CTD_ICON_NONE || icon >= CTD_ICON_COUNT) return -1;
    return g_icons[icon].std;
}

// An HICON for a role, or NULL. The caller owns it and must DestroyIcon it;
// SHGetStockIconInfo hands out a copy per call rather than a shared one.
HICON ctd_icon_handle(int32_t icon) {
    if (icon <= CTD_ICON_NONE || icon >= CTD_ICON_COUNT) return NULL;
    if (g_icons[icon].stock < 0) return NULL;
    SHSTOCKICONINFO info;
    memset(&info, 0, sizeof info);
    info.cbSize = sizeof info;
    if (FAILED(SHGetStockIconInfo((SHSTOCKICONID)g_icons[icon].stock,
                                  SHGSI_ICON | SHGSI_SMALLICON, &info))) {
        return NULL;
    }
    return info.hIcon;
}

int32_t ctd_icon_name(int32_t icon, char *out, int32_t cap) {
    if (icon < 0 || icon >= CTD_ICON_COUNT) return CTD_ERR_RANGE;
    if (icon == CTD_ICON_NONE) return ctd_copy_out("", out, cap);
    const char *label = g_icons[icon].label;
    if (!label) return CTD_ERR_RANGE;
    return ctd_copy_out(label, out, cap);
}
