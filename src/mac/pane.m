// The containers a platform draws chrome for.
//
// A disclosure is the first of them, and the reason this file exists rather
// than another case in widget.m: AppKit has no disclosure *container*. It has
// the triangle — an NSButton with NSBezelStyleDisclosure, which AppKit draws,
// AppKit rotates, and AppKit reports to assistive technology as
// AXDisclosureTriangle — and putting one beside a title with a body under it
// is what an application does. This class does that and nothing else; there is
// no cortado-drawn pixel in it.
//
// The arrangement is the group box's: children go into a content view this one
// keeps positioned under the header, so a child's coordinates start at the
// content view's corner and a caller never has to know the header is there.
// `ctd_view_content_inset` is how the layout learns how much room it took.

#import "internal.h"

// The space a platform leaves between one thing and the next.
//
// AppKit's own number rather than one written here: it is the vertical content
// margin of a box, which is the system's idea of "a small space". Asked once,
// because it is the same on every box on this machine and building an NSBox
// inside a layout pass would be a needless allocation on every frame change.
static CGFloat ctd_pane_gap(void) {
    static CGFloat known = 0.0;
    static int asked = 0;
    if (!asked) {
        NSBox *ruler = [[NSBox alloc] initWithFrame:NSZeroRect];
        known = [ruler contentViewMargins].height;
        [ruler release];
        asked = 1;
    }
    return known;
}

@implementation CortadoDisclosure

- (BOOL)isFlipped { return YES; }

// The header's height, from AppKit's own numbers: whichever of the triangle
// and the title wants to be taller, plus the space under it.
//
// Not a constant, because the title's height follows the user's text size and
// the triangle's follows the system's control metrics. A number written here
// would be right on the machine it was written on.
- (CGFloat)headerHeight {
    NSSize glyph = [_triangle fittingSize];
    NSSize words = [_caption fittingSize];
    CGFloat tall = glyph.height > words.height ? glyph.height : words.height;
    return tall + ctd_pane_gap();
}

- (void)relayout {
    NSRect own = [self bounds];
    CGFloat header = [self headerHeight];
    CGFloat gap = ctd_pane_gap();
    NSSize glyph = [_triangle fittingSize];
    [_triangle setFrame:NSMakeRect(0.0, 0.0, glyph.width, header)];
    CGFloat left = glyph.width + gap;
    CGFloat words = own.size.width - left;
    [_caption setFrame:NSMakeRect(left, 0.0, words > 0.0 ? words : 0.0, header)];
    CGFloat body = own.size.height - header;
    [_content setFrame:NSMakeRect(0.0, header, own.size.width, body > 0.0 ? body : 0.0)];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self relayout];
}

@end

// ------------------------------------------------------------------ building

// The triangle's action. It is the control's own click, so the state AppKit
// put it in is the truth; the body follows, and the event goes out as a value
// change because that is what happened.
@interface CortadoTwist : NSObject
@property (assign) ctd_handle handle;
- (void)twisted:(id)sender;
@end

@implementation CortadoTwist
- (void)twisted:(id)sender {
    id object = ctd_resolve(_handle);
    if (![object isKindOfClass:[CortadoDisclosure class]]) return;
    CortadoDisclosure *twisty = (CortadoDisclosure *)object;
    BOOL open = [[twisty triangle] state] == NSControlStateValueOn;
    [[twisty content] setHidden:!open];
    ctd_emit(CTD_EV_VALUE_CHANGED, _handle, open ? 1 : 0, 0);
}
@end

NSView *ctd_disclosure_new(void) {
    CortadoDisclosure *twisty =
        [[CortadoDisclosure alloc] initWithFrame:NSZeroRect];

    NSButton *triangle = [[NSButton alloc] initWithFrame:NSZeroRect];
    [triangle setBezelStyle:NSBezelStyleDisclosure];
    [triangle setButtonType:NSButtonTypePushOnPushOff];
    [triangle setTitle:@""];
    [triangle setState:NSControlStateValueOn];
    [twisty addSubview:triangle];
    [twisty setTriangle:triangle];
    [triangle release];

    NSTextField *caption = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [caption setBezeled:NO];
    [caption setDrawsBackground:NO];
    [caption setEditable:NO];
    [caption setSelectable:NO];
    [caption setStringValue:@""];
    [twisty addSubview:caption];
    [twisty setCaption:caption];
    [caption release];

    CortadoView *content = [[CortadoView alloc] initWithFrame:NSZeroRect];
    ctd_tag(content);
    [twisty addSubview:content];
    [twisty setContent:content];
    [content release];

    return twisty;
}

// Wires the triangle to the handle, once the handle exists. Split from the
// builder above for the reason the table's data source is: a handle is only
// made after the view is, and the forwarder has to carry it.
void ctd_disclosure_attach(ctd_handle handle, NSView *view) {
    if (![view isKindOfClass:[CortadoDisclosure class]]) return;
    CortadoDisclosure *twisty = (CortadoDisclosure *)view;
    CortadoTwist *forwarder = [[CortadoTwist alloc] init];
    [forwarder setHandle:handle];
    [[twisty triangle] setTarget:forwarder];
    [[twisty triangle] setAction:@selector(twisted:)];
    [g_targets addObject:forwarder];
    [forwarder release];
}

// ------------------------------------------------------------------ tab views
//
// A tab view's children are its pages, one each, in order. That is what makes
// the tree a program builds and the tree a screen reader walks the same tree —
// and it is why the four functions below exist rather than the ordinary
// subview path: an NSTabViewItem is not a view, so a page is added to the tab
// view's item list and never to its subviews.

// The delegate. AppKit holds it weakly, so `g_targets` keeps it alive — the
// same arrangement as the target/action forwarder and the table's data source.
@interface CortadoTabs : NSObject <NSTabViewDelegate>
@property (assign) ctd_handle handle;
@end

@implementation CortadoTabs
- (void)tabView:(NSTabView *)view didSelectTabViewItem:(NSTabViewItem *)item {
    ctd_emit(CTD_EV_VALUE_CHANGED, _handle,
             (int64_t)[view indexOfTabViewItem:item], 0);
}
@end

NSTabView *ctd_tab_view(id object) {
    if ([object isKindOfClass:[NSTabView class]]) return (NSTabView *)object;
    return nil;
}

void ctd_tabs_attach(ctd_handle handle, NSView *view) {
    NSTabView *tabs = ctd_tab_view(view);
    if (!tabs) return;
    CortadoTabs *delegate = [[CortadoTabs alloc] init];
    [delegate setHandle:handle];
    [tabs setDelegate:delegate];
    [g_targets addObject:delegate];
    [delegate release];
}

// The page a view stands on, or NSNotFound.
NSInteger ctd_tab_index_of(NSTabView *tabs, NSView *page) {
    for (NSInteger at = 0; at < [tabs numberOfTabViewItems]; at++) {
        if ([[tabs tabViewItemAtIndex:at] view] == page) return at;
    }
    return NSNotFound;
}

ctd_status ctd_tab_add_page(NSTabView *tabs, NSView *page, int32_t index) {
    NSTabViewItem *item =
        [[NSTabViewItem alloc] initWithIdentifier:[NSNumber numberWithLong:(long)page]];
    [item setLabel:@""];
    [item setView:page];
    NSInteger count = [tabs numberOfTabViewItems];
    if (index < 0 || index >= (int32_t)count) {
        [tabs addTabViewItem:item];
    } else {
        [tabs insertTabViewItem:item atIndex:(NSInteger)index];
    }
    [item release];
    return CTD_OK;
}

// A tab's label is text on the strip, and a longer one makes the strip wider.
ctd_status ctd_tab_set_label(ctd_handle widget, int32_t index,
                             const char *utf8, int32_t len) {
    ctd_forget_size(widget);
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    NSTabView *tabs = ctd_tab_view(ctd_resolve(widget));
    if (!tabs) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= (int32_t)[tabs numberOfTabViewItems]) return CTD_ERR_RANGE;
    [[tabs tabViewItemAtIndex:(NSInteger)index] setLabel:ctd_string(utf8, len)];
    return CTD_OK;
}

int32_t ctd_tab_label(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    NSTabView *tabs = ctd_tab_view(ctd_resolve(widget));
    if (!tabs) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= (int32_t)[tabs numberOfTabViewItems]) return CTD_ERR_RANGE;
    return ctd_copy_out([[tabs tabViewItemAtIndex:(NSInteger)index] label], out, cap);
}

// ---------------------------------------------------------------- split views
//
// The one kind whose children the *platform* positions. NSSplitView lays its
// panes out from the divider's position and cannot be talked out of it, so
// cortado sets the position and reads it back rather than setting two frames.

@interface CortadoSplit : NSObject <NSSplitViewDelegate>
@property (assign) ctd_handle handle;
@end

@implementation CortadoSplit
- (void)splitViewDidResizeSubviews:(NSNotification *)note {
    // Only a drag. AppKit posts this for every resize the split view sees,
    // its window's included, and a value_changed raised because the user
    // widened the window would be cortado reporting its own layout back to
    // the program. The divider index is in the note exactly when a divider is
    // what moved.
    if (![[note userInfo] objectForKey:@"NSSplitViewDividerIndex"]) return;
    // And a divider does move when nobody dragged it: giving the split view
    // its frame re-divides the panes, with a divider index in the note like
    // any drag, so the test above is not enough on its own. `g_writing` is
    // non-zero exactly while cortado is inside -setFrame:, which is the only
    // way that happens.
    if (g_writing) return;
    id object = ctd_resolve(_handle);
    if (![object isKindOfClass:[NSSplitView class]]) return;
    NSSplitView *split = (NSSplitView *)object;
    if ([[split subviews] count] < 1) return;
    NSRect first = [[[split subviews] objectAtIndex:0] frame];
    double where = [split isVertical] ? first.size.width : first.size.height;
    ctd_emit(CTD_EV_VALUE_CHANGED, _handle, (int64_t)where, 0);
}
@end

NSSplitView *ctd_split_view(id object) {
    if ([object isKindOfClass:[NSSplitView class]]) return (NSSplitView *)object;
    return nil;
}

NSView *ctd_split_new(void) {
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    // Side by side is CTD_P_AXIS 0, and AppKit spells the same arrangement
    // "vertical" — the divider is vertical, the panes are not. cortado names
    // the axis the panes run along, which is what a caller is thinking about.
    [split setVertical:YES];
    [split setDividerStyle:NSSplitViewDividerStyleThin];
    return split;
}

void ctd_split_attach(ctd_handle handle, NSView *view) {
    NSSplitView *split = ctd_split_view(view);
    if (!split) return;
    CortadoSplit *delegate = [[CortadoSplit alloc] init];
    [delegate setHandle:handle];
    [split setDelegate:delegate];
    [g_targets addObject:delegate];
    [delegate release];
}

// Where the divider is, in points from the leading edge: the first pane's size
// along the axis. Read from the panes rather than kept beside them, because
// the user can drag it and a second record of the same fact is a second
// answer.
double ctd_split_position(NSSplitView *split) {
    if ([[split subviews] count] < 1) return 0.0;
    NSRect first = [[[split subviews] objectAtIndex:0] frame];
    return [split isVertical] ? first.size.width : first.size.height;
}
