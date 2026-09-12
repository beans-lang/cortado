// The pointer, the keyboard, and where the keys go.
//
// **A phone's shape, which is GTK4's shape: a recognizer per control, and no
// way to build an event.** UIKit has no application-wide hook that sees input
// before a control does, and `UIEvent` has no public constructor — so a
// synthesised touch runs cortado's own handler, one step short of UIKit's
// dispatch, and the header says so rather than letting a test look like it
// proves more than it does.
//
// Two things differ from every desktop here, and neither is a gap to paper
// over:
//
//   * **A touch has no button.** There is no right-click on a finger. Every
//     pointer event is CTD_BTN_LEFT, which is what UIKit itself reports and
//     what a program written against this ABI already handles.
//   * **A button cannot take the keyboard.** `-canBecomeFirstResponder` is NO
//     for UIButton and every other control that is not text input, which is a
//     real difference from AppKit and not a missing feature: there is no Tab
//     key to move focus with and no focus ring to show it. So
//     `ctd_widget_focus` on one is CTD_ERR_UNSUPPORTED, which is the same
//     answer a label gets everywhere.

#import "internal.h"

static int g_wanted[CTD_EV_COUNT];

int ctd_listening(uint32_t kind) {
    if (kind >= (uint32_t)CTD_EV_COUNT) return 0;
    return g_wanted[kind];
}

ctd_status ctd_listen(int32_t kind, int32_t on) {
    if (kind < 0 || kind >= CTD_EV_COUNT) return CTD_ERR_RANGE;
    g_wanted[kind] = on ? 1 : 0;
    // The two services that watch the machine start and stop here, for the
    // same reason: a path monitor is work nobody asked for until somebody
    // does. There is no ctd_net_watch because this call already is one.
    if (kind == CTD_EV_NET_CHANGED)   { if (on) ctd_net_start();   else ctd_net_stop(); }
    if (kind == CTD_EV_POWER_CHANGED) { if (on) ctd_power_start(); else ctd_power_stop(); }
    return CTD_OK;
}

// ----------------------------------------------------------------------- keys

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

// -------------------------------------------------------------- the reverse

// The handle a view was tracked under.
//
// An associated object rather than a table of cortado's own: it is O(1), it
// goes away with the view, and UIKit has no equivalent of AppKit's identifier
// to borrow.
static const void *kCortadoHandleKey = &kCortadoHandleKey;

void ctd_input_remember(id object, ctd_handle handle) {
    if (![object isKindOfClass:[UIView class]]) return;
    objc_setAssociatedObject(object, kCortadoHandleKey,
                             [NSNumber numberWithUnsignedLongLong:handle],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

ctd_handle ctd_handle_for_view(UIView *view) {
    while (view) {
        NSNumber *kept = objc_getAssociatedObject(view, kCortadoHandleKey);
        if (kept) return (ctd_handle)[kept unsignedLongLongValue];
        view = [view superview];
    }
    return 0;
}

// ---------------------------------------------------------------- the raising

static void ctd_raise_pointer(uint32_t kind, UIView *view, double x, double y) {
    if (!g_sink || !ctd_listening(kind)) return;
    ctd_handle target = ctd_handle_for_view(view);
    if (!target) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = target;
    // A finger is the only pointer here, and UIKit calls it the primary one.
    out.index = CTD_BTN_LEFT;
    out.x = x;
    out.y = y;
    g_sink(g_sink_context, &out);
}

// What a key typed, with the control characters taken out — the same rule the
// other three hosts apply, and stated beside CTD_KEY_CHARACTER in the header.
static NSString *ctd_text_of(NSString *typed) {
    if (!typed || [typed length] == 0) return @"";
    unichar first = [typed characterAtIndex:0];
    if (first < 0x20 || first == 0x7f) return @"";
    return typed;
}

static void ctd_raise_key(uint32_t kind, UIView *view, int32_t key,
                          NSString *typed, uint32_t modifiers) {
    if (!g_sink || !ctd_listening(kind)) return;
    ctd_handle target = ctd_handle_for_view(view);
    if (!target) return;
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

// Which control has the keyboard, as far as cortado is concerned.
//
// UIKit has no window-level hook for it — there is no -makeFirstResponder: to
// override, only -becomeFirstResponder on the view, and the view that *loses*
// it is never told through any API cortado can reach. So the one that had it
// is remembered, and the blur is raised from here when the next one takes it.
static ctd_handle g_focused;

void ctd_focus_moved(ctd_handle took) {
    if (g_focused == took) return;
    ctd_handle left = g_focused;
    g_focused = took;
    if (left && ctd_listening(CTD_EV_BLUR))  ctd_emit(CTD_EV_BLUR, left, 0, 0);
    if (took && ctd_listening(CTD_EV_FOCUS)) ctd_emit(CTD_EV_FOCUS, took, 0, 0);
}

// ------------------------------------------------------------- the recognizer

// A recognizer that watches and never wins.
//
// It reports every touch and then fails, so it never claims the gesture — a
// button under it still works, a scroll view under it still scrolls. A
// recognizer that recognised would take input away from the control it was
// attached to, which is the phone's version of swallowing an event.
@implementation CortadoTouches
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UIView *view = [self view];
    CGPoint where = [[touches anyObject] locationInView:view];
    ctd_raise_pointer(CTD_EV_POINTER_DOWN, view, where.x, where.y);
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    UIView *view = [self view];
    CGPoint where = [[touches anyObject] locationInView:view];
    ctd_raise_pointer(CTD_EV_POINTER_MOVE, view, where.x, where.y);
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    UIView *view = [self view];
    CGPoint where = [[touches anyObject] locationInView:view];
    ctd_raise_pointer(CTD_EV_POINTER_UP, view, where.x, where.y);
    [self setState:UIGestureRecognizerStateFailed];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self setState:UIGestureRecognizerStateFailed];
}
@end

void ctd_input_attach(id object, ctd_handle handle) {
    if (![object isKindOfClass:[UIView class]]) return;
    UIView *view = (UIView *)object;
    ctd_input_remember(view, handle);
    CortadoTouches *watching = [[CortadoTouches alloc] initWithTarget:nil action:NULL];
    // Neither delays nor cancels: the control under it must behave exactly as
    // it would with nothing attached.
    [watching setCancelsTouchesInView:NO];
    [watching setDelaysTouchesBegan:NO];
    [watching setDelaysTouchesEnded:NO];
    [view addGestureRecognizer:watching];
    [watching release];
}

// ---------------------------------------------------------------------- focus

ctd_status ctd_widget_focus(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIView class]]) return CTD_ERR_UNSUPPORTED;
    UIView *view = (UIView *)object;
    // The phone's own rule, and the reason this line differs from the Mac's:
    // only text input can take the keyboard here.
    if (![view canBecomeFirstResponder]) return CTD_ERR_UNSUPPORTED;
    if (![view window]) return CTD_ERR_STATE;
    if (![view becomeFirstResponder]) return CTD_ERR_UNSUPPORTED;
    ctd_focus_moved(widget);
    return CTD_OK;
}

int32_t ctd_widget_focused(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (![object isKindOfClass:[UIView class]]) return 0;
    return [(UIView *)object isFirstResponder] ? 1 : 0;
}

// ----------------------------------------------------------------- synthesis

ctd_status ctd_widget_synth_pointer(ctd_handle widget, int32_t what,
                                    double x, double y, int32_t button) {
    if (what != CTD_EV_POINTER_DOWN && what != CTD_EV_POINTER_UP &&
        what != CTD_EV_POINTER_MOVE) return CTD_ERR_RANGE;
    if (button < CTD_BTN_LEFT || button > CTD_BTN_MIDDLE) return CTD_ERR_RANGE;
    // A finger has no second button, and there is no gesture on a phone that
    // means "right click" — a long press is a long press, and an application
    // decides what it is for. So a caller asking for one is asking for
    // something this platform does not have, and hears so. Answering with a
    // left click instead would hand a program an event it did not ask for and
    // cannot tell apart from a real one.
    if (button != CTD_BTN_LEFT) return CTD_ERR_UNSUPPORTED;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIView class]]) return CTD_ERR_UNSUPPORTED;
    // UIEvent has no public constructor, so this is the handler and not the
    // road to it. What it does prove is everything above the recognizer: the
    // reverse lookup, the coordinate space, the listen gate and the sink.
    ctd_raise_pointer((uint32_t)what, (UIView *)object, x, y);
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
    if (![object isKindOfClass:[UIView class]]) return CTD_ERR_UNSUPPORTED;
    UIView *view = (UIView *)object;
    if (![view isFirstResponder]) {
        ctd_status moved = ctd_widget_focus(widget);
        if (moved != CTD_OK) return moved;
    }
    NSString *typed = (text && len > 0)
        ? [[[NSString alloc] initWithBytes:text length:(NSUInteger)len
                                  encoding:NSUTF8StringEncoding] autorelease]
        : @"";
    if (!typed) return CTD_ERR_RANGE;
    ctd_raise_key((uint32_t)what, view, key, typed, modifiers);
    return CTD_OK;
}
