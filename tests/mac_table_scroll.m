// Native regression for the database grid: fixed column widths must remain
// reachable after a split pane narrows the table's viewport.
#import "../src/mac/internal.h"
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        ctd_handle handle = ctd_widget_new(CTD_W_TABLE);
        if (!handle || ctd_table_columns(handle, 4) != CTD_OK) return 1;
        for (int32_t i = 0; i < 4; i++) {
            if (ctd_table_column_width(handle, i, 150.0) != CTD_OK) return 2;
        }
        if (ctd_view_set_frame(handle, 0, 0, 760, 160) != CTD_OK ||
            ctd_view_set_frame(handle, 0, 0, 300, 160) != CTD_OK) return 3;
        NSScrollView *scroll = (NSScrollView *)ctd_resolve(handle);
        NSTableView *table = ctd_table_view(scroll);
        NSClipView *clip = [scroll contentView];
        BOOL wide = [table frame].size.width > [clip bounds].size.width;
        BOOL fixed = YES;
        for (NSTableColumn *column in [table tableColumns]) {
            if (fabs([column width] - 150.0) > 0.1) fixed = NO;
        }
        [clip scrollToPoint:NSMakePoint(120, 0)];
        [scroll reflectScrolledClipView:clip];
        BOOL moved = [clip bounds].origin.x > 0;
        BOOL passed = [scroll hasHorizontalScroller] && wide && fixed && moved;
        printf("native table horizontal scroll: %s\n", passed ? "true" : "false");
        ctd_widget_release(handle);
        return passed ? 0 : 4;
    }
}
