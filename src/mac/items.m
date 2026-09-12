// A control that offers a list of choices.
//
// Items are replaced wholesale rather than patched — the reasoning is beside
// `ctd_items_clear` in ../cortado_host.h.

#import "internal.h"

// ------------------------------------------------------------------ item lists

// The control that holds the items. A combo box is its own list; a wrapper —
// a text area's scroll view, say — is not, and answers nil so the caller gets
// CTD_ERR_KIND rather than a silent no-op.
static NSPopUpButton *ctd_item_list(id object) {
    if ([object isKindOfClass:[NSPopUpButton class]]) return (NSPopUpButton *)object;
    return nil;
}

// A segmented control holds the same list and keeps it in a different place:
// AppKit has no menu behind it, only a segment count and a label per segment.
// Both answer ctd_items_*, because "a list of choices" is one idea and a
// caller should not have to know which control it landed in.
static NSSegmentedControl *ctd_item_bar(id object) {
    if ([object isKindOfClass:[NSSegmentedControl class]]) {
        return (NSSegmentedControl *)object;
    }
    return nil;
}

ctd_status ctd_items_clear(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    // A list is not a property and does not come through ctd_set_*, and a
    // segmented control with three segments is wider than one with none.
    ctd_forget_size(widget);
    NSSegmentedControl *bar = ctd_item_bar(object);
    if (bar) { [bar setSegmentCount:0]; return CTD_OK; }
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    [menu removeAllItems];
    return CTD_OK;
}

ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    ctd_forget_size(widget);
    NSSegmentedControl *bar = ctd_item_bar(object);
    if (len < 0) return CTD_ERR_RANGE;
    if (bar) {
        NSInteger at = [bar segmentCount];
        [bar setSegmentCount:at + 1];
        [bar setLabel:ctd_string(utf8, len) forSegment:at];
        return CTD_OK;
    }
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    NSString *text = ctd_string(utf8, len);
    // NSPopUpButton drops a duplicate title, which would silently renumber
    // every later index and make a selection point at the wrong row. Adding
    // the item directly keeps the list exactly as the caller wrote it.
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:text
                                                 action:NULL
                                          keyEquivalent:@""];
    [[menu menu] addItem:item];
    [item release];
    return CTD_OK;
}

ctd_status ctd_items_count(ctd_handle widget, int32_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSSegmentedControl *bar = ctd_item_bar(object);
    if (bar) {
        if (out) *out = (int32_t)[bar segmentCount];
        return CTD_OK;
    }
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    if (out) *out = (int32_t)[menu numberOfItems];
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSSegmentedControl *bar = ctd_item_bar(object);
    if (bar) {
        if (index < 0 || index >= (int32_t)[bar segmentCount]) return CTD_ERR_RANGE;
        NSString *label = [bar labelForSegment:index];
        return ctd_copy_out(label ? label : @"", out, cap);
    }
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    if (index < 0 || index >= (int32_t)[menu numberOfItems]) return CTD_ERR_RANGE;
    return ctd_copy_out([[menu itemAtIndex:index] title], out, cap);
}
