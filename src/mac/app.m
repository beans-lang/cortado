// Starting AppKit, stopping it, and turning a control's action into an event.
//
// The one callback edge in the whole host is here: `g_sink` is a function
// pointer Beans registered at run time, and nothing in cortado's C half ever
// names a Beans symbol.

#import "internal.h"

// ------------------------------------------------------- the flipped container


@implementation CortadoView
- (BOOL)isFlipped { return YES; }
@end

// ------------------------------------------------------------ action forwarding
//
// AppKit's target/action wants an object with a selector. One of these sits
// between a control and the sink, carrying the handle the event belongs to.
// The control holds its target weakly, so the table below keeps it alive.




// One target object for every menu item cortado owns. The interface is here,
// beside the declaration, because `ctd_init` makes it and the menu section
// further down implements it.

CortadoCommand *g_commands;

@implementation CortadoTarget
- (void)fire:(id)sender {
    ctd_emit_control(self.handle, sender);
}
@end

NSMutableArray *g_targets;   // keeps every CortadoTarget alive

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

// One control's action, as the event it actually is.
//
// AppKit sends every control's action down one selector, so the kind has to be
// decided here. The rule is the one a person would give: a control that
// carries a *value* reports that the value changed; a control that is a
// *command* reports that it was activated; a field that has been committed
// reports the commit. A framework that called all of them "activate" would
// make a slider and a button indistinguishable to a handler, and every
// application would re-derive this from the control's class.
void ctd_emit_control(ctd_handle target, id sender) {
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

int g_stop_requested;

// Whether the unbounded loop is the one that is running.
//
// -[NSApplication stop:] is understood by -[NSApplication run] and by nothing
// else, and a stop sent while that loop is not running does not vanish: it is
// remembered, and the next -run returns straight away. So it is sent only when
// there is a -run to stop, and a bounded run is ended by its own flag instead.
static int g_in_run;

void ctd_app_run(void) {
    if (!g_started) return;
    g_stop_requested = 0;
    g_in_run = 1;
    [NSApp run];
    g_in_run = 0;
}

// The same loop, with a deadline.
//
// -[NSApplication run] is the loop, and it does two things: it pulls the next
// event and it sends it. Doing both here is what makes a bounded run a real
// run rather than a bare CFRunLoopRunInMode — an event pulled off the queue
// and never sent reaches no window, so a control would stop responding for
// exactly as long as a program waited.
//
// Waiting is also what services the main dispatch queue, which is how a frame
// reaches Beans: the display link's thread posts the frame there and this is
// the code that runs it.
ctd_status ctd_app_run_for(double seconds) {
    if (!g_started) return CTD_ERR_STATE;
    if (!(seconds >= 0.0)) return CTD_ERR_RANGE;
    g_stop_requested = 0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!g_stop_requested) {
        @autoreleasepool {
            NSDate *now = [NSDate date];
            if ([now compare:deadline] != NSOrderedAscending) break;
            // Waited in slices rather than in one go, because ctd_app_stop
            // sets a flag and this loop is the only thing that reads it.
            // -[NSApplication stop:] wakes -run and not this; and an event
            // posted to wake it cannot be relied on either, because an
            // application that never finished launching has no event queue
            // worth the name. So the slice is how late a stop can be: ten
            // milliseconds, well under a frame, for a hundred wake-ups a
            // second in a call whose entire job is to wait.
            NSDate *slice = [now dateByAddingTimeInterval:0.01];
            if ([slice compare:deadline] == NSOrderedDescending) slice = deadline;
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:slice
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            // Waiting is what runs the main dispatch queue, which is how a
            // frame reaches Beans; an event is the other thing that can
            // happen, and it still has to be sent or no window would see it.
            if (event) [NSApp sendEvent:event];
        }
    }
    return CTD_OK;
}

void ctd_app_stop(void) {
    g_stop_requested = 1;
    if (g_in_run) [NSApp stop:nil];
    // -stop: only takes effect when the loop next finishes an event, so a stop
    // requested from outside one would otherwise sit until the user moved the
    // mouse. Posting an empty event is what makes it immediate — and it is
    // what lets a bounded run end early too, since that loop is asleep inside
    // -nextEventMatchingMask until something arrives.
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
        case CTD_CAP_GPU:           return 1;
        default:                    return 0;
    }
}
