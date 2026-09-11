// Alerts and file choosers, every one of them asynchronous.
//
// The answer arrives as an event carrying the token the request was made
// with, because a modal loop that blocked here would block the Beans side
// inside a call it could not return from.

#import "internal.h"

// -------------------------------------------------------------------- dialogs

ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token) {
    NSWindow *window = nil;
    if (parent) {
        id object = ctd_resolve(parent);
        if (!object) return CTD_ERR_STALE;
        if (![object isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
        window = (NSWindow *)object;
        // A sheet needs a window that is actually on screen. Attaching one to
        // a window that was never shown runs no completion handler at all, so
        // the caller waits on a token that will never arrive — a hang, and the
        // worst possible failure for an asynchronous API. A window that cannot
        // host a sheet is treated as no window, which answers immediately.
        if (![window isVisible]) window = nil;
    }
    NSString *heading = ctd_string(title, title_len);
    NSString *detail = ctd_string(body, body_len);

    // The answer is delivered as an event and never returned, because every
    // platform's dialog is asynchronous and a blocking form would have to spin
    // an inner event loop — re-entering the render this call came out of.
    void (^answer)(NSInteger, NSString *) = ^(NSInteger which, NSString *path) {
        ctd_event event;
        memset(&event, 0, sizeof event);
        event.kind = CTD_EV_POST;
        event.token = token;
        event.index = (int64_t)which;
        const char *utf8 = path ? [path UTF8String] : NULL;
        event.text = utf8;
        event.text_len = utf8 ? (int32_t)strlen(utf8) : 0;
        if (g_sink) g_sink(g_sink_context, &event);
    };

    if (kind == CTD_DLG_MESSAGE || kind == CTD_DLG_CONFIRM) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:heading];
        [alert setInformativeText:detail];
        [alert addButtonWithTitle:@"OK"];
        if (kind == CTD_DLG_CONFIRM) [alert addButtonWithTitle:@"Cancel"];
        if (window) {
            [alert beginSheetModalForWindow:window
                          completionHandler:^(NSModalResponse response) {
                answer(response == NSAlertFirstButtonReturn ? 0 : 1, nil);
            }];
        } else {
            // No surface to attach to — which is the headless case, where
            // running a modal alert would hang. The answer is the default
            // button, reported the same way, so a caller's code path is the
            // same with and without a display.
            answer(0, nil);
        }
        [alert release];
        return CTD_OK;
    }

    if (kind == CTD_DLG_OPEN || kind == CTD_DLG_SAVE) {
        if (!window) {
            // Same reason: a file panel with nothing to attach to would run
            // modally and never return under a test. Report a cancel.
            answer(1, nil);
            return CTD_OK;
        }
        NSSavePanel *panel = kind == CTD_DLG_OPEN
            ? (NSSavePanel *)[NSOpenPanel openPanel]
            : [NSSavePanel savePanel];
        [panel setTitle:heading];
        [panel setMessage:detail];
        [panel beginSheetModalForWindow:window
                      completionHandler:^(NSModalResponse response) {
            if (response != NSModalResponseOK) { answer(1, nil); return; }
            answer(0, [[panel URL] path]);
        }];
        return CTD_OK;
    }
    return CTD_ERR_RANGE;
}
