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
static void ctd_emit_control(ctd_handle target) {
    if (!g_sink) return;
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
        case CTD_W_TEXT_FIELD:
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
        default:                    return 0;
    }
}
