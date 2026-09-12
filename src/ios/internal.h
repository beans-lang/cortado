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

// A table's data source and delegate. UIKit holds both weakly, so `g_targets`
// keeps it alive — the same arrangement as the target/action forwarder below.
@interface CortadoTableSource : NSObject <UITableViewDataSource, UITableViewDelegate>
@property (assign) ctd_handle handle;
@property (assign) NSInteger rows;
@property (retain) NSString *title;
@end

// A link's own target. A tap opens the URL; see the note beside CTD_S_URL in
// the header for why a link raises nothing.
// A title you press to show or hide what is under it. See pane.m, and the
// macOS host's file of the same name, for why UIKit needs a class here at all.
@interface CortadoDisclosure : UIView
@property (assign) UIButton *triangle;
@property (assign) UILabel *caption;
@property (assign) UIView *content;
@property (assign) BOOL open;
- (void)relayout;
- (CGFloat)headerHeight;
- (BOOL)isOpen;
@end

@interface CortadoLink : NSObject
@property (assign) ctd_handle handle;
- (void)follow:(id)sender;
@end

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

// The system image for a CTD_ICON_* role, or nil. See src/ios/icon.m.
UIImage *ctd_icon_image(int32_t icon);

// Which CTD_ICON_* a widget is showing, and setting it. The table is private
// to handles.m here, the way g_kind is.
int32_t ctd_slot_icon(ctd_handle handle);
void    ctd_set_slot_icon(ctd_handle handle, int32_t icon);
int32_t ctd_slot_kind(ctd_handle handle);
void ctd_emit_control(ctd_handle target, id sender);

// A UIColor as CTD_P_COLOR carries it, 0xRRGGBBAA.
//
// Here rather than beside the property because three files need it — the
// setter, the getter and the event — and a colour unpacked three ways is the
// sort of thing that looks right until somebody uses a colour that is not
// grey. Extended sRGB, because a UIColor built from a P3 literal reports
// components outside 0..1 and ctd_color_byte clamps them to the nearest sRGB
// byte, which is the colour cortado promised to carry.
int64_t ctd_ui_color_packed(UIColor *color);
void ctd_give_back(uint32_t slot);
// Forgets the clock a slot may have had, before the slot is handed out again.
// Declared here rather than in the clock's own file because the handle table
// is what calls it, and the table must not have to include QuartzCore to.
void ctd_clock_forget(uint32_t slot);
void ctd_tag(id object);

// The UITableView a CTD_W_TABLE handle stands for; nil for anything else.
// One event, raised by the host itself rather than by a control's action.
// Shared rather than static in app.m: table.m raises a selection too.
void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token);

// ------------------------------------------------------------------- input.m

// A recognizer that watches every touch and never claims one, so the control
// under it behaves exactly as it would with nothing attached.
@interface CortadoTouches : UIGestureRecognizer
@end

// Gives a view the recognizer touches arrive through, and records the handle it
// was tracked under. Called from ctd_track for every control there is.
void ctd_input_attach(id object, ctd_handle handle);
// The handle for the nearest ancestor of a view that cortado built, starting
// with the view itself. 0 for anything cortado did not build.
ctd_handle ctd_handle_for_view(UIView *view);
// Records that a control took the keyboard, raising blur on whatever had it.
// UIKit never tells the view that lost it, so cortado remembers.
void ctd_focus_moved(ctd_handle took);
// Whether anything asked for this kind.
int ctd_listening(uint32_t kind);

// ----------------------------------------------------------------- surface.m

// Raises one of the four things that happen to a surface, if anything asked.
void ctd_surface_event(uint32_t kind, ctd_handle surface, double a, double b);

// --------------------------------------------------------------- machine.m

// The platform's own watchers, up when the first handler for their kind
// arrives and down with the last — which is what ctd_listen is for.
// The one guard every gated call goes through: a bundle, a declared reason,
// and a permission that is not already denied. It touches no framework to
// decide, which is the whole point.
ctd_status ctd_gated(int32_t what);

void ctd_net_start(void);
void ctd_net_stop(void);
void ctd_power_start(void);
void ctd_power_stop(void);
UITableView *ctd_table_view(id object);

// ------------------------------------------------------------------- pane.m

UIView *ctd_disclosure_new(void);
void    ctd_disclosure_attach(ctd_handle handle, UIView *view);
void    ctd_chrome_of(id object, double *out);

// -------------------------------------------------------------------- web.m

UIView *ctd_web_new(void);
void    ctd_web_attach(ctd_handle handle, UIView *view);

#endif
