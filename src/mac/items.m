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

ctd_status ctd_items_clear(ctd_handle widget) {
    NSPopUpButton *menu = ctd_item_list(ctd_resolve(widget));
    if (!ctd_resolve(widget)) return CTD_ERR_STALE;
    if (!menu) return CTD_ERR_KIND;
    [menu removeAllItems];
    return CTD_OK;
}

ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    if (len < 0) return CTD_ERR_RANGE;
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
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    if (out) *out = (int32_t)[menu numberOfItems];
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    if (index < 0 || index >= (int32_t)[menu numberOfItems]) return CTD_ERR_RANGE;
    return ctd_copy_out([[menu itemAtIndex:index] title], out, cap);
}
