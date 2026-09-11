// Windows: making them, titling them, showing them, and what they contain.

#import "internal.h"

// ------------------------------------------------------------------- surfaces

ctd_handle ctd_surface_new(double width, double height) {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, width, height)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setReleasedWhenClosed:NO];
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
