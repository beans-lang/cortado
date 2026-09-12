// Rows and columns, filled by asking rather than by building.
//
// UIKit's half of the contract in ../cortado_host.h. A UITableView is already
// a pull data source — it asks for the cells it is about to draw and nothing
// else — so the shape fits exactly. What does not fit is the *columns*: a
// UITableView is a list, and the cell styles that look like two columns are a
// label and a detail label, not columns anything can size, title or sort. So
// more than one column is CTD_ERR_UNSUPPORTED here and honest about it.

#import "internal.h"

static ctd_table_fn g_table_source;
static void        *g_table_context;

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
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section {
    (void)view; (void)section;
    return _rows;
}

- (UITableViewCell *)tableView:(UITableView *)view
         cellForRowAtIndexPath:(NSIndexPath *)where {
    UITableViewCell *cell = [view dequeueReusableCellWithIdentifier:@"ctd"];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:@"ctd"] autorelease];
    }
    [[cell textLabel] setText:ctd_table_text(_handle, (int32_t)[where row], 0)];
    return cell;
}

- (NSString *)tableView:(UITableView *)view titleForHeaderInSection:(NSInteger)section {
    (void)view; (void)section;
    return _title;
}

- (void)tableView:(UITableView *)view didSelectRowAtIndexPath:(NSIndexPath *)where {
    (void)view;
    ctd_emit(CTD_EV_SELECTION, _handle, (int64_t)[where row], 0);
}

- (void)dealloc {
    [_title release];
    [super dealloc];
}
@end

UITableView *ctd_table_view(id object) {
    if ([object isKindOfClass:[UITableView class]]) return (UITableView *)object;
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
    UITableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (count < 0) return CTD_ERR_RANGE;
    // One, or none. Two would have to be drawn by cortado rather than by
    // UIKit, and a column nobody can size or sort is not the column the caller
    // asked for — see the note beside ctd_table_columns in the header.
    if (count > 1) return CTD_ERR_UNSUPPORTED;
    [view reloadData];
    return CTD_OK;
}

ctd_status ctd_table_column_title(ctd_handle table, int32_t column,
                                  const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    UITableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (column != 0) return CTD_ERR_RANGE;
    CortadoTableSource *source = (CortadoTableSource *)[view dataSource];
    if (!source) return CTD_ERR_STATE;
    // A section header is the nearest thing a list has to a column title, and
    // it is what a UIKit program would use for the same words.
    [source setTitle:ctd_string(utf8, len)];
    [view reloadData];
    return CTD_OK;
}

ctd_status ctd_table_column_width(ctd_handle table, int32_t column, double points) {
    (void)points;
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    if (!ctd_table_view(object)) return CTD_ERR_KIND;
    if (column != 0) return CTD_ERR_RANGE;
    // The one column is the width of the table. There is nothing to set, and
    // saying so beats accepting a number and ignoring it.
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_table_rows(ctd_handle table, int32_t count) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    UITableView *view = ctd_table_view(object);
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
    UITableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    [view reloadData];
    return CTD_OK;
}

int32_t ctd_table_cell(ctd_handle table, int32_t row, int32_t column,
                       char *out, int32_t cap) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    UITableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    CortadoTableSource *source = (CortadoTableSource *)[view dataSource];
    if (!source) return CTD_ERR_STATE;
    if (row < 0 || row >= [source rows]) return CTD_ERR_RANGE;
    if (column != 0) return CTD_ERR_RANGE;
    // Through the data source, the way the table itself asks — so what comes
    // back is what a drawn row would hold, not what cortado believes.
    UITableViewCell *cell =
        [source tableView:view
        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    NSString *text = [[cell textLabel] text];
    return ctd_copy_out(text ? text : @"", out, cap);
}

ctd_status ctd_table_selected(ctd_handle table, int32_t *out) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    UITableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    NSIndexPath *where = [view indexPathForSelectedRow];
    if (out) *out = where ? (int32_t)[where row] : -1;
    return CTD_OK;
}

ctd_status ctd_table_select(ctd_handle table, int32_t row) {
    id object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    UITableView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (row < 0) {
        NSIndexPath *where = [view indexPathForSelectedRow];
        if (where) [view deselectRowAtIndexPath:where animated:NO];
        return CTD_OK;
    }
    CortadoTableSource *source = (CortadoTableSource *)[view dataSource];
    if (!source || row >= [source rows]) return CTD_ERR_RANGE;
    [view selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                      animated:NO
                scrollPosition:UITableViewScrollPositionNone];
    return CTD_OK;
}
