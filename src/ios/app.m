// Launching, the scene dance, and turning a control's action into an event.
//
// The one callback edge in the whole host is here: `g_sink` is a function
// pointer Beans registered at run time, and nothing in cortado's C half ever
// names a Beans symbol.

#import "internal.h"


NSMutableArray *g_targets;

@implementation CortadoTarget
- (void)fire:(id)sender {
    ctd_emit_control(self.handle, sender);
}
@end

void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token) {
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
void ctd_emit_control(ctd_handle target, id sender) {
    if (!g_sink) return;
    uint32_t kind = CTD_EV_ACTIVATE;
    int64_t index = 0;
    NSString *text = nil;

    int32_t made_as = ctd_slot_kind(target);
    if ([sender isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *bar = (UISegmentedControl *)sender;
        kind = CTD_EV_VALUE_CHANGED;
        index = (int64_t)[bar selectedSegmentIndex];
        if (index >= 0) text = [bar titleForSegmentAtIndex:(NSUInteger)index];
    } else if ([sender isKindOfClass:[UIStepper class]]) {
        kind = CTD_EV_VALUE_CHANGED;
        index = (int64_t)[(UIStepper *)sender value];
    } else if ([sender isKindOfClass:[UISlider class]]) {
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

ctd_handle g_shown;

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

// The loop, with a deadline.
//
// ctd_app_run never returns on a phone, and this is the call that lets a
// program wait for the platform anyway: for a frame, for an animation to
// finish, for an answer to a permission. Running the run loop in slices rather
// than once is what makes ctd_app_stop able to cut it short — the flag it sets
// is only read here, between slices.
int g_stop_requested;

ctd_status ctd_app_run_for(double seconds) {
    if (!g_started) return CTD_ERR_STATE;
    if (!(seconds >= 0.0)) return CTD_ERR_RANGE;
    g_stop_requested = 0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!g_stop_requested) {
        @autoreleasepool {
            NSDate *now = [NSDate date];
            if ([now compare:deadline] != NSOrderedAscending) break;
            NSDate *slice = [now dateByAddingTimeInterval:0.01];
            if ([slice compare:deadline] == NSOrderedDescending) slice = deadline;
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:slice];
        }
    }
    return CTD_OK;
}

// There is no such thing as stopping an iOS application. Apple's guidance is
// explicit that a program which exits on its own looks like a crash to the
// person holding the phone, so this ends a bounded run and nothing else — and
// a bounded run is a wait, not the application.
void ctd_app_stop(void) { g_stop_requested = 1; }

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
        // Metal, and it is real here rather than a refusal: a device
        // comes back in the Simulator, MSL compiles at run time, and a
        // command queue is made. A phone is the platform where drawing
        // on the GPU matters most.
        case CTD_CAP_GPU:           return 1;
        default:                    return 0;
    }
}
