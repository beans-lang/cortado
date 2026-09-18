// A tree, filled by asking about one node at a time.
//
// The table's data source with identity added. The reasoning is in
// ../cortado_host.h beside `ctd_outline_fn`; what is here is AppKit's half of
// it, and the whole of the work is one problem:
//
// **NSOutlineView deals in objects; cortado deals in int64s.** The control
// hands an `id` back in every callback and compares items by pointer, so the
// *same* node has to be the *same* object every time or the control loses
// track of what is open the moment it asks again. So this file keeps one
// NSNumber per node and hands out that one — a small map that exists purely
// because two ways of naming a thing meet here.
//
// The map is per outline and cleared when the control is reloaded from the
// root, which is also the only moment a node id may legitimately mean
// something else than it did before.

#import "internal.h"
#import <objc/runtime.h>

static ctd_outline_fn      g_outline_shape;
static void               *g_outline_shape_context;
static ctd_outline_text_fn g_outline_text;
static void               *g_outline_text_context;

@implementation CortadoOutlineSource

- (id)init {
    self = [super init];
    if (self) {
        // Strong on the values so the NSNumber a node was given stays alive
        // as long as the control may ask about it; the keys are boxed ints.
        _nodes = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_nodes release];
    [super dealloc];
}

// The one object standing for a node, made once and handed out every time.
- (NSNumber *)boxed:(int64_t)node {
    NSNumber *key = [NSNumber numberWithLongLong:(long long)node];
    NSNumber *kept = [_nodes objectForKey:key];
    if (kept) return kept;
    [_nodes setObject:key forKey:key];
    return key;
}

- (int64_t)nodeOf:(id)item {
    if (!item) return CTD_OUTLINE_ROOT;
    if (![item isKindOfClass:[NSNumber class]]) return CTD_OUTLINE_ROOT;
    return (int64_t)[(NSNumber *)item longLongValue];
}

- (void)forget {
    [_nodes removeAllObjects];
}

// ---- the data source ----

- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item {
    (void)view;
    if (!g_outline_shape) return 0;
    int64_t count = g_outline_shape(g_outline_shape_context, _handle,
                                    CTD_OUTLINE_CHILDREN, [self nodeOf:item], 0);
    return count > 0 ? (NSInteger)count : 0;
}

- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item {
    (void)view;
    if (!g_outline_shape) return [self boxed:CTD_OUTLINE_ROOT];
    int64_t child = g_outline_shape(g_outline_shape_context, _handle,
                                    CTD_OUTLINE_CHILD, [self nodeOf:item],
                                    (int32_t)index);
    return [self boxed:child];
}

- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item {
    (void)view;
    if (!g_outline_shape) return NO;
    // Asked, not inferred from the child count: a folder nobody has read yet
    // has no children to report and must still draw a twisty.
    return g_outline_shape(g_outline_shape_context, _handle, CTD_OUTLINE_EXPANDS,
                           [self nodeOf:item], 0) ? YES : NO;
}

- (id)outlineView:(NSOutlineView *)view
    objectValueForTableColumn:(NSTableColumn *)column
                       byItem:(id)item {
    NSInteger at = [[view tableColumns] indexOfObject:column];
    if (at == NSNotFound) return @"";
    return ctd_outline_words(_handle, [self nodeOf:item], (int32_t)at);
}

// A native view cell gives the first column room for an SF Symbol beside its
// text. AppKit keeps selection, focus, disclosure triangles, colors, and row
// reuse; Cortado supplies only the role of the symbol for the visible node.
- (NSView *)outlineView:(NSOutlineView *)view
    viewForTableColumn:(NSTableColumn *)column
                  item:(id)item {
    NSInteger at = [[view tableColumns] indexOfObject:column];
    if (at == NSNotFound) return nil;

    NSString *identifier = at == 0 ? @"cortado-outline-icon-cell"
                                    : @"cortado-outline-text-cell";
    NSTableCellView *cell = [view makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        CGFloat width = [column width];
        CGFloat height = [view rowHeight];
        cell = [[[NSTableCellView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0, width, height)] autorelease];
        [cell setIdentifier:identifier];

        NSTextField *label = [[[NSTextField alloc]
            initWithFrame:NSMakeRect(2.0, 0.0, width - 4.0, height)] autorelease];
        [label setBezeled:NO];
        [label setEditable:NO];
        [label setSelectable:NO];
        [label setDrawsBackground:NO];
        [label setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
        [label setLineBreakMode:NSLineBreakByTruncatingTail];
        [label setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [cell addSubview:label];
        [cell setTextField:label];

        if (at == 0) {
            NSImageView *picture = [[[NSImageView alloc]
                initWithFrame:NSMakeRect(2.0, (height - 15.0) / 2.0,
                                         15.0, 15.0)] autorelease];
            [picture setImageScaling:NSImageScaleProportionallyDown];
            [picture setAutoresizingMask:NSViewMinYMargin | NSViewMaxYMargin];
            [cell addSubview:picture];
            [cell setImageView:picture];
        }
    }

    if ([objc_getAssociatedObject(view, @selector(ctdCompact)) boolValue]) {
        [[cell textField] setFont:[NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular]];
    }
    [[cell textField] setStringValue:ctd_outline_words(_handle, [self nodeOf:item],
                                                        (int32_t)at)];
    if (at == 0) {
        int32_t role = CTD_ICON_NONE;
        if (g_outline_shape) {
            role = (int32_t)g_outline_shape(g_outline_shape_context, _handle,
                                            CTD_OUTLINE_ICON, [self nodeOf:item], 0);
        }
        NSImage *symbol = ctd_icon_image(role);
        [[cell imageView] setImage:symbol];
        [[cell imageView] setHidden:(symbol == nil)];
        CGFloat left = symbol ? 21.0 : 2.0;
        CGFloat width = [column width] - left - 2.0;
        [[cell textField] setFrame:NSMakeRect(left, 0.0,
            width > 0.0 ? width : 0.0, [view rowHeight])];
    }
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note {
    // Silent when the program did it, like every other write — see g_writing
    // in internal.h.
    if (g_writing) return;
    NSOutlineView *view = (NSOutlineView *)[note object];
    if (![view isKindOfClass:[NSOutlineView class]]) return;
    NSInteger row = [view selectedRow];
    int64_t node = row < 0 ? CTD_OUTLINE_ROOT
                           : [self nodeOf:[view itemAtRow:row]];
    ctd_emit(CTD_EV_SELECTION, _handle, node, 0);
}

@end

// The text of one cell, asked for the way ctd_get_text answers: write at most
// `cap`, answer what was needed. Same two-call shape and the same reason for
// the heap path as the table's.
NSString *ctd_outline_words(ctd_handle outline, int64_t node, int32_t column) {
    if (!g_outline_text) return @"";
    char small[256];
    int32_t needed = g_outline_text(g_outline_text_context, outline, node, column,
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
    int32_t wrote = g_outline_text(g_outline_text_context, outline, node, column,
                                   big, needed);
    NSString *text = nil;
    if (wrote > 0) {
        text = [[[NSString alloc] initWithBytes:big
                                         length:(NSUInteger)(wrote < needed ? wrote : needed)
                                       encoding:NSUTF8StringEncoding] autorelease];
    }
    free(big);
    return text ? text : @"";
}

// The NSOutlineView a handle stands for. cortado tracks the *scroll view*, as
// it does for a table, because that is the thing with a frame.
NSOutlineView *ctd_outline_view(id object) {
    if ([object isKindOfClass:[NSOutlineView class]]) return (NSOutlineView *)object;
    if ([object isKindOfClass:[NSScrollView class]]) {
        id inside = [(NSScrollView *)object documentView];
        if ([inside isKindOfClass:[NSOutlineView class]]) {
            return (NSOutlineView *)inside;
        }
    }
    return nil;
}

static CortadoOutlineSource *ctd_outline_source_of(NSOutlineView *view) {
    id source = [view dataSource];
    if ([source isKindOfClass:[CortadoOutlineSource class]]) {
        return (CortadoOutlineSource *)source;
    }
    return nil;
}

// Filled in after the handle exists, because the source carries the handle it
// answers for.
void ctd_outline_attach(ctd_handle outline, NSView *view) {
    NSOutlineView *rows = ctd_outline_view(view);
    if (!rows) return;
    CortadoOutlineSource *source = [[CortadoOutlineSource alloc] init];
    [source setHandle:outline];
    [rows setDataSource:source];
    [rows setDelegate:source];
    [g_targets addObject:source];
    [source release];
}

// ---------------------------------------------------------------- entry points

ctd_status ctd_set_outline_source(ctd_outline_fn shape, void *shape_context,
                                  ctd_outline_text_fn text, void *text_context) {
    g_outline_shape = shape;
    g_outline_shape_context = shape_context;
    g_outline_text = text;
    g_outline_text_context = text_context;
    return CTD_OK;
}

static NSOutlineView *ctd_outline_of(ctd_handle outline, ctd_status *problem) {
    id object = ctd_resolve(outline);
    if (!object) { *problem = CTD_ERR_STALE; return nil; }
    NSOutlineView *view = ctd_outline_view(object);
    if (!view) { *problem = CTD_ERR_KIND; return nil; }
    *problem = CTD_OK;
    return view;
}

ctd_status ctd_outline_columns(ctd_handle outline, int32_t count) {
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    if (count < 1) return CTD_ERR_RANGE;
    while ([[view tableColumns] count] > (NSUInteger)count) {
        [view removeTableColumn:[[view tableColumns] lastObject]];
    }
    while ([[view tableColumns] count] < (NSUInteger)count) {
        NSString *name = [NSString stringWithFormat:@"ctd-%lu",
                          (unsigned long)[[view tableColumns] count]];
        NSTableColumn *column =
            [[NSTableColumn alloc] initWithIdentifier:name];
        [column setWidth:120.0];
        [view addTableColumn:column];
        // The first column carries the indent and the twisty. AppKit needs
        // telling which one that is, and it is not told again when columns
        // are added later — so it is set every time the set changes.
        [column release];
    }
    if ([[view tableColumns] count] > 0) {
        [view setOutlineTableColumn:[[view tableColumns] objectAtIndex:0]];
    }
    return CTD_OK;
}

ctd_status ctd_outline_column_title(ctd_handle outline, int32_t column,
                                    const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    if (column < 0 || column >= (int32_t)[[view tableColumns] count]) {
        return CTD_ERR_RANGE;
    }
    [[[[view tableColumns] objectAtIndex:(NSUInteger)column] headerCell]
        setStringValue:ctd_string(utf8, len)];
    return CTD_OK;
}

ctd_status ctd_outline_column_width(ctd_handle outline, int32_t column,
                                    double points) {
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    if (column < 0 || column >= (int32_t)[[view tableColumns] count]) {
        return CTD_ERR_RANGE;
    }
    if (points <= 0.0) return CTD_ERR_RANGE;
    [[[view tableColumns] objectAtIndex:(NSUInteger)column] setWidth:points];
    return CTD_OK;
}

ctd_status ctd_outline_reload(ctd_handle outline) {
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    // The node map is *not* cleared. AppKit compares items by pointer, and
    // throwing the objects away here would make every open node a different
    // thing from the one the control remembers — so a reload would close the
    // tree, which is the one thing a refresh must not do.
    [view reloadData];
    return CTD_OK;
}

ctd_status ctd_outline_expand(ctd_handle outline, int64_t node, int32_t on) {
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    CortadoOutlineSource *source = ctd_outline_source_of(view);
    if (!source) return CTD_ERR_STATE;
    if (node == CTD_OUTLINE_ROOT) {
        // The root is always open — its children are the top level — so
        // opening it is a no-op and closing it is refused, the same answer
        // the other two hosts give.
        return on ? CTD_OK : CTD_ERR_RANGE;
    }
    id item = [source boxed:node];
    // A node the control has never been asked about is not one it can open.
    // -rowForItem: answers -1 for it, which is the check.
    if ([view rowForItem:item] < 0) return CTD_ERR_RANGE;
    g_writing = g_writing + 1;
    if (on) {
        [view expandItem:item];
    } else {
        [view collapseItem:item];
    }
    g_writing = g_writing - 1;
    return CTD_OK;
}

ctd_status ctd_outline_expanded(ctd_handle outline, int64_t node, int32_t *out) {
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    CortadoOutlineSource *source = ctd_outline_source_of(view);
    if (!source) return CTD_ERR_STATE;
    if (node == CTD_OUTLINE_ROOT) {
        // The root is always open: its children are the top level, and a
        // control showing nothing would be one whose root was shut.
        if (out) *out = 1;
        return CTD_OK;
    }
    id item = [source boxed:node];
    if ([view rowForItem:item] < 0) return CTD_ERR_RANGE;
    if (out) *out = [view isItemExpanded:item] ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_outline_selected(ctd_handle outline, int64_t *out) {
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    CortadoOutlineSource *source = ctd_outline_source_of(view);
    if (!source) return CTD_ERR_STATE;
    NSInteger row = [view selectedRow];
    if (out) {
        *out = row < 0 ? CTD_OUTLINE_ROOT
                       : [source nodeOf:[view itemAtRow:row]];
    }
    return CTD_OK;
}

ctd_status ctd_outline_select(ctd_handle outline, int64_t node) {
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    CortadoOutlineSource *source = ctd_outline_source_of(view);
    if (!source) return CTD_ERR_STATE;
    g_writing = g_writing + 1;
    if (node == CTD_OUTLINE_ROOT) {
        [view deselectAll:nil];
        g_writing = g_writing - 1;
        return CTD_OK;
    }
    NSInteger row = [view rowForItem:[source boxed:node]];
    if (row < 0) {
        g_writing = g_writing - 1;
        return CTD_ERR_RANGE;
    }
    [view selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
      byExtendingSelection:NO];
    g_writing = g_writing - 1;
    return CTD_OK;
}

int32_t ctd_outline_cell(ctd_handle outline, int64_t node, int32_t column,
                         char *out, int32_t cap) {
    ctd_status problem;
    NSOutlineView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    CortadoOutlineSource *source = ctd_outline_source_of(view);
    if (!source) return CTD_ERR_STATE;
    if (column < 0 || column >= (int32_t)[[view tableColumns] count]) {
        return CTD_ERR_RANGE;
    }
    // Only a node the control is showing, like every other node-keyed call
    // here. Asking the source directly would answer for a node the control
    // has never heard of, which would make this a second reading of the
    // source rather than the round trip it exists to be.
    id item = node == CTD_OUTLINE_ROOT ? nil : [source boxed:node];
    if (item && [view rowForItem:item] < 0) return CTD_ERR_RANGE;
    // Through the control's own data source, which is the round trip this
    // call exists for: out through ctd_outline_text_fn, into AppKit, back.
    id value = [source outlineView:view
         objectValueForTableColumn:[[view tableColumns] objectAtIndex:(NSUInteger)column]
                            byItem:item];
    return ctd_copy_out([value isKindOfClass:[NSString class]] ? value : @"",
                        out, cap);
}
