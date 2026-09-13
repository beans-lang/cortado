// The pointer, the keyboard, and where the keys go.
//
// **One hook for the whole application.** AppKit routes every event through
// -[NSApplication sendEvent:], and a local event monitor sees them all before
// any control does — so unlike GTK4 and UIKit, which need a controller per
// widget, this host installs exactly one thing and routes on an integer. That
// is the rule the rest of cortado follows for the same reason: one stored
// callback, one registration, no per-object lifetime to get wrong.
//
// The monitor returns the event it was given. Swallowing one would take the
// click away from the control it was going to, and a program that listened for
// pointer events would find its buttons stopped working.

#import "internal.h"

// Whether anything is listening, per event kind. The header calls ctd_listen
// advice rather than permission, and this array is what the advice becomes: a
// kind nobody wants costs one array read and no crossing into the program.
static int g_wanted[CTD_EV_COUNT];
// The monitor, kept so it can be taken down. AppKit returns an opaque object
// from -addLocalMonitor... and -removeMonitor: is the only thing that accepts
// it.
static id  g_monitor = nil;

// ------------------------------------------------------------------ modifiers

uint32_t ctd_modifiers_of(NSEventModifierFlags flags) {
    uint32_t bits = 0;
    if (flags & NSEventModifierFlagShift)   bits |= CTD_MOD_SHIFT;
    if (flags & NSEventModifierFlagControl) bits |= CTD_MOD_CONTROL;
    if (flags & NSEventModifierFlagOption)  bits |= CTD_MOD_ALT;
    if (flags & NSEventModifierFlagCommand) bits |= CTD_MOD_COMMAND;
    return bits;
}

static NSEventModifierFlags ctd_flags_of(uint32_t bits) {
    NSEventModifierFlags flags = 0;
    if (bits & CTD_MOD_SHIFT)   flags |= NSEventModifierFlagShift;
    if (bits & CTD_MOD_CONTROL) flags |= NSEventModifierFlagControl;
    if (bits & CTD_MOD_ALT)     flags |= NSEventModifierFlagOption;
    if (bits & CTD_MOD_COMMAND) flags |= NSEventModifierFlagCommand;
    return flags;
}

// ----------------------------------------------------------------------- keys

// AppKit's virtual key codes for the keys that type nothing.
//
// These are the numbers Carbon's Events.h froze in the 1990s and every Mac
// still reports; they are positions on the keyboard, not characters, which is
// exactly what this table wants — the key left of "1" is a different character
// on every layout and the same position on all of them.
static int32_t ctd_key_of_code(unsigned short code) {
    switch (code) {
        case 53:  return CTD_KEY_ESCAPE;
        case 48:  return CTD_KEY_TAB;
        case 36:  return CTD_KEY_RETURN;      // Return
        case 76:  return CTD_KEY_RETURN;      // Enter, on the keypad
        case 49:  return CTD_KEY_SPACE;
        case 51:  return CTD_KEY_BACKSPACE;   // AppKit calls this Delete
        case 117: return CTD_KEY_DELETE;      // and this Forward Delete
        case 123: return CTD_KEY_LEFT;
        case 124: return CTD_KEY_RIGHT;
        case 126: return CTD_KEY_UP;
        case 125: return CTD_KEY_DOWN;
        case 115: return CTD_KEY_HOME;
        case 119: return CTD_KEY_END;
        case 116: return CTD_KEY_PAGE_UP;
        case 121: return CTD_KEY_PAGE_DOWN;
        case 122: return CTD_KEY_F1;
        case 120: return CTD_KEY_F2;
        case 99:  return CTD_KEY_F3;
        case 118: return CTD_KEY_F4;
        case 96:  return CTD_KEY_F5;
        case 97:  return CTD_KEY_F6;
        case 98:  return CTD_KEY_F7;
        case 100: return CTD_KEY_F8;
        case 101: return CTD_KEY_F9;
        case 109: return CTD_KEY_F10;
        case 103: return CTD_KEY_F11;
        case 111: return CTD_KEY_F12;
        default:  return CTD_KEY_CHARACTER;
    }
}

// Space is in the table above *and* types a character, which is not a
// contradiction: a program listening for the space bar on a button wants the
// key, and a program filling a text field wants the character. Both are true
// of the same keystroke and both are reported — the key in `index`, the
// character in `text`.
static unsigned short ctd_code_of_key(int32_t key) {
    switch (key) {
        case CTD_KEY_ESCAPE:    return 53;
        case CTD_KEY_TAB:       return 48;
        case CTD_KEY_RETURN:    return 36;
        case CTD_KEY_SPACE:     return 49;
        case CTD_KEY_BACKSPACE: return 51;
        case CTD_KEY_DELETE:    return 117;
        case CTD_KEY_LEFT:      return 123;
        case CTD_KEY_RIGHT:     return 124;
        case CTD_KEY_UP:        return 126;
        case CTD_KEY_DOWN:      return 125;
        case CTD_KEY_HOME:      return 115;
        case CTD_KEY_END:       return 119;
        case CTD_KEY_PAGE_UP:   return 116;
        case CTD_KEY_PAGE_DOWN: return 121;
        case CTD_KEY_F1:        return 122;
        case CTD_KEY_F2:        return 120;
        case CTD_KEY_F3:        return 99;
        case CTD_KEY_F4:        return 118;
        case CTD_KEY_F5:        return 96;
        case CTD_KEY_F6:        return 97;
        case CTD_KEY_F7:        return 98;
        case CTD_KEY_F8:        return 100;
        case CTD_KEY_F9:        return 101;
        case CTD_KEY_F10:       return 109;
        case CTD_KEY_F11:       return 103;
        case CTD_KEY_F12:       return 111;
        default:                return 0;
    }
}

int32_t ctd_key_name(int32_t key, char *out, int32_t cap) {
    static const char *const names[CTD_KEY_COUNT] = {
        "unknown", "character", "escape", "tab", "return", "space",
        "backspace", "delete", "left", "right", "up", "down",
        "home", "end", "page_up", "page_down",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"
    };
    if (key < 0 || key >= CTD_KEY_COUNT) return CTD_ERR_RANGE;
    return ctd_copy_out([NSString stringWithUTF8String:names[key]], out, cap);
}

// --------------------------------------------------------------------- listen

ctd_status ctd_listen(int32_t kind, int32_t on) {
    if (kind < 0 || kind >= CTD_EV_COUNT) return CTD_ERR_RANGE;
    g_wanted[kind] = on ? 1 : 0;
    // A window generates no mouse-moved events at all until it is told to want
    // them, which is the whole reason this call exists: the alternative is
    // paying for a thousand events a second that nobody reads.
    if (kind == CTD_EV_POINTER_MOVE) {
        for (NSWindow *window in [NSApp windows]) {
            [window setAcceptsMouseMovedEvents:on ? YES : NO];
        }
    }
    // The two services that watch the machine start and stop here for the same
    // reason: a path monitor and two notification observers are work nobody
    // asked for until somebody does. There is no ctd_net_watch because this
    // call already is one.
    if (kind == CTD_EV_NET_CHANGED)   { if (on) ctd_net_start();   else ctd_net_stop(); }
    if (kind == CTD_EV_POWER_CHANGED) { if (on) ctd_power_start(); else ctd_power_stop(); }
    return CTD_OK;
}

int ctd_listening(uint32_t kind) {
    if (kind >= (uint32_t)CTD_EV_COUNT) return 0;
    return g_wanted[kind];
}

// ---------------------------------------------------------------- the raising

// One input event, in the target's own space.
//
// `x` and `y` are converted into the view the event landed on, which is the
// same space `ctd_view_set_frame` uses — so a program that put a control
// somewhere knows what a point inside it means without asking about windows,
// screens or whether the content view is flipped. It is flipped, and the
// conversion is what makes that invisible from up here.
static void ctd_raise_pointer(uint32_t kind, NSEvent *event, NSView *view,
                              ctd_handle target, int32_t button) {
    if (!g_sink) return;
    NSPoint local = [view convertPoint:[event locationInWindow] fromView:nil];
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = target;
    out.index = button;
    out.modifiers = ctd_modifiers_of([event modifierFlags]);
    out.x = local.x;
    out.y = local.y;
    g_sink(g_sink_context, &out);
}

// What a key typed, with the control characters taken out.
//
// AppKit answers "\x1b" to -characters for Escape, "\r" for Return and "\t"
// for Tab. Passing those through would say that Escape typed something, and a
// field appending what it hears would fill with control codes. Space is
// U+0020 and stays, which is why the bound is where it is.
static NSString *ctd_text_of(NSString *typed) {
    if (!typed || [typed length] == 0) return @"";
    unichar first = [typed characterAtIndex:0];
    if (first < 0x20 || first == 0x7f) return @"";
    return typed;
}

static void ctd_raise_key(uint32_t kind, ctd_handle target, int32_t key,
                          NSString *typed, uint32_t modifiers) {
    if (!g_sink) return;
    const char *utf8 = [ctd_text_of(typed) UTF8String];
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = target;
    out.index = key;
    out.modifiers = modifiers;
    out.text = utf8;
    out.text_len = utf8 ? (int32_t)strlen(utf8) : 0;
    g_sink(g_sink_context, &out);
}

// The control a responder stands for.
//
// **AppKit does not make a text field first responder.** It installs the
// window's *field editor* — one shared NSTextView that moves from field to
// field — and that is what -firstResponder answers. So a host comparing the
// first responder against the control would say no for the one control that
// most obviously has the keyboard. The field editor's delegate is the field it
// is editing, which is the way back.
static NSView *ctd_responder_view(NSResponder *who) {
    if (![who isKindOfClass:[NSView class]]) return nil;
    if ([who isKindOfClass:[NSTextView class]] &&
        [(NSTextView *)who isFieldEditor]) {
        id owner = [(NSTextView *)who delegate];
        if ([owner isKindOfClass:[NSView class]]) return (NSView *)owner;
    }
    return (NSView *)who;
}

// Focus, raised from one place so that a program moving it and a user tabbing
// into a field look identical to a handler. See ctd_window_focus_moved, which
// CortadoWindow calls on every first-responder change there is.
// The control a responder belongs to, as a handle. Resolved while the
// responder is still installed, because a field editor that has been resigned
// can no longer be traced back to its field.
ctd_handle ctd_focus_handle(NSResponder *who) {
    return ctd_handle_for_view(ctd_responder_view(who));
}

void ctd_focus_moved(ctd_handle left, ctd_handle took) {
    if (left == took) return;
    if (left && ctd_listening(CTD_EV_BLUR))  ctd_emit(CTD_EV_BLUR, left, 0, 0);
    if (took && ctd_listening(CTD_EV_FOCUS)) ctd_emit(CTD_EV_FOCUS, took, 0, 0);
}

// ------------------------------------------------------------------ the hook

static int32_t ctd_button_of(NSEvent *event) {
    switch ([event type]) {
        case NSEventTypeRightMouseDown:
        case NSEventTypeRightMouseUp:
        case NSEventTypeRightMouseDragged: return CTD_BTN_RIGHT;
        case NSEventTypeOtherMouseDown:
        case NSEventTypeOtherMouseUp:
        case NSEventTypeOtherMouseDragged: return CTD_BTN_MIDDLE;
        default:                           return CTD_BTN_LEFT;
    }
}

static void ctd_saw(NSEvent *event) {
    NSWindow *window = [event window];
    if (!window) return;

    switch ([event type]) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown:
        case NSEventTypeLeftMouseUp:
        case NSEventTypeRightMouseUp:
        case NSEventTypeOtherMouseUp:
        case NSEventTypeMouseMoved:
        case NSEventTypeLeftMouseDragged:
        case NSEventTypeRightMouseDragged:
        case NSEventTypeOtherMouseDragged: {
            uint32_t kind = CTD_EV_POINTER_MOVE;
            NSEventType type = [event type];
            if (type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown ||
                type == NSEventTypeOtherMouseDown) kind = CTD_EV_POINTER_DOWN;
            else if (type == NSEventTypeLeftMouseUp || type == NSEventTypeRightMouseUp ||
                     type == NSEventTypeOtherMouseUp) kind = CTD_EV_POINTER_UP;
            if (!ctd_listening(kind)) return;
            // A drag is a move with a button held, which is what every
            // platform here calls it and what a program drawing a line wants.
            NSView *hit = [[window contentView] hitTest:[event locationInWindow]];
            ctd_handle target = ctd_handle_for_view(hit);
            if (!target) return;
            ctd_raise_pointer(kind, event, hit, target, ctd_button_of(event));
            return;
        }
        case NSEventTypeKeyDown:
        case NSEventTypeKeyUp: {
            uint32_t kind = ([event type] == NSEventTypeKeyDown)
                ? CTD_EV_KEY_DOWN : CTD_EV_KEY_UP;
            if (!ctd_listening(kind)) return;
            // A key goes to whoever has the keyboard, not to whatever is under
            // the pointer — which is why this does not hit-test.
            ctd_handle target =
                ctd_handle_for_view(ctd_responder_view([window firstResponder]));
            if (!target) return;
            ctd_raise_key(kind, target, ctd_key_of_code([event keyCode]),
                          [event characters],
                          ctd_modifiers_of([event modifierFlags]));
            return;
        }
        default: return;
    }
}

void ctd_input_start(void) {
    if (g_monitor) return;
    NSEventMask mask = (NSEventMaskLeftMouseDown  | NSEventMaskLeftMouseUp |
                        NSEventMaskRightMouseDown | NSEventMaskRightMouseUp |
                        NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp |
                        NSEventMaskMouseMoved     |
                        NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged |
                        NSEventMaskOtherMouseDragged |
                        NSEventMaskKeyDown | NSEventMaskKeyUp);
    g_monitor = [[NSEvent addLocalMonitorForEventsMatchingMask:mask
        handler:^NSEvent *(NSEvent *event) {
            ctd_saw(event);
            // Given back unchanged. Swallowing it would take the click away
            // from the control it was going to, and a program that listened
            // for pointer events would find its buttons stopped working.
            return event;
        }] retain];
}

void ctd_input_stop(void) {
    if (!g_monitor) return;
    [NSEvent removeMonitor:g_monitor];
    [g_monitor release];
    g_monitor = nil;
    memset(g_wanted, 0, sizeof g_wanted);
}

// ---------------------------------------------------------------------- focus

// Whether this control can take the keyboard at all.
//
// AppKit answers -acceptsFirstResponder, and the answer differs by control and
// by the user's own Full Keyboard Access setting — which is a real difference
// and not one to paper over: a label cannot take the keyboard on any platform,
// and a button can on this one and cannot on a phone.
ctd_status ctd_widget_focus(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSView class]]) return CTD_ERR_UNSUPPORTED;
    NSView *view = (NSView *)object;
    if (![view acceptsFirstResponder]) {
        // Two different answers to two different questions. A canvas *can*
        // take the keyboard on this platform and simply has not been asked to;
        // a label cannot on any. Telling them apart is the difference between
        // "turn CTD_P_FOCUSABLE on" and "stop trying".
        if (ctd_kind_is_drawn(ctd_slot_kind(widget))) return CTD_ERR_STATE;
        return CTD_ERR_UNSUPPORTED;
    }
    NSWindow *window = [view window];
    // A view that is in no window would still take first responder from a
    // window it does not belong to — AppKit does not check — and the program
    // would have moved the keyboard onto something that is not on screen.
    if (!window) return CTD_ERR_STATE;
    return [window makeFirstResponder:view] ? CTD_OK : CTD_ERR_UNSUPPORTED;
}

int32_t ctd_widget_focused(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (![object isKindOfClass:[NSView class]]) return 0;
    NSView *view = (NSView *)object;
    NSWindow *window = [view window];
    if (!window) return 0;
    // "The control this window would type into", not "the control the user is
    // typing into". The second needs the window to be on screen and in front,
    // which makes it a fact about the desktop rather than about the program —
    // and would make this unanswerable in a headless run.
    return ctd_responder_view([window firstResponder]) == view ? 1 : 0;
}

// ----------------------------------------------------------------- synthesis

// A real NSEvent, posted the way a mouse's is.
//
// It travels the path a mouse travels: into the application's queue, out
// through -[NSApplication sendEvent:], past the monitor above, and into the
// control. Two of the four hosts can do this and two cannot, and the header
// says which — it matters, because a test that called cortado's own handler
// would prove that the handler works and nothing about how it is reached.
ctd_status ctd_widget_synth_pointer(ctd_handle widget, int32_t what,
                                    double x, double y, int32_t button) {
    if (what != CTD_EV_POINTER_DOWN && what != CTD_EV_POINTER_UP &&
        what != CTD_EV_POINTER_MOVE) return CTD_ERR_RANGE;
    if (button < CTD_BTN_LEFT || button > CTD_BTN_MIDDLE) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSView class]]) return CTD_ERR_UNSUPPORTED;
    NSView *view = (NSView *)object;
    NSWindow *window = [view window];
    if (!window) return CTD_ERR_STATE;

    NSEventType type;
    if (what == CTD_EV_POINTER_MOVE) type = NSEventTypeMouseMoved;
    else if (button == CTD_BTN_RIGHT)
        type = (what == CTD_EV_POINTER_DOWN) ? NSEventTypeRightMouseDown
                                             : NSEventTypeRightMouseUp;
    else if (button == CTD_BTN_MIDDLE)
        type = (what == CTD_EV_POINTER_DOWN) ? NSEventTypeOtherMouseDown
                                             : NSEventTypeOtherMouseUp;
    else
        type = (what == CTD_EV_POINTER_DOWN) ? NSEventTypeLeftMouseDown
                                             : NSEventTypeLeftMouseUp;

    NSPoint in_window = [view convertPoint:NSMakePoint(x, y) toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:type
                                        location:in_window
                                   modifierFlags:0
                                       timestamp:[[NSProcessInfo processInfo] systemUptime]
                                    windowNumber:[window windowNumber]
                                         context:nil
                                     eventNumber:0
                                      clickCount:(what == CTD_EV_POINTER_MOVE) ? 0 : 1
                                        pressure:(what == CTD_EV_POINTER_DOWN) ? 1.0 : 0.0];
    if (!event) return CTD_ERR_PLATFORM;
    [NSApp sendEvent:event];
    return CTD_OK;
}

ctd_status ctd_widget_synth_key(ctd_handle widget, int32_t what, int32_t key,
                                const char *text, int32_t len,
                                uint32_t modifiers) {
    if (what != CTD_EV_KEY_DOWN && what != CTD_EV_KEY_UP) return CTD_ERR_RANGE;
    if (key < 0 || key >= CTD_KEY_COUNT) return CTD_ERR_RANGE;
    if (ctd_has_nul(text, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSView class]]) return CTD_ERR_UNSUPPORTED;
    NSView *view = (NSView *)object;
    NSWindow *window = [view window];
    if (!window) return CTD_ERR_STATE;
    // A key goes to whoever has the keyboard. Driving one at a control that
    // does not means testing what a user could not do, so the control is
    // given the keyboard first — refused if it cannot take it, which is the
    // same refusal a program would get for asking.
    if (ctd_responder_view([window firstResponder]) != view) {
        ctd_status moved = ctd_widget_focus(widget);
        if (moved != CTD_OK) return moved;
    }

    NSString *typed = (text && len > 0)
        ? [[[NSString alloc] initWithBytes:text length:(NSUInteger)len
                                  encoding:NSUTF8StringEncoding] autorelease]
        : @"";
    if (!typed) return CTD_ERR_RANGE;
    NSEvent *event = [NSEvent keyEventWithType:(what == CTD_EV_KEY_DOWN)
                                                ? NSEventTypeKeyDown : NSEventTypeKeyUp
                                      location:NSZeroPoint
                                 modifierFlags:ctd_flags_of(modifiers)
                                     timestamp:[[NSProcessInfo processInfo] systemUptime]
                                  windowNumber:[window windowNumber]
                                       context:nil
                                    characters:typed
                   charactersIgnoringModifiers:typed
                                     isARepeat:NO
                                       keyCode:ctd_code_of_key(key)];
    if (!event) return CTD_ERR_PLATFORM;
    [NSApp sendEvent:event];
    return CTD_OK;
}
