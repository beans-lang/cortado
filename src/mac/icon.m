// The system's own icons, named by role.
//
// SF Symbols, which is what a Mac has had since macOS 11 and what every
// application a person already uses draws its toolbar from. The point of
// using them rather than shipping pictures is that the person recognises
// them: their idea of "refresh" is the one their system draws, not the one
// this program invented.
//
// The table below is the whole of this file's content. Everything else here
// is looking a role up in it and handing the answer to AppKit.

#import "internal.h"

// One row per CTD_ICON_*, in the header's order. A NULL name is a role this
// platform has no symbol for; there are none here, because SF Symbols covers
// every role cortado names — which is not true of the Windows host, and the
// reason ctd_icon_name is allowed to refuse.
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

// The image for a role, or nil for CTD_ICON_NONE and for a role this system
// is too old to know. The second case is real: SF Symbols arrived in macOS 11
// and a symbol added in 14 is nil on 12, so the answer comes from asking
// rather than from the table.
NSImage *ctd_icon_image(int32_t icon) {
    if (icon <= CTD_ICON_NONE || icon >= CTD_ICON_COUNT) return nil;
    const char *name = g_symbols[icon];
    if (!name) return nil;
    if (![NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
        return nil;
    }
    return [NSImage imageWithSystemSymbolName:[NSString stringWithUTF8String:name]
                     accessibilityDescription:nil];
}

int32_t ctd_icon_name(int32_t icon, char *out, int32_t cap) {
    if (icon < 0 || icon >= CTD_ICON_COUNT) return CTD_ERR_RANGE;
    if (icon == CTD_ICON_NONE) return ctd_copy_out(@"", out, cap);
    const char *name = g_symbols[icon];
    if (!name) return CTD_ERR_RANGE;
    // Named only if the system can actually draw it, so this answers about
    // the machine rather than about the table.
    if (!ctd_icon_image(icon)) return CTD_ERR_RANGE;
    return ctd_copy_out([NSString stringWithUTF8String:name], out, cap);
}
