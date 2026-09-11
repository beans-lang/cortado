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

// One target object for every menu item cortado owns. `ctd_init` makes it and
// `menu.m` implements it.
@interface CortadoCommand : NSObject
- (void)chose:(id)sender;
@end

// ------------------------------------------------------------------- the table
//
// Defined in handles.m, except the two the event plumbing owns, which are in
// app.m.

extern id           g_object[CTD_SLOTS];
extern uint32_t     g_generation[CTD_SLOTS];
extern int32_t      g_kind[CTD_SLOTS];
extern uint32_t     g_used;             // slot 0 is reserved for "no handle"
extern ctd_event_fn g_sink;
extern void        *g_sink_context;
extern int32_t      g_role;
extern int          g_started;

extern NSMutableArray *g_targets;       // app.m — keeps every CortadoTarget alive
extern CortadoCommand *g_commands;      // app.m — the one menu-item target

// ------------------------------------------------------------------ handles.m

ctd_handle  ctd_track(id object, int32_t kind);
id          ctd_resolve(ctd_handle handle);
void        ctd_give_back(uint32_t slot);
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

// ------------------------------------------------------------------ property.m

NSString   *ctd_string(const char *utf8, int32_t len);
NSTextView *ctd_text_view(id object);

#endif
