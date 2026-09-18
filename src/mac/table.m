// Rows and columns, filled by asking rather than by building.
//
// The one control in this host that calls *into* Beans. The reasoning is in
// ../cortado_host.h beside ctd_table_fn; what is here is AppKit's half of it:
// an NSTableView inside an NSScrollView, and one object standing in as its
// data source and delegate.

#import "internal.h"
#import <objc/runtime.h>

// One source for the process, like the event sink, and routed the same way:
// on the table's handle. Not one per table — a stored callback per control is
// a leak by construction, which the hazard note at the top of the header
// states in full.
static ctd_table_fn g_table_source;
static void        *g_table_context;
static ctd_table_editable_fn g_table_edit_policy;
static void                  *g_table_edit_context;

// The text of one cell, asked for the way ctd_get_text answers: write at most
// `cap`, answer what was needed. A 256-byte stack buffer covers a cell in
// almost every table there has ever been, and the heap path is there for the
// one that does not — truncating instead would be a table that is subtly wrong
// exactly where the data is interesting.
static NSString *ctd_table_text(ctd_handle table, int32_t row, int32_t column) {
    if (!g_table_source) return @"";
    char small[256];
    int32_t needed = g_table_source(g_table_context, table, row, column,
                                    small, (int32_t)sizeof small);
    if (needed <= 0) return @"";
    if (needed <= (int32_t)sizeof small) {
        NSString *text = [[[NSString alloc] initWithBytes:small
                                                  length:(NSUInteger)needed
                                                encoding:NSUTF8StringEncoding] autorelease];
        return text ? text : @"";
    }
    char *big = (char *)malloc((size_t)needed);
    if (!big) return @"";
    int32_t wrote = g_table_source(g_table_context, table, row, column, big, needed);
    NSString *text = nil;
    if (wrote > 0) {
        text = [[[NSString alloc] initWithBytes:big
                                         length:(NSUInteger)(wrote < needed ? wrote : needed)
                                       encoding:NSUTF8StringEncoding] autorelease];
    }
    free(big);
    return text ? text : @"";
}

@implementation CortadoDataTable
- (BOOL)ctdCompact {
    return [objc_getAssociatedObject(self, @selector(ctdCompact)) boolValue];
}
- (void)drawBackgroundInClipRect:(NSRect)clip {
    if (![self ctdCompact]) { [super drawBackgroundInClipRect:clip]; return; }
    BOOL dark = [[[self effectiveAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    [[NSColor colorWithCalibratedWhite:dark ? 0.12 : 1.0 alpha:1] setFill];
    NSRectFill(clip);
    CGFloat pitch = [self rowHeight] + [self intercellSpacing].height;
    NSInteger first = MAX(0, (NSInteger)floor(NSMinY(clip) / pitch));
    NSInteger last = (NSInteger)ceil(NSMaxY(clip) / pitch);
    [[NSColor colorWithCalibratedWhite:dark ? 0.155 : 0.96 alpha:1] setFill];
    for (NSInteger row = first; row <= last; row++) {
        if (row % 2) NSRectFill(NSIntersectionRect(clip, NSMakeRect(0, row * pitch, [self bounds].size.width, pitch)));
    }
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger column = [self columnAtPoint:point];
    if (column >= 0) _ctdActiveColumn = column;
    [super mouseDown:event];
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    if (![self ctdCompact] || [self selectedRow] < 0 ||
        _ctdActiveColumn < 0 || _ctdActiveColumn >= [self numberOfColumns]) return;
    NSRect cell = [self frameOfCellAtColumn:_ctdActiveColumn row:[self selectedRow]];
    [[NSColor keyboardFocusIndicatorColor] setStroke];
    NSBezierPath *ring = [NSBezierPath bezierPathWithRect:NSInsetRect(cell, 1, 1)];
    [ring setLineWidth:2];
    [ring stroke];
}
- (void)copy:(id)sender {
    if (![self ctdCompact] || [self selectedRow] < 0 || [self numberOfColumns] == 0) return;
    NSInteger col = MIN(MAX(0, _ctdActiveColumn), [self numberOfColumns] - 1);
    id value = [[self dataSource] tableView:self objectValueForTableColumn:[[self tableColumns] objectAtIndex:col] row:[self selectedRow]];
    if (![value isKindOfClass:[NSString class]]) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:value forType:NSPasteboardTypeString];
}
- (void)keyDown:(NSEvent *)event {
    if (![self ctdCompact]) { [super keyDown:event]; return; }
    NSString *key = [event charactersIgnoringModifiers];
    if (([event modifierFlags] & NSEventModifierFlagCommand) && [key isEqualToString:@"c"]) {
        [self copy:nil]; return;
    }
    NSInteger row = [self selectedRow];
    NSInteger cols = [self numberOfColumns];
    if (row < 0 || cols == 0) { [super keyDown:event]; return; }
    _ctdActiveColumn = MIN(MAX(0, _ctdActiveColumn), cols - 1);
    unsigned short code = [event keyCode];
    if (code == 123 || code == 124 || code == 48) {
        NSInteger step = code == 123 || (code == 48 && ([event modifierFlags] & NSEventModifierFlagShift)) ? -1 : 1;
        NSInteger col = _ctdActiveColumn + step;
        if (code == 48 && col >= cols && row + 1 < [self numberOfRows]) { row++; col = 0; }
        if (code == 48 && col < 0 && row > 0) { row--; col = cols - 1; }
        _ctdActiveColumn = MIN(MAX(0, col), cols - 1);
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [self scrollRowToVisible:row];
        [self scrollColumnToVisible:_ctdActiveColumn];
        [self setNeedsDisplay:YES];
        return;
    }
    if (code == 36 || code == 76) {
        NSTableColumn *column = [[self tableColumns] objectAtIndex:_ctdActiveColumn];
        id delegate = [self delegate];
        if ([delegate respondsToSelector:@selector(tableView:shouldEditTableColumn:row:)] &&
            [delegate tableView:self shouldEditTableColumn:column row:row]) {
            [self editColumn:_ctdActiveColumn row:row withEvent:nil select:YES];
        }
        return;
    }
    [super keyDown:event];
    [self setNeedsDisplay:YES];
}
@end

@implementation CortadoTableSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)view {
    (void)view;
    return _rows;
}

- (id)tableView:(NSTableView *)view
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
    NSInteger at = [[view tableColumns] indexOfObject:column];
    if (at == NSNotFound) return @"";
    return ctd_table_text(_handle, (int32_t)row, (int32_t)at);
}

- (BOOL)tableView:(NSTableView *)view
    shouldEditTableColumn:(NSTableColumn *)column
                     row:(NSInteger)row {
    NSInteger at = [[view tableColumns] indexOfObject:column];
    if (!_editable || !g_table_edit_policy || at == NSNotFound ||
        row < 0 || row >= _rows) return NO;
    return g_table_edit_policy(g_table_edit_context, _handle,
                               (int32_t)row, (int32_t)at) != 0;
}

- (void)tableView:(NSTableView *)view
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row {
    NSInteger at = [[view tableColumns] indexOfObject:column];
    if (at == NSNotFound || row < 0 || row >= _rows) return;
    if (![self tableView:view shouldEditTableColumn:column row:row]) {
        [view reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                       columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)at]];
        return;
    }
    NSString *text = [value isKindOfClass:[NSString class]] ? value : @"";
    const char *bytes = [text UTF8String];
    NSUInteger byteCount = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (!bytes || byteCount > INT32_MAX || ctd_has_nul(bytes, (int32_t)byteCount)) return;
    int32_t length = (int32_t)byteCount;
    ctd_handle handle = _handle;
    [view retain];
    [text retain];
    if (g_sink && !g_writing) {
        ctd_event event;
        memset(&event, 0, sizeof event);
        event.kind = CTD_EV_TEXT_COMMIT;
        event.target = handle;
        event.index = (int64_t)row;
        event.token = (int64_t)at;
        event.text = bytes;
        event.text_len = length;
        g_sink(g_sink_context, &event);
    }
    // The handler may close the table or replace its source. Read back only
    // while the handle remains live; accepted and rejected edits both redraw
    // from the source instead of keeping an unsaved editor value.
    if (ctd_resolve(handle) && row < [view numberOfRows] &&
        at < (NSInteger)[[view tableColumns] count]) {
        [view reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                       columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)at]];
    }
    [text release];
    [view release];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    // Not when the program did it. NSTableView posts this for
    // -selectRowIndexes: exactly as it does for a click, and the header's
    // rule is that a write is silent — see g_writing in internal.h. A
    // navigator that opens a node and then selects it would otherwise hear
    // the selection and toggle the node shut again, which is what
    // examples/cask did.
    if (g_writing) return;
    NSTableView *view = (NSTableView *)[note object];
    NSInteger row = [view isKindOfClass:[NSTableView class]] ? [view selectedRow] : -1;
    ctd_emit(CTD_EV_SELECTION, _handle, (int64_t)row, 0);
}
@end

// The NSTableView a handle stands for. cortado tracks the *scroll view*,
// because that is the thing with a frame — a table that cannot scroll is a
// table with a hidden bottom — and every call here reaches through it.
NSTableView *ctd_table_view(id object) {
    if (![object isKindOfClass:[NSScrollView class]]) return nil;
    id inner = [(NSScrollView *)object documentView];
    if ([inner isKindOfClass:[NSTableView class]]) return (NSTableView *)inner;
    return nil;
}

// -------------------------------------------------------------- entry points

ctd_status ctd_set_table_source(ctd_table_fn source, void *context) {
    g_table_source = source;
    g_table_context = context;
    return CTD_OK;
}

ctd_status ctd_set_table_edit_policy(ctd_table_editable_fn policy, void *context) {
    g_table_edit_policy = policy;
    g_table_edit_context = context;
    return CTD_OK;
}

ctd_status ctd_table_columns(ctd_handle table, int32_t count) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (count < 0) return CTD_ERR_RANGE;
    while ([[view tableColumns] count] > 0) {
        [view removeTableColumn:[[view tableColumns] objectAtIndex:0]];
    }
    for (int32_t i = 0; i < count; i++) {
        NSString *name = [NSString stringWithFormat:@"c%d", i];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:name];
        [[column headerCell] setStringValue:@""];
        CortadoTableSource *source = (CortadoTableSource *)[view dataSource];
        BOOL editing = source && [source editable];
        [column setEditable:editing];
        if ([objc_getAssociatedObject(view, @selector(ctdCompact)) boolValue]) {
            [[column dataCell] setFont:[NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular]];
            [[column dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
        }
        [[column dataCell] setSelectable:YES];
        [[column dataCell] setEditable:editing];
        [view addTableColumn:column];
        [column release];
    }
    [view reloadData];
    return CTD_OK;
}

ctd_status ctd_table_editing(ctd_handle table, int32_t on) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (on != 0 && on != 1) return CTD_ERR_RANGE;
    CortadoTableSource *source = (CortadoTableSource *)[view dataSource];
    if (!source) return CTD_ERR_STATE;
    [source setEditable:on != 0];
    for (NSTableColumn *column in [view tableColumns]) {
        [column setEditable:on != 0];
        [[column dataCell] setSelectable:YES];
        [[column dataCell] setEditable:on != 0];
    }
    return CTD_OK;
}

ctd_status ctd_table_edit_as_user(ctd_handle table, int32_t row, int32_t column,
                                  const char *utf8, int32_t len) {
    if (len < 0 || (!utf8 && len > 0) || ctd_has_nul(utf8, len))
        return CTD_ERR_RANGE;
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (row < 0 || row >= [view numberOfRows] ||
        column < 0 || column >= (int32_t)[[view tableColumns] count]) return CTD_ERR_RANGE;
    CortadoTableSource *source = (CortadoTableSource *)[view dataSource];
    NSTableColumn *at = [[view tableColumns] objectAtIndex:(NSUInteger)column];
    if (!source || ![source tableView:view shouldEditTableColumn:at row:row])
        return CTD_ERR_STATE;
    [source tableView:view setObjectValue:ctd_string(utf8, len)
                           forTableColumn:at row:row];
    return CTD_OK;
}

ctd_status ctd_table_column_title(ctd_handle table, int32_t column,
                                  const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (column < 0 || column >= (int32_t)[[view tableColumns] count]) return CTD_ERR_RANGE;
    [[[[view tableColumns] objectAtIndex:column] headerCell]
        setStringValue:ctd_string(utf8, len)];
    return CTD_OK;
}

ctd_status ctd_table_column_width(ctd_handle table, int32_t column, double points) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (column < 0 || column >= (int32_t)[[view tableColumns] count]) return CTD_ERR_RANGE;
    if (points <= 0.0) return CTD_ERR_RANGE;
    [[[view tableColumns] objectAtIndex:column] setWidth:(CGFloat)points];
    return CTD_OK;
}

ctd_status ctd_table_rows(ctd_handle table, int32_t count) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (count < 0) return CTD_ERR_RANGE;
    CortadoTableSource *source = (CortadoTableSource *)[view dataSource];
    if (!source) return CTD_ERR_STATE;
    [source setRows:count];
    [view reloadData];
    return CTD_OK;
}

ctd_status ctd_table_reload(ctd_handle table) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    [view reloadData];
    return CTD_OK;
}

int32_t ctd_table_cell(ctd_handle table, int32_t row, int32_t column,
                       char *out, int32_t cap) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (row < 0 || row >= [view numberOfRows]) return CTD_ERR_RANGE;
    NSArray *columns = [view tableColumns];
    if (column < 0 || column >= (int32_t)[columns count]) return CTD_ERR_RANGE;
    // Through the data source, not around it: asking cortado's own book again
    // would prove only that cortado agrees with itself.
    id value = [[view dataSource] tableView:view
                  objectValueForTableColumn:[columns objectAtIndex:column]
                                        row:row];
    NSString *text = [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
    return ctd_copy_out(text, out, cap);
}

ctd_status ctd_table_selected(ctd_handle table, int32_t *out) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (out) *out = (int32_t)[view selectedRow];
    return CTD_OK;
}

ctd_status ctd_table_select(ctd_handle table, int32_t row) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    NSTableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (row < 0) {
        g_writing = g_writing + 1;
        [view deselectAll:nil];
        g_writing = g_writing - 1;
        return CTD_OK;
    }
    if (row >= [view numberOfRows]) return CTD_ERR_RANGE;
    g_writing = g_writing + 1;
    [view selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
      byExtendingSelection:NO];
    g_writing = g_writing - 1;
    return CTD_OK;
}
