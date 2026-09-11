// The iOS host: real UIKit objects behind the same flat C ABI.
//
// This file exists to make one claim testable: `src/cortado_host.h` is a
// contract and not a description of AppKit. Everything above it — the layout
// solver, the component model, the markup compiler, the widget classes — is
// unchanged, and `tests/roles.out` is the same bytes here as on macOS.
//
// Where iOS genuinely has no equivalent, the answer is CTD_ERR_UNSUPPORTED and
// a capability that says no. That is the whole point of the capability API,
// and this is the first host that exercises it: there is no menu bar on a
// phone, and no second window either.
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
// it — across. It is the one place this host does something structural that
// the macOS host does not, and it is why `ctd_app_run` was always allowed not
// to return.

#import <UIKit/UIKit.h>
#include <string.h>
#include <float.h>
#include "cortado_host.h"

// ---------------------------------------------------------------- the table
//
// Identical to the macOS host's, deliberately. A handle is (generation << 32)
// | slot, so a handle used after its widget is released is a checked error
// rather than a jump into freed memory.

enum { CTD_SLOTS = 8192 };

static id       g_object[CTD_SLOTS];
static uint32_t g_generation[CTD_SLOTS];
static int32_t  g_kind[CTD_SLOTS];
static uint32_t g_used;

static ctd_event_fn g_sink;
static void        *g_sink_context;
static int32_t      g_role = CTD_ROLE_GUI;
static int          g_started;


// Slots a released widget gave back.
//
// The handle carries a generation *so that* a slot can be reused: a stale copy
// of a handle names the old generation and answers CTD_ERR_STALE, and a new
// widget in the same slot is a different handle entirely. Without this list
// the table is an arena that only ever grows, and a program that makes and
// destroys widgets — which is every program with a list in it — runs out after
// CTD_SLOTS of them however few are alive at once.
// Named `g_recycled` rather than `g_free`: the GTK host includes glib, and
// `g_free` is one of its functions.
static uint32_t g_recycled[CTD_SLOTS];
static uint32_t g_recycled_count;

// The next slot to use: one somebody gave back, or the next never-used one.
// Zero when the table is genuinely full.
static uint32_t ctd_take_slot(void) {
    if (g_recycled_count > 0) return g_recycled[--g_recycled_count];
    if (g_used + 1 >= CTD_SLOTS) return 0;
    return ++g_used;
}

static void ctd_give_back(uint32_t slot) {
    if (g_recycled_count < CTD_SLOTS) g_recycled[g_recycled_count++] = slot;
}

static ctd_handle ctd_track(id object, int32_t kind) {
    uint32_t slot = ctd_take_slot();
    if (slot == 0) return 0;
    g_object[slot] = [object retain];
    g_kind[slot] = kind;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    return ((uint64_t)g_generation[slot] << 32) | slot;
}

static id ctd_resolve(ctd_handle handle) {
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    uint32_t generation = (uint32_t)(handle >> 32);
    if (slot == 0 || slot > g_used) return nil;
    if (g_generation[slot] != generation) return nil;
    return g_object[slot];
}

static int32_t ctd_slot_kind(ctd_handle handle) {
    if (!ctd_resolve(handle)) return -1;
    return g_kind[(uint32_t)(handle & 0xffffffffu)];
}

// Only views cortado made are part of cortado's tree. UIKit installs private
// subviews of its own — a UITextField has several — and their names are not
// API, so counting them would make the tree depend on an iOS release.
static NSString *const kCortadoTag = @"cortado";

static void ctd_tag(id object) {
    if ([object isKindOfClass:[UIView class]]) {
        [(UIView *)object setAccessibilityIdentifier:kCortadoTag];
    }
}

static BOOL ctd_is_ours(UIView *view) {
    return [[view accessibilityIdentifier] isEqualToString:kCortadoTag];
}

static NSArray *ctd_children(UIView *container) {
    NSMutableArray *ours = [NSMutableArray array];
    for (UIView *child in [container subviews]) {
        if (ctd_is_ours(child)) [ours addObject:child];
    }
    return ours;
}

static int32_t ctd_copy_out(NSString *text, char *out, int32_t cap) {
    if (!text) text = @"";
    const char *utf8 = [text UTF8String];
    int32_t needed = utf8 ? (int32_t)strlen(utf8) : 0;
    if (out && cap > 0) {
        int32_t n = needed < cap ? needed : cap;
        if (n > 0) memcpy(out, utf8, (size_t)n);
    }
    return needed;
}

static NSString *ctd_string(const char *utf8, int32_t len) {
    NSString *text = [[[NSString alloc] initWithBytes:utf8
                                               length:(NSUInteger)(len < 0 ? 0 : len)
                                             encoding:NSUTF8StringEncoding] autorelease];
    return text ? text : @"";
}

// ------------------------------------------------------------------- events

static void ctd_emit_control(ctd_handle target, id sender);
static void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token);
static UIView *ctd_surface_view(id object);

@interface CortadoTarget : NSObject
@property (assign) ctd_handle handle;
- (void)fire:(id)sender;
@end

static NSMutableArray *g_targets;

@implementation CortadoTarget
- (void)fire:(id)sender {
    ctd_emit_control(self.handle, sender);
}
@end

static void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token) {
    if (!g_sink) return;
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = kind;
    event.target = target;
    event.index = index;
    event.token = token;
    g_sink(g_sink_context, &event);
}

// The same rule as the macOS host: a control that carries a value reports that
// it changed; a control that is a command reports that it was activated.
static void ctd_emit_control(ctd_handle target, id sender) {
    if (!g_sink) return;
    uint32_t kind = CTD_EV_ACTIVATE;
    int64_t index = 0;
    NSString *text = nil;

    int32_t made_as = ctd_slot_kind(target);
    if ([sender isKindOfClass:[UISlider class]]) {
        kind = CTD_EV_VALUE_CHANGED;
        index = (int64_t)[(UISlider *)sender value];
    } else if ([sender isKindOfClass:[UISwitch class]]) {
        kind = CTD_EV_VALUE_CHANGED;
        index = [(UISwitch *)sender isOn] ? 1 : 0;
    } else if ([sender isKindOfClass:[UITextField class]]) {
        kind = CTD_EV_TEXT_COMMIT;
        text = [(UITextField *)sender text];
    } else if (made_as == CTD_W_COMBO_BOX) {
        kind = CTD_EV_VALUE_CHANGED;
        index = (int64_t)[(UIButton *)sender tag];
        text = [(UIButton *)sender currentTitle];
    } else if (made_as == CTD_W_RADIO_BUTTON) {
        kind = CTD_EV_VALUE_CHANGED;
        index = [(UIButton *)sender isSelected] ? 1 : 0;
    }

    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = kind;
    event.target = target;
    event.index = index;
    if (text) {
        const char *utf8 = [text UTF8String];
        event.text = utf8;
        event.text_len = utf8 ? (int32_t)strlen(utf8) : 0;
    }
    g_sink(g_sink_context, &event);
}

// ---------------------------------------------------------------- lifecycle

// iOS will not start an application without a delegate — `UIApplicationMain`
// with none raises rather than returning an error. cortado's does nothing: the
// window and its controls already exist by the time `ctd_app_run` is called,
// which is the same order every other platform uses, and the delegate is only
// there because UIKit insists on one.
//
// It is also where the lifecycle events belong. A phone backgrounds an
// application constantly, and `CTD_EV_APP_BACKGROUND` and `CTD_EV_LOW_MEMORY`
// were in the event set from the first commit for exactly this — a desktop
// ignores them and a phone is built on them.
//
// It has one real job. cortado's order is create-then-run, which is every
// other platform's: build the window, fill it, show it, then start the loop.
// iOS is run-then-create — a `UIWindow` made before `UIApplicationMain` is not
// attached to anything, and `makeKeyAndVisible` on one does nothing. So the
// host remembers which surface was shown and the delegate shows it again once
// UIKit is running. That is the whole of the adaptation, and it is why
// `ctd_app_run` is allowed not to return: the header said so from the start.
@interface CortadoAppDelegate : UIResponder <UIApplicationDelegate>
// UIKit's legacy launch path asks the delegate for this, and hands the
// application a window of its own when the answer is nil. That window is the
// one on screen, and cortado's — correct, populated and key — sits behind it.
@property (nonatomic, retain) UIWindow *window;
@end

static ctd_handle g_shown;

// Attaches cortado's window to a scene.
//
// This is the one thing about iOS that genuinely has no counterpart anywhere
// else, and it cost the longest to find. Since iOS 13 a `UIWindow` belongs to a
// `UIWindowScene`, and one created before the application launched belongs to
// none. Such a window can be key, visible, unhidden, fully populated and
// correctly laid out — every property reads right — and it draws nothing at
// all, because it is attached to no screen.
//
// cortado builds its window before starting the loop, because that is the
// order every other platform uses and the order an application's code reads
// in. So the window is adopted by the first scene that connects, here.
static UIWindow *ctd_attach_scene(UIWindow *window) {
    if (!window) return nil;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in [[UIApplication sharedApplication] connectedScenes]) {
        if ([candidate isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) return window;
    if ([window windowScene] == scene) return window;

    // A window is *built from* its scene, not assigned one afterwards.
    // Assigning `windowScene` to a window made with `initWithFrame:` leaves
    // something that reads correct in every respect — key, visible, unhidden,
    // right frame, right scene — and renders nothing, not even its own
    // background colour. So a real scene window is made here and the view
    // controller, with cortado's whole tree under it, moves across.
    UIWindow *attached = [[UIWindow alloc] initWithWindowScene:scene];
    [attached setFrame:[[scene coordinateSpace] bounds]];
    [attached setBackgroundColor:[window backgroundColor]];
    UIViewController *controller = [window rootViewController];
    [[controller retain] autorelease];
    [window setRootViewController:nil];
    [window setHidden:YES];
    [attached setRootViewController:controller];
    [attached makeKeyAndVisible];

    // The safe area is only known once the window is on a scene, and a phone's
    // is not a detail: content under the notch or the home indicator is
    // content nobody can read or tap. The tree was laid out before any of this
    // existed, so the root is moved into the safe area and the surface reports
    // its new size — an application that listens for `surface_resized` lays
    // out again and fits exactly.
    UIView *content = [controller view];
    [content layoutIfNeeded];
    CGRect safe = [[content safeAreaLayoutGuide] layoutFrame];
    if (!CGRectIsEmpty(safe)) {
        for (UIView *child in ctd_children(content)) {
            [child setFrame:safe];
        }
        ctd_event resized;
        memset(&resized, 0, sizeof resized);
        resized.kind = CTD_EV_SURFACE_RESIZED;
        resized.width = safe.size.width;
        resized.height = safe.size.height;
        if (g_sink) g_sink(g_sink_context, &resized);
    }

    // The handle the caller holds must keep naming the surface it named
    // before, so the table's object is replaced rather than a second handle
    // minted. Everything above this file goes on using the same `Window`.
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == window) {
            [g_object[slot] release];
            g_object[slot] = [attached retain];
            break;
        }
    }
    [attached release];
    return attached;
}

@implementation CortadoAppDelegate
- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    id surface = g_shown ? ctd_resolve(g_shown) : nil;
    if ([surface isKindOfClass:[UIWindow class]]) {
        // Handed to UIKit as *the* window, not merely made key. A delegate
        // that answers nil for its `window` gets one created for it, and that
        // one is what the screen shows — cortado's would be correct,
        // populated, key, and behind it.
        //
        // Nothing is resized here either, and that is a fix rather than an
        // omission: a view controller's view has not been laid out at this
        // point, so its bounds are not yet the screen, and resizing the root
        // to them collapses the whole tree to nothing. The frames the solver
        // computed are already right, because `Surface.content_size` asked the
        // window, which has had the screen's bounds since it was made.
        self.window = ctd_attach_scene((UIWindow *)surface);
        [self.window makeKeyAndVisible];
    }
    ctd_emit(CTD_EV_APP_LAUNCHED, 0, 0, 0);
    return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    // A scene has certainly connected by now; at didFinishLaunching it may not
    // have, so the attach is attempted at both and is a no-op once it has
    // taken.
    // A scene has certainly connected by now; at didFinishLaunching it may not
    // have, so the attach is attempted at both and is a no-op once it has
    // taken.
    self.window = ctd_attach_scene(self.window);
    ctd_emit(CTD_EV_APP_FOREGROUND, 0, 0, 0);
}
- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    ctd_emit(CTD_EV_APP_BACKGROUND, 0, 0, 0);
}
- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    ctd_emit(CTD_EV_APP_WILL_QUIT, 0, 0, 0);
}
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    (void)application;
    ctd_emit(CTD_EV_LOW_MEMORY, 0, 0, 0);
}
@end

uint32_t ctd_abi_version(void) { return CTD_ABI_VERSION; }

ctd_status ctd_init(uint32_t want_abi) {
    if (want_abi != CTD_ABI_VERSION) return CTD_ERR_ABI;
    if (g_started) return CTD_OK;
    g_targets = [[NSMutableArray alloc] init];
    g_started = 1;
    return CTD_OK;
}

// An application has no activation policy on iOS — it is whatever the system
// launched. The role is remembered so `ctd_capability` and `ctd_surface_show`
// can answer consistently, which is what a headless test needs.
ctd_status ctd_app_set_role(int32_t role) {
    if (role != CTD_ROLE_GUI && role != CTD_ROLE_ACCESSORY &&
        role != CTD_ROLE_HEADLESS) {
        return CTD_ERR_RANGE;
    }
    g_role = role;
    return CTD_OK;
}

ctd_status ctd_set_event_sink(ctd_event_fn sink, void *context) {
    g_sink = sink;
    g_sink_context = context;
    return CTD_OK;
}

void ctd_shutdown(void) {
    g_sink = NULL;
    g_sink_context = NULL;
}

// `UIApplicationMain` never returns, and on iOS the program does not own its
// own loop: the system starts it, and a program that called this expecting to
// get control back at the end would never run its teardown. A headless run
// does nothing at all, which is what makes the test suite work here.
void ctd_app_run(void) {
    if (g_role == CTD_ROLE_HEADLESS) return;
    @autoreleasepool {
        // UIApplicationMain wants a real argv even when it reads nothing from
        // it; passing NULL is a nonnull violation the compiler warns about and
        // the runtime would be within its rights to trap on.
        static char program[] = "cortado";
        static char *argv[] = { program, NULL };
        UIApplicationMain(1, argv, nil,
                          NSStringFromClass([CortadoAppDelegate class]));
    }
}

// There is no such thing. An iOS application is stopped by the system, never
// by itself — Apple's guidance is explicit that a program which exits on its
// own looks like a crash to the person holding the phone.
void ctd_app_stop(void) {}

void ctd_post(int64_t token) {
    ctd_emit(CTD_EV_POST, 0, 0, token);
}

int32_t ctd_capability(int32_t capability) {
    switch (capability) {
        // The two a phone does not have, and the reason this host is worth
        // writing: a framework that assumed a menu bar would have had to
        // discover it here rather than declare it.
        case CTD_CAP_MENU_BAR:      return 0;
        case CTD_CAP_WINDOW_MENU:   return 0;
        case CTD_CAP_MULTI_SURFACE: return 0;
        case CTD_CAP_RESIZABLE:     return 0;
        case CTD_CAP_FILE_DIALOG:   return 1;
        case CTD_CAP_SNAPSHOT:      return 0;
        default:                    return 0;
    }
}

// -------------------------------------------------------------------- surfaces
//
// A surface is a UIWindow with a root view controller. A phone has one, always
// full screen, so the requested size is advisory — `ctd_surface_content_size`
// answers what the surface actually is, which is what the layout solver uses.

ctd_handle ctd_surface_new(double width, double height) {
    CGRect bounds = CGRectMake(0, 0, width, height);
    UIScreen *screen = [UIScreen mainScreen];
    if (screen && !CGRectIsEmpty([screen bounds])) bounds = [screen bounds];
    UIWindow *window = [[UIWindow alloc] initWithFrame:bounds];
    UIViewController *controller = [[UIViewController alloc] init];
    // A window on macOS has the system background without being asked; a
    // UIWindow has none, which is black. Text drawn in the system label colour
    // is then black on black, and the screen looks empty rather than wrong.
    [window setBackgroundColor:[UIColor systemBackgroundColor]];
    [[controller view] setBackgroundColor:[UIColor systemBackgroundColor]];
    [window setRootViewController:controller];
    [controller release];
    ctd_handle handle = ctd_track(window, -1);
    [window release];
    return handle;
}

// A window has no title on iOS. It is stored so `ctd_surface_title` answers
// what was set — a program that names its screens should not lose the name
// just because this platform does not show it — and a navigation bar, when
// there is one, is the place it belongs.
static NSMutableDictionary *g_titles;

// A zero byte anywhere in the text. Every entry point that takes a string
// checks, because no platform text control can hold one: NSString's
// UTF8String ends at it, GTK's const char* ends at it, and Win32's
// SetWindowTextW ends at it. Passing one through would cut a program's string
// in half somewhere inside the platform, with nothing at the boundary able to
// say where — so it is refused here, by name, while the caller's own string
// is still in view.
static int ctd_has_nul(const char *utf8, int32_t len) {
    if (!utf8 || len <= 0) return 0;
    for (int32_t i = 0; i < len; i++) {
        if (utf8[i] == 0) return 1;
    }
    return 0;
}

ctd_status ctd_surface_set_title(ctd_handle surface, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIWindow class]]) return CTD_ERR_KIND;
    if (!g_titles) g_titles = [[NSMutableDictionary alloc] init];
    [g_titles setObject:ctd_string(utf8, len)
                 forKey:[NSNumber numberWithUnsignedLongLong:surface]];
    return CTD_OK;
}

int32_t ctd_surface_title(ctd_handle surface, char *out, int32_t cap) {
    if (!ctd_resolve(surface)) return CTD_ERR_STALE;
    NSString *held = [g_titles objectForKey:
        [NSNumber numberWithUnsignedLongLong:surface]];
    return ctd_copy_out(held ? held : @"", out, cap);
}

static UIView *ctd_surface_view(id object) {
    if (![object isKindOfClass:[UIWindow class]]) return nil;
    UIViewController *controller = [(UIWindow *)object rootViewController];
    return controller ? [controller view] : nil;
}

ctd_status ctd_surface_set_root(ctd_handle surface, ctd_handle root) {
    id object = ctd_resolve(surface);
    UIView *view = (UIView *)ctd_resolve(root);
    if (!object || !view) return CTD_ERR_STALE;
    UIView *content = ctd_surface_view(object);
    if (!content) return CTD_ERR_KIND;
    for (UIView *existing in ctd_children(content)) {
        [existing removeFromSuperview];
    }
    [view setFrame:[content bounds]];
    [content addSubview:view];
    return CTD_OK;
}

ctd_handle ctd_surface_root(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (!object) return 0;
    UIView *content = ctd_surface_view(object);
    if (!content) return 0;
    NSArray *ours = ctd_children(content);
    if ([ours count] == 0) return 0;
    id wanted = [ours objectAtIndex:0];
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == wanted) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

ctd_status ctd_surface_content_size(ctd_handle surface, double *out_size) {
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    UIView *content = ctd_surface_view(object);
    if (!content) return CTD_ERR_KIND;
    // The safe area when there is one — the part of the screen a person can
    // actually see and reach. Before the window is on a scene there is none,
    // and the full bounds are the honest answer until `surface_resized` says
    // otherwise.
    CGRect safe = [[content safeAreaLayoutGuide] layoutFrame];
    CGRect bounds = CGRectIsEmpty(safe) ? [content bounds] : safe;
    if (out_size) {
        out_size[0] = bounds.size.width;
        out_size[1] = bounds.size.height;
    }
    return CTD_OK;
}

ctd_status ctd_surface_show(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIWindow class]]) return CTD_ERR_KIND;
    if (g_role == CTD_ROLE_HEADLESS) return CTD_OK;
    // Remembered as well as applied: this usually runs before
    // `UIApplicationMain`, where it has no effect, and the delegate does it
    // again once UIKit is running.
    g_shown = surface;
    [(UIWindow *)object makeKeyAndVisible];
    return CTD_OK;
}

ctd_status ctd_surface_close(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIWindow class]]) return CTD_ERR_KIND;
    [(UIWindow *)object setHidden:YES];
    return CTD_OK;
}

int32_t ctd_surface_visible(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (!object) return 0;
    if (![object isKindOfClass:[UIWindow class]]) return 0;
    return [(UIWindow *)object isHidden] ? 0 : 1;
}

// --------------------------------------------------------------------- widgets

// iOS has no radio button and no pop-up list control. Both are built from a
// UIButton — a radio out of a selected state, a combo box out of a UIMenu —
// which is what Apple's own applications do. Neither is a stand-in drawn by
// cortado: a UIButton with a menu *is* the platform's control for choosing one
// of several on this system.

ctd_handle ctd_widget_new(int32_t kind) {
    UIView *view = nil;
    switch (kind) {
        case CTD_W_CONTAINER:
            view = [[UIView alloc] initWithFrame:CGRectZero];
            break;
        case CTD_W_LABEL: {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            [label setText:@""];
            view = label;
            break;
        }
        case CTD_W_BUTTON: {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setFrame:CGRectZero];
            view = [button retain];
            break;
        }
        case CTD_W_TEXT_FIELD: {
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
            [field setBorderStyle:UITextBorderStyleRoundedRect];
            view = field;
            break;
        }
        case CTD_W_CHECK_BOX: {
            // A switch is what iOS uses where a desktop uses a check box. It
            // has no mixed state, which `ctd_set_int` reports rather than
            // rounding to on or off.
            UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
            view = toggle;
            break;
        }
        case CTD_W_IMAGE_VIEW:
            view = [[UIImageView alloc] initWithFrame:CGRectZero];
            break;
        case CTD_W_SLIDER: {
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
            [slider setMinimumValue:0.0f];
            [slider setMaximumValue:1.0f];
            view = slider;
            break;
        }
        case CTD_W_PROGRESS_BAR: {
            UIProgressView *bar =
                [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
            view = bar;
            break;
        }
        case CTD_W_SEPARATOR: {
            // iOS has no separator control; a hairline view is what a table's
            // own separators are, and `separatorColor` is the system's.
            UIView *rule = [[UIView alloc] initWithFrame:CGRectZero];
            [rule setBackgroundColor:[UIColor separatorColor]];
            view = rule;
            break;
        }
        case CTD_W_TEXT_AREA: {
            UITextView *text = [[UITextView alloc] initWithFrame:CGRectZero];
            [text setScrollEnabled:YES];
            view = text;
            break;
        }
        case CTD_W_COMBO_BOX: {
            UIButton *menu = [UIButton buttonWithType:UIButtonTypeSystem];
            [menu setFrame:CGRectZero];
            [menu setShowsMenuAsPrimaryAction:YES];
            [menu setTag:-1];
            view = [menu retain];
            break;
        }
        case CTD_W_SCROLL_VIEW: {
            UIScrollView *scroller = [[UIScrollView alloc] initWithFrame:CGRectZero];
            view = scroller;
            break;
        }
        case CTD_W_RADIO_BUTTON: {
            UIButton *radio = [UIButton buttonWithType:UIButtonTypeSystem];
            [radio setFrame:CGRectZero];
            view = [radio retain];
            break;
        }
        default:
            return 0;
    }
    ctd_tag(view);
    ctd_handle handle = ctd_track(view, kind);
    if ([view isKindOfClass:[UIControl class]]) {
        CortadoTarget *forwarder = [[CortadoTarget alloc] init];
        [forwarder setHandle:handle];
        // Both events, because a UIControl reports a press and a value change
        // on different ones and cortado decides the kind from the widget.
        [(UIControl *)view addTarget:forwarder
                              action:@selector(fire:)
                    forControlEvents:UIControlEventTouchUpInside |
                                     UIControlEventValueChanged |
                                     UIControlEventEditingDidEndOnExit];
        [g_targets addObject:forwarder];
        [forwarder release];
    }
    [view release];
    return handle;
}

int32_t ctd_widget_kind(ctd_handle widget) { return ctd_slot_kind(widget); }

int32_t ctd_widget_alive(ctd_handle widget) { return ctd_resolve(widget) ? 1 : 0; }

ctd_status ctd_widget_release(ctd_handle widget) {
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[UIView class]]) {
        [(UIView *)object removeFromSuperview];
    }
    [object release];
    g_object[slot] = nil;
    // Bumping the generation is what turns a stale handle into a checked
    // error rather than a jump into a slot somebody else now owns — and what
    // makes handing the slot back safe.
    g_generation[slot] = g_generation[slot] + 1;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    ctd_give_back(slot);
    return CTD_OK;
}

// ------------------------------------------------------------------------ tree

static UIView *ctd_container_of(id object) {
    if ([object isKindOfClass:[UIWindow class]]) return ctd_surface_view(object);
    if ([object isKindOfClass:[UIView class]]) return (UIView *)object;
    return nil;
}

// A text view holds text, not widgets. Adding a button to one would put it
// inside a paragraph — UIKit allows it and nothing good comes of it.
static BOOL ctd_can_hold(UIView *content) {
    if (!content) return NO;
    if ([content isKindOfClass:[UITextView class]]) return NO;
    if ([content isKindOfClass:[UITextField class]]) return NO;
    return YES;
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    id owner = ctd_resolve(parent);
    UIView *view = (UIView *)ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    UIView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    NSArray *existing = ctd_children(container);
    if (index < 0 || index >= (int32_t)[existing count]) {
        [container addSubview:view];
    } else {
        [container insertSubview:view
                    belowSubview:[existing objectAtIndex:(NSUInteger)index]];
    }
    return CTD_OK;
}

ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child) {
    id owner = ctd_resolve(parent);
    UIView *view = (UIView *)ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    UIView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    if ([view superview] != container) return CTD_ERR_RANGE;
    [view removeFromSuperview];
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    UIView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    NSArray *children = ctd_children(container);
    int32_t count = (int32_t)[children count];
    if (from < 0 || from >= count || to < 0 || to >= count) return CTD_ERR_RANGE;
    if (from == to) return CTD_OK;
    // Held across the move: -removeFromSuperview drops the superview's
    // reference, and on a view the caller no longer names that is the last one.
    UIView *moving = [[children objectAtIndex:(NSUInteger)from] retain];
    UIResponder *first = nil;
    if ([moving isFirstResponder]) first = moving;
    [moving removeFromSuperview];
    NSArray *rest = ctd_children(container);
    if (to >= (int32_t)[rest count]) {
        [container addSubview:moving];
    } else {
        [container insertSubview:moving
                    belowSubview:[rest objectAtIndex:(NSUInteger)to]];
    }
    // Reordering a list should not take the keyboard away from the field being
    // edited, which is what UIKit does on its own.
    if (first) [first becomeFirstResponder];
    [moving release];
    return CTD_OK;
}

ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    UIView *container = ctd_container_of(owner);
    if (!container || !ctd_can_hold(container)) {
        if (out) *out = 0;
        return CTD_OK;
    }
    if (out) *out = (int32_t)[ctd_children(container) count];
    return CTD_OK;
}

ctd_handle ctd_view_child_at(ctd_handle parent, int32_t index) {
    id owner = ctd_resolve(parent);
    if (!owner) return 0;
    UIView *container = ctd_container_of(owner);
    if (!container || !ctd_can_hold(container)) return 0;
    NSArray *children = ctd_children(container);
    if (index < 0 || index >= (int32_t)[children count]) return 0;
    id wanted = [children objectAtIndex:(NSUInteger)index];
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == wanted) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

ctd_handle ctd_view_parent(ctd_handle child) {
    UIView *view = (UIView *)ctd_resolve(child);
    if (!view) return 0;
    UIView *parent = [view superview];
    if (!parent) return 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == parent) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

// -------------------------------------------------------------------- geometry

ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height) {
    UIView *view = (UIView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    // No flip. UIKit's coordinate space already has its origin at the top left
    // with y growing downward, which is what cortado means by a frame — the
    // macOS host is the one that has work to do here.
    [view setFrame:CGRectMake(x, y, width, height)];
    return CTD_OK;
}

ctd_status ctd_view_frame(ctd_handle widget, double *out_frame) {
    UIView *view = (UIView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    CGRect frame = [view frame];
    if (out_frame) {
        out_frame[0] = frame.origin.x;
        out_frame[1] = frame.origin.y;
        out_frame[2] = frame.size.width;
        out_frame[3] = frame.size.height;
    }
    return CTD_OK;
}

ctd_status ctd_view_measure(ctd_handle widget, double avail_width, double avail_height,
                            double *out_size) {
    UIView *view = (UIView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    CGSize offer = CGSizeMake(avail_width < 0 ? CGFLOAT_MAX : avail_width,
                              avail_height < 0 ? CGFLOAT_MAX : avail_height);
    CGSize wanted = [view sizeThatFits:offer];
    if (ctd_slot_kind(widget) == CTD_W_SEPARATOR) {
        // A hairline. iOS has no separator control, so cortado's is a plain
        // view, and a plain view measures zero — which collapses it to
        // nothing. One point is what a table's own separators are, and is the
        // same answer an NSBox gives on macOS, so the two platforms agree.
        wanted = CGSizeMake(avail_width < 0 ? 0.0 : avail_width, 1.0);
    } else if (wanted.width <= 0.0 && wanted.height <= 0.0) {
        // A view with no intrinsic size answers zero. Its own frame is the
        // honest fallback: it is what the caller last set.
        wanted = [view frame].size;
    }
    if (out_size) {
        out_size[0] = wanted.width;
        out_size[1] = wanted.height;
    }
    return CTD_OK;
}

// ------------------------------------------------------------------ properties

ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_ENABLED:
            if (![object isKindOfClass:[UIControl class]]) return CTD_ERR_KIND;
            [(UIControl *)object setEnabled:value ? YES : NO];
            return CTD_OK;
        case CTD_P_HIDDEN:
            if (![object isKindOfClass:[UIView class]]) return CTD_ERR_KIND;
            [(UIView *)object setHidden:value ? YES : NO];
            return CTD_OK;
        case CTD_P_CHECKED:
            if ([object isKindOfClass:[UISwitch class]]) {
                // A switch has two states. A mixed one is not something iOS
                // can show, and quietly rounding it to on or off would make a
                // tri-state check box lie about itself on this platform only.
                if (value == 2) return CTD_ERR_UNSUPPORTED;
                [(UISwitch *)object setOn:value ? YES : NO];
                return CTD_OK;
            }
            if (ctd_slot_kind(widget) == CTD_W_RADIO_BUTTON) {
                UIButton *radio = (UIButton *)object;
                [radio setSelected:value == 1];
                // iOS has no radio control, so the state has to be visible
                // some other way. A filled circle beside the title is what
                // Apple's own settings screens use.
                [radio setImage:[UIImage systemImageNamed:
                    value == 1 ? @"largecircle.fill.circle" : @"circle"]
               forState:UIControlStateNormal];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_EDITABLE:
            if ([object isKindOfClass:[UITextField class]]) {
                [(UITextField *)object setEnabled:value ? YES : NO];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setEditable:value ? YES : NO];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_ALIGNMENT: {
            NSTextAlignment alignment = value == 1 ? NSTextAlignmentCenter
                                      : value == 2 ? NSTextAlignmentRight
                                                   : NSTextAlignmentLeft;
            if ([object isKindOfClass:[UILabel class]]) {
                [(UILabel *)object setTextAlignment:alignment];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UITextField class]]) {
                [(UITextField *)object setTextAlignment:alignment];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setTextAlignment:alignment];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        }
        case CTD_P_SELECTED: {
            if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
            UIButton *menu = (UIButton *)object;
            UIMenu *items = [menu menu];
            NSArray *children = items ? [items children] : @[];
            if (value < 0) {
                [menu setTag:-1];
                [menu setTitle:@"" forState:UIControlStateNormal];
                return CTD_OK;
            }
            if (value >= (int64_t)[children count]) return CTD_ERR_RANGE;
            UIAction *chosen = (UIAction *)[children objectAtIndex:(NSUInteger)value];
            [menu setTag:(NSInteger)value];
            [menu setTitle:[chosen title] forState:UIControlStateNormal];
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE:
            // A UIProgressView is always determinate; an indeterminate one is
            // a UIActivityIndicatorView, a different control. Saying so beats
            // showing a bar stuck at zero.
            if (![object isKindOfClass:[UIProgressView class]]) return CTD_ERR_KIND;
            return value ? CTD_ERR_UNSUPPORTED : CTD_OK;
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    int64_t value = 0;
    switch (key) {
        case CTD_P_ENABLED:
            if (![object isKindOfClass:[UIControl class]]) return CTD_ERR_KIND;
            value = [(UIControl *)object isEnabled] ? 1 : 0;
            break;
        case CTD_P_HIDDEN:
            if (![object isKindOfClass:[UIView class]]) return CTD_ERR_KIND;
            value = [(UIView *)object isHidden] ? 1 : 0;
            break;
        case CTD_P_CHECKED:
            if ([object isKindOfClass:[UISwitch class]]) {
                value = [(UISwitch *)object isOn] ? 1 : 0;
            } else if (ctd_slot_kind(widget) == CTD_W_RADIO_BUTTON) {
                value = [(UIButton *)object isSelected] ? 1 : 0;
            } else {
                return CTD_ERR_KIND;
            }
            break;
        case CTD_P_EDITABLE:
            if ([object isKindOfClass:[UITextField class]]) {
                value = [(UITextField *)object isEnabled] ? 1 : 0;
            } else if ([object isKindOfClass:[UITextView class]]) {
                value = [(UITextView *)object isEditable] ? 1 : 0;
            } else {
                return CTD_ERR_KIND;
            }
            break;
        case CTD_P_SELECTED:
            if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
            value = (int64_t)[(UIButton *)object tag];
            break;
        case CTD_P_INDETERMINATE:
            if (![object isKindOfClass:[UIProgressView class]]) return CTD_ERR_KIND;
            value = 0;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// A slider and a progress view both carry a range and a position, and UIKit
// puts them on unrelated classes with different spellings — a progress view
// has no range at all, only a 0..1 fraction. The property bag hides that: a
// caller sets CTD_P_MIN on either and the host does the arithmetic.
static double g_progress_min[CTD_SLOTS];
static double g_progress_max[CTD_SLOTS];

static uint32_t ctd_slot_of(ctd_handle handle) {
    return (uint32_t)(handle & 0xffffffffu);
}

ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = ctd_slot_of(widget);
    switch (key) {
        case CTD_P_FONT_SIZE: {
            UIFont *font = [UIFont systemFontOfSize:value];
            if ([object isKindOfClass:[UILabel class]]) {
                [(UILabel *)object setFont:font];
            } else if ([object isKindOfClass:[UITextField class]]) {
                [(UITextField *)object setFont:font];
            } else if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setFont:font];
            } else if ([object isKindOfClass:[UIButton class]]) {
                [[(UIButton *)object titleLabel] setFont:font];
            } else {
                return CTD_ERR_KIND;
            }
            return CTD_OK;
        }
        case CTD_P_MIN:
            if ([object isKindOfClass:[UISlider class]]) {
                [(UISlider *)object setMinimumValue:(float)value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UIProgressView class]]) {
                g_progress_min[slot] = value;
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if ([object isKindOfClass:[UISlider class]]) {
                [(UISlider *)object setMaximumValue:(float)value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UIProgressView class]]) {
                g_progress_max[slot] = value;
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[UISlider class]]) {
                [(UISlider *)object setValue:(float)value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UIProgressView class]]) {
                double low = g_progress_min[slot];
                double high = g_progress_max[slot];
                double span = high - low;
                double fraction = span > 0.0 ? (value - low) / span : 0.0;
                if (fraction < 0.0) fraction = 0.0;
                if (fraction > 1.0) fraction = 1.0;
                [(UIProgressView *)object setProgress:(float)fraction];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_STEP: {
            // A UISlider is always continuous. Refusing beats snapping in the
            // host: a caller that asked for detents and got none should be
            // told, not left wondering why the thumb slides freely.
            if (![object isKindOfClass:[UISlider class]]) return CTD_ERR_KIND;
            if (value <= 0.0) return CTD_OK;
            return CTD_ERR_UNSUPPORTED;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = ctd_slot_of(widget);
    double value = 0.0;
    switch (key) {
        case CTD_P_FONT_SIZE:
            if ([object isKindOfClass:[UILabel class]]) {
                value = [[(UILabel *)object font] pointSize];
            } else if ([object isKindOfClass:[UITextField class]]) {
                value = [[(UITextField *)object font] pointSize];
            } else if ([object isKindOfClass:[UITextView class]]) {
                value = [[(UITextView *)object font] pointSize];
            } else if ([object isKindOfClass:[UIButton class]]) {
                value = [[[(UIButton *)object titleLabel] font] pointSize];
            } else {
                return CTD_ERR_KIND;
            }
            break;
        case CTD_P_MIN:
            if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object minimumValue];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                value = g_progress_min[slot];
            } else { return CTD_ERR_KIND; }
            break;
        case CTD_P_MAX:
            if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object maximumValue];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                value = g_progress_max[slot];
            } else { return CTD_ERR_KIND; }
            break;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object value];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                double low = g_progress_min[slot];
                double high = g_progress_max[slot];
                value = low + (high - low) * [(UIProgressView *)object progress];
            } else { return CTD_ERR_KIND; }
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// ----------------------------------------------------------------------- text

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = ctd_string(utf8, len);
    if ([object isKindOfClass:[UILabel class]])          [(UILabel *)object setText:text];
    else if ([object isKindOfClass:[UITextField class]]) [(UITextField *)object setText:text];
    else if ([object isKindOfClass:[UITextView class]])  [(UITextView *)object setText:text];
    else if ([object isKindOfClass:[UIButton class]])
        [(UIButton *)object setTitle:text forState:UIControlStateNormal];
    else if ([object isKindOfClass:[UISwitch class]]) {
        // A UISwitch shows no text — on iOS the label sits beside it as its
        // own view. But the text a program gives a check box is exactly what
        // VoiceOver should read, so it becomes the accessibility label. That
        // is not a place to park it: it is where that string belongs on this
        // platform, and it is the only thing that makes the switch legible to
        // somebody who cannot see it.
        [(UISwitch *)object setAccessibilityLabel:text];
    }
    else return CTD_ERR_KIND;
    return CTD_OK;
}

int32_t ctd_get_text(ctd_handle widget, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[UILabel class]])
        return ctd_copy_out([(UILabel *)object text], out, cap);
    if ([object isKindOfClass:[UITextField class]])
        return ctd_copy_out([(UITextField *)object text], out, cap);
    if ([object isKindOfClass:[UITextView class]])
        return ctd_copy_out([(UITextView *)object text], out, cap);
    if ([object isKindOfClass:[UIButton class]])
        return ctd_copy_out([(UIButton *)object currentTitle], out, cap);
    if ([object isKindOfClass:[UISwitch class]])
        return ctd_copy_out([(UISwitch *)object accessibilityLabel], out, cap);
    return ctd_copy_out(@"", out, cap);
}

// ---------------------------------------------------------------------- menus
//
// **A phone has no menu bar, and this is what that looks like.** Every menu
// call answers CTD_ERR_UNSUPPORTED and `ctd_capability(CTD_CAP_MENU_BAR)`
// answers no, so a program asks before it builds one and gets a typed refusal
// if it does not. That is the capability API doing the job it exists for, and
// this host is the first to exercise it.
//
// It is not a stub in the sense of unfinished work. iOS commands live in a
// navigation bar, a toolbar or a context menu, which are different controls
// with different placement rules — modelling them as a menu bar would produce
// something that is neither.

ctd_handle ctd_menu_new(const char *title, int32_t len) {
    (void)title; (void)len;
    return 0;
}

ctd_status ctd_menu_add_item(ctd_handle menu, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token) {
    if (ctd_has_nul(title, title_len) || ctd_has_nul(key, key_len))
        return CTD_ERR_RANGE;
    (void)menu; (void)title; (void)title_len; (void)key; (void)key_len;
    (void)role; (void)token;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_add_separator(ctd_handle menu) {
    (void)menu;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_add_submenu(ctd_handle menu, ctd_handle child) {
    (void)menu; (void)child;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_item_count(ctd_handle menu, int32_t *out) {
    (void)menu; (void)out;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_menu_item_title(ctd_handle menu, int32_t index, char *out, int32_t cap) {
    (void)menu; (void)index; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_menu_item_key(ctd_handle menu, int32_t index, char *out, int32_t cap) {
    (void)menu; (void)index; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_set_bar(ctd_handle menu) {
    (void)menu;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_set_enabled(ctd_handle menu, int64_t token, int32_t on) {
    (void)menu; (void)token; (void)on;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_invoke(ctd_handle menu, int64_t token) {
    (void)menu; (void)token;
    return CTD_ERR_UNSUPPORTED;
}

// ------------------------------------------------------------------ item lists

ctd_status ctd_items_clear(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    UIButton *menu = (UIButton *)object;
    [menu setMenu:[UIMenu menuWithChildren:@[]]];
    [menu setTag:-1];
    [menu setTitle:@"" forState:UIControlStateNormal];
    return CTD_OK;
}

ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    if (len < 0) return CTD_ERR_RANGE;
    UIButton *menu = (UIButton *)object;
    UIMenu *existing = [menu menu];
    NSMutableArray *children =
        [NSMutableArray arrayWithArray:existing ? [existing children] : @[]];
    NSString *title = ctd_string(utf8, len);
    NSInteger position = (NSInteger)[children count];
    ctd_handle self_handle = widget;
    UIAction *item = [UIAction actionWithTitle:title
                                         image:nil
                                    identifier:nil
                                       handler:^(__kindof UIAction *action) {
        (void)action;
        id control = ctd_resolve(self_handle);
        if (!control) return;
        [(UIButton *)control setTag:position];
        [(UIButton *)control setTitle:title forState:UIControlStateNormal];
        ctd_emit_control(self_handle, control);
    }];
    [children addObject:item];
    [menu setMenu:[UIMenu menuWithChildren:children]];
    return CTD_OK;
}

ctd_status ctd_items_count(ctd_handle widget, int32_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    UIMenu *items = [(UIButton *)object menu];
    if (out) *out = items ? (int32_t)[[items children] count] : 0;
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    UIMenu *items = [(UIButton *)object menu];
    NSArray *children = items ? [items children] : @[];
    if (index < 0 || index >= (int32_t)[children count]) return CTD_ERR_RANGE;
    UIMenuElement *item = [children objectAtIndex:(NSUInteger)index];
    return ctd_copy_out([item title], out, cap);
}

// -------------------------------------------------------------------- dialogs

// The top view controller a sheet can be presented from. A window with no root
// has none, which is the headless case.
static UIViewController *ctd_presenter(ctd_handle parent) {
    id object = parent ? ctd_resolve(parent) : nil;
    if (![object isKindOfClass:[UIWindow class]]) return nil;
    UIWindow *window = (UIWindow *)object;
    if ([window isHidden]) return nil;
    UIViewController *controller = [window rootViewController];
    while (controller && [controller presentedViewController]) {
        controller = [controller presentedViewController];
    }
    return controller;
}

ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token) {
    if (kind < CTD_DLG_MESSAGE || kind > CTD_DLG_SAVE) return CTD_ERR_RANGE;
    if (parent && !ctd_resolve(parent)) return CTD_ERR_STALE;

    NSString *heading = ctd_string(title, title_len);
    NSString *detail = ctd_string(body, body_len);
    void (^answer)(NSInteger, NSString *) = ^(NSInteger which, NSString *path) {
        ctd_event event;
        memset(&event, 0, sizeof event);
        event.kind = CTD_EV_POST;
        event.token = token;
        event.index = (int64_t)which;
        const char *utf8 = path ? [path UTF8String] : NULL;
        event.text = utf8;
        event.text_len = utf8 ? (int32_t)strlen(utf8) : 0;
        if (g_sink) g_sink(g_sink_context, &event);
    };

    UIViewController *presenter = ctd_presenter(parent);
    // Same contract as the macOS host, and for the same reason: a dialog that
    // answered nothing would leave the caller waiting on a token forever.
    if (!presenter) {
        answer(kind == CTD_DLG_MESSAGE || kind == CTD_DLG_CONFIRM ? 0 : 1, nil);
        return CTD_OK;
    }

    if (kind == CTD_DLG_OPEN || kind == CTD_DLG_SAVE) {
        // A document picker is the iOS file dialog, and it needs a delegate to
        // report through rather than a completion block. Until that is wired,
        // a file dialog answers a cancel — which is a refusal the caller can
        // see, not a promise that never resolves.
        answer(1, nil);
        return CTD_OK;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:heading
                                            message:detail
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        (void)action;
        answer(0, nil);
    }]];
    if (kind == CTD_DLG_CONFIRM) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *action) {
            (void)action;
            answer(1, nil);
        }]];
    }
    [presenter presentViewController:alert animated:NO completion:nil];
    return CTD_OK;
}

// ----------------------------------------------------------------- appearance

int32_t ctd_appearance(void) {
    UITraitCollection *traits = [UITraitCollection currentTraitCollection];
    return [traits userInterfaceStyle] == UIUserInterfaceStyleDark ? 1 : 0;
}

ctd_status ctd_surface_scale(ctd_handle surface, double *out) {
    double scale = [[UIScreen mainScreen] scale];
    if (surface) {
        id object = ctd_resolve(surface);
        if (!object) return CTD_ERR_STALE;
        if (![object isKindOfClass:[UIWindow class]]) return CTD_ERR_KIND;
        UIScreen *screen = [(UIWindow *)object screen];
        if (screen) scale = [screen scale];
    }
    if (scale <= 0.0) scale = 1.0;
    if (out) *out = scale;
    return CTD_OK;
}

// ---------------------------------------------------------------------- fonts

static UIFont *ctd_font_for(int32_t role) {
    switch (role) {
        case CTD_FONT_HEADING:
            return [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        case CTD_FONT_CAPTION:
            return [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        case CTD_FONT_MONO:
            return [UIFont monospacedSystemFontOfSize:[UIFont systemFontSize]
                                               weight:UIFontWeightRegular];
        case CTD_FONT_BODY:
            return [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        default:
            return nil;
    }
}

int32_t ctd_font_family(int32_t role, char *out, int32_t cap) {
    UIFont *font = ctd_font_for(role);
    if (!font) return CTD_ERR_RANGE;
    return ctd_copy_out([font familyName], out, cap);
}

ctd_status ctd_font_size(int32_t role, double *out) {
    UIFont *font = ctd_font_for(role);
    if (!font) return CTD_ERR_RANGE;
    if (out) *out = (double)[font pointSize];
    return CTD_OK;
}

// ------------------------------------------------------------- introspection

int32_t ctd_native_class(ctd_handle widget, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    return ctd_copy_out(NSStringFromClass([object class]), out, cap);
}

// The same vocabulary the macOS host answers, which is what lets
// `tests/roles.out` be one file for both.
int32_t ctd_a11y_role(ctd_handle widget, char *out, int32_t cap) {
    if (!ctd_resolve(widget)) return CTD_ERR_STALE;
    NSString *role = @"group";
    switch (ctd_slot_kind(widget)) {
        case CTD_W_CONTAINER:    role = @"group";       break;
        case CTD_W_LABEL:        role = @"text";        break;
        case CTD_W_BUTTON:       role = @"button";      break;
        case CTD_W_TEXT_FIELD:   role = @"textbox";     break;
        case CTD_W_CHECK_BOX:    role = @"checkbox";    break;
        case CTD_W_IMAGE_VIEW:   role = @"image";       break;
        case CTD_W_SLIDER:       role = @"slider";      break;
        case CTD_W_PROGRESS_BAR: role = @"progressbar"; break;
        case CTD_W_SEPARATOR:    role = @"separator";   break;
        case CTD_W_TEXT_AREA:    role = @"textbox";     break;
        case CTD_W_COMBO_BOX:    role = @"combobox";    break;
        case CTD_W_SCROLL_VIEW:  role = @"scrollarea";  break;
        case CTD_W_RADIO_BUTTON: role = @"radio";       break;
        default:                 role = @"group";       break;
    }
    return ctd_copy_out(role, out, cap);
}

// No snapshot here, and `ctd_capability(CTD_CAP_SNAPSHOT)` says so rather than
// this being discovered at the call. Reading a widget back as pixels is real
// work on this platform and it has not been done; a stub that answered a blank
// image would be worse than a refusal, because a test asserting "something was
// drawn" would then fail for a reason that has nothing to do with drawing.
int32_t ctd_snapshot(ctd_handle widget, double *out_size, char *out, int32_t cap) {
    (void)widget; (void)out_size; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_widget_activate(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIControl class]]) return CTD_ERR_KIND;
    [(UIControl *)object sendActionsForControlEvents:UIControlEventTouchUpInside];
    return CTD_OK;
}

ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[UISlider class]]) {
        [(UISlider *)object setValue:(float)value];
    } else if ([object isKindOfClass:[UISwitch class]]) {
        [(UISwitch *)object setOn:index == 1];
    } else if (ctd_slot_kind(widget) == CTD_W_COMBO_BOX ||
               ctd_slot_kind(widget) == CTD_W_RADIO_BUTTON) {
        ctd_status wrote = ctd_set_int(widget,
            ctd_slot_kind(widget) == CTD_W_COMBO_BOX ? CTD_P_SELECTED : CTD_P_CHECKED,
            index);
        if (wrote != CTD_OK) return wrote;
    } else {
        return CTD_ERR_KIND;
    }
    ctd_emit_control(widget, object);
    return CTD_OK;
}

ctd_status ctd_widget_synth_text(ctd_handle widget, const char *utf8, int32_t len) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = ctd_string(utf8, len);
    if ([object isKindOfClass:[UITextField class]])      [(UITextField *)object setText:text];
    else if ([object isKindOfClass:[UITextView class]])  [(UITextView *)object setText:text];
    else return CTD_ERR_KIND;
    ctd_emit_control(widget, object);
    return CTD_OK;
}
