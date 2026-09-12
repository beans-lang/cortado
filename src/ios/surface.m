// Windows — which on a phone means one, inside a scene.

#import "internal.h"

//
// A surface is a UIWindow with a root view controller. A phone has one, always
// full screen, so the requested size is advisory — `ctd_surface_content_size`
// answers what the surface actually is, which is what the layout solver uses.

ctd_handle ctd_surface_new(double width, double height) {
    CGRect bounds = CGRectMake(0, 0, width, height);
    UIScreen *screen = [UIScreen mainScreen];
    if (screen && !CGRectIsEmpty([screen bounds])) bounds = [screen bounds];
    UIWindow *window = [[UIWindow alloc] initWithFrame:bounds];
    UIViewController *controller = [[UIViewController alloc] init];
    // A window on macOS has the system background without being asked; a
    // UIWindow has none, which is black. Text drawn in the system label colour
    // is then black on black, and the screen looks empty rather than wrong.
    [window setBackgroundColor:[UIColor systemBackgroundColor]];
    [[controller view] setBackgroundColor:[UIColor systemBackgroundColor]];
    [window setRootViewController:controller];
    // And into the window by hand, which UIKit would otherwise only do when
    // the window stops being hidden.
    //
    // Until it is in one, a control has no `window` — and without one nothing
    // can take the keyboard: -becomeFirstResponder answers NO for a view that
    // is not in a window, so every focus call in a headless run would be
    // refused for a reason that has nothing to do with the control. Proven
    // both ways in a bare simulator process: a field under an unattached root
    // controller refuses, and the same field after this line takes the
    // keyboard with the window still hidden.
    //
    // Nothing is shown by this. The window is hidden until ctd_surface_show
    // makes it key and visible, which is what that call is for.
    if (![[controller view] superview]) [window addSubview:[controller view]];
    [controller release];
    ctd_handle handle = ctd_track(window, -1);
    [window release];
    return handle;
}

// A window has no title on iOS. It is stored so `ctd_surface_title` answers
// what was set — a program that names its screens should not lose the name
// just because this platform does not show it — and a navigation bar, when
// there is one, is the place it belongs.
static NSMutableDictionary *g_titles;

// A zero byte anywhere in the text. Every entry point that takes a string
// checks, because no platform text control can hold one: NSString's
// UTF8String ends at it, GTK's const char* ends at it, and Win32's
// SetWindowTextW ends at it. Passing one through would cut a program's string
// in half somewhere inside the platform, with nothing at the boundary able to
// say where — so it is refused here, by name, while the caller's own string
// is still in view.
int ctd_has_nul(const char *utf8, int32_t len) {
    if (!utf8 || len <= 0) return 0;
    for (int32_t i = 0; i < len; i++) {
        if (utf8[i] == 0) return 1;
    }
    return 0;
}

ctd_status ctd_surface_set_title(ctd_handle surface, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIWindow class]]) return CTD_ERR_KIND;
    if (!g_titles) g_titles = [[NSMutableDictionary alloc] init];
    [g_titles setObject:ctd_string(utf8, len)
                 forKey:[NSNumber numberWithUnsignedLongLong:surface]];
    return CTD_OK;
}

int32_t ctd_surface_title(ctd_handle surface, char *out, int32_t cap) {
    if (!ctd_resolve(surface)) return CTD_ERR_STALE;
    NSString *held = [g_titles objectForKey:
        [NSNumber numberWithUnsignedLongLong:surface]];
    return ctd_copy_out(held ? held : @"", out, cap);
}

UIView *ctd_surface_view(id object) {
    if (![object isKindOfClass:[UIWindow class]]) return nil;
    UIViewController *controller = [(UIWindow *)object rootViewController];
    return controller ? [controller view] : nil;
}

ctd_status ctd_surface_set_root(ctd_handle surface, ctd_handle root) {
    id object = ctd_resolve(surface);
    UIView *view = (UIView *)ctd_resolve(root);
    if (!object || !view) return CTD_ERR_STALE;
    UIView *content = ctd_surface_view(object);
    if (!content) return CTD_ERR_KIND;
    for (UIView *existing in ctd_children(content)) {
        [existing removeFromSuperview];
    }
    [view setFrame:[content bounds]];
    [content addSubview:view];
    return CTD_OK;
}

ctd_handle ctd_surface_root(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (!object) return 0;
    UIView *content = ctd_surface_view(object);
    if (!content) return 0;
    NSArray *ours = ctd_children(content);
    if ([ours count] == 0) return 0;
    id wanted = [ours objectAtIndex:0];
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == wanted) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

ctd_status ctd_surface_content_size(ctd_handle surface, double *out_size) {
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    UIView *content = ctd_surface_view(object);
    if (!content) return CTD_ERR_KIND;
    // The safe area when there is one — the part of the screen a person can
    // actually see and reach. Before the window is on a scene there is none,
    // and the full bounds are the honest answer until `surface_resized` says
    // otherwise.
    CGRect safe = [[content safeAreaLayoutGuide] layoutFrame];
    CGRect bounds = CGRectIsEmpty(safe) ? [content bounds] : safe;
    if (out_size) {
        out_size[0] = bounds.size.width;
        out_size[1] = bounds.size.height;
    }
    return CTD_OK;
}

ctd_status ctd_surface_show(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIWindow class]]) return CTD_ERR_KIND;
    if (g_role == CTD_ROLE_HEADLESS) return CTD_OK;
    // Remembered as well as applied: this usually runs before
    // `UIApplicationMain`, where it has no effect, and the delegate does it
    // again once UIKit is running.
    g_shown = surface;
    [(UIWindow *)object makeKeyAndVisible];
    return CTD_OK;
}

ctd_status ctd_surface_close(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIWindow class]]) return CTD_ERR_KIND;
    [(UIWindow *)object setHidden:YES];
    return CTD_OK;
}

int32_t ctd_surface_visible(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (!object) return 0;
    if (![object isKindOfClass:[UIWindow class]]) return 0;
    return [(UIWindow *)object isHidden] ? 0 : 1;
}
