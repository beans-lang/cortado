// What the iOS host's translation units share, and nothing else does.
//
// `cortado_host.h` is the contract every platform implements. This is the
// opposite: private to this one platform, naming UIKit types freely, included
// by no other host and seen by no Beans file.
//
// Two things are worth knowing before reading any of those files.
//
// The handle table. A handle is `(generation << 32) | slot`, not a pointer.
// Releasing a widget bumps its slot's generation, so a handle held past its
// widget's life resolves to nil and every entry point answers CTD_ERR_STALE.
//
// Coordinates are already top-left with y downward on iOS, so unlike the macOS
// host there is no flip: a UIView's frame is what cortado means by a frame.
//
// ## The one thing about iOS that has no counterpart anywhere else
//
// A `UIWindow` belongs to a `UIWindowScene`, and one built before the
// application launched belongs to none. Such a window can be key, visible,
// unhidden, correctly sized, fully populated — every property reads right, and
// it renders **nothing**, not even its own background colour. Assigning
// `windowScene` afterwards does not fix it.
//
// cortado builds its window before starting the loop, because that is the
// order every other platform uses and the order an application's own code
// reads in. So `ctd_attach_scene` builds a real scene window once a scene
// connects and moves the view controller — with cortado's whole tree under
// it — across. It is in app.m, it is the one place this host does something
// structural that the macOS host does not, and it is why `ctd_app_run` was
// always allowed not to return.
#ifndef CORTADO_IOS_INTERNAL_H
#define CORTADO_IOS_INTERNAL_H

#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <string.h>
#include <float.h>
#include "../cortado_host.h"
#include "../cortado_rules.h"

enum { CTD_SLOTS = 8192 };

@interface CortadoTarget : NSObject
@property (assign) ctd_handle handle;
- (void)fire:(id)sender;
@end

extern NSMutableArray *g_targets;
extern ctd_event_fn g_sink;
extern ctd_handle g_shown;
extern id g_object[CTD_SLOTS];
extern int g_started;
extern int32_t g_role;
extern uint32_t g_generation[CTD_SLOTS];
extern uint32_t g_used;
extern void *g_sink_context;
// Set by ctd_app_stop and read by ctd_app_run_for. A phone's application is
// never stopped by itself, but a *bounded* run is not the application — it is
// a wait with a deadline, and a wait can be cut short.
extern int g_stop_requested;

NSArray *ctd_children(UIView *container);
NSString *ctd_string(const char *utf8, int32_t len);
UIView *ctd_surface_view(id object);
ctd_handle ctd_track(id object, int32_t kind);
void ctd_untrack(ctd_handle handle);
id ctd_resolve(ctd_handle handle);
int ctd_has_nul(const char *utf8, int32_t len);
int32_t ctd_copy_out(NSString *text, char *out, int32_t cap);
int32_t ctd_slot_kind(ctd_handle handle);
void ctd_emit_control(ctd_handle target, id sender);
void ctd_give_back(uint32_t slot);
// Forgets the clock a slot may have had, before the slot is handed out again.
// Declared here rather than in the clock's own file because the handle table
// is what calls it, and the table must not have to include QuartzCore to.
void ctd_clock_forget(uint32_t slot);
void ctd_tag(id object);

#endif
