// Alerts and document pickers, every one of them asynchronous.

#import "internal.h"

// The top view controller a sheet can be presented from. A window with no root
// has none, which is the headless case.
static UIViewController *ctd_presenter(ctd_handle parent) {
    id object = parent ? ctd_resolve(parent) : nil;
    if (![object isKindOfClass:[UIWindow class]]) return nil;
    UIWindow *window = (UIWindow *)object;
    if ([window isHidden]) return nil;
    UIViewController *controller = [window rootViewController];
    while (controller && [controller presentedViewController]) {
        controller = [controller presentedViewController];
    }
    return controller;
}

ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token) {
    if (kind < CTD_DLG_MESSAGE || kind > CTD_DLG_SAVE) return CTD_ERR_RANGE;
    if (parent && !ctd_resolve(parent)) return CTD_ERR_STALE;

    NSString *heading = ctd_string(title, title_len);
    NSString *detail = ctd_string(body, body_len);
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

    UIViewController *presenter = ctd_presenter(parent);
    // Same contract as the macOS host, and for the same reason: a dialog that
    // answered nothing would leave the caller waiting on a token forever.
    if (!presenter) {
        answer(kind == CTD_DLG_MESSAGE || kind == CTD_DLG_CONFIRM ? 0 : 1, nil);
        return CTD_OK;
    }

    if (kind == CTD_DLG_OPEN || kind == CTD_DLG_SAVE) {
        // A document picker is the iOS file dialog, and it needs a delegate to
        // report through rather than a completion block. Until that is wired,
        // a file dialog answers a cancel — which is a refusal the caller can
        // see, not a promise that never resolves.
        answer(1, nil);
        return CTD_OK;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:heading
                                            message:detail
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        (void)action;
        answer(0, nil);
    }]];
    if (kind == CTD_DLG_CONFIRM) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *action) {
            (void)action;
            answer(1, nil);
        }]];
    }
    [presenter presentViewController:alert animated:NO completion:nil];
    return CTD_OK;
}
