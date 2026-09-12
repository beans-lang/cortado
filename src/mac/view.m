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
NSView *ctd_container_of(id object) {
    if ([object isKindOfClass:[NSWindow class]]) return [(NSWindow *)object contentView];
    // A box holds its children in a content view of its own, so the frame it
    // draws stays outside them — unless it is a separator, which is also an
    // NSBox and holds nothing. A rule that forgot that would let a horizontal
    // rule have children.
    if ([object isKindOfClass:[NSBox class]]) {
        if ([(NSBox *)object boxType] == NSBoxSeparator) return (NSView *)object;
        return [(NSBox *)object contentView];
    }
    if ([object isKindOfClass:[NSScrollView class]]) {
        id inner = [(NSScrollView *)object documentView];
        if ([inner isKindOfClass:[NSView class]]) return (NSView *)inner;
        return (NSView *)object;
    }
    if ([object isKindOfClass:[CortadoDisclosure class]])
        return [(CortadoDisclosure *)object content];
    if ([object isKindOfClass:[NSView class]]) return (NSView *)object;
    return nil;
}

// AppKit's own inset for a titled box, asked once and remembered.
//
// There is no call that answers it. `contentViewMargins` is the border, five
// points on every side; `titleRect` is where the words go; and the gap AppKit
// leaves between the words and the content is neither of those — adding them
// gives fourteen where the truth is seventeen. So one box is built the way
// AppKit expects, a frame *before* a content view, and the difference between
// the two frames is the answer. Built once, because it is the same number for
// every box on this system, and read from AppKit rather than written here
// because seventeen is not cortado's number to choose.
static void ctd_box_chrome(double *out) {
    static double known[4];
    static int asked = 0;
    if (!asked) {
        NSBox *ruler = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        [ruler setBoxType:NSBoxPrimary];
        [ruler setTitle:@"X"];
        NSView *inside = [[NSView alloc] initWithFrame:NSZeroRect];
        [ruler setContentView:inside];
        NSRect own = [ruler bounds];
        NSRect held = [inside frame];
        known[0] = held.origin.x;
        known[1] = own.size.height - (held.origin.y + held.size.height);
        known[2] = own.size.width - (held.origin.x + held.size.width);
        known[3] = held.origin.y;
        [inside release];
        [ruler release];
        asked = 1;
    }
    out[0] = known[0]; out[1] = known[1]; out[2] = known[2]; out[3] = known[3];
}

void ctd_chrome_of(id object, double *out) {
    out[0] = 0.0; out[1] = 0.0; out[2] = 0.0; out[3] = 0.0;
    if ([object isKindOfClass:[NSSplitView class]]) {
        // The divider's thickness, on the axis it eats. The two panes together
        // get everything but this, which is what a layout needs to know and
        // the only part of a split view's geometry that is not the platform's
        // own business.
        NSSplitView *split = (NSSplitView *)object;
        if ([split isVertical]) out[2] = [split dividerThickness];
        else                    out[3] = [split dividerThickness];
        return;
    }
    if ([object isKindOfClass:[NSTabView class]]) {
        // AppKit's own, and it does not depend on the size: contentRect at any
        // frame, zero included, reports the same four gaps. It is also where
        // AppKit itself puts a page, which is the number that has to agree.
        NSTabView *tabs = (NSTabView *)object;
        NSRect own = [tabs bounds];
        NSRect inner = [tabs contentRect];
        out[0] = inner.origin.x;
        out[1] = own.size.height - (inner.origin.y + inner.size.height);
        out[2] = own.size.width - (inner.origin.x + inner.size.width);
        out[3] = inner.origin.y;
        return;
    }
    if ([object isKindOfClass:[NSBox class]]) {
        // A separator is an NSBox too and holds nothing, so it has no content
        // to leave room for.
        if ([(NSBox *)object boxType] == NSBoxSeparator) return;
        ctd_box_chrome(out);
        return;
    }
    if ([object isKindOfClass:[CortadoDisclosure class]]) {
        CortadoDisclosure *twisty = (CortadoDisclosure *)object;
        out[1] = (double)[twisty headerHeight];
        return;
    }
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
    // A tab view's children are its pages, and a page is not a subview: it
    // belongs to an NSTabViewItem, which AppKit installs and removes as the
    // selection moves. Asked first, because a tab view is an NSView and would
    // otherwise take the ordinary path and end up holding a subview nobody
    // could see.
    NSTabView *tabs = ctd_tab_view(owner);
    if (tabs) return ctd_tab_add_page(tabs, view, index);
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
    NSTabView *tabs = ctd_tab_view(owner);
    if (tabs) {
        NSInteger at = ctd_tab_index_of(tabs, view);
        if (at == NSNotFound) return CTD_ERR_RANGE;
        [tabs removeTabViewItem:[tabs tabViewItemAtIndex:at]];
        return CTD_OK;
    }
    NSView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    if ([view superview] != container) return CTD_ERR_RANGE;
    [view removeFromSuperview];
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    NSTabView *tabs = ctd_tab_view(owner);
    if (tabs) {
        int32_t count = (int32_t)[tabs numberOfTabViewItems];
        if (from < 0 || from >= count || to < 0 || to >= count) return CTD_ERR_RANGE;
        if (from == to) return CTD_OK;
        // Remove and re-insert is the move here, and unlike a subview it is
        // exactly equivalent: an NSTabViewItem carries its label, its view and
        // its identifier with it, and the item object itself is what moves.
        NSTabViewItem *moving = [[tabs tabViewItemAtIndex:(NSInteger)from] retain];
        BOOL was_showing = [tabs selectedTabViewItem] == moving;
        [tabs removeTabViewItem:moving];
        [tabs insertTabViewItem:moving atIndex:(NSInteger)to];
        if (was_showing) [tabs selectTabViewItem:moving];
        [moving release];
        return CTD_OK;
    }
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
    NSTabView *tabs = ctd_tab_view(owner);
    if (tabs) {
        if (out) *out = (int32_t)[tabs numberOfTabViewItems];
        return CTD_OK;
    }
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
    id wanted = nil;
    NSTabView *tabs = ctd_tab_view(owner);
    if (tabs) {
        if (index < 0 || index >= (int32_t)[tabs numberOfTabViewItems]) return 0;
        wanted = [[tabs tabViewItemAtIndex:(NSInteger)index] view];
    } else {
    NSView *container = ctd_container_of(owner);
    if (!container || !ctd_can_hold(container)) return 0;
    NSArray *children = ctd_children(container);
    if (index < 0 || index >= (int32_t)[children count]) return 0;
    wanted = [children objectAtIndex:(NSUInteger)index];
    }
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
    // A split view's panes are the platform's to place, and it will place
    // them again on its next layout pass whatever is written here. Writing
    // anyway is worse than doing nothing: -setFrame: on a pane makes AppKit
    // post splitViewDidResizeSubviews, and the program would hear its own
    // layout come back as a value change.
    NSView *owner = [view superview];
    if (owner && [owner isKindOfClass:[NSSplitView class]]) return CTD_OK;
    [view setFrame:NSMakeRect(x, y, width, height)];
    return CTD_OK;
}

ctd_status ctd_view_content_inset(ctd_handle widget, double *out_inset) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSView class]]) return CTD_ERR_KIND;
    double chrome[4];
    ctd_chrome_of(object, chrome);
    if (out_inset) {
        out_inset[0] = chrome[0];
        out_inset[1] = chrome[1];
        out_inset[2] = chrome[2];
        out_inset[3] = chrome[3];
    }
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

// The surface a widget is in.
//
// The window is what AppKit answers; turning it back into a handle is a scan
// of the table, and that is the right trade here. A reverse map would have to
// be kept correct on every track and untrack — two more places to be wrong —
// to save a walk over eight thousand pointers on a call that happens when a
// control is set up, not when it draws.
ctd_handle ctd_view_surface(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object || ![object isKindOfClass:[NSView class]]) return 0;
    NSWindow *window = [(NSView *)object window];
    if (!window) return 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == window) {
            return ((uint64_t)g_generation[slot] << 32) | slot;
        }
    }
    return 0;
}
