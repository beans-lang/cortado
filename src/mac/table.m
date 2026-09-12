// Rows and columns, filled by asking rather than by building.
//
// The one control in this host that calls *into* Beans. The reasoning is in
// ../cortado_host.h beside ctd_table_fn; what is here is AppKit's half of it:
// an NSTableView inside an NSScrollView, and one object standing in as its
// data source and delegate.

#import "internal.h"

// One source for the process, like the event sink, and routed the same way:
// on the table's handle. Not one per table — a stored callback per control is
// a leak by construction, which the hazard note at the top of the header
// states in full.
static ctd_table_fn g_table_source;
static void        *g_table_context;

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
        [view addTableColumn:column];
        [column release];
    }
    [view reloadData];
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
