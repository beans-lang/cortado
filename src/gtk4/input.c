// The pointer, the keyboard, and where the keys go.
//
// **GTK4 has no global hook, and no way to build an event.** Both facts shape
// this file. There is no equivalent of AppKit's local event monitor: input
// reaches a widget through a GtkEventController attached to that widget, so
// the host attaches one set per control as it builds it — which is done in
// `ctd_track`, the one place every control passes through.
//
// And GdkEvent has public getters and no public constructor, so nothing
// outside GTK can make one. A synthesised click therefore emits the
// controller's own signal: the same handler a real click reaches, one step
// short of GDK's dispatch. The header says so, because a test that proved less
// than it looked like it proved would be worse than no test.

#include "internal.h"

#include <gdk/gdkkeysyms.h>

// Whether anything is listening, per event kind. The header calls ctd_listen
// advice rather than permission; this is what the advice becomes.
static int g_wanted[CTD_EV_COUNT];

// The button a synthesised click is carrying.
//
// A real click's button is read off the event GDK is dispatching. A
// synthesised one has no event, so the handler would read 0 and call every
// click a left one — which is exactly the kind of thing a suite proves and a
// program then trips over. Set for the length of one signal emission, which
// is a single call on the UI thread with nothing in between.
static int32_t g_synth_button;

// The handle a widget was tracked under, and the controllers cortado gave it.
// GObject carries its own key/value table, so the reverse lookup an event
// needs — from the widget the controller names back to the handle a program
// knows — costs one hash lookup and no table of cortado's own.
#define CTD_HANDLE_KEY "ctd-handle"
#define CTD_CLICK_KEY  "ctd-click"
#define CTD_MOTION_KEY "ctd-motion"
#define CTD_KEYS_KEY   "ctd-keys"
#define CTD_SCROLL_POINT_KEY "ctd-scroll-point"

int ctd_listening(uint32_t kind) {
    if (kind >= (uint32_t)CTD_EV_COUNT) return 0;
    return g_wanted[kind];
}

ctd_status ctd_listen(int32_t kind, int32_t on) {
    if (kind < 0 || kind >= CTD_EV_COUNT) return CTD_ERR_RANGE;
    // GTK asks its backend for motion whether or not anyone reads it, so
    // there is nothing to turn off here beyond the crossing itself — which is
    // exactly what the header says this call is allowed to be: advice.
    g_wanted[kind] = on ? 1 : 0;
    // The two services that watch the machine start and stop here, for the
    // same reason: a network monitor is work nobody asked for until somebody
    // does. There is no ctd_net_watch because this call already is one.
    if (kind == CTD_EV_NET_CHANGED)   { if (on) ctd_net_start();   else ctd_net_stop(); }
    if (kind == CTD_EV_POWER_CHANGED) { if (on) ctd_power_start(); else ctd_power_stop(); }
    return CTD_OK;
}

ctd_handle ctd_handle_for_widget(GtkWidget *widget) {
    while (widget) {
        gpointer kept = g_object_get_data(G_OBJECT(widget), CTD_HANDLE_KEY);
        if (kept) return (ctd_handle)GPOINTER_TO_SIZE(kept);
        widget = gtk_widget_get_parent(widget);
    }
    return 0;
}

// ----------------------------------------------------------------------- keys

static int32_t ctd_key_of_keyval(guint keyval) {
    switch (keyval) {
        case GDK_KEY_Escape:    return CTD_KEY_ESCAPE;
        case GDK_KEY_Tab:
        case GDK_KEY_ISO_Left_Tab: return CTD_KEY_TAB;
        case GDK_KEY_Return:
        case GDK_KEY_KP_Enter:  return CTD_KEY_RETURN;
        case GDK_KEY_space:     return CTD_KEY_SPACE;
        case GDK_KEY_BackSpace: return CTD_KEY_BACKSPACE;
        case GDK_KEY_Delete:    return CTD_KEY_DELETE;
        case GDK_KEY_Left:      return CTD_KEY_LEFT;
        case GDK_KEY_Right:     return CTD_KEY_RIGHT;
        case GDK_KEY_Up:        return CTD_KEY_UP;
        case GDK_KEY_Down:      return CTD_KEY_DOWN;
        case GDK_KEY_Home:      return CTD_KEY_HOME;
        case GDK_KEY_End:       return CTD_KEY_END;
        case GDK_KEY_Page_Up:   return CTD_KEY_PAGE_UP;
        case GDK_KEY_Page_Down: return CTD_KEY_PAGE_DOWN;
        case GDK_KEY_F1:        return CTD_KEY_F1;
        case GDK_KEY_F2:        return CTD_KEY_F2;
        case GDK_KEY_F3:        return CTD_KEY_F3;
        case GDK_KEY_F4:        return CTD_KEY_F4;
        case GDK_KEY_F5:        return CTD_KEY_F5;
        case GDK_KEY_F6:        return CTD_KEY_F6;
        case GDK_KEY_F7:        return CTD_KEY_F7;
        case GDK_KEY_F8:        return CTD_KEY_F8;
        case GDK_KEY_F9:        return CTD_KEY_F9;
        case GDK_KEY_F10:       return CTD_KEY_F10;
        case GDK_KEY_F11:       return CTD_KEY_F11;
        case GDK_KEY_F12:       return CTD_KEY_F12;
        default:                return CTD_KEY_CHARACTER;
    }
}

static guint ctd_keyval_of_key(int32_t key) {
    switch (key) {
        case CTD_KEY_ESCAPE:    return GDK_KEY_Escape;
        case CTD_KEY_TAB:       return GDK_KEY_Tab;
        case CTD_KEY_RETURN:    return GDK_KEY_Return;
        case CTD_KEY_SPACE:     return GDK_KEY_space;
        case CTD_KEY_BACKSPACE: return GDK_KEY_BackSpace;
        case CTD_KEY_DELETE:    return GDK_KEY_Delete;
        case CTD_KEY_LEFT:      return GDK_KEY_Left;
        case CTD_KEY_RIGHT:     return GDK_KEY_Right;
        case CTD_KEY_UP:        return GDK_KEY_Up;
        case CTD_KEY_DOWN:      return GDK_KEY_Down;
        case CTD_KEY_HOME:      return GDK_KEY_Home;
        case CTD_KEY_END:       return GDK_KEY_End;
        case CTD_KEY_PAGE_UP:   return GDK_KEY_Page_Up;
        case CTD_KEY_PAGE_DOWN: return GDK_KEY_Page_Down;
        case CTD_KEY_F1:        return GDK_KEY_F1;
        case CTD_KEY_F2:        return GDK_KEY_F2;
        case CTD_KEY_F3:        return GDK_KEY_F3;
        case CTD_KEY_F4:        return GDK_KEY_F4;
        case CTD_KEY_F5:        return GDK_KEY_F5;
        case CTD_KEY_F6:        return GDK_KEY_F6;
        case CTD_KEY_F7:        return GDK_KEY_F7;
        case CTD_KEY_F8:        return GDK_KEY_F8;
        case CTD_KEY_F9:        return GDK_KEY_F9;
        case CTD_KEY_F10:       return GDK_KEY_F10;
        case CTD_KEY_F11:       return GDK_KEY_F11;
        case CTD_KEY_F12:       return GDK_KEY_F12;
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
    return ctd_copy_out(names[key], out, cap);
}

static uint32_t ctd_modifiers_of(GdkModifierType state) {
    uint32_t bits = 0;
    if (state & GDK_SHIFT_MASK)   bits |= CTD_MOD_SHIFT;
    if (state & GDK_CONTROL_MASK) bits |= CTD_MOD_CONTROL;
    if (state & GDK_ALT_MASK)     bits |= CTD_MOD_ALT;
    if (state & GDK_META_MASK)    bits |= CTD_MOD_COMMAND;
    return bits;
}

static GdkModifierType ctd_state_of(uint32_t bits) {
    GdkModifierType state = 0;
    if (bits & CTD_MOD_SHIFT)   state |= GDK_SHIFT_MASK;
    if (bits & CTD_MOD_CONTROL) state |= GDK_CONTROL_MASK;
    if (bits & CTD_MOD_ALT)     state |= GDK_ALT_MASK;
    if (bits & CTD_MOD_COMMAND) state |= GDK_META_MASK;
    return state;
}

// ---------------------------------------------------------------- the raising

static void ctd_raise_pointer(uint32_t kind, GtkWidget *widget,
                              double x, double y, int32_t button,
                              uint32_t modifiers, int32_t clicks) {
    if (!g_sink || !ctd_listening(kind)) return;
    ctd_handle target = ctd_handle_for_widget(widget);
    if (!target) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = target;
    out.index = button;
    out.token = clicks;
    out.modifiers = modifiers;
    out.x = x;
    out.y = y;
    g_sink(g_sink_context, &out);
}

// What a key typed, with the control characters taken out.
//
// An X11 keysym carries the ASCII control code: gdk_keyval_to_unicode answers
// 0x1B for Escape and 0x0D for Return, not 0. Passing those through would say
// that Escape typed something. Space is U+0020 and stays.
static const char *ctd_text_of(const char *typed) {
    if (!typed || !typed[0]) return "";
    unsigned char first = (unsigned char)typed[0];
    if (first < 0x20 || first == 0x7f) return "";
    return typed;
}

static void ctd_raise_key(uint32_t kind, GtkWidget *widget, int32_t key,
                          const char *typed, uint32_t modifiers) {
    if (!g_sink || !ctd_listening(kind)) return;
    typed = ctd_text_of(typed);
    ctd_handle target = ctd_handle_for_widget(widget);
    if (!target) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = target;
    out.index = key;
    out.modifiers = modifiers;
    out.text = typed;
    out.text_len = typed ? (int32_t)strlen(typed) : 0;
    g_sink(g_sink_context, &out);
}

// ----------------------------------------------------------- the controllers

// Which button a click is carrying: GDK's, or the one a synthesised call left
// here because GDK has no event for it to read.
static int32_t ctd_button_of(GtkGestureClick *gesture) {
    guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(gesture));
    if (button == 0) return g_synth_button ? g_synth_button : CTD_BTN_LEFT;
    if (button == 3) return CTD_BTN_RIGHT;
    if (button == 2) return CTD_BTN_MIDDLE;
    return CTD_BTN_LEFT;
}

static void ctd_on_pressed(GtkGestureClick *gesture, int presses,
                           double x, double y, gpointer data) {
    ctd_raise_pointer(CTD_EV_POINTER_DOWN, GTK_WIDGET(data), x, y,
                      ctd_button_of(gesture),
                      ctd_modifiers_of(gtk_event_controller_get_current_event_state(
                          GTK_EVENT_CONTROLLER(gesture))), MAX(1, presses));
}

static void ctd_on_released(GtkGestureClick *gesture, int presses,
                            double x, double y, gpointer data) {
    ctd_raise_pointer(CTD_EV_POINTER_UP, GTK_WIDGET(data), x, y,
                      ctd_button_of(gesture),
                      ctd_modifiers_of(gtk_event_controller_get_current_event_state(
                          GTK_EVENT_CONTROLLER(gesture))), MAX(1, presses));
}

static void ctd_on_motion(GtkEventControllerMotion *motion,
                          double x, double y, gpointer data) {
    double *point = g_object_get_data(G_OBJECT(data), CTD_SCROLL_POINT_KEY);
    if (point) { point[0] = x; point[1] = y; }
    ctd_raise_pointer(CTD_EV_POINTER_MOVE, GTK_WIDGET(data), x, y, CTD_BTN_LEFT,
                      ctd_modifiers_of(gtk_event_controller_get_current_event_state(
                          GTK_EVENT_CONTROLLER(motion))), 0);
}

static void ctd_on_motion_leave(GtkEventControllerMotion *motion, gpointer data) {
    (void)motion;
    ctd_raise_pointer(CTD_EV_POINTER_MOVE, GTK_WIDGET(data), -1.0, -1.0, CTD_BTN_LEFT, 0, 0);
}

static gboolean ctd_on_scroll(GtkEventControllerScroll *controller,
                              double dx, double dy, gpointer data) {
    (void)controller;
    if (!g_sink || !ctd_listening(CTD_EV_POINTER_SCROLL)) return FALSE;
    ctd_handle target = ctd_handle_for_widget(GTK_WIDGET(data));
    if (!target) return FALSE;
    double *point = g_object_get_data(G_OBJECT(data), CTD_SCROLL_POINT_KEY);
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = CTD_EV_POINTER_SCROLL;
    event.target = target;
    event.x = point ? point[0] : 0.0;
    event.y = point ? point[1] : 0.0;
    event.width = dx * 32.0;
    event.height = dy * 32.0;
    g_sink(g_sink_context, &event);
    return FALSE;
}

static gboolean ctd_on_key_pressed(GtkEventControllerKey *keys, guint keyval,
                                   guint code, GdkModifierType state,
                                   gpointer data) {
    (void)code;
    if (ctd_canvas_im_filter(GTK_WIDGET(data), gtk_event_controller_get_current_event(GTK_EVENT_CONTROLLER(keys))))
        return TRUE;
    if (ctd_canvas_text_active(GTK_WIDGET(data)) &&
        !(state & (GDK_CONTROL_MASK | GDK_META_MASK)) &&
        (ctd_key_of_keyval(keyval) == CTD_KEY_CHARACTER ||
         ctd_key_of_keyval(keyval) == CTD_KEY_SPACE)) return FALSE;
    // The character the key types, which is what a text field wants and what
    // an arrow key does not have. gdk_keyval_to_unicode answers 0 for a key
    // that types nothing, and that is the empty string here.
    char typed[8];
    guint32 point = gdk_keyval_to_unicode(keyval);
    int written = point ? g_unichar_to_utf8((gunichar)point, typed) : 0;
    typed[written] = '\0';
    ctd_raise_key(CTD_EV_KEY_DOWN, GTK_WIDGET(data), ctd_key_of_keyval(keyval),
                  typed, ctd_modifiers_of(state));
    (void)keys;
    // FALSE, so the key goes on to the control. Claiming it would stop a text
    // field from receiving what was typed into it.
    return FALSE;
}

static void ctd_on_key_released(GtkEventControllerKey *keys, guint keyval,
                                guint code, GdkModifierType state,
                                gpointer data) {
    (void)code; (void)keys;
    char typed[8];
    guint32 point = gdk_keyval_to_unicode(keyval);
    int written = point ? g_unichar_to_utf8((gunichar)point, typed) : 0;
    typed[written] = '\0';
    ctd_raise_key(CTD_EV_KEY_UP, GTK_WIDGET(data), ctd_key_of_keyval(keyval),
                  typed, ctd_modifiers_of(state));
}

static void ctd_on_focus_in(GtkEventControllerFocus *focus, gpointer data) {
    (void)focus;
    ctd_canvas_im_focus(GTK_WIDGET(data), TRUE);
    if (!ctd_listening(CTD_EV_FOCUS)) return;
    ctd_handle target = ctd_handle_for_widget(GTK_WIDGET(data));
    if (target) ctd_emit(CTD_EV_FOCUS, target, 0, 0);
}

static void ctd_on_focus_out(GtkEventControllerFocus *focus, gpointer data) {
    (void)focus;
    ctd_canvas_im_focus(GTK_WIDGET(data), FALSE);
    if (!ctd_listening(CTD_EV_BLUR)) return;
    ctd_handle target = ctd_handle_for_widget(GTK_WIDGET(data));
    if (target) ctd_emit(CTD_EV_BLUR, target, 0, 0);
}

// Called from ctd_track, the one place every control passes through.
//
// The handle is stored on the widget *before* the controllers are attached, so
// a signal that arrives during construction — GTK emits focus signals while a
// window is being built — already has something to report.
void ctd_input_attach(gpointer object, ctd_handle handle) {
    if (!GTK_IS_WIDGET(object)) return;
    GtkWidget *widget = GTK_WIDGET(object);
    g_object_set_data(G_OBJECT(widget), CTD_HANDLE_KEY, GSIZE_TO_POINTER(handle));

    GtkGesture *click = gtk_gesture_click_new();
    // Every button, not only the first: a right-click is a pointer event like
    // any other, and a gesture that listened to button 1 alone would make
    // CTD_BTN_RIGHT unreachable.
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), 0);
    g_signal_connect(click, "pressed", G_CALLBACK(ctd_on_pressed), widget);
    g_signal_connect(click, "released", G_CALLBACK(ctd_on_released), widget);
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(click));
    g_object_set_data(G_OBJECT(widget), CTD_CLICK_KEY, click);

    GtkEventController *motion = gtk_event_controller_motion_new();
    g_signal_connect(motion, "motion", G_CALLBACK(ctd_on_motion), widget);
    g_signal_connect(motion, "leave", G_CALLBACK(ctd_on_motion_leave), widget);
    gtk_widget_add_controller(widget, motion);
    g_object_set_data(G_OBJECT(widget), CTD_MOTION_KEY, motion);
    g_object_set_data_full(G_OBJECT(widget), CTD_SCROLL_POINT_KEY, g_new0(double, 2), g_free);
    GtkEventController *scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES);
    g_signal_connect(scroll, "scroll", G_CALLBACK(ctd_on_scroll), widget);
    gtk_widget_add_controller(widget, scroll);

    GtkEventController *keys = gtk_event_controller_key_new();
    g_signal_connect(keys, "key-pressed", G_CALLBACK(ctd_on_key_pressed), widget);
    g_signal_connect(keys, "key-released", G_CALLBACK(ctd_on_key_released), widget);
    gtk_widget_add_controller(widget, keys);
    g_object_set_data(G_OBJECT(widget), CTD_KEYS_KEY, keys);

    GtkEventController *focus = gtk_event_controller_focus_new();
    g_signal_connect(focus, "enter", G_CALLBACK(ctd_on_focus_in), widget);
    g_signal_connect(focus, "leave", G_CALLBACK(ctd_on_focus_out), widget);
    gtk_widget_add_controller(widget, focus);
}

// ---------------------------------------------------------------------- focus

// Whether the keyboard is pointing at this control, or at something inside it.
//
// **A GtkEntry never has the focus itself.** It is a wrapper around a GtkText,
// and GTK4 delegates focus to that child — `gtk_widget_get_focusable` answers
// FALSE for the entry and `gtk_window_get_focus` answers the GtkText. A host
// comparing the two directly would say no for the one control that most
// obviously has the keyboard, which is the same trap AppKit sets with its
// field editor and is answered here the same way: the control a program knows
// is the nearest ancestor cortado built.
static int ctd_holds_focus(GtkWidget *view) {
    GtkRoot *root = gtk_widget_get_root(view);
    if (!root || !GTK_IS_WINDOW(root)) return 0;
    GtkWidget *holder = gtk_window_get_focus(GTK_WINDOW(root));
    while (holder) {
        if (holder == view) return 1;
        holder = gtk_widget_get_parent(holder);
    }
    return 0;
}

ctd_status ctd_widget_focus(ctd_handle widget) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WIDGET(object)) return CTD_ERR_UNSUPPORTED;
    GtkWidget *view = GTK_WIDGET(object);
    GtkRoot *root = gtk_widget_get_root(view);
    // A widget in no window would be given the keyboard by a window it does
    // not belong to, and the program would have moved focus onto something
    // that is not on screen.
    if (!root || !GTK_IS_WINDOW(root)) return CTD_ERR_STATE;
    // grab_focus rather than a focusable check and a set: it is the call that
    // knows about delegation, so it reaches the GtkText inside an entry and
    // answers FALSE for a label, which is the refusal a program wants.
    if (!gtk_widget_grab_focus(view)) return CTD_ERR_UNSUPPORTED;
    return ctd_holds_focus(view) ? CTD_OK : CTD_ERR_UNSUPPORTED;
}

int32_t ctd_widget_focused(ctd_handle widget) {
    gpointer object = ctd_resolve(widget);
    if (!GTK_IS_WIDGET(object)) return 0;
    // "The control this window would type into", not "the control the user is
    // typing into" — gtk_widget_has_focus asks the second, and answers no for
    // every window that is not on screen, which would make this unanswerable
    // in a headless run.
    return ctd_holds_focus(GTK_WIDGET(object));
}

// ----------------------------------------------------------------- synthesis

ctd_status ctd_widget_synth_pointer(ctd_handle widget, int32_t what,
                                    double x, double y, int32_t button) {
    if (what != CTD_EV_POINTER_DOWN && what != CTD_EV_POINTER_UP &&
        what != CTD_EV_POINTER_MOVE) return CTD_ERR_RANGE;
    if (button < CTD_BTN_LEFT || button > CTD_BTN_MIDDLE) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WIDGET(object)) return CTD_ERR_UNSUPPORTED;
    GtkWidget *view = GTK_WIDGET(object);

    // The controller's own signal, because GdkEvent cannot be built from out
    // here. It runs cortado's handler — the same one a real click runs — which
    // is the whole point: raising the event straight from here would prove
    // that this function works and nothing about the path a click takes.
    //
    // The button has to be handed over beside the signal. The handler reads it
    // from the event GDK is dispatching, and in a synthesised call there is
    // none, so it would answer 0 and every click would look like a left one.
    if (what == CTD_EV_POINTER_MOVE) {
        GtkEventController *motion =
            g_object_get_data(G_OBJECT(view), CTD_MOTION_KEY);
        if (!motion) return CTD_ERR_UNSUPPORTED;
        g_signal_emit_by_name(motion, "motion", x, y);
        return CTD_OK;
    }
    GtkGesture *click = g_object_get_data(G_OBJECT(view), CTD_CLICK_KEY);
    if (!click) return CTD_ERR_UNSUPPORTED;
    g_synth_button = button;
    g_signal_emit_by_name(click, what == CTD_EV_POINTER_DOWN ? "pressed" : "released",
                          1, x, y);
    g_synth_button = 0;
    return CTD_OK;
}

ctd_status ctd_widget_synth_key(ctd_handle widget, int32_t what, int32_t key,
                                const char *text, int32_t len,
                                uint32_t modifiers) {
    if (what != CTD_EV_KEY_DOWN && what != CTD_EV_KEY_UP) return CTD_ERR_RANGE;
    if (key < 0 || key >= CTD_KEY_COUNT) return CTD_ERR_RANGE;
    if (ctd_has_nul(text, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WIDGET(object)) return CTD_ERR_UNSUPPORTED;
    GtkWidget *view = GTK_WIDGET(object);
    GtkRoot *root = gtk_widget_get_root(view);
    if (!root || !GTK_IS_WINDOW(root)) return CTD_ERR_STATE;
    // A key goes to whoever has the keyboard, so the control is given it
    // first — refused if it cannot take it, which is the same refusal a
    // program asking would get.
    if (!ctd_holds_focus(view)) {
        ctd_status moved = ctd_widget_focus(widget);
        if (moved != CTD_OK) return moved;
    }

    GtkEventController *keys = g_object_get_data(G_OBJECT(view), CTD_KEYS_KEY);
    if (!keys) return CTD_ERR_UNSUPPORTED;

    // A keyval and nothing else, because that is all a real key event carries:
    // the handler derives the character from it with gdk_keyval_to_unicode,
    // and going in through the same door is what makes this a test of the
    // handler rather than of this function. A named key has a keyval of its
    // own; a character key's is whatever the text says it typed.
    guint keyval = ctd_keyval_of_key(key);
    if (!keyval && text && len > 0) {
        char first[8];
        int32_t room = len < (int32_t)sizeof first - 1 ? len : (int32_t)sizeof first - 1;
        memcpy(first, text, (size_t)room);
        first[room] = '\0';
        keyval = gdk_unicode_to_keyval((guint32)g_utf8_get_char(first));
    }
    if (what == CTD_EV_KEY_DOWN) {
        gboolean claimed = FALSE;
        g_signal_emit_by_name(keys, "key-pressed", keyval, 0u,
                              ctd_state_of(modifiers), &claimed);
    } else {
        g_signal_emit_by_name(keys, "key-released", keyval, 0u,
                              ctd_state_of(modifiers));
    }
    return CTD_OK;
}
