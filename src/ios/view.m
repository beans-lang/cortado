// The view tree: parenting, ordering, frames and measurement.
//
// A control here is allowed to refuse the frame it is given, and two of them
// do: a UISwitch is 51 by 31 and a UIProgressView is 4 points tall whatever
// is asked. That is why `tests/roles.out` carries no frames.

#import "internal.h"

static UIView *ctd_container_of(id object) {
    if ([object isKindOfClass:[UIWindow class]]) return ctd_surface_view(object);
    // A disclosure's children go under its header, not beside it. Asked before
    // UIView, because a disclosure is one.
    if ([object isKindOfClass:[CortadoDisclosure class]])
        return [(CortadoDisclosure *)object content];
    if ([object isKindOfClass:[UIView class]]) return (UIView *)object;
    return nil;
}

// A text view holds text, not widgets. Adding a button to one would put it
// inside a paragraph — UIKit allows it and nothing good comes of it.
static BOOL ctd_can_hold(UIView *content) {
    if (!content) return NO;
    if ([content isKindOfClass:[UITextView class]]) return NO;
    if ([content isKindOfClass:[UITextField class]]) return NO;
    return YES;
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    id owner = ctd_resolve(parent);
    UIView *view = (UIView *)ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    UIView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    NSArray *existing = ctd_children(container);
    if (index < 0 || index >= (int32_t)[existing count]) {
        [container addSubview:view];
    } else {
        [container insertSubview:view
                    belowSubview:[existing objectAtIndex:(NSUInteger)index]];
    }
    return CTD_OK;
}

ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child) {
    id owner = ctd_resolve(parent);
    UIView *view = (UIView *)ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    UIView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    if ([view superview] != container) return CTD_ERR_RANGE;
    [view removeFromSuperview];
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    UIView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    NSArray *children = ctd_children(container);
    int32_t count = (int32_t)[children count];
    if (from < 0 || from >= count || to < 0 || to >= count) return CTD_ERR_RANGE;
    if (from == to) return CTD_OK;
    // Held across the move: -removeFromSuperview drops the superview's
    // reference, and on a view the caller no longer names that is the last one.
    UIView *moving = [[children objectAtIndex:(NSUInteger)from] retain];
    UIResponder *first = nil;
    if ([moving isFirstResponder]) first = moving;
    [moving removeFromSuperview];
    NSArray *rest = ctd_children(container);
    if (to >= (int32_t)[rest count]) {
        [container addSubview:moving];
    } else {
        [container insertSubview:moving
                    belowSubview:[rest objectAtIndex:(NSUInteger)to]];
    }
    // Reordering a list should not take the keyboard away from the field being
    // edited, which is what UIKit does on its own.
    if (first) [first becomeFirstResponder];
    [moving release];
    return CTD_OK;
}

ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    UIView *container = ctd_container_of(owner);
    if (!container || !ctd_can_hold(container)) {
        if (out) *out = 0;
        return CTD_OK;
    }
    if (out) *out = (int32_t)[ctd_children(container) count];
    return CTD_OK;
}

ctd_handle ctd_view_child_at(ctd_handle parent, int32_t index) {
    id owner = ctd_resolve(parent);
    if (!owner) return 0;
    UIView *container = ctd_container_of(owner);
    if (!container || !ctd_can_hold(container)) return 0;
    NSArray *children = ctd_children(container);
    if (index < 0 || index >= (int32_t)[children count]) return 0;
    id wanted = [children objectAtIndex:(NSUInteger)index];
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == wanted) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

ctd_handle ctd_view_parent(ctd_handle child) {
    UIView *view = (UIView *)ctd_resolve(child);
    if (!view) return 0;
    UIView *parent = [view superview];
    if (!parent) return 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == parent) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}


ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height) {
    UIView *view = (UIView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    // No flip. UIKit's coordinate space already has its origin at the top left
    // with y growing downward, which is what cortado means by a frame — the
    // macOS host is the one that has work to do here.
    [view setFrame:CGRectMake(x, y, width, height)];
    return CTD_OK;
}

ctd_status ctd_view_frame(ctd_handle widget, double *out_frame) {
    UIView *view = (UIView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    CGRect frame = [view frame];
    if (out_frame) {
        out_frame[0] = frame.origin.x;
        out_frame[1] = frame.origin.y;
        out_frame[2] = frame.size.width;
        out_frame[3] = frame.size.height;
    }
    return CTD_OK;
}

ctd_status ctd_view_measure(ctd_handle widget, double avail_width, double avail_height,
                            double *out_size) {
    UIView *view = (UIView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    CGSize offer = CGSizeMake(avail_width < 0 ? CGFLOAT_MAX : avail_width,
                              avail_height < 0 ? CGFLOAT_MAX : avail_height);
    CGSize wanted = [view sizeThatFits:offer];
    if (ctd_slot_kind(widget) == CTD_W_SEPARATOR) {
        // A hairline. iOS has no separator control, so cortado's is a plain
        // view, and a plain view measures zero — which collapses it to
        // nothing. One point is what a table's own separators are, and is the
        // same answer an NSBox gives on macOS, so the two platforms agree.
        wanted = CGSizeMake(avail_width < 0 ? 0.0 : avail_width, 1.0);
    } else if (wanted.width <= 0.0 && wanted.height <= 0.0) {
        // A view with no intrinsic size answers zero. Its own frame is the
        // honest fallback: it is what the caller last set.
        wanted = [view frame].size;
    }
    if (out_size) {
        out_size[0] = wanted.width;
        out_size[1] = wanted.height;
    }
    return CTD_OK;
}

// The surface a widget is in. See the macOS host for why this is a scan.
ctd_handle ctd_view_surface(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object || ![object isKindOfClass:[UIView class]]) return 0;
    UIWindow *window = [(UIView *)object window];
    if (!window) return 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == window) {
            return ((uint64_t)g_generation[slot] << 32) | slot;
        }
    }
    return 0;
}
