// What the macOS host's translation units share, and nothing else does.
//
// `cortado_host.h` is the contract every platform implements. This is the
// opposite: it is private to this one platform, it names AppKit types freely,
// and no other host and no Beans file ever sees it. Splitting the host into
// files made it necessary — before that the whole host was one translation
// unit and everything below was `static`.
//
// Two things are worth knowing before reading any of those files.
//
// The handle table. A handle is `(generation << 32) | slot`, not a pointer.
// Releasing a widget bumps its slot's generation, so a handle held past its
// widget's life resolves to nil and every entry point answers CTD_ERR_STALE.
// An address could not do that: a freed `NSView *` is indistinguishable from a
// live one until it crashes.
//
// The flip. AppKit puts the origin at the bottom-left and grows y upward;
// cortado, like Win32, GTK4, UIKit and Android, puts it at the top-left. A
// subview's frame is read in its superview's coordinate system, so flipping is
// a property of containers alone: CortadoView answers YES to -isFlipped, and
// every surface's content view and every CTD_W_CONTAINER is one. Nothing else
// in this host has to think about it.
#ifndef CORTADO_MAC_INTERNAL_H
#define CORTADO_MAC_INTERNAL_H

#import <Cocoa/Cocoa.h>
#include <string.h>
#include <float.h>
#include "../cortado_host.h"
#include "../cortado_rules.h"

enum { CTD_SLOTS = 8192 };

// ---------------------------------------------------- the classes this host owns

// A container that agrees with cortado about which way y grows.
@interface CortadoView : NSView
@end

// AppKit's target/action wants an object with a selector. One of these sits
// between a control and the sink, carrying the handle the event belongs to.
// The control holds its target weakly, so `g_targets` keeps it alive.
@interface CortadoTarget : NSObject
@property (assign) ctd_handle handle;
@end

// A table's data source and delegate. AppKit holds both weakly, so `g_targets`
// keeps it alive — the same arrangement, and for the same reason, as the
// target/action forwarder above.
@interface CortadoTableSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (assign) ctd_handle handle;
@property (assign) NSInteger rows;
@end

// A title you press to show or hide what is under it.
//
// AppKit has no disclosure *container* — no class that holds a body and
// collapses it. What it has is the triangle: an NSButton with
// NSBezelStyleDisclosure, drawn by AppKit, rotated by AppKit, reported to
// assistive technology by AppKit as AXDisclosureTriangle. Putting one beside a
// title and hiding a view below it is what an application does, and it is what
// this class does; no pixel here is cortado's.
//
// The same arrangement as the group box's: children go into `content`, which
// this view keeps positioned under the header, so a child's coordinates start
// at the content's corner and the caller never has to know the header is
// there. `ctd_view_content_inset` is what tells the layout how much room it
// took.
@interface CortadoDisclosure : NSView
@property (assign) NSButton *triangle;
@property (assign) NSTextField *caption;
@property (assign) NSView *content;
- (void)relayout;
- (CGFloat)headerHeight;
@end

// One target object for every menu item cortado owns. `ctd_init` makes it and
// `menu.m` implements it.
@interface CortadoCommand : NSObject
- (void)chose:(id)sender;
@end

// ------------------------------------------------------------------- the table
//
// Defined in handles.m, except the ones the application's own lifecycle owns,
// which are in app.m.

extern id           g_object[CTD_SLOTS];
extern uint32_t     g_generation[CTD_SLOTS];
extern int32_t      g_kind[CTD_SLOTS];
extern uint32_t     g_used;             // slot 0 is reserved for "no handle"
extern ctd_event_fn g_sink;
extern void        *g_sink_context;
extern int32_t      g_role;
extern int          g_started;
// Set by ctd_app_stop and read by ctd_app_run_for. -[NSApplication stop:] is
// only understood by -[NSApplication run], and a bounded run is not that loop.
extern int          g_stop_requested;

extern NSMutableArray *g_targets;       // app.m — keeps every CortadoTarget alive
extern CortadoCommand *g_commands;      // app.m — the one menu-item target

// ------------------------------------------------------------------ handles.m

ctd_handle  ctd_track(id object, int32_t kind);
id          ctd_resolve(ctd_handle handle);
void        ctd_give_back(uint32_t slot);
void        ctd_untrack(ctd_handle handle);
int32_t     ctd_slot_kind(ctd_handle handle);
void        ctd_tag(id object);
NSArray    *ctd_children(NSView *container);
// Answers the byte length the text needs, and writes at most `cap` bytes —
// the two-call shape every text reader in the ABI uses.
int32_t     ctd_copy_out(NSString *text, char *out, int32_t cap);
// Rule 3 at the top of cortado_host.h: no platform text control can hold a
// zero byte, so one is refused at the boundary rather than cutting a string
// in half inside the platform.
int         ctd_has_nul(const char *utf8, int32_t len);

// ----------------------------------------------------------------------- app.m

void        ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token);
void        ctd_emit_control(ctd_handle target, id sender);

// ---------------------------------------------------------------------- clock.m

// Forgets the clock a slot may have had, before the slot is handed out again.
// Declared here rather than in the clock's own file because the handle table
// is what calls it, and the table must not have to include CoreVideo to do so.
void        ctd_clock_forget(uint32_t slot);

// ------------------------------------------------------------------ property.m

NSString   *ctd_string(const char *utf8, int32_t len);
NSTextView *ctd_text_view(id object);

// The NSTableView a CTD_W_TABLE handle stands for; nil for anything else.
NSTableView *ctd_table_view(id object);

// ------------------------------------------------------------------ view.m

// The view a container's children actually go into: a scroll view's document
// view, a box's content view, a disclosure's body. The view itself for
// anything else, and nil for an object that is not a view at all.
NSView *ctd_container_of(id object);

// What the platform keeps for itself, as left, top, right, bottom. Four zeros
// for everything but the containers that draw chrome. See
// ctd_view_content_inset in ../cortado_host.h.
void ctd_chrome_of(id object, double *out);

// ------------------------------------------------------------------- pane.m

NSView *ctd_disclosure_new(void);
void    ctd_disclosure_attach(ctd_handle handle, NSView *view);

// The NSTabView a CTD_W_TAB_VIEW handle stands for; nil for anything else.
NSTabView *ctd_tab_view(id object);
void       ctd_tabs_attach(ctd_handle handle, NSView *view);
// Which page a view is, or NSNotFound. A page is not a subview of the tab
// view, so the ordinary child walk cannot find it.
NSInteger  ctd_tab_index_of(NSTabView *tabs, NSView *page);
ctd_status ctd_tab_add_page(NSTabView *tabs, NSView *page, int32_t index);

// The NSSplitView a CTD_W_SPLIT_VIEW handle stands for; nil for anything else.
NSSplitView *ctd_split_view(id object);
NSView      *ctd_split_new(void);
void         ctd_split_attach(ctd_handle handle, NSView *view);
double       ctd_split_position(NSSplitView *split);

#endif
