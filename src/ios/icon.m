// The system's own icons, named by role.
//
// The same SF Symbols the Mac host draws, through UIKit's spelling of the
// same API. Two hosts, one symbol table — which is the point: a role that
// looks right on a Mac looks right on a phone without the program saying
// anything twice.
//
// It is deliberately a second copy of the table rather than a shared file.
// `src/mac/internal.h` is private to that platform by design, and a header
// shared between two hosts would be the first thing every other host had to
// be excused from. The table is data; the gate that matters is
// `tests/icons.out`, which is byte-identical on both hosts and would not be
// if these two drifted.

#import "internal.h"

static const char *const g_symbols[CTD_ICON_COUNT] = {
    NULL,                        /* CTD_ICON_NONE     */
    "arrow.clockwise",           /* REFRESH  */
    "plus",                      /* ADD      */
    "minus",                     /* REMOVE   */
    "trash",                     /* DELETE   */
    "folder",                    /* OPEN     */
    "square.and.arrow.down",     /* SAVE     */
    "magnifyingglass",           /* SEARCH   */
    "play.fill",                 /* RUN      */
    "stop.fill",                 /* STOP     */
    "chevron.left",              /* BACK     */
    "chevron.right",             /* FORWARD  */
    "scissors",                  /* CUT      */
    "doc.on.doc",                /* COPY     */
    "doc.on.clipboard",          /* PASTE    */
    "arrow.uturn.backward",      /* UNDO     */
    "arrow.uturn.forward",       /* REDO     */
    "printer",                   /* PRINT    */
    "gearshape",                 /* SETTINGS */
    "info.circle",               /* INFO     */
    "exclamationmark.triangle",  /* WARNING  */
    "xmark.octagon",             /* ERROR    */
    "questionmark.circle",       /* HELP     */
    "doc",                       /* DOCUMENT */
    "folder.fill",               /* FOLDER   */
    "cylinder.split.1x2",        /* DATABASE */
    "tablecells",                /* TABLE    */
};

UIImage *ctd_icon_image(int32_t icon) {
    if (icon <= CTD_ICON_NONE || icon >= CTD_ICON_COUNT) return nil;
    const char *name = g_symbols[icon];
    if (!name) return nil;
    return [UIImage systemImageNamed:[NSString stringWithUTF8String:name]];
}

int32_t ctd_icon_name(int32_t icon, char *out, int32_t cap) {
    if (icon < 0 || icon >= CTD_ICON_COUNT) return CTD_ERR_RANGE;
    if (icon == CTD_ICON_NONE) return ctd_copy_out(@"", out, cap);
    const char *name = g_symbols[icon];
    if (!name) return CTD_ERR_RANGE;
    if (!ctd_icon_image(icon)) return CTD_ERR_RANGE;
    return ctd_copy_out([NSString stringWithUTF8String:name], out, cap);
}
