// The view tree: parenting, ordering, frames and measurement.

#import "internal.h"

// ----------------------------------------------------------------------- tree

// A surface addresses its content view; everything else addresses itself.
// Where a widget's children actually live.
//
// Two of the cases are indirections the tree above must not know about: a
// window's children sit in its content view, and a scroll view's in its
// document view. A caller that had to know which control wraps what would be a
// caller writing platform code in Beans.
//
// Every view answers something here, including a leaf. Asking a label how many
// children it has is a question with a real answer — none — and refusing it
// would make every tree walk special-case every kind. Refusing to *add* a
// child to one is a different question, and `ctd_can_hold` is where that lives.
static NSView *ctd_container_of(id object) {
    if ([object isKindOfClass:[NSWindow class]]) return [(NSWindow *)object contentView];
    if ([object isKindOfClass:[NSScrollView class]]) {
        id inner = [(NSScrollView *)object documentView];
        if ([inner isKindOfClass:[NSView class]]) return (NSView *)inner;
        return (NSView *)object;
    }
    if ([object isKindOfClass:[NSView class]]) return (NSView *)object;
    return nil;
}

// Whether a widget may be given children.
//
// A text area is a scroll view whose document view holds text, not widgets.
// Adding a button to one would put it inside a paragraph — AppKit allows it
// and nothing good comes of it — so the refusal is here rather than in a
// comment.
static BOOL ctd_can_hold(NSView *content) {
    if (!content) return NO;
    return ![content isKindOfClass:[NSTextView class]];
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    id owner = ctd_resolve(parent);
    NSView *view = (NSView *)ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    NSView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    NSArray *existing = ctd_children(container);
    if (index < 0 || index >= (int32_t)[existing count]) {
        [container addSubview:view];
    } else {
        [container addSubview:view
                   positioned:NSWindowBelow
                   relativeTo:[existing objectAtIndex:(NSUInteger)index]];
    }
    return CTD_OK;
}

ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child) {
    id owner = ctd_resolve(parent);
    NSView *view = (NSView *)ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    NSView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    if ([view superview] != container) return CTD_ERR_RANGE;
    [view removeFromSuperview];
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    NSView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    NSArray *children = ctd_children(container);
    int32_t count = (int32_t)[children count];
    if (from < 0 || from >= count || to < 0 || to >= count) return CTD_ERR_RANGE;
    if (from == to) return CTD_OK;
    // Held across the move because -removeFromSuperview drops the superview's
    // reference, and on a view the caller no longer names that is the last one.
    NSView *moving = [[children objectAtIndex:(NSUInteger)from] retain];
    NSResponder *responder = [[container window] firstResponder];
    BOOL had_focus = [responder isKindOfClass:[NSView class]] &&
                     [(NSView *)responder isDescendantOf:moving];
    [moving removeFromSuperview];
    NSArray *rest = ctd_children(container);
    if (to >= (int32_t)[rest count]) {
        [container addSubview:moving];
    } else {
        [container addSubview:moving
                   positioned:NSWindowBelow
                   relativeTo:[rest objectAtIndex:(NSUInteger)to]];
    }
    // Reordering a list should not take the caret out of the field being
    // edited, which is what AppKit does on its own.
    if (had_focus) [[container window] makeFirstResponder:responder];
    [moving release];
    return CTD_OK;
}

ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    NSView *container = ctd_container_of(owner);
    // A control that cannot hold children has none, which is an answer and not
    // a refusal — a tree walk asks this of every node and would otherwise have
    // to know which kinds to skip.
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
    NSView *container = ctd_container_of(owner);
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
    NSView *view = (NSView *)ctd_resolve(child);
    if (!view) return 0;
    NSView *parent = [view superview];
    if (!parent) return 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == parent) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

// ------------------------------------------------------------------- geometry

ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height) {
    NSView *view = (NSView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    if (![view isKindOfClass:[NSView class]]) return CTD_ERR_KIND;
    [view setFrame:NSMakeRect(x, y, width, height)];
    return CTD_OK;
}

ctd_status ctd_view_frame(ctd_handle widget, double *out_frame) {
    NSView *view = (NSView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    NSRect frame = [view frame];
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
    NSView *view = (NSView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    NSSize wanted;
    if ([view isKindOfClass:[NSControl class]]) {
        wanted = [(NSControl *)view fittingSize];
    } else {
        wanted = [view intrinsicContentSize];
        if (wanted.width  == NSViewNoIntrinsicMetric) wanted.width  = 0;
        if (wanted.height == NSViewNoIntrinsicMetric) wanted.height = 0;
    }
    // A negative available size means unbounded, so only a real bound clamps.
    if (avail_width  >= 0 && wanted.width  > avail_width)  wanted.width  = avail_width;
    if (avail_height >= 0 && wanted.height > avail_height) wanted.height = avail_height;
    if (out_size) {
        out_size[0] = wanted.width;
        out_size[1] = wanted.height;
    }
    return CTD_OK;
}
