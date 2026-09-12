// Windows: making them, titling them, showing them, and what they contain.

#import "internal.h"

// One of the four things that happen to a surface.
//
// Guarded on ctd_listening for the same reason every input event is: a window
// being dragged by its corner reports a resize on every frame of the drag, and
// a program that is not listening should not be crossed into sixty times a
// second to be told something it does not want.
void ctd_surface_event(uint32_t kind, ctd_handle surface, double a, double b) {
    if (!g_sink || !surface) return;
    if (!ctd_listening(kind)) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = surface;
    if (kind == CTD_EV_SURFACE_RESIZED) {
        out.width = a;
        out.height = b;
    } else if (kind == CTD_EV_APPEARANCE || kind == CTD_EV_SCALE_CHANGED) {
        // `index` for the appearance, which is a whole number; `x` for the
        // scale, which is not — a Retina display is 2 and a scaled one is not
        // a whole number at all.
        out.index = (int64_t)a;
        out.x = a;
    }
    g_sink(g_sink_context, &out);
}

@implementation CortadoWindow
// Every way the keyboard moves goes through here — a program calling this, a
// user clicking a field, a user pressing Tab — so this is where blur and focus
// are raised. Asked *after* AppKit has decided, because a control may refuse
// to take it and a program told that focus moved when it did not would draw a
// caret in the wrong place.
//
// **Only the outermost call reports.** AppKit re-enters this method on its own
// and more than once: making a text field first responder resigns whatever had
// the keyboard, hands it to the window, and then installs the shared field
// editor, each step a nested call of its own. Reporting each one hands a
// program a blur and a focus for a move that never happened — measured, on
// this file's first version: one `focus()` on a field that already had the
// keyboard raised two blurs and no focus. So the responder is remembered on
// the way in at depth zero and compared once on the way out, which reports the
// move a person would describe and not the steps AppKit took to make it.
- (BOOL)makeFirstResponder:(NSResponder *)responder {
    static int depth = 0;
    static ctd_handle started_from = 0;
    // The *handle*, not the responder, and resolved on the way in. A field
    // editor is found again through its delegate — and by the time the call
    // returns it has been resigned, its delegate is nil and it is no longer a
    // subview of the field it was editing. Asking afterwards answers nothing,
    // which is a blur that never arrives for the control that just lost the
    // keyboard.
    if (depth == 0) started_from = ctd_focus_handle([self firstResponder]);
    depth = depth + 1;
    BOOL took = [super makeFirstResponder:responder];
    depth = depth - 1;
    if (depth == 0) {
        ctd_handle was = started_from;
        started_from = 0;
        ctd_focus_moved(was, ctd_focus_handle([self firstResponder]));
    }
    return took;
}

// ---- the four things that happen to a window ----
//
// A delegate on itself. AppKit wants an object for each of these and cortado
// has exactly one window class, so the window is its own delegate — which also
// means a program cannot take the delegate away by accident, because there is
// no property for it in this ABI.

- (void)windowDidResize:(NSNotification *)note {
    (void)note;
    // The header's rule: a write is silent. A window the *program* resized
    // re-solves its own layout on the way out of that call, and a layout that
    // also re-solved on the notification would re-solve for ever.
    if (g_writing) return;
    NSRect content = [[self contentView] frame];
    ctd_surface_event(CTD_EV_SURFACE_RESIZED, ctd_handle_for(self),
                      content.size.width, content.size.height);
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    ctd_surface_event(CTD_EV_SURFACE_CLOSE, ctd_handle_for(self), 0, 0);
    // A program with a close handler keeps its window and decides; one
    // without gets what every platform does on its own. A handler cannot
    // answer back, so the question is settled by the only thing the host
    // already knows — see the note beside ctd_surface_synth.
    return ctd_listening(CTD_EV_SURFACE_CLOSE) ? NO : YES;
}

- (void)windowDidChangeBackingProperties:(NSNotification *)note {
    (void)note;
    ctd_surface_event(CTD_EV_SCALE_CHANGED, ctd_handle_for(self),
                      [self backingScaleFactor], 0);
}

// The appearance is the *application's*, not one window's — every window
// changes together — but it reaches a program through a window because that is
// what a program has a handle to. AppKit tells a view, so the flipped content
// view passes it on.
- (void)ctdAppearanceChanged {
    ctd_surface_event(CTD_EV_APPEARANCE, ctd_handle_for(self),
                      (double)ctd_appearance(), 0);
}
@end

// ------------------------------------------------------------------- surfaces

ctd_handle ctd_surface_new(double width, double height) {
    NSWindow *window = [[CortadoWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, width, height)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:(id<NSWindowDelegate>)window];
    // The default content view is not flipped, so every surface gets one that
    // is. This is the only place the flip has to be installed.
    CortadoView *content = [[CortadoView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    ctd_tag(content);
    [window setContentView:content];
    [content release];
    ctd_handle handle = ctd_track(window, -1);
    [window release];
    return handle;
}

ctd_status ctd_surface_set_title(ctd_handle surface, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    if (![window isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
    NSString *text = [[[NSString alloc] initWithBytes:utf8
                                               length:(NSUInteger)(len < 0 ? 0 : len)
                                             encoding:NSUTF8StringEncoding] autorelease];
    [window setTitle:text ? text : @""];
    return CTD_OK;
}

int32_t ctd_surface_title(ctd_handle surface, char *out, int32_t cap) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    return ctd_copy_out([window title], out, cap);
}

ctd_status ctd_surface_set_root(ctd_handle surface, ctd_handle root) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    NSView *view = (NSView *)ctd_resolve(root);
    if (!window || !view) return CTD_ERR_STALE;
    NSView *content = [window contentView];
    for (NSView *existing in ctd_children(content)) {
        [existing removeFromSuperview];
    }
    [view setFrame:[content bounds]];
    [content addSubview:view];
    return CTD_OK;
}

ctd_handle ctd_surface_root(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return 0;
    NSArray *children = ctd_children([window contentView]);
    if ([children count] == 0) return 0;
    NSView *first = [children objectAtIndex:0];
    // Find the handle that already names it rather than minting a second one:
    // two handles for one view would each carry their own lifetime.
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == first) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

ctd_status ctd_surface_content_size(ctd_handle surface, double *out_size) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    NSRect bounds = [[window contentView] bounds];
    if (out_size) {
        out_size[0] = bounds.size.width;
        out_size[1] = bounds.size.height;
    }
    return CTD_OK;
}

ctd_status ctd_surface_show(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    // Headless builds widgets and measures them but never puts one on screen,
    // so a test suite reads the same tree on a CI runner as on a desk.
    if (g_role == CTD_ROLE_HEADLESS) return CTD_OK;
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    return CTD_OK;
}

ctd_status ctd_surface_synth(ctd_handle surface, int32_t what,
                             double a, double b) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    switch (what) {
        case CTD_EV_SURFACE_RESIZED: {
            if (!(a >= 0.0) || !(b >= 0.0)) return CTD_ERR_RANGE;
            // A real resize, so the platform's own notification is what
            // arrives — and outside g_writing, because this is standing in for
            // the *user* dragging the corner and not for the program.
            [window setContentSize:NSMakeSize(a, b)];
            return CTD_OK;
        }
        case CTD_EV_SURFACE_CLOSE:
            // -performClose: is the close button, not -close: it asks the
            // delegate first, which is the road a real click takes.
            [window performClose:nil];
            return CTD_OK;
        case CTD_EV_APPEARANCE:
        case CTD_EV_SCALE_CHANGED:
            // No program can change the system's appearance or a display's
            // scale, so there is no real road to take here and the event is
            // raised directly. See the note beside ctd_surface_synth.
            ctd_surface_event((uint32_t)what, surface, a, b);
            return CTD_OK;
        default:
            return CTD_ERR_RANGE;
    }
}

ctd_status ctd_surface_close(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    [window close];
    return CTD_OK;
}

int32_t ctd_surface_visible(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return 0;
    return [window isVisible] ? 1 : 0;
}
