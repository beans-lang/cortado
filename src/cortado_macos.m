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
#include "cortado_host.h"

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

static ctd_handle ctd_track(id object, int32_t kind) {
    if (g_used + 1 >= CTD_SLOTS) return 0;
    uint32_t slot = ++g_used;
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

@implementation CortadoTarget
- (void)fire:(id)sender {
    (void)sender;
    ctd_emit(CTD_EV_ACTIVATE, self.handle, 0, 0);
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

// ------------------------------------------------------------------ lifecycle

uint32_t ctd_abi_version(void) { return CTD_ABI_VERSION; }

ctd_status ctd_init(uint32_t want_abi) {
    if (want_abi != CTD_ABI_VERSION) return CTD_ERR_ABI;
    if (g_started) return CTD_OK;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    g_targets = [[NSMutableArray alloc] init];
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
    return CTD_OK;
}

// ----------------------------------------------------------------------- tree

// A surface addresses its content view; everything else addresses itself.
static NSView *ctd_container_of(id object) {
    if ([object isKindOfClass:[NSWindow class]]) return [(NSWindow *)object contentView];
    if ([object isKindOfClass:[NSView class]]) return (NSView *)object;
    return nil;
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    NSView *container = ctd_container_of(ctd_resolve(parent));
    NSView *view = (NSView *)ctd_resolve(child);
    if (!container || !view) return CTD_ERR_STALE;
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
    NSView *container = ctd_container_of(ctd_resolve(parent));
    NSView *view = (NSView *)ctd_resolve(child);
    if (!container || !view) return CTD_ERR_STALE;
    if ([view superview] != container) return CTD_ERR_RANGE;
    [view removeFromSuperview];
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    NSView *container = ctd_container_of(ctd_resolve(parent));
    if (!container) return CTD_ERR_STALE;
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
    NSView *container = ctd_container_of(ctd_resolve(parent));
    if (!container) return CTD_ERR_STALE;
    if (out) *out = (int32_t)[ctd_children(container) count];
    return CTD_OK;
}

ctd_handle ctd_view_child_at(ctd_handle parent, int32_t index) {
    NSView *container = ctd_container_of(ctd_resolve(parent));
    if (!container) return 0;
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

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = [[[NSString alloc] initWithBytes:utf8
                                               length:(NSUInteger)(len < 0 ? 0 : len)
                                             encoding:NSUTF8StringEncoding] autorelease];
    if (!text) text = @"";
    if ([object isKindOfClass:[NSButton class]])         [(NSButton *)object setTitle:text];
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
    if ([object isKindOfClass:[NSButton class]])
        return ctd_copy_out([(NSButton *)object title], out, cap);
    if ([object isKindOfClass:[NSTextField class]])
        return ctd_copy_out([(NSTextField *)object stringValue], out, cap);
    return ctd_copy_out(@"", out, cap);
}

ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_ENABLED:
            if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
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
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    int64_t value = 0;
    switch (key) {
        case CTD_P_ENABLED:
            // A plain container has no enabled state, and answering 0 for it
            // would read as "disabled" — a wrong answer rather than a missing
            // one. The caller gets to tell the difference.
            if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
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
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (key == CTD_P_FONT_SIZE) {
        if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
        [(NSControl *)object setFont:[NSFont systemFontOfSize:value]];
        return CTD_OK;
    }
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (key == CTD_P_FONT_SIZE) {
        if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
        if (out) *out = (double)[[(NSControl *)object font] pointSize];
        return CTD_OK;
    }
    return CTD_ERR_UNSUPPORTED;
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
        case CTD_W_CONTAINER:  role = @"group";    break;
        case CTD_W_LABEL:      role = @"text";     break;
        case CTD_W_BUTTON:     role = @"button";   break;
        case CTD_W_TEXT_FIELD: role = @"textbox";  break;
        case CTD_W_CHECK_BOX:  role = @"checkbox"; break;
        case CTD_W_IMAGE_VIEW: role = @"image";    break;
        default:               role = @"window";   break;
    }
    return ctd_copy_out(role, out, cap);
}

ctd_status ctd_widget_activate(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
    [(NSControl *)object performClick:nil];
    return CTD_OK;
}
