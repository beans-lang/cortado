// AppKit regression: compact styling, chrome-free pages, and keyboard cells.
#import "../src/mac/internal.h"
#include <assert.h>
#import <objc/runtime.h>
#include <stdio.h>

static int32_t words(void *context, ctd_handle table, int32_t row, int32_t col, char *out, int32_t cap) {
    const char *text = "value";
    if (out && cap >= 5) memcpy(out, text, 5);
    return 5;
}
static void key(CortadoDataTable *table, unsigned short code, NSEventModifierFlags flags) {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:flags timestamp:0 windowNumber:0 context:nil
        characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
    [table keyDown:event];
}
int main(void) {
    @autoreleasepool {
        assert(ctd_init(CTD_ABI_VERSION) == CTD_OK);
        ctd_handle tabs = ctd_widget_new(CTD_W_TAB_VIEW);
        double inset[4];
        assert(ctd_set_int(tabs, CTD_P_BORDERLESS, 1) == CTD_OK);
        assert(ctd_view_content_inset(tabs, inset) == CTD_OK);
        assert(inset[0] == 0 && inset[1] == 0 && inset[2] == 0 && inset[3] == 0);
        assert(ctd_set_int(tabs, CTD_P_BORDERLESS, 0) == CTD_OK);
        assert(ctd_view_content_inset(tabs, inset) == CTD_OK);
        assert(inset[0] + inset[1] + inset[2] + inset[3] > 0);
        assert(ctd_set_int(tabs, CTD_P_BORDERLESS, 2) == CTD_ERR_RANGE);
        ctd_handle handle = ctd_widget_new(CTD_W_TABLE);
        assert(ctd_set_int(handle, CTD_P_BORDERLESS, 1) == CTD_ERR_KIND);
        assert(ctd_set_int(handle, CTD_P_COMPACT, 1) == CTD_OK);
        assert(ctd_table_columns(handle, 3) == CTD_OK);
        ctd_set_table_source(words, NULL);
        assert(ctd_table_rows(handle, 4) == CTD_OK);
        ctd_view_set_frame(handle, 0, 0, 280, 100);
        CortadoDataTable *table = (CortadoDataTable *)ctd_table_view(ctd_resolve(handle));
        assert([table rowHeight] == 23);
        assert([[[[table tableColumns] objectAtIndex:0] dataCell] font].pointSize == 12);
        assert([table gridStyleMask] == NSTableViewSolidVerticalGridLineMask);
        ctd_handle window = ctd_surface_new(420, 260);
        ctd_handle root = ctd_widget_new(CTD_W_CONTAINER);
        assert(ctd_surface_set_root(window, root) == CTD_OK);
        assert(ctd_view_add_child(root, handle, 0) == CTD_OK);
        assert(ctd_widget_focus(handle) == CTD_OK);
        assert(ctd_widget_focused(handle) == 1);
        ctd_handle editor = ctd_widget_new(CTD_W_TEXT_AREA);
        assert(ctd_view_add_child(root, editor, 1) == CTD_OK);
        assert(ctd_widget_focus(editor) == CTD_OK);
        assert(ctd_widget_focused(editor) == 1 && ctd_widget_focused(handle) == 0);
        assert(ctd_widget_focus(handle) == CTD_OK);
        ctd_table_select(handle, 0);
        key(table, 124, 0); assert([table ctdActiveColumn] == 1);
        key(table, 48, 0); assert([table ctdActiveColumn] == 2);
        key(table, 48, 0); assert([table ctdActiveColumn] == 0 && [table selectedRow] == 1);
        key(table, 48, NSEventModifierFlagShift); assert([table ctdActiveColumn] == 2 && [table selectedRow] == 0);
        key(table, 36, 0); assert([table editedRow] == -1); // policy is read-only
        assert(ctd_set_int(handle, CTD_P_COMPACT, 0) == CTD_OK);
        assert([table gridStyleMask] == NSTableViewGridNone);
        ctd_handle outline = ctd_widget_new(CTD_W_OUTLINE_VIEW);
        assert(ctd_set_int(outline, CTD_P_COMPACT, 1) == CTD_OK);
        assert([ctd_outline_view(ctd_resolve(outline)) headerView] == nil);
        assert(ctd_set_int(outline, CTD_P_COMPACT, 0) == CTD_OK);
        assert([ctd_outline_view(ctd_resolve(outline)) headerView] != nil);
        ctd_widget_release(editor);
        ctd_widget_release(outline);
        ctd_widget_release(handle);
        ctd_widget_release(tabs);
        puts("native browser controls: true");
    }
    return 0;
}
