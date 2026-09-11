// The macOS host: real AppKit controls behind cortado's flat C ABI.
//
// Every Objective-C detail in cortado stops in this file. What leaves it is
// integers, doubles and UTF-8 bytes, which is the whole reason one Beans
// binding can drive five platforms.
//
// Two things here are worth knowing before reading the rest.
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
// in this file has to think about it.

#import <Cocoa/Cocoa.h>
#include <string.h>
#include <float.h>
#include "cortado_host.h"
#include "cortado_rules.h"

enum { CTD_SLOTS = 8192 };

// ---------------------------------------------------------------- the table

static id       g_object[CTD_SLOTS];
static uint32_t g_generation[CTD_SLOTS];
static int32_t  g_kind[CTD_SLOTS];
static uint32_t g_used;                 // slot 0 is reserved for "no handle"

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

// Marks a view as one cortado built.
//
// AppKit installs private subviews of its own — an NSImageView carries an
// _NSImageViewSimpleImageView — and their names and number are not API. A tree
// query that counted them would answer about AppKit's internals rather than
// about the tree the program wrote, and would change under an OS update.
static NSString *const kCortadoTag = @"cortado";

static void ctd_tag(id object) {
    if ([object isKindOfClass:[NSView class]]) {
        [(NSView *)object setIdentifier:kCortadoTag];
    }
}

static BOOL ctd_is_ours(NSView *view) {
    return [[view identifier] isEqualToString:kCortadoTag];
}

// The subviews cortado put there, in order, and nothing else.
static NSArray *ctd_children(NSView *container) {
    NSMutableArray *ours = [NSMutableArray array];
    for (NSView *child in [container subviews]) {
        if (ctd_is_ours(child)) [ours addObject:child];
    }
    return ours;
}

static int32_t ctd_slot_kind(ctd_handle handle) {
    if (!ctd_resolve(handle)) return -1;
    return g_kind[(uint32_t)(handle & 0xffffffffu)];
}

// Copies a UTF-8 string out through the two-call shape. Answers the length the
// caller needs, writes at most `cap` bytes, and never relies on the caller
// having guessed right.
static int32_t ctd_copy_out(NSString *text, char *out, int32_t cap) {
    if (!text) text = @"";
    const char *bytes = [text UTF8String];
    if (!bytes) bytes = "";
    size_t length = strlen(bytes);
    if (out && cap > 0) {
        size_t room = (size_t)cap < length ? (size_t)cap : length;
        memcpy(out, bytes, room);
    }
    return (int32_t)length;
}

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

// ------------------------------------------------------- the flipped container

@interface CortadoView : NSView
@end

@implementation CortadoView
- (BOOL)isFlipped { return YES; }
@end

// ------------------------------------------------------------ action forwarding
//
// AppKit's target/action wants an object with a selector. One of these sits
// between a control and the sink, carrying the handle the event belongs to.
// The control holds its target weakly, so the table below keeps it alive.

@interface CortadoTarget : NSObject
@property (assign) ctd_handle handle;
@end

static void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token);

static void ctd_emit_control(ctd_handle target, id sender);

// One target object for every menu item cortado owns. The interface is here,
// beside the declaration, because `ctd_init` makes it and the menu section
// further down implements it.
@interface CortadoCommand : NSObject
- (void)chose:(id)sender;
@end

static CortadoCommand *g_commands;

@implementation CortadoTarget
- (void)fire:(id)sender {
    ctd_emit_control(self.handle, sender);
}
@end

static NSMutableArray *g_targets;   // keeps every CortadoTarget alive

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

// One control's action, as the event it actually is.
//
// AppKit sends every control's action down one selector, so the kind has to be
// decided here. The rule is the one a person would give: a control that
// carries a *value* reports that the value changed; a control that is a
// *command* reports that it was activated; a field that has been committed
// reports the commit. A framework that called all of them "activate" would
// make a slider and a button indistinguishable to a handler, and every
// application would re-derive this from the control's class.
static void ctd_emit_control(ctd_handle target, id sender) {
    if (!g_sink) return;
    uint32_t kind = CTD_EV_ACTIVATE;
    int64_t index = 0;
    NSString *text = nil;

    if ([sender isKindOfClass:[NSSlider class]]) {
        kind = CTD_EV_VALUE_CHANGED;
        index = (int64_t)[(NSSlider *)sender doubleValue];
    } else if ([sender isKindOfClass:[NSPopUpButton class]]) {
        kind = CTD_EV_VALUE_CHANGED;
        index = (int64_t)[(NSPopUpButton *)sender indexOfSelectedItem];
        text = [(NSPopUpButton *)sender titleOfSelectedItem];
    } else if ([sender isKindOfClass:[NSTextField class]]) {
        kind = CTD_EV_TEXT_COMMIT;
        text = [(NSTextField *)sender stringValue];
    } else if ([sender isKindOfClass:[NSButton class]]) {
        // A switch and a radio carry a state; a push button is a command. The
        // kind cortado created it as is the authority — AppKit uses one class
        // for all three and the cell's button type is not readable back.
        int32_t made_as = ctd_slot_kind(target);
        if (made_as == CTD_W_CHECK_BOX || made_as == CTD_W_RADIO_BUTTON) {
            kind = CTD_EV_VALUE_CHANGED;
            NSControlStateValue state = [(NSButton *)sender state];
            index = state == NSControlStateValueMixed ? 2
                  : state == NSControlStateValueOn    ? 1 : 0;
        }
    }

    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = kind;
    event.target = target;
    event.index = index;
    if (text) {
        // Valid only for the duration of the call, which is the contract in
        // the header: a binding that keeps the text copies it.
        const char *utf8 = [text UTF8String];
        event.text = utf8;
        event.text_len = utf8 ? (int32_t)strlen(utf8) : 0;
    }
    g_sink(g_sink_context, &event);
}

// ------------------------------------------------------------------ lifecycle

uint32_t ctd_abi_version(void) { return CTD_ABI_VERSION; }

ctd_status ctd_init(uint32_t want_abi) {
    if (want_abi != CTD_ABI_VERSION) return CTD_ERR_ABI;
    if (g_started) return CTD_OK;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    g_targets = [[NSMutableArray alloc] init];
    g_commands = [[CortadoCommand alloc] init];
    g_started = 1;
    return CTD_OK;
}

ctd_status ctd_app_set_role(int32_t role) {
    NSApplicationActivationPolicy policy;
    switch (role) {
        case CTD_ROLE_GUI:       policy = NSApplicationActivationPolicyRegular; break;
        case CTD_ROLE_ACCESSORY: policy = NSApplicationActivationPolicyAccessory; break;
        case CTD_ROLE_HEADLESS:  policy = NSApplicationActivationPolicyProhibited; break;
        default: return CTD_ERR_RANGE;
    }
    g_role = role;
    [NSApp setActivationPolicy:policy];
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

void ctd_app_run(void) {
    if (!g_started) return;
    [NSApp run];
}

void ctd_app_stop(void) {
    [NSApp stop:nil];
    // -stop: only takes effect when the loop next finishes an event, so a stop
    // requested from outside one would otherwise sit until the user moved the
    // mouse. Posting an empty event is what makes it immediate.
    NSEvent *nudge = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:0
                                           data1:0
                                           data2:0];
    [NSApp postEvent:nudge atStart:YES];
}

void ctd_post(int64_t token) {
    // dispatch_async rather than performSelectorOnMainThread: the latter needs
    // a run loop already spinning, and cortado wants a post issued before
    // Application.run() to survive until it does.
    dispatch_async(dispatch_get_main_queue(), ^{
        ctd_emit(CTD_EV_POST, 0, 0, token);
    });
}

int32_t ctd_capability(int32_t capability) {
    switch (capability) {
        case CTD_CAP_MENU_BAR:      return 1;
        case CTD_CAP_WINDOW_MENU:   return 0;   // macOS has one menu bar, not one per window
        case CTD_CAP_MULTI_SURFACE: return 1;
        case CTD_CAP_RESIZABLE:     return 1;
        case CTD_CAP_FILE_DIALOG:   return 1;
        case CTD_CAP_SNAPSHOT:      return 1;
        default:                    return 0;
    }
}

// ------------------------------------------------------------------- surfaces

ctd_handle ctd_surface_new(double width, double height) {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, width, height)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setReleasedWhenClosed:NO];
    // The default content view is not flipped, so every surface gets one that
    // is. This is the only place the flip has to be installed.
    CortadoView *content = [[CortadoView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    ctd_tag(content);
    [window setContentView:content];
    [content release];
    ctd_handle handle = ctd_track(window, -1);
    [window release];
    return handle;
}

ctd_status ctd_surface_set_title(ctd_handle surface, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    if (![window isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
    NSString *text = [[[NSString alloc] initWithBytes:utf8
                                               length:(NSUInteger)(len < 0 ? 0 : len)
                                             encoding:NSUTF8StringEncoding] autorelease];
    [window setTitle:text ? text : @""];
    return CTD_OK;
}

int32_t ctd_surface_title(ctd_handle surface, char *out, int32_t cap) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    return ctd_copy_out([window title], out, cap);
}

ctd_status ctd_surface_set_root(ctd_handle surface, ctd_handle root) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    NSView *view = (NSView *)ctd_resolve(root);
    if (!window || !view) return CTD_ERR_STALE;
    NSView *content = [window contentView];
    for (NSView *existing in ctd_children(content)) {
        [existing removeFromSuperview];
    }
    [view setFrame:[content bounds]];
    [content addSubview:view];
    return CTD_OK;
}

ctd_handle ctd_surface_root(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return 0;
    NSArray *children = ctd_children([window contentView]);
    if ([children count] == 0) return 0;
    NSView *first = [children objectAtIndex:0];
    // Find the handle that already names it rather than minting a second one:
    // two handles for one view would each carry their own lifetime.
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == first) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

ctd_status ctd_surface_content_size(ctd_handle surface, double *out_size) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    NSRect bounds = [[window contentView] bounds];
    if (out_size) {
        out_size[0] = bounds.size.width;
        out_size[1] = bounds.size.height;
    }
    return CTD_OK;
}

ctd_status ctd_surface_show(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    // Headless builds widgets and measures them but never puts one on screen,
    // so a test suite reads the same tree on a CI runner as on a desk.
    if (g_role == CTD_ROLE_HEADLESS) return CTD_OK;
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    return CTD_OK;
}

ctd_status ctd_surface_close(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    [window close];
    return CTD_OK;
}

int32_t ctd_surface_visible(ctd_handle surface) {
    NSWindow *window = (NSWindow *)ctd_resolve(surface);
    if (!window) return 0;
    return [window isVisible] ? 1 : 0;
}

// -------------------------------------------------------------------- widgets

ctd_handle ctd_widget_new(int32_t kind) {
    NSView *view = nil;
    switch (kind) {
        case CTD_W_CONTAINER:
            view = [[CortadoView alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_LABEL: {
            NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
            [label setBezeled:NO];
            [label setDrawsBackground:NO];
            [label setEditable:NO];
            [label setSelectable:NO];
            view = label;
            break;
        }
        case CTD_W_BUTTON: {
            NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
            [button setBezelStyle:NSBezelStyleRounded];
            [button setButtonType:NSButtonTypeMomentaryPushIn];
            [button setTitle:@""];
            view = button;
            break;
        }
        case CTD_W_TEXT_FIELD:
            view = [[NSTextField alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_CHECK_BOX: {
            NSButton *box = [[NSButton alloc] initWithFrame:NSZeroRect];
            [box setButtonType:NSButtonTypeSwitch];
            [box setAllowsMixedState:YES];
            [box setTitle:@""];
            view = box;
            break;
        }
        case CTD_W_IMAGE_VIEW:
            view = [[NSImageView alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_SLIDER: {
            NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
            [slider setMinValue:0.0];
            [slider setMaxValue:1.0];
            [slider setDoubleValue:0.0];
            // Continuous by default: a slider that only reports on mouse-up
            // cannot drive a live preview, which is most of what sliders are
            // for. A program that wants the other behaviour ignores the events
            // until it stops getting them.
            [slider setContinuous:YES];
            view = slider;
            break;
        }
        case CTD_W_PROGRESS_BAR: {
            NSProgressIndicator *bar =
                [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
            [bar setStyle:NSProgressIndicatorStyleBar];
            [bar setIndeterminate:NO];
            [bar setMinValue:0.0];
            [bar setMaxValue:1.0];
            [bar setDoubleValue:0.0];
            view = bar;
            break;
        }
        case CTD_W_SEPARATOR: {
            NSBox *rule = [[NSBox alloc] initWithFrame:NSZeroRect];
            [rule setBoxType:NSBoxSeparator];
            view = rule;
            break;
        }
        case CTD_W_TEXT_AREA: {
            // A text view has to live inside a scroll view to scroll, and a
            // multi-line field that cannot scroll is a field with a hidden
            // bottom. The scroll view is what cortado tracks: it is the thing
            // with a frame, and the text view inside it is an implementation
            // detail the tree never shows.
            NSScrollView *scroller =
                [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
            NSTextView *text =
                [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
            [text setMinSize:NSMakeSize(0, 0)];
            [text setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
            [text setVerticallyResizable:YES];
            [text setHorizontallyResizable:NO];
            [text setAutoresizingMask:NSViewWidthSizable];
            [[text textContainer] setWidthTracksTextView:YES];
            [scroller setDocumentView:text];
            [scroller setHasVerticalScroller:YES];
            [scroller setBorderType:NSBezelBorder];
            [text release];
            view = scroller;
            break;
        }
        case CTD_W_COMBO_BOX: {
            NSPopUpButton *menu =
                [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
            view = menu;
            break;
        }
        case CTD_W_SCROLL_VIEW: {
            NSScrollView *scroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
            CortadoView *content = [[CortadoView alloc] initWithFrame:NSZeroRect];
            [scroller setDocumentView:content];
            [scroller setHasVerticalScroller:YES];
            [scroller setDrawsBackground:NO];
            ctd_tag(content);
            [content release];
            view = scroller;
            break;
        }
        case CTD_W_RADIO_BUTTON: {
            NSButton *radio = [[NSButton alloc] initWithFrame:NSZeroRect];
            [radio setButtonType:NSButtonTypeRadio];
            [radio setTitle:@""];
            view = radio;
            break;
        }
        default:
            return 0;
    }
    ctd_tag(view);
    ctd_handle handle = ctd_track(view, kind);
    // Controls report their own actions from birth; a widget with no handler
    // registered simply reaches a sink that does nothing with it.
    if ([view isKindOfClass:[NSControl class]]) {
        CortadoTarget *forwarder = [[CortadoTarget alloc] init];
        [forwarder setHandle:handle];
        [(NSControl *)view setTarget:forwarder];
        [(NSControl *)view setAction:@selector(fire:)];
        [g_targets addObject:forwarder];
        [forwarder release];
    }
    [view release];
    return handle;
}

int32_t ctd_widget_kind(ctd_handle widget) { return ctd_slot_kind(widget); }

int32_t ctd_widget_alive(ctd_handle widget) { return ctd_resolve(widget) ? 1 : 0; }

ctd_status ctd_widget_release(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    if ([object isKindOfClass:[NSView class]]) [(NSView *)object removeFromSuperview];
    [object release];
    g_object[slot] = nil;
    g_kind[slot] = -1;
    // The bump is what makes every copy of this handle answer CTD_ERR_STALE
    // from here on, rather than one of them reaching a recycled widget.
    g_generation[slot]++;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    ctd_give_back(slot);
    return CTD_OK;
}

// ----------------------------------------------------------------------- tree

// A surface addresses its content view; everything else addresses itself.
// Where a widget's children actually live.
//
// Two of the cases are indirections the tree above must not know about: a
// window's children sit in its content view, and a scroll view's in its
// document view. A caller that had to know which control wraps what would be a
// caller writing platform code in Beans.
//
// Every view answers something here, including a leaf. Asking a label how many
// children it has is a question with a real answer — none — and refusing it
// would make every tree walk special-case every kind. Refusing to *add* a
// child to one is a different question, and `ctd_can_hold` is where that lives.
static NSView *ctd_container_of(id object) {
    if ([object isKindOfClass:[NSWindow class]]) return [(NSWindow *)object contentView];
    if ([object isKindOfClass:[NSScrollView class]]) {
        id inner = [(NSScrollView *)object documentView];
        if ([inner isKindOfClass:[NSView class]]) return (NSView *)inner;
        return (NSView *)object;
    }
    if ([object isKindOfClass:[NSView class]]) return (NSView *)object;
    return nil;
}

// Whether a widget may be given children.
//
// A text area is a scroll view whose document view holds text, not widgets.
// Adding a button to one would put it inside a paragraph — AppKit allows it
// and nothing good comes of it — so the refusal is here rather than in a
// comment.
static BOOL ctd_can_hold(NSView *content) {
    if (!content) return NO;
    return ![content isKindOfClass:[NSTextView class]];
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    id owner = ctd_resolve(parent);
    NSView *view = (NSView *)ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    NSView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    NSArray *existing = ctd_children(container);
    if (index < 0 || index >= (int32_t)[existing count]) {
        [container addSubview:view];
    } else {
        [container addSubview:view
                   positioned:NSWindowBelow
                   relativeTo:[existing objectAtIndex:(NSUInteger)index]];
    }
    return CTD_OK;
}

ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child) {
    id owner = ctd_resolve(parent);
    NSView *view = (NSView *)ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    NSView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    if ([view superview] != container) return CTD_ERR_RANGE;
    [view removeFromSuperview];
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    NSView *container = ctd_container_of(owner);
    if (!ctd_can_hold(container)) return CTD_ERR_KIND;
    NSArray *children = ctd_children(container);
    int32_t count = (int32_t)[children count];
    if (from < 0 || from >= count || to < 0 || to >= count) return CTD_ERR_RANGE;
    if (from == to) return CTD_OK;
    // Held across the move because -removeFromSuperview drops the superview's
    // reference, and on a view the caller no longer names that is the last one.
    NSView *moving = [[children objectAtIndex:(NSUInteger)from] retain];
    NSResponder *responder = [[container window] firstResponder];
    BOOL had_focus = [responder isKindOfClass:[NSView class]] &&
                     [(NSView *)responder isDescendantOf:moving];
    [moving removeFromSuperview];
    NSArray *rest = ctd_children(container);
    if (to >= (int32_t)[rest count]) {
        [container addSubview:moving];
    } else {
        [container addSubview:moving
                   positioned:NSWindowBelow
                   relativeTo:[rest objectAtIndex:(NSUInteger)to]];
    }
    // Reordering a list should not take the caret out of the field being
    // edited, which is what AppKit does on its own.
    if (had_focus) [[container window] makeFirstResponder:responder];
    [moving release];
    return CTD_OK;
}

ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out) {
    id owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    NSView *container = ctd_container_of(owner);
    // A control that cannot hold children has none, which is an answer and not
    // a refusal — a tree walk asks this of every node and would otherwise have
    // to know which kinds to skip.
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
    NSView *container = ctd_container_of(owner);
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
    NSView *view = (NSView *)ctd_resolve(child);
    if (!view) return 0;
    NSView *parent = [view superview];
    if (!parent) return 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == parent) return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

// ------------------------------------------------------------------- geometry

ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height) {
    NSView *view = (NSView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    if (![view isKindOfClass:[NSView class]]) return CTD_ERR_KIND;
    [view setFrame:NSMakeRect(x, y, width, height)];
    return CTD_OK;
}

ctd_status ctd_view_frame(ctd_handle widget, double *out_frame) {
    NSView *view = (NSView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    NSRect frame = [view frame];
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
    NSView *view = (NSView *)ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    NSSize wanted;
    if ([view isKindOfClass:[NSControl class]]) {
        wanted = [(NSControl *)view fittingSize];
    } else {
        wanted = [view intrinsicContentSize];
        if (wanted.width  == NSViewNoIntrinsicMetric) wanted.width  = 0;
        if (wanted.height == NSViewNoIntrinsicMetric) wanted.height = 0;
    }
    // A negative available size means unbounded, so only a real bound clamps.
    if (avail_width  >= 0 && wanted.width  > avail_width)  wanted.width  = avail_width;
    if (avail_height >= 0 && wanted.height > avail_height) wanted.height = avail_height;
    if (out_size) {
        out_size[0] = wanted.width;
        out_size[1] = wanted.height;
    }
    return CTD_OK;
}

// ----------------------------------------------------------------- properties

// UTF-8 bytes with an explicit length, as an NSString. Never NUL-terminated:
// a string with an embedded NUL crosses this boundary whole.
static NSString *ctd_string(const char *utf8, int32_t len) {
    NSString *text = [[[NSString alloc] initWithBytes:utf8
                                               length:(NSUInteger)(len < 0 ? 0 : len)
                                             encoding:NSUTF8StringEncoding] autorelease];
    return text ? text : @"";
}

// The object a widget's text actually lives on. A text area is tracked as its
// scroll view, because that is the thing with a frame — the text view inside
// is an implementation detail, and every text call has to reach through it.
static NSTextView *ctd_text_view(id object) {
    if (![object isKindOfClass:[NSScrollView class]]) return nil;
    id inner = [(NSScrollView *)object documentView];
    if ([inner isKindOfClass:[NSTextView class]]) return (NSTextView *)inner;
    return nil;
}

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = ctd_string(utf8, len);
    NSTextView *inner = ctd_text_view(object);
    if (inner)                                           [inner setString:text];
    else if ([object isKindOfClass:[NSButton class]])    [(NSButton *)object setTitle:text];
    else if ([object isKindOfClass:[NSTextField class]]) [(NSTextField *)object setStringValue:text];
    else return CTD_ERR_KIND;
    return CTD_OK;
}

int32_t ctd_get_text(ctd_handle widget, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    // Class checks are explicit rather than -respondsToSelector:, because
    // NSImageView inherits -stringValue from NSControl and answers its
    // objectValue's description, which carries a heap address in it.
    NSTextView *inner = ctd_text_view(object);
    if (inner)
        return ctd_copy_out([inner string], out, cap);
    if ([object isKindOfClass:[NSButton class]])
        return ctd_copy_out([(NSButton *)object title], out, cap);
    if ([object isKindOfClass:[NSTextField class]])
        return ctd_copy_out([(NSTextField *)object stringValue], out, cap);
    if ([object isKindOfClass:[NSPopUpButton class]])
        return ctd_copy_out([(NSPopUpButton *)object titleOfSelectedItem], out, cap);
    return ctd_copy_out(@"", out, cap);
}

ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_ENABLED:
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            [(NSControl *)object setEnabled:value ? YES : NO];
            return CTD_OK;
        case CTD_P_HIDDEN:
            [(NSView *)object setHidden:value ? YES : NO];
            return CTD_OK;
        case CTD_P_CHECKED: {
            if (![object isKindOfClass:[NSButton class]]) return CTD_ERR_KIND;
            NSControlStateValue state = value == 2 ? NSControlStateValueMixed
                                      : value == 1 ? NSControlStateValueOn
                                                   : NSControlStateValueOff;
            [(NSButton *)object setState:state];
            return CTD_OK;
        }
        case CTD_P_EDITABLE:
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            [(NSTextField *)object setEditable:value ? YES : NO];
            return CTD_OK;
        case CTD_P_ALIGNMENT: {
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            NSTextAlignment alignment = value == 1 ? NSTextAlignmentCenter
                                      : value == 2 ? NSTextAlignmentRight
                                                   : NSTextAlignmentLeft;
            [(NSTextField *)object setAlignment:alignment];
            return CTD_OK;
        }
        case CTD_P_SELECTED: {
            if (![object isKindOfClass:[NSPopUpButton class]]) return CTD_ERR_KIND;
            NSPopUpButton *menu = (NSPopUpButton *)object;
            if (value < 0) { [menu selectItem:nil]; return CTD_OK; }
            if (value >= (int64_t)[menu numberOfItems]) return CTD_ERR_RANGE;
            [menu selectItemAtIndex:(NSInteger)value];
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE: {
            if (![object isKindOfClass:[NSProgressIndicator class]]) return CTD_ERR_KIND;
            NSProgressIndicator *bar = (NSProgressIndicator *)object;
            [bar setIndeterminate:value ? YES : NO];
            // An indeterminate bar that is not animating is a bar that looks
            // broken, so the two are one property rather than two.
            if (value) [bar startAnimation:nil]; else [bar stopAnimation:nil];
            return CTD_OK;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    int64_t value = 0;
    switch (key) {
        case CTD_P_ENABLED:
            // A kind with no enabled state answers "wrong widget" rather than
            // 0, because 0 reads as "disabled" — a wrong answer rather than a
            // missing one. The caller gets to tell the difference.
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = [(NSControl *)object isEnabled] ? 1 : 0;
            break;
        case CTD_P_HIDDEN:
            value = [(NSView *)object isHidden] ? 1 : 0;
            break;
        case CTD_P_CHECKED: {
            if (![object isKindOfClass:[NSButton class]]) return CTD_ERR_KIND;
            NSControlStateValue state = [(NSButton *)object state];
            value = state == NSControlStateValueMixed ? 2
                  : state == NSControlStateValueOn    ? 1 : 0;
            break;
        }
        case CTD_P_EDITABLE:
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            value = [(NSTextField *)object isEditable] ? 1 : 0;
            break;
        case CTD_P_SELECTED:
            if (![object isKindOfClass:[NSPopUpButton class]]) return CTD_ERR_KIND;
            value = (int64_t)[(NSPopUpButton *)object indexOfSelectedItem];
            break;
        case CTD_P_INDETERMINATE:
            if (![object isKindOfClass:[NSProgressIndicator class]]) return CTD_ERR_KIND;
            value = [(NSProgressIndicator *)object isIndeterminate] ? 1 : 0;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

/* A slider and a progress bar both carry a range and a position, and AppKit
 * puts them on unrelated classes — NSSlider is an NSControl, NSProgressIndicator
 * is not. The property bag hides that: a caller sets CTD_P_MIN on either and
 * the host knows which message to send. */
ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_FONT_SIZE:
            if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
            [(NSControl *)object setFont:[NSFont systemFontOfSize:value]];
            return CTD_OK;
        case CTD_P_MIN:
            if ([object isKindOfClass:[NSSlider class]]) {
                [(NSSlider *)object setMinValue:value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[NSProgressIndicator class]]) {
                [(NSProgressIndicator *)object setMinValue:value];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if ([object isKindOfClass:[NSSlider class]]) {
                [(NSSlider *)object setMaxValue:value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[NSProgressIndicator class]]) {
                [(NSProgressIndicator *)object setMaxValue:value];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[NSSlider class]]) {
                [(NSSlider *)object setDoubleValue:value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[NSProgressIndicator class]]) {
                [(NSProgressIndicator *)object setDoubleValue:value];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_STEP: {
            if (![object isKindOfClass:[NSSlider class]]) return CTD_ERR_KIND;
            NSSlider *slider = (NSSlider *)object;
            if (value <= 0.0) {
                [slider setAllowsTickMarkValuesOnly:NO];
                [slider setNumberOfTickMarks:0];
                return CTD_OK;
            }
            double span = [slider maxValue] - [slider minValue];
            if (span <= 0.0) return CTD_ERR_RANGE;
            // AppKit has no increment: a stepped slider is one with tick marks
            // it must land on. The count is the number of positions, which is
            // one more than the number of steps.
            [slider setNumberOfTickMarks:(NSInteger)(span / value) + 1];
            [slider setAllowsTickMarkValuesOnly:YES];
            return CTD_OK;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    double value = 0.0;
    switch (key) {
        case CTD_P_FONT_SIZE:
            if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
            value = (double)[[(NSControl *)object font] pointSize];
            break;
        case CTD_P_MIN:
            if ([object isKindOfClass:[NSSlider class]])
                value = [(NSSlider *)object minValue];
            else if ([object isKindOfClass:[NSProgressIndicator class]])
                value = [(NSProgressIndicator *)object minValue];
            else return CTD_ERR_KIND;
            break;
        case CTD_P_MAX:
            if ([object isKindOfClass:[NSSlider class]])
                value = [(NSSlider *)object maxValue];
            else if ([object isKindOfClass:[NSProgressIndicator class]])
                value = [(NSProgressIndicator *)object maxValue];
            else return CTD_ERR_KIND;
            break;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[NSSlider class]])
                value = [(NSSlider *)object doubleValue];
            else if ([object isKindOfClass:[NSProgressIndicator class]])
                value = [(NSProgressIndicator *)object doubleValue];
            else return CTD_ERR_KIND;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// -------------------------------------------------------------------- dialogs

ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token) {
    NSWindow *window = nil;
    if (parent) {
        id object = ctd_resolve(parent);
        if (!object) return CTD_ERR_STALE;
        if (![object isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
        window = (NSWindow *)object;
        // A sheet needs a window that is actually on screen. Attaching one to
        // a window that was never shown runs no completion handler at all, so
        // the caller waits on a token that will never arrive — a hang, and the
        // worst possible failure for an asynchronous API. A window that cannot
        // host a sheet is treated as no window, which answers immediately.
        if (![window isVisible]) window = nil;
    }
    NSString *heading = ctd_string(title, title_len);
    NSString *detail = ctd_string(body, body_len);

    // The answer is delivered as an event and never returned, because every
    // platform's dialog is asynchronous and a blocking form would have to spin
    // an inner event loop — re-entering the render this call came out of.
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

    if (kind == CTD_DLG_MESSAGE || kind == CTD_DLG_CONFIRM) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:heading];
        [alert setInformativeText:detail];
        [alert addButtonWithTitle:@"OK"];
        if (kind == CTD_DLG_CONFIRM) [alert addButtonWithTitle:@"Cancel"];
        if (window) {
            [alert beginSheetModalForWindow:window
                          completionHandler:^(NSModalResponse response) {
                answer(response == NSAlertFirstButtonReturn ? 0 : 1, nil);
            }];
        } else {
            // No surface to attach to — which is the headless case, where
            // running a modal alert would hang. The answer is the default
            // button, reported the same way, so a caller's code path is the
            // same with and without a display.
            answer(0, nil);
        }
        [alert release];
        return CTD_OK;
    }

    if (kind == CTD_DLG_OPEN || kind == CTD_DLG_SAVE) {
        if (!window) {
            // Same reason: a file panel with nothing to attach to would run
            // modally and never return under a test. Report a cancel.
            answer(1, nil);
            return CTD_OK;
        }
        NSSavePanel *panel = kind == CTD_DLG_OPEN
            ? (NSSavePanel *)[NSOpenPanel openPanel]
            : [NSSavePanel savePanel];
        [panel setTitle:heading];
        [panel setMessage:detail];
        [panel beginSheetModalForWindow:window
                      completionHandler:^(NSModalResponse response) {
            if (response != NSModalResponseOK) { answer(1, nil); return; }
            answer(0, [[panel URL] path]);
        }];
        return CTD_OK;
    }
    return CTD_ERR_RANGE;
}

// ----------------------------------------------------------------- appearance

int32_t ctd_appearance(void) {
    NSAppearance *current = [NSApp effectiveAppearance];
    NSAppearanceName best =
        [current bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,
                                                     NSAppearanceNameDarkAqua]];
    return [best isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
}

ctd_status ctd_surface_scale(ctd_handle surface, double *out) {
    double scale = [[NSScreen mainScreen] backingScaleFactor];
    if (surface) {
        id object = ctd_resolve(surface);
        if (!object) return CTD_ERR_STALE;
        if (![object isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
        scale = [(NSWindow *)object backingScaleFactor];
        // A window that has not been shown has no screen yet, and AppKit
        // answers 0 for one. The main display's scale is the honest guess and
        // the one the window will get when it appears.
        if (scale <= 0.0) scale = [[NSScreen mainScreen] backingScaleFactor];
    }
    if (scale <= 0.0) scale = 1.0;
    if (out) *out = scale;
    return CTD_OK;
}

// ---------------------------------------------------------------------- fonts

static NSFont *ctd_font_for(int32_t role) {
    switch (role) {
        case CTD_FONT_HEADING:
            return [NSFont systemFontOfSize:[NSFont systemFontSize] + 4.0
                                     weight:NSFontWeightSemibold];
        case CTD_FONT_CAPTION:
            return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        case CTD_FONT_MONO:
            return [NSFont monospacedSystemFontOfSize:[NSFont systemFontSize]
                                               weight:NSFontWeightRegular];
        case CTD_FONT_BODY:
            return [NSFont systemFontOfSize:[NSFont systemFontSize]];
        default:
            return nil;
    }
}

int32_t ctd_font_family(int32_t role, char *out, int32_t cap) {
    NSFont *font = ctd_font_for(role);
    if (!font) return CTD_ERR_RANGE;
    return ctd_copy_out([font familyName], out, cap);
}

ctd_status ctd_font_size(int32_t role, double *out) {
    NSFont *font = ctd_font_for(role);
    if (!font) return CTD_ERR_RANGE;
    if (out) *out = (double)[font pointSize];
    return CTD_OK;
}

// ---------------------------------------------------------------------- menus

// One menu item's identity, carried on the NSMenuItem itself.
//
// AppKit gives a menu item one `tag`, an NSInteger, and that is exactly what is
// needed: the application's own token, handed back on CTD_EV_COMMAND. Nothing
// else about the item has to be remembered.

@implementation CortadoCommand
- (void)chose:(id)sender {
    if (![sender isKindOfClass:[NSMenuItem class]]) return;
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = CTD_EV_COMMAND;
    event.token = (int64_t)[(NSMenuItem *)sender tag];
    if (g_sink) g_sink(g_sink_context, &event);
}
@end

// A portable shortcut description — "mod+shift+s" — as the key and the
// modifier mask AppKit wants.
//
// `mod` is Command here and Control elsewhere, which is the whole reason the
// description is portable rather than a literal key. An unrecognised word is
// ignored rather than refused: a shortcut that did not attach is a menu item
// that still works, and refusing the whole menu over one would be worse.
static NSString *ctd_shortcut(NSString *spec, NSEventModifierFlags *mask) {
    *mask = 0;
    if ([spec length] == 0) return @"";
    NSArray *parts = [[spec lowercaseString] componentsSeparatedByString:@"+"];
    NSString *key = @"";
    for (NSString *part in parts) {
        if ([part isEqualToString:@"mod"] || [part isEqualToString:@"cmd"]) {
            *mask |= NSEventModifierFlagCommand;
        } else if ([part isEqualToString:@"shift"]) {
            *mask |= NSEventModifierFlagShift;
        } else if ([part isEqualToString:@"alt"] || [part isEqualToString:@"opt"]) {
            *mask |= NSEventModifierFlagOption;
        } else if ([part isEqualToString:@"ctrl"] || [part isEqualToString:@"control"]) {
            *mask |= NSEventModifierFlagControl;
        } else {
            key = part;
        }
    }
    return key;
}

// The shortcut a menu item ended up with, in the portable spelling.
static NSString *ctd_shortcut_text(NSMenuItem *item) {
    NSString *key = [item keyEquivalent];
    if ([key length] == 0) return @"";
    NSMutableArray *parts = [NSMutableArray array];
    NSEventModifierFlags mask = [item keyEquivalentModifierMask];
    if (mask & NSEventModifierFlagCommand) [parts addObject:@"mod"];
    if (mask & NSEventModifierFlagControl) [parts addObject:@"ctrl"];
    if (mask & NSEventModifierFlagOption)  [parts addObject:@"alt"];
    if (mask & NSEventModifierFlagShift)   [parts addObject:@"shift"];
    [parts addObject:[key lowercaseString]];
    return [parts componentsJoinedByString:@"+"];
}

// What the platform calls a role, and what key it gives it.
//
// The titles are Apple's own words — "Quit Coffee", not "Exit" — because a
// menu that said the wrong word would be the one thing a user notices
// immediately. The selector matters more: Cut, Copy, Paste, Undo and Select
// All go to `nil`, so AppKit walks the responder chain and the focused text
// field handles them. Wiring them to a handler of ours would break editing in
// every system control in the window.
static SEL ctd_role_selector(int32_t role) {
    switch (role) {
        case CTD_CMD_HIDE:       return @selector(hide:);
        case CTD_CMD_QUIT:       return @selector(terminate:);
        case CTD_CMD_UNDO:       return @selector(undo:);
        case CTD_CMD_REDO:       return @selector(redo:);
        case CTD_CMD_CUT:        return @selector(cut:);
        case CTD_CMD_COPY:       return @selector(copy:);
        case CTD_CMD_PASTE:      return @selector(paste:);
        case CTD_CMD_SELECT_ALL: return @selector(selectAll:);
        case CTD_CMD_CLOSE:      return @selector(performClose:);
        case CTD_CMD_MINIMIZE:   return @selector(performMiniaturize:);
        case CTD_CMD_FULLSCREEN: return @selector(toggleFullScreen:);
        default:                 return NULL;
    }
}

static NSString *ctd_role_title(int32_t role, NSString *fallback) {
    switch (role) {
        case CTD_CMD_ABOUT:       return @"About";
        case CTD_CMD_PREFERENCES: return @"Settings…";
        case CTD_CMD_QUIT:        return @"Quit";
        case CTD_CMD_HIDE:        return @"Hide";
        case CTD_CMD_UNDO:        return @"Undo";
        case CTD_CMD_REDO:        return @"Redo";
        case CTD_CMD_CUT:         return @"Cut";
        case CTD_CMD_COPY:        return @"Copy";
        case CTD_CMD_PASTE:       return @"Paste";
        case CTD_CMD_SELECT_ALL:  return @"Select All";
        case CTD_CMD_CLOSE:       return @"Close";
        case CTD_CMD_MINIMIZE:    return @"Minimize";
        case CTD_CMD_FULLSCREEN:  return @"Enter Full Screen";
        default:                  return fallback;
    }
}

static NSString *ctd_role_key(int32_t role, NSString *fallback) {
    switch (role) {
        case CTD_CMD_PREFERENCES: return @"mod+,";
        case CTD_CMD_QUIT:        return @"mod+q";
        case CTD_CMD_HIDE:        return @"mod+h";
        case CTD_CMD_UNDO:        return @"mod+z";
        case CTD_CMD_REDO:        return @"mod+shift+z";
        case CTD_CMD_CUT:         return @"mod+x";
        case CTD_CMD_COPY:        return @"mod+c";
        case CTD_CMD_PASTE:       return @"mod+v";
        case CTD_CMD_SELECT_ALL:  return @"mod+a";
        case CTD_CMD_CLOSE:       return @"mod+w";
        case CTD_CMD_MINIMIZE:    return @"mod+m";
        case CTD_CMD_FULLSCREEN:  return @"mod+ctrl+f";
        default:                  return fallback;
    }
}

static NSMenu *ctd_menu_of(ctd_handle handle) {
    id object = ctd_resolve(handle);
    if ([object isKindOfClass:[NSMenu class]]) return (NSMenu *)object;
    return nil;
}

ctd_handle ctd_menu_new(const char *title, int32_t len) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:ctd_string(title, len)];
    // A menu enables its own items by asking their targets; cortado's items
    // are enabled explicitly, so automatic validation is off and an item stays
    // as the application set it.
    [menu setAutoenablesItems:NO];
    ctd_handle handle = ctd_track(menu, CTD_W_CONTAINER);
    [menu release];
    return handle;
}

ctd_status ctd_menu_add_item(ctd_handle handle, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token) {
    if (ctd_has_nul(title, title_len) || ctd_has_nul(key, key_len))
        return CTD_ERR_RANGE;
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (role < 0 || role > CTD_CMD_FULLSCREEN) return CTD_ERR_RANGE;

    NSString *shown = ctd_role_title(role, ctd_string(title, title_len));
    NSString *spec = ctd_role_key(role, ctd_string(key, key_len));
    NSEventModifierFlags mask = 0;
    NSString *equivalent = ctd_shortcut(spec, &mask);

    SEL action = ctd_role_selector(role);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:shown
                                                 action:action ? action : @selector(chose:)
                                          keyEquivalent:equivalent];
    [item setKeyEquivalentModifierMask:mask];
    [item setTag:(NSInteger)token];
    // A role with a platform selector goes to nil, so AppKit's responder chain
    // finds whoever can do it — the focused text field, the window, NSApp.
    // Anything else is the application's own command.
    [item setTarget:action ? nil : g_commands];
    [item setEnabled:YES];
    [menu addItem:item];
    [item release];
    return CTD_OK;
}

ctd_status ctd_menu_add_separator(ctd_handle handle) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    [menu addItem:[NSMenuItem separatorItem]];
    return CTD_OK;
}

ctd_status ctd_menu_add_submenu(ctd_handle handle, ctd_handle child) {
    NSMenu *menu = ctd_menu_of(handle);
    NSMenu *inner = ctd_menu_of(child);
    if (!menu || !inner) return CTD_ERR_STALE;
    NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:[inner title]
                                                   action:NULL
                                            keyEquivalent:@""];
    [holder setSubmenu:inner];
    [menu addItem:holder];
    [holder release];
    return CTD_OK;
}

ctd_status ctd_menu_item_count(ctd_handle handle, int32_t *out) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = (int32_t)[menu numberOfItems];
    return CTD_OK;
}

int32_t ctd_menu_item_title(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= (int32_t)[menu numberOfItems]) return CTD_ERR_RANGE;
    NSMenuItem *item = [menu itemAtIndex:index];
    if ([item isSeparatorItem]) return ctd_copy_out(@"-", out, cap);
    return ctd_copy_out([item title], out, cap);
}

int32_t ctd_menu_item_key(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= (int32_t)[menu numberOfItems]) return CTD_ERR_RANGE;
    return ctd_copy_out(ctd_shortcut_text([menu itemAtIndex:index]), out, cap);
}

ctd_status ctd_menu_set_bar(ctd_handle handle) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    [NSApp setMainMenu:menu];
    return CTD_OK;
}

// Finds an item by token anywhere under `menu`, submenus included. A token is
// the application's own number and it names one command; where that command
// was placed is not something the application should have to remember.
static NSMenuItem *ctd_find_command(NSMenu *menu, int64_t token) {
    for (NSMenuItem *item in [menu itemArray]) {
        if (!([item isSeparatorItem]) && (int64_t)[item tag] == token) return item;
        NSMenu *inner = [item submenu];
        if (inner) {
            NSMenuItem *found = ctd_find_command(inner, token);
            if (found) return found;
        }
    }
    return nil;
}

ctd_status ctd_menu_set_enabled(ctd_handle handle, int64_t token, int32_t on) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    NSMenuItem *item = ctd_find_command(menu, token);
    if (!item) return CTD_ERR_RANGE;
    [item setEnabled:on ? YES : NO];
    return CTD_OK;
}

ctd_status ctd_menu_invoke(ctd_handle handle, int64_t token) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    NSMenuItem *item = ctd_find_command(menu, token);
    if (!item) return CTD_ERR_RANGE;
    if (![item isEnabled]) return CTD_ERR_PLATFORM;
    // Through the item's own target and action, so a role's command reaches
    // the responder chain exactly as choosing it would.
    if ([item target] == g_commands) {
        [g_commands chose:item];
    } else if ([item action]) {
        [NSApp sendAction:[item action] to:[item target] from:item];
    }
    return CTD_OK;
}

// ------------------------------------------------------------------ item lists

// The control that holds the items. A combo box is its own list; a wrapper —
// a text area's scroll view, say — is not, and answers nil so the caller gets
// CTD_ERR_KIND rather than a silent no-op.
static NSPopUpButton *ctd_item_list(id object) {
    if ([object isKindOfClass:[NSPopUpButton class]]) return (NSPopUpButton *)object;
    return nil;
}

ctd_status ctd_items_clear(ctd_handle widget) {
    NSPopUpButton *menu = ctd_item_list(ctd_resolve(widget));
    if (!ctd_resolve(widget)) return CTD_ERR_STALE;
    if (!menu) return CTD_ERR_KIND;
    [menu removeAllItems];
    return CTD_OK;
}

ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    if (len < 0) return CTD_ERR_RANGE;
    NSString *text = ctd_string(utf8, len);
    // NSPopUpButton drops a duplicate title, which would silently renumber
    // every later index and make a selection point at the wrong row. Adding
    // the item directly keeps the list exactly as the caller wrote it.
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:text
                                                 action:NULL
                                          keyEquivalent:@""];
    [[menu menu] addItem:item];
    [item release];
    return CTD_OK;
}

ctd_status ctd_items_count(ctd_handle widget, int32_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    if (out) *out = (int32_t)[menu numberOfItems];
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSPopUpButton *menu = ctd_item_list(object);
    if (!menu) return CTD_ERR_KIND;
    if (index < 0 || index >= (int32_t)[menu numberOfItems]) return CTD_ERR_RANGE;
    return ctd_copy_out([[menu itemAtIndex:index] title], out, cap);
}

// -------------------------------------------------------------- introspection

int32_t ctd_native_class(ctd_handle widget, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    return ctd_copy_out(NSStringFromClass([object class]), out, cap);
}

int32_t ctd_a11y_role(ctd_handle widget, char *out, int32_t cap) {
    int32_t kind = ctd_slot_kind(widget);
    if (kind < 0 && !ctd_resolve(widget)) return CTD_ERR_STALE;
    NSString *role;
    switch (kind) {
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
        default:               role = @"window";   break;
    }
    return ctd_copy_out(role, out, cap);
}

ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[NSSlider class]]) {
        [(NSSlider *)object setDoubleValue:value];
    } else if ([object isKindOfClass:[NSPopUpButton class]]) {
        NSPopUpButton *menu = (NSPopUpButton *)object;
        if (index < 0 || index >= (int64_t)[menu numberOfItems]) return CTD_ERR_RANGE;
        [menu selectItemAtIndex:(NSInteger)index];
    } else if ([object isKindOfClass:[NSButton class]]) {
        NSControlStateValue state = index == 2 ? NSControlStateValueMixed
                                  : index == 1 ? NSControlStateValueOn
                                               : NSControlStateValueOff;
        [(NSButton *)object setState:state];
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
    NSTextView *inner = ctd_text_view(object);
    if (inner)                                           [inner setString:text];
    else if ([object isKindOfClass:[NSTextField class]]) [(NSTextField *)object setStringValue:text];
    else return CTD_ERR_KIND;
    ctd_emit_control(widget, object);
    return CTD_OK;
}

// Reads a view back as pixels.
//
// `bitmapImageRepForCachingDisplayInRect:` and `cacheDisplayInRect:` draw into
// a bitmap rather than onto the screen, which is what makes this work in a
// headless run: the window is never ordered front and the controls still
// paint. That is the point of the call — it is what a program that had to
// answer "did anything actually appear" needs, and nothing else in this header
// can answer it.
//
// The bitmap is built explicitly rather than taken from the view, because the
// view's own caching rep follows the display: 8 bits a channel, four channels,
// alpha last, one row after another with no padding. A caller reading
// (y * width + x) * 4 has to be right on every machine.
int32_t ctd_snapshot(ctd_handle widget, double *out_size, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSView class]]) return CTD_ERR_KIND;
    NSView *view = (NSView *)object;
    NSRect bounds = [view bounds];
    int32_t width = (int32_t)bounds.size.width;
    int32_t height = (int32_t)bounds.size.height;
    if (width <= 0 || height <= 0) return CTD_ERR_RANGE;
    if (out_size) {
        out_size[0] = (double)width;
        out_size[1] = (double)height;
    }
    int32_t needed = width * height * 4;
    if (!out || cap <= 0) return needed;

    NSBitmapImageRep *rep =
        [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                 pixelsWide:width
                                                 pixelsHigh:height
                                              bitsPerSample:8
                                            samplesPerPixel:4
                                                   hasAlpha:YES
                                                   isPlanar:NO
                                             colorSpaceName:NSDeviceRGBColorSpace
                                                bitmapFormat:0
                                                bytesPerRow:width * 4
                                               bitsPerPixel:32] autorelease];
    if (!rep) return CTD_ERR_PLATFORM;
    // Every byte, so an untouched pixel is a known value rather than whatever
    // the allocator left behind — otherwise "nothing was drawn here" and
    // "something was drawn and happened to be that" are the same answer.
    memset([rep bitmapData], 0, (size_t)needed);

    NSGraphicsContext *context =
        [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!context) return CTD_ERR_PLATFORM;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [view displayRectIgnoringOpacity:bounds inContext:context];
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    int32_t room = cap < needed ? cap : needed;
    memcpy(out, [rep bitmapData], (size_t)room);
    return needed;
}

ctd_status ctd_widget_activate(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
    [(NSControl *)object performClick:nil];
    return CTD_OK;
}
