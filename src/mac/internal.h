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

// A container that agrees with cortado about which way y grows, and — for the
// one kind whose contents are the program's — whether it takes the keyboard
// and what it calls itself.
//
// The flags live on this class rather than in a side table because a canvas is
// one of these already; a table keyed by handle would be a second lifetime to
// keep in step with the first.
@interface CortadoView : NSView
@property (nonatomic) BOOL ctdFocusable;
@property (nonatomic) int32_t ctdRole;
@end

// A shared-rendered canvas remains an NSView. This class only talks to the
// system input method; Beans owns its text and editing policy.
@interface CortadoSharedCanvas : CortadoView <NSTextInputClient>
@property (nonatomic) BOOL ctdTextActive;
@property (nonatomic) BOOL ctdSecureInput;
@property (nonatomic, retain) NSString *ctdEditorText;
@property (nonatomic) NSRange ctdEditorSelection;
@property (nonatomic) NSRect ctdCaretRect;
@property (nonatomic, retain) NSMutableArray *ctdSemantics;
- (void)ctdDiscardMarked;
@end
void ctd_clipboard_use_pasteboard(NSPasteboard *board); // isolated native tests

// The native editor inside a text area's scroll view. Keeping its code-mode
// state here ties it to the view's lifetime, even when handle slots are reused.
@interface CortadoTextView : NSTextView {
    NSFont *_ctdRegularFont;
    BOOL _ctdCodeMode;
    BOOL _ctdRichText;
    BOOL _ctdSmartQuotes;
    BOOL _ctdSmartDashes;
    BOOL _ctdReplacements;
    BOOL _ctdSpellingCorrection;
    BOOL _ctdSpellChecking;
}
- (BOOL)ctdCodeMode;
- (void)ctdSetCodeMode:(BOOL)on;
- (void)ctdSetFontSize:(CGFloat)points;
@end

// AppKit's target/action wants an object with a selector. One of these sits
// between a control and the sink, carrying the handle the event belongs to.
// The control holds its target weakly, so `g_targets` keeps it alive.
// The window cortado makes, and the one thing it overrides.
//
// AppKit has no notification for the first responder changing. There is no
// delegate method, the property is not KVO-compliant, and every route into it
// — a program calling -makeFirstResponder:, a user clicking a field, a user
// pressing Tab — goes through that one method. So it is the hook: overriding
// it catches all three, which is what makes a program moving focus and a user
// moving it look the same to a handler.
@interface CortadoWindow : NSWindow <NSWindowDelegate>
@end

@interface CortadoTarget : NSObject
@property (assign) ctd_handle handle;
@end

// A table's data source and delegate. AppKit holds both weakly, so `g_targets`
// keeps it alive — the same arrangement, and for the same reason, as the
// target/action forwarder above.
@interface CortadoOutlineSource : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (assign) ctd_handle handle;
@property (retain) NSMutableDictionary *nodes;
- (NSNumber *)boxed:(int64_t)node;
- (int64_t)nodeOf:(id)item;
- (void)forget;
@end

// Native data-grid navigation. Standard tables keep AppKit's normal behavior.
@interface CortadoDataTable : NSTableView
@property (assign) NSInteger ctdActiveColumn;
@end

@interface CortadoTableSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (assign) ctd_handle handle;
@property (assign) NSInteger rows;
@property (assign) BOOL editable;
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
/// The header's height, remembered — see `-headerHeight`. Forgotten by
/// `ctd_forget_size`, which every write to a control already calls.
@property (assign) CGFloat knownHeader;
@property (assign) BOOL headerKnown;
- (void)relayout;
- (CGFloat)headerHeight;
- (void)forgetHeader;
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
extern int32_t      g_icon[CTD_SLOTS];  // CTD_P_ICON, per slot
extern uint32_t     g_used;             // slot 0 is reserved for "no handle"
extern ctd_event_fn g_sink;
extern void        *g_sink_context;
extern int32_t      g_role;
extern int          g_started;
// Set by ctd_app_stop and read by ctd_app_run_for. -[NSApplication stop:] is
// only understood by -[NSApplication run], and a bounded run is not that loop.
extern int          g_stop_requested;

// Non-zero while cortado is writing on the program's behalf.
//
// The header is explicit that ctd_set_* changes a control *silently*: a
// program that heard about its own writes would feed itself for as long as it
// ran. Most of AppKit is quiet by construction — -setState: sends no action,
// -setDoubleValue: sends no action — but three places are not, and all three
// are controls whose state AppKit treats as the user's:
//
//   * -setFrame: on a split view re-divides its panes and tells the delegate
//     a divider moved;
//   * -setPosition:ofDividerAtIndex: tells it the same thing;
//   * -selectRowIndexes: on a table posts a selection change.
//
// A program that keeps what it hears then writes the platform's transient
// even split where its own divider used to be, or closes the tree node it
// just opened. Both happened in examples/cask.
//
// The GTK4 host has had this since it was written, under this name and for
// this reason — see g_writing in src/gtk4/internal.h. A counter rather than a
// flag because a setter can reach another setter.
extern int          g_writing;

extern NSMutableArray *g_targets;       // app.m — keeps every CortadoTarget alive
extern CortadoCommand *g_commands;      // app.m — the one menu-item target

// ------------------------------------------------------------------ handles.m

ctd_handle  ctd_track(id object, int32_t kind);
id          ctd_resolve(ctd_handle handle);
// The handle for an object cortado is holding, and the handle for the nearest
// ancestor of a view that it is. Input needs both: an event names a view and a
// program knows a handle. 0 for anything cortado did not build.
ctd_handle  ctd_handle_for(id object);
ctd_handle  ctd_handle_for_view(NSView *view);
void        ctd_give_back(uint32_t slot);
void        ctd_untrack(ctd_handle handle);
int32_t     ctd_slot_kind(ctd_handle handle);
void        ctd_tag(id object);
NSArray    *ctd_children(NSView *container);
// Answers the byte length the text needs, and writes at most `cap` bytes —
// the two-call shape every text reader in the ABI uses.
int32_t     ctd_copy_out(NSString *text, char *out, int32_t cap);

// The system image for a CTD_ICON_* role, or nil when this system has none —
// which is a real answer and not only a stale table: SF Symbols arrived in
// macOS 11 and a symbol added later is nil on an older one. See src/mac/icon.m.
NSImage    *ctd_icon_image(int32_t icon);
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

// The outline's half of the same idea, in src/mac/outline.m. NSOutlineView
// compares items by pointer, so one NSNumber per node is kept and handed out
// every time — see the note at the top of that file.
@class CortadoOutlineSource;
NSOutlineView *ctd_outline_view(id object);
void           ctd_outline_attach(ctd_handle outline, NSView *view);
NSString      *ctd_outline_words(ctd_handle outline, int64_t node, int32_t column);

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

// -------------------------------------------------------------------- web.m

NSView *ctd_web_new(void);
void    ctd_web_attach(ctd_handle handle, NSView *view);


// --------------------------------------------------------------------- input.m

// The one local event monitor, up at application start and down at shutdown.
void        ctd_input_start(void);
void        ctd_input_stop(void);
// Whether anything asked for this kind. The header calls ctd_listen advice
// rather than permission; this is what the advice becomes on the hot path.
int         ctd_listening(uint32_t kind);
// CTD_MOD_* for a set of AppKit flags, shared with anything else that reports
// which keys were held.
uint32_t    ctd_modifiers_of(NSEventModifierFlags flags);
// The control a responder belongs to, as a handle. Asked while the responder
// is still installed: a field editor that has been resigned can no longer be
// traced back to the field it was editing.
ctd_handle  ctd_focus_handle(NSResponder *who);
// Raises blur on what had the keyboard and focus on what took it. Called from
// CortadoWindow once per first-responder change, so that a program moving
// focus and a user tabbing look the same to a handler.
void        ctd_focus_moved(ctd_handle left, ctd_handle took);

// ----------------------------------------------------------------- surface.m

// Raises one of the four things that happen to a surface, if anything asked
// for it. `a` and `b` are the width and height for a resize, the new value for
// an appearance or a scale, and ignored for a close.
void        ctd_surface_event(uint32_t kind, ctd_handle surface,
                              double a, double b);

// -------------------------------------------------------------- property.m

// The view's layer, making it layer-backed if it is not already.
//
// Lazy for the reason ctd_anim_start's comment gives, and in one place now
// that more than one caller wants it: a layer costs memory on every control in
// a window, and only a control that actually uses one needs it. It costs more
// than the one view, too — AppKit makes every ancestor of a layer-backed view
// layer-backed as well, so styling one control deep in a window backs the
// branch above it. That is AppKit's rule and not cortado's to change; it is
// written down here so nobody meets it as a mystery in a memory graph.
CALayer    *ctd_layer_of(NSView *view);

// --------------------------------------------------------------- machine.m

// The platform's own watchers, up when the first handler for their kind
// arrives and down with the last — which is what ctd_listen is for.
// ------------------------------------------------------------ permission.m

// The one guard every gated call goes through: a bundle, a declared reason,
// and a permission that is not already denied. CTD_ERR_UNSUPPORTED for any of
// the three, and it touches no framework to decide. See the note beside it.
ctd_status  ctd_gated(int32_t what);

// ----------------------------------------------------------------- view.m

// Drops what a control said it wanted to be, so the next measure asks again.
// Called from every property write — see the note beside g_wanted.
void        ctd_forget_size(ctd_handle widget);
// All of them, for the one thing that changes every control at once and writes
// to none of them: the system font.
void        ctd_forget_all_sizes(void);

// -------------------------------------------------------------- property.m

// The view's layer, making it layer-backed if it is not already.
//
// Lazy for the reason ctd_anim_start's comment gives, and in one place now
// that more than one caller wants it: a layer costs memory on every control in
// a window, and only a control that actually uses one needs it. It costs more
// than the one view, too — AppKit makes every ancestor of a layer-backed view
// layer-backed as well, so styling one control deep in a window backs the
// branch above it. That is AppKit's rule and not cortado's to change; it is
// written down here so nobody meets it as a mystery in a memory graph.
CALayer    *ctd_layer_of(NSView *view);

// --------------------------------------------------------------- machine.m

void        ctd_net_start(void);
void        ctd_net_stop(void);
void        ctd_power_start(void);
void        ctd_power_stop(void);

#endif
