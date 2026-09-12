// Starting GTK, stopping it, and turning a signal into an event.
//
// The one callback edge in the whole host is here: `g_sink` is a function
// pointer Beans registered at run time, and nothing in cortado's C half ever
// names a Beans symbol.

#include "internal.h"

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

// The same rule the other two hosts follow: a control that carries a value
// says the value changed; a control that is a command says it was activated.
int g_writing = 0;

static void ctd_emit_control(ctd_handle target) {
    if (!g_sink) return;
    // A write cortado is making on the program's behalf is not news. See
    // g_writing in internal.h.
    if (g_writing) return;
    gpointer object = ctd_resolve(target);
    if (!object) return;

    uint32_t kind = CTD_EV_ACTIVATE;
    int64_t index = 0;
    const char *text = NULL;

    switch (ctd_slot_kind(target)) {
        case CTD_W_SLIDER:
            kind = CTD_EV_VALUE_CHANGED;
            index = (int64_t)gtk_range_get_value(GTK_RANGE(object));
            break;
        case CTD_W_STEPPER:
            kind = CTD_EV_VALUE_CHANGED;
            index = (int64_t)gtk_spin_button_get_value(GTK_SPIN_BUTTON(object));
            break;
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON:
            kind = CTD_EV_VALUE_CHANGED;
            index = gtk_check_button_get_active(GTK_CHECK_BUTTON(object)) ? 1 : 0;
            break;
        case CTD_W_COMBO_BOX: {
            kind = CTD_EV_VALUE_CHANGED;
            GtkDropDown *menu = GTK_DROP_DOWN(object);
            index = (int64_t)gtk_drop_down_get_selected(menu);
            GtkStringList *items = GTK_STRING_LIST(gtk_drop_down_get_model(menu));
            if (items && index >= 0)
                text = gtk_string_list_get_string(items, (guint)index);
            break;
        }
        case CTD_W_SWITCH:
            kind = CTD_EV_VALUE_CHANGED;
            index = gtk_switch_get_active(GTK_SWITCH(object)) ? 1 : 0;
            break;
        case CTD_W_DISCLOSURE:
            kind = CTD_EV_VALUE_CHANGED;
            index = gtk_expander_get_expanded(GTK_EXPANDER(object)) ? 1 : 0;
            break;
        case CTD_W_DATE_PICKER:
            kind = CTD_EV_VALUE_CHANGED;
            index = (int64_t)ctd_calendar_seconds(GTK_CALENDAR(object));
            break;
        case CTD_W_COLOR_WELL: {
            kind = CTD_EV_VALUE_CHANGED;
            const GdkRGBA *shown =
                gtk_color_dialog_button_get_rgba(GTK_COLOR_DIALOG_BUTTON(object));
            index = shown ? ctd_color_pack(ctd_color_byte(shown->red),
                                           ctd_color_byte(shown->green),
                                           ctd_color_byte(shown->blue),
                                           ctd_color_byte(shown->alpha))
                          : 0;
            break;
        }
        case CTD_W_TEXT_FIELD:
        case CTD_W_SECURE_FIELD:
        case CTD_W_SEARCH_FIELD:
            kind = CTD_EV_TEXT_COMMIT;
            text = gtk_editable_get_text(GTK_EDITABLE(object));
            break;
        default: break;
    }

    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = kind;
    event.target = target;
    event.index = index;
    if (text) {
        event.text = text;
        event.text_len = (int32_t)strlen(text);
    }
    g_sink(g_sink_context, &event);
}

void ctd_on_signal(GtkWidget *widget, gpointer user) {
    (void)widget;
    ctd_emit_control((ctd_handle)(uintptr_t)user);
}

// The same, for the signals that carry a parameter.
//
// This is not a convenience. A "notify" closure is marshalled as
// callback(object, pspec, user_data), so a two-argument function connected to
// one receives the pspec where it expects its user data — and cortado passes
// the widget's handle as user data. The drop-down was connected that way and
// nothing noticed, because the only case in the suite that drives a control
// through a property notification is the one added to tests/events.b beside
// this change.
void ctd_on_notify(GObject *object, GParamSpec *pspec, gpointer user) {
    (void)object;
    (void)pspec;
    ctd_emit_control((ctd_handle)(uintptr_t)user);
}


uint32_t ctd_abi_version(void) { return CTD_ABI_VERSION; }

ctd_status ctd_init(uint32_t want_abi) {
    if (want_abi != CTD_ABI_VERSION) return CTD_ERR_ABI;
    if (g_started) return CTD_OK;
    // gtk_init aborts the process when there is no display, which would take a
    // headless test down with no message anybody can act on. The checked form
    // reports it, and the caller gets CTD_ERR_PLATFORM.
    if (!gtk_init_check()) return CTD_ERR_PLATFORM;
    g_started = 1;
    return CTD_OK;
}

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

static gboolean g_running;

void ctd_app_run(void) {
    if (g_role == CTD_ROLE_HEADLESS) return;
    g_running = TRUE;
    // GTK4 has no gtk_main. The loop is GLib's, and running it directly is
    // what an application that owns its own startup does — a GtkApplication
    // would take that ownership away and call back instead, which is the
    // shape iOS forces and the one every other platform here avoids.
    GMainContext *context = g_main_context_default();
    while (g_running) {
        g_main_context_iteration(context, TRUE);
    }
}

// Fires once, when the time is up.
static gboolean ctd_deadline_reached(gpointer data) {
    *(int *)data = 1;
    return G_SOURCE_REMOVE;
}

// The same loop, with a deadline.
//
// A one-shot source for the deadline and an otherwise ordinary iteration.
// Blocking properly rather than polling is the whole of it: this call exists
// to wait, and a wait that spins keeps the thing it is waiting for from
// getting any work done.
//
// Unlike ctd_app_run there is no headless check. Running the loop with nothing
// on screen is exactly what this is for — waiting for the platform is not the
// same as showing something to somebody.
ctd_status ctd_app_run_for(double seconds) {
    if (!g_started) return CTD_ERR_STATE;
    if (!(seconds >= 0.0)) return CTD_ERR_RANGE;
    GMainContext *context = g_main_context_default();
    int expired = 0;
    guint deadline = g_timeout_add((guint)(seconds * 1000.0),
                                   ctd_deadline_reached, &expired);
    g_running = TRUE;
    while (g_running && !expired) {
        g_main_context_iteration(context, TRUE);
    }
    g_running = FALSE;
    if (!expired) g_source_remove(deadline);
    return CTD_OK;
}

void ctd_app_stop(void) {
    g_running = FALSE;
    // Wake the loop, which is otherwise blocked waiting for an event that may
    // never come.
    g_main_context_wakeup(g_main_context_default());
}

static gboolean ctd_deliver_post(gpointer data) {
    ctd_emit(CTD_EV_POST, 0, 0, (int64_t)(intptr_t)data);
    return G_SOURCE_REMOVE;
}

void ctd_post(int64_t token) {
    g_idle_add(ctd_deliver_post, (gpointer)(intptr_t)token);
}

int32_t ctd_capability(int32_t capability) {
    switch (capability) {
        // GTK4 removed the application menu bar as a widget: a menu belongs to
        // a GtkPopoverMenuBar inside a window, not to the application. So
        // cortado answers no to the application-wide one and yes to the
        // per-window one — which is exactly the distinction the two
        // capabilities were written for.
        case CTD_CAP_MENU_BAR:      return 0;
        case CTD_CAP_WINDOW_MENU:   return 1;
        case CTD_CAP_MULTI_SURFACE: return 1;
        case CTD_CAP_RESIZABLE:     return 1;
        case CTD_CAP_FILE_DIALOG:   return 1;
        case CTD_CAP_SNAPSHOT:      return 0;
        // Written out rather than left to the default, because "no GPU
        // host" is a decision this host is making and not a key nobody
        // has heard of. src/gtk4/gpu.c says what would have to land.
        case CTD_CAP_GPU:           return 0;
        default:                    return 0;
    }
}
