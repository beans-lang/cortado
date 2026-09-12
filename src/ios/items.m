// A control that offers a list of choices.

#import "internal.h"

// A segmented control holds the same list of choices in a different place:
// UIKit puts them on the control itself rather than in a menu behind it. Both
// answer ctd_items_*, because "a list of choices" is one idea and a caller
// should not have to know which control it landed in.
ctd_status ctd_items_clear(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) == CTD_W_SEGMENTED) {
        [(UISegmentedControl *)object removeAllSegments];
        return CTD_OK;
    }
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    UIButton *menu = (UIButton *)object;
    [menu setMenu:[UIMenu menuWithChildren:@[]]];
    [menu setTag:-1];
    [menu setTitle:@"" forState:UIControlStateNormal];
    return CTD_OK;
}

ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (len < 0) return CTD_ERR_RANGE;
    if (ctd_slot_kind(widget) == CTD_W_SEGMENTED) {
        UISegmentedControl *bar = (UISegmentedControl *)object;
        [bar insertSegmentWithTitle:ctd_string(utf8, len)
                            atIndex:(NSUInteger)[bar numberOfSegments]
                           animated:NO];
        return CTD_OK;
    }
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    UIButton *menu = (UIButton *)object;
    UIMenu *existing = [menu menu];
    NSMutableArray *children =
        [NSMutableArray arrayWithArray:existing ? [existing children] : @[]];
    NSString *title = ctd_string(utf8, len);
    NSInteger position = (NSInteger)[children count];
    ctd_handle self_handle = widget;
    UIAction *item = [UIAction actionWithTitle:title
                                         image:nil
                                    identifier:nil
                                       handler:^(__kindof UIAction *action) {
        (void)action;
        id control = ctd_resolve(self_handle);
        if (!control) return;
        [(UIButton *)control setTag:position];
        [(UIButton *)control setTitle:title forState:UIControlStateNormal];
        ctd_emit_control(self_handle, control);
    }];
    [children addObject:item];
    [menu setMenu:[UIMenu menuWithChildren:children]];
    return CTD_OK;
}

ctd_status ctd_items_count(ctd_handle widget, int32_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) == CTD_W_SEGMENTED) {
        if (out) *out = (int32_t)[(UISegmentedControl *)object numberOfSegments];
        return CTD_OK;
    }
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    UIMenu *items = [(UIButton *)object menu];
    if (out) *out = items ? (int32_t)[[items children] count] : 0;
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) == CTD_W_SEGMENTED) {
        UISegmentedControl *bar = (UISegmentedControl *)object;
        if (index < 0 || index >= (int32_t)[bar numberOfSegments]) return CTD_ERR_RANGE;
        NSString *title = [bar titleForSegmentAtIndex:(NSUInteger)index];
        return ctd_copy_out(title ? title : @"", out, cap);
    }
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    UIMenu *items = [(UIButton *)object menu];
    NSArray *children = items ? [items children] : @[];
    if (index < 0 || index >= (int32_t)[children count]) return CTD_ERR_RANGE;
    UIMenuElement *item = [children objectAtIndex:(NSUInteger)index];
    return ctd_copy_out([item title], out, cap);
}
