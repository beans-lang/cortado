// The two things that hang off a window rather than sit inside it.
//
// A toolbar and a popover are not widgets: neither has a frame the solver sets
// and neither is a child of anything. A toolbar belongs to a window and lives
// in its title bar; a popover is its own window, which is what lets it draw
// outside the one that spawned it and take the keyboard while it is up.
//
// Both are described with things cortado already has. A toolbar is a **menu** —
// the same handle, the same tokens, the same ctd_menu_set_enabled — so a
// program with one command table needs no second one. A popover holds an
// ordinary widget subtree.

#import "internal.h"

// ----------------------------------------------------------------- toolbars

// The delegate. NSToolbar asks it for an item every time one appears, so the
// menu a toolbar was built from has to stay reachable — `menu` is the handle
// and not the NSMenu, so a menu released behind the toolbar's back leaves a
// stale handle rather than a dangling pointer.
@interface CortadoToolbar : NSObject <NSToolbarDelegate>
@property (assign) ctd_handle menu;
@property (retain) NSMutableArray *ids;
@end

@implementation CortadoToolbar

- (void)dealloc {
    [_ids release];
    [super dealloc];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return _ids;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return _ids;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
 willBeInsertedIntoToolbar:(BOOL)inserting {
    NSMenu *menu = (NSMenu *)ctd_resolve(_menu);
    if (!menu) return nil;
    NSInteger at = [_ids indexOfObject:identifier];
    if (at == NSNotFound) return nil;
    // The identifier carries the menu index, so an item that moved in the menu
    // is a different item here rather than the same one with new words.
    NSInteger row = [[identifier substringFromIndex:5] integerValue];
    if (row < 0 || row >= [menu numberOfItems]) return nil;
    NSMenuItem *source = [menu itemAtIndex:row];
    NSToolbarItem *item =
        [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    [item setLabel:[source title]];
    [item setPaletteLabel:[source title]];
    [item setTarget:g_commands];
    [item setAction:@selector(chose:)];
    [item setTag:[source tag]];
    [item setEnabled:[source isEnabled]];
    return item;
}

@end

// A toolbar item's action reaches CortadoCommand, whose -chose: reads the tag
// off an NSMenuItem. A toolbar item is not one, so it needs its own path to the
// same event — and it must carry the same token, or the two ways of asking for
// one command would report two different things.
@interface CortadoCommand (Toolbar)
- (void)chose:(id)sender;
@end

NSToolbar *ctd_toolbar_of(NSWindow *window) {
    return [window toolbar];
}

ctd_status ctd_toolbar_set(ctd_handle surface, ctd_handle menu_handle) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    id source = ctd_resolve(menu_handle);
    if (!window || !source) return CTD_ERR_STALE;
    if (![window isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
    if (![source isKindOfClass:[NSMenu class]]) return CTD_ERR_KIND;
    NSMenu *menu = (NSMenu *)source;

    CortadoToolbar *delegate = [[CortadoToolbar alloc] init];
    [delegate setMenu:menu_handle];
    NSMutableArray *ids = [NSMutableArray array];
    for (NSInteger row = 0; row < [menu numberOfItems]; row++) {
        NSMenuItem *item = [menu itemAtIndex:row];
        // A separator becomes AppKit's own separator item; a submenu is not a
        // toolbar item on any platform here and is left out.
        if ([item isSeparatorItem]) {
            [ids addObject:NSToolbarSpaceItemIdentifier];
            continue;
        }
        if ([item hasSubmenu]) continue;
        [ids addObject:[NSString stringWithFormat:@"ctd-%ld", (long)row]];
    }
    [delegate setIds:ids];

    NSToolbar *bar = [[NSToolbar alloc] initWithIdentifier:@"cortado"];
    [bar setDelegate:delegate];
    [bar setAllowsUserCustomization:NO];
    [window setToolbar:bar];
    [g_targets addObject:delegate];
    [delegate release];
    [bar release];
    return CTD_OK;
}

ctd_status ctd_toolbar_clear(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    if (![window isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
    [window setToolbar:nil];
    return CTD_OK;
}

ctd_status ctd_toolbar_count(ctd_handle surface, int32_t *out) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    if (![window isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
    NSToolbar *bar = [window toolbar];
    // The delegate's own list, not -items: AppKit fills -items in when the
    // toolbar is shown, and a headless window never shows one. What is being
    // asked is how many items the toolbar has, which is a fact about the
    // description and not about whether anybody has looked at it.
    id delegate = bar ? [bar delegate] : nil;
    if (out) {
        *out = [delegate isKindOfClass:[CortadoToolbar class]]
             ? (int32_t)[[(CortadoToolbar *)delegate ids] count] : 0;
    }
    return CTD_OK;
}

// ----------------------------------------------------------------- popovers

// A popover is its own window and cortado's handle table holds the NSPopover.
// The content widget stays a widget with its own handle: the popover borrows
// it, and releasing the popover does not release the tree inside it, because
// the caller built that tree and may show it again.
@interface CortadoPopover : NSObject <NSPopoverDelegate>
@property (assign) ctd_handle handle;
@end

@implementation CortadoPopover
- (void)popoverDidClose:(NSNotification *)note {
    ctd_emit(CTD_EV_DISMISS, _handle, 0, 0);
}
@end

static NSPopover *ctd_popover_of(ctd_handle handle) {
    id object = ctd_resolve(handle);
    if ([object isKindOfClass:[NSPopover class]]) return (NSPopover *)object;
    return nil;
}

ctd_handle ctd_popover_new(ctd_handle content, double width, double height) {
    NSView *inside = (NSView *)ctd_resolve(content);
    if (!inside || ![inside isKindOfClass:[NSView class]]) return 0;
    if (width <= 0.0 || height <= 0.0) return 0;

    // A view controller, because that is the only way to give an NSPopover a
    // view. It holds the caller's view without owning the handle: the widget
    // outlives the popover if the caller keeps it, which is what makes a
    // popover that can be shown twice possible.
    NSViewController *holder = [[NSViewController alloc] init];
    [holder setView:inside];

    NSPopover *popover = [[NSPopover alloc] init];
    [popover setContentViewController:holder];
    [popover setContentSize:NSMakeSize(width, height)];
    [popover setBehavior:NSPopoverBehaviorTransient];
    [holder release];

    ctd_handle handle = ctd_track(popover, -1);
    [popover release];
    if (!handle) return 0;

    CortadoPopover *delegate = [[CortadoPopover alloc] init];
    [delegate setHandle:handle];
    [popover setDelegate:delegate];
    [g_targets addObject:delegate];
    [delegate release];
    return handle;
}

ctd_status ctd_popover_show(ctd_handle handle, ctd_handle anchor, int32_t edge) {
    NSPopover *popover = ctd_popover_of(handle);
    NSView *view = (NSView *)ctd_resolve(anchor);
    if (!popover || !view) return CTD_ERR_STALE;
    if (![view isKindOfClass:[NSView class]]) return CTD_ERR_KIND;
    if (edge < CTD_EDGE_MIN_X || edge > CTD_EDGE_MAX_Y) return CTD_ERR_RANGE;
    // A view that is in no window has nothing to anchor to, and AppKit throws
    // rather than returning — which in a headless run would take the process
    // down with an exception instead of a status.
    if (![view window]) return CTD_ERR_PLATFORM;
    NSRectEdge which = edge == CTD_EDGE_MIN_X ? NSRectEdgeMinX
                     : edge == CTD_EDGE_MIN_Y ? NSRectEdgeMinY
                     : edge == CTD_EDGE_MAX_X ? NSRectEdgeMaxX
                                              : NSRectEdgeMaxY;
    [popover showRelativeToRect:[view bounds] ofView:view preferredEdge:which];
    return CTD_OK;
}

ctd_status ctd_popover_close(ctd_handle handle) {
    NSPopover *popover = ctd_popover_of(handle);
    if (!popover) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    [popover performClose:nil];
    return CTD_OK;
}

ctd_status ctd_popover_shown(ctd_handle handle, int32_t *out) {
    NSPopover *popover = ctd_popover_of(handle);
    if (!popover) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = [popover isShown] ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_popover_release(ctd_handle handle) {
    NSPopover *popover = ctd_popover_of(handle);
    if (!popover) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // The content view goes back to being an ordinary unparented widget, still
    // named by its own handle. Letting the view controller take it down with
    // the popover would free a widget the caller still holds.
    [popover setContentViewController:nil];
    [popover setDelegate:nil];
    ctd_untrack(handle);
    return CTD_OK;
}
