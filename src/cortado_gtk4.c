// The Linux host: real GTK4 objects behind the same flat C ABI.
//
// The third implementation of `src/cortado_host.h`, and the first that is
// neither Apple's nor written in Objective-C. That matters more than it
// sounds: AppKit and UIKit share a great deal of shape — reference counting,
// a view tree of `NSView`/`UIView`, a target/action dispatch — and a header
// that only those two had implemented could have been accidentally shaped by
// them. GTK is a different object system (GObject), a different memory model
// (floating references), a different event model (signals) and a different
// layout model (containers that negotiate size). If the ABI fits here too, it
// is a contract rather than a description.
//
// Coordinates are top-left with y downward, which is already GTK's convention,
// so there is no flip.
//
// ## Frames, and GTK's size negotiation
//
// cortado computes every frame itself and tells the platform where things go.
// GTK does not usually work that way: a container asks each child how big it
// wants to be and allocates accordingly. `GtkFixed` is the one that does —
// `gtk_fixed_put` places a child at a point — and `gtk_widget_set_size_request`
// asks for a size.
//
// That request is a **minimum**, not an exact size, and GTK will not allocate
// a widget smaller than it says it needs. A 20-point button really does come
// out taller here. `tests/roles.out` carries no frames for exactly this reason
// — a control is allowed to refuse the frame it is given, which iOS
// established and this confirms from a second direction — so the portable
// golden holds regardless, and `tests/shelf.out` records what each platform
// actually did.

#include <gtk/gtk.h>
#include <string.h>
#include <stdio.h>
#include "cortado_host.h"
#include "cortado_rules.h"

// ---------------------------------------------------------------- the table

enum { CTD_SLOTS = 8192 };

static GObject  *g_object[CTD_SLOTS];
static uint32_t  g_generation[CTD_SLOTS];
static int32_t   g_kind[CTD_SLOTS];
static uint32_t  g_used;

static ctd_event_fn g_sink;
static void        *g_sink_context;
static int32_t      g_role = CTD_ROLE_GUI;
static int          g_started;

// GTK hands out *floating* references: a freshly made widget owns itself until
// something sinks it. The table takes a real reference with g_object_ref_sink,
// so a widget cortado is holding cannot be finalized by a parent letting go —
// which is the GTK4 hazard the ABI's own comment about `ctd_view_move_child`
// already names.

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

static ctd_handle ctd_track(gpointer object, int32_t kind) {
    uint32_t slot = ctd_take_slot();
    if (slot == 0) return 0;
    g_object[slot] = G_OBJECT(g_object_ref_sink(object));
    g_kind[slot] = kind;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    return ((uint64_t)g_generation[slot] << 32) | slot;
}

static gpointer ctd_resolve(ctd_handle handle) {
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    uint32_t generation = (uint32_t)(handle >> 32);
    if (slot == 0 || slot > g_used) return NULL;
    if (g_generation[slot] != generation) return NULL;
    return g_object[slot];
}

static int32_t ctd_slot_kind(ctd_handle handle) {
    if (!ctd_resolve(handle)) return -1;
    return g_kind[(uint32_t)(handle & 0xffffffffu)];
}

static ctd_handle ctd_handle_of(gpointer object) {
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_object[slot] == G_OBJECT(object))
            return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

// Only widgets cortado made are part of cortado's tree. GTK installs children
// of its own inside almost everything — a GtkScale has a trough and a slider,
// a GtkDropDown has a button and a popover — and their structure is not API.
#define CTD_TAG "cortado"

static void ctd_tag(GtkWidget *widget) {
    g_object_set_data(G_OBJECT(widget), CTD_TAG, GINT_TO_POINTER(1));
}

static gboolean ctd_is_ours(GtkWidget *widget) {
    return g_object_get_data(G_OBJECT(widget), CTD_TAG) != NULL;
}

static int32_t ctd_copy_out(const char *text, char *out, int32_t cap) {
    if (!text) text = "";
    int32_t needed = (int32_t)strlen(text);
    if (out && cap > 0) {
        int32_t n = needed < cap ? needed : cap;
        if (n > 0) memcpy(out, text, (size_t)n);
    }
    return needed;
}

// A NUL-terminated copy of a length-delimited string, for the GTK calls that
// take a `const char *`. The ABI never NUL-terminates, on purpose, so the
// terminator is added here and nowhere above.
static char *ctd_dup(const char *utf8, int32_t len) {
    if (len < 0) len = 0;
    char *copy = g_malloc((size_t)len + 1);
    if (len > 0) memcpy(copy, utf8, (size_t)len);
    copy[len] = 0;
    return copy;
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

// ------------------------------------------------------------------- events

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

static void ctd_on_signal(GtkWidget *widget, gpointer user) {
    (void)widget;
    ctd_emit_control((ctd_handle)(uintptr_t)user);
}

// ---------------------------------------------------------------- lifecycle

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

// -------------------------------------------------------------------- surfaces

ctd_handle ctd_surface_new(double width, double height) {
    GtkWidget *window = gtk_window_new();
    gtk_window_set_default_size(GTK_WINDOW(window), (int)width, (int)height);
    return ctd_track(window, -1);
}

ctd_status ctd_surface_set_title(ctd_handle surface, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    char *title = ctd_dup(utf8, len);
    gtk_window_set_title(GTK_WINDOW(object), title);
    g_free(title);
    return CTD_OK;
}

int32_t ctd_surface_title(ctd_handle surface, char *out, int32_t cap) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    return ctd_copy_out(gtk_window_get_title(GTK_WINDOW(object)), out, cap);
}

ctd_status ctd_surface_set_root(ctd_handle surface, ctd_handle root) {
    gpointer object = ctd_resolve(surface);
    gpointer view = ctd_resolve(root);
    if (!object || !view) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    gtk_window_set_child(GTK_WINDOW(object), GTK_WIDGET(view));
    return CTD_OK;
}

ctd_handle ctd_surface_root(ctd_handle surface) {
    gpointer object = ctd_resolve(surface);
    if (!object || !GTK_IS_WINDOW(object)) return 0;
    GtkWidget *child = gtk_window_get_child(GTK_WINDOW(object));
    return child ? ctd_handle_of(child) : 0;
}

ctd_status ctd_surface_content_size(ctd_handle surface, double *out_size) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    int width = gtk_widget_get_width(GTK_WIDGET(object));
    int height = gtk_widget_get_height(GTK_WIDGET(object));
    // A window that has not been presented has no allocation yet; the default
    // size is what it will get, and is the honest answer until it does.
    if (width <= 0 || height <= 0) {
        gtk_window_get_default_size(GTK_WINDOW(object), &width, &height);
    }
    if (out_size) {
        out_size[0] = (double)width;
        out_size[1] = (double)height;
    }
    return CTD_OK;
}

ctd_status ctd_surface_show(ctd_handle surface) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    if (g_role == CTD_ROLE_HEADLESS) return CTD_OK;
    gtk_window_present(GTK_WINDOW(object));
    return CTD_OK;
}

ctd_status ctd_surface_close(ctd_handle surface) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    gtk_window_close(GTK_WINDOW(object));
    return CTD_OK;
}

int32_t ctd_surface_visible(ctd_handle surface) {
    gpointer object = ctd_resolve(surface);
    if (!object || !GTK_IS_WINDOW(object)) return 0;
    return gtk_widget_get_visible(GTK_WIDGET(object)) ? 1 : 0;
}

// --------------------------------------------------------------------- widgets

// GTK4 has no radio button class any more: a radio is a GtkCheckButton whose
// group another check button joins. Grouping is by parent here, the same rule
// the macOS and iOS hosts follow, and it is applied when the child is added.

ctd_handle ctd_widget_new(int32_t kind) {
    GtkWidget *widget = NULL;
    switch (kind) {
        case CTD_W_CONTAINER:
            // GtkFixed is the one container that places children where it is
            // told. Every other GTK container negotiates, which is the right
            // model for GTK and the wrong one for a framework that has already
            // computed every frame.
            widget = gtk_fixed_new();
            break;
        case CTD_W_LABEL:
            widget = gtk_label_new("");
            gtk_label_set_xalign(GTK_LABEL(widget), 0.0f);
            break;
        case CTD_W_BUTTON:
            widget = gtk_button_new_with_label("");
            break;
        case CTD_W_TEXT_FIELD:
            widget = gtk_entry_new();
            break;
        case CTD_W_CHECK_BOX:
            widget = gtk_check_button_new();
            break;
        case CTD_W_RADIO_BUTTON:
            widget = gtk_check_button_new();
            break;
        case CTD_W_IMAGE_VIEW:
            widget = gtk_picture_new();
            break;
        case CTD_W_SLIDER:
            widget = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL,
                                              0.0, 1.0, 0.01);
            gtk_scale_set_draw_value(GTK_SCALE(widget), FALSE);
            break;
        case CTD_W_PROGRESS_BAR:
            widget = gtk_progress_bar_new();
            break;
        case CTD_W_SEPARATOR:
            widget = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
            break;
        case CTD_W_TEXT_AREA: {
            GtkWidget *scroller = gtk_scrolled_window_new();
            GtkWidget *text = gtk_text_view_new();
            gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(text), GTK_WRAP_WORD);
            gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), text);
            widget = scroller;
            break;
        }
        case CTD_W_COMBO_BOX: {
            GtkStringList *items = gtk_string_list_new(NULL);
            widget = gtk_drop_down_new(G_LIST_MODEL(items), NULL);
            break;
        }
        case CTD_W_SCROLL_VIEW: {
            GtkWidget *scroller = gtk_scrolled_window_new();
            GtkWidget *content = gtk_fixed_new();
            ctd_tag(content);
            gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), content);
            widget = scroller;
            break;
        }
        default:
            return 0;
    }
    ctd_tag(widget);
    ctd_handle handle = ctd_track(widget, kind);

    // One signal per kind, chosen so the event the control raises is the one
    // it actually is.
    switch (kind) {
        case CTD_W_BUTTON:
            g_signal_connect(widget, "clicked", G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON:
            g_signal_connect(widget, "toggled", G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        case CTD_W_SLIDER:
            g_signal_connect(widget, "value-changed", G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        case CTD_W_TEXT_FIELD:
            g_signal_connect(widget, "activate", G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        case CTD_W_COMBO_BOX:
            // A GtkDropDown has no "changed": the selection is a property, and
            // a property notification is how GObject spells this.
            g_signal_connect(widget, "notify::selected",
                             G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        default: break;
    }
    return handle;
}

int32_t ctd_widget_kind(ctd_handle widget) { return ctd_slot_kind(widget); }

int32_t ctd_widget_alive(ctd_handle widget) { return ctd_resolve(widget) ? 1 : 0; }

ctd_status ctd_widget_release(ctd_handle widget) {
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(object));
    if (parent && GTK_IS_FIXED(parent)) {
        gtk_fixed_remove(GTK_FIXED(parent), GTK_WIDGET(object));
    } else if (parent) {
        gtk_widget_unparent(GTK_WIDGET(object));
    }
    g_object_unref(g_object[slot]);
    g_object[slot] = NULL;
    g_generation[slot] = g_generation[slot] + 1;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    ctd_give_back(slot);
    return CTD_OK;
}

// ------------------------------------------------------------------------ tree

// Where a widget's children go. A scroll view's live in its GtkFixed child; a
// text area's scrolled window holds text and can hold nothing else.
static GtkFixed *ctd_container_of(gpointer object) {
    if (GTK_IS_FIXED(object)) return GTK_FIXED(object);
    if (GTK_IS_SCROLLED_WINDOW(object)) {
        GtkWidget *inner = gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(object));
        if (inner && GTK_IS_FIXED(inner)) return GTK_FIXED(inner);
        return NULL;
    }
    if (GTK_IS_WINDOW(object)) {
        GtkWidget *child = gtk_window_get_child(GTK_WINDOW(object));
        if (child && GTK_IS_FIXED(child)) return GTK_FIXED(child);
        return NULL;
    }
    return NULL;
}

// cortado's children of a container, in order, skipping anything GTK put there
// itself.
static GPtrArray *ctd_children(GtkFixed *container) {
    GPtrArray *ours = g_ptr_array_new();
    for (GtkWidget *child = gtk_widget_get_first_child(GTK_WIDGET(container));
         child != NULL;
         child = gtk_widget_get_next_sibling(child)) {
        if (ctd_is_ours(child)) g_ptr_array_add(ours, child);
    }
    return ours;
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    gpointer owner = ctd_resolve(parent);
    gpointer view = ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    GtkFixed *container = ctd_container_of(owner);
    if (!container) return CTD_ERR_KIND;

    gtk_fixed_put(container, GTK_WIDGET(view), 0, 0);

    // A radio button joins the group of the first radio already under this
    // parent. GTK4 has no radio class; a group is a chain of check buttons,
    // and "the same parent is one group" is the rule every host here follows.
    if (ctd_slot_kind(child) == CTD_W_RADIO_BUTTON) {
        GPtrArray *siblings = ctd_children(container);
        for (guint i = 0; i < siblings->len; i++) {
            GtkWidget *other = g_ptr_array_index(siblings, i);
            if (other == GTK_WIDGET(view)) continue;
            if (ctd_slot_kind(ctd_handle_of(other)) != CTD_W_RADIO_BUTTON) continue;
            gtk_check_button_set_group(GTK_CHECK_BUTTON(view),
                                       GTK_CHECK_BUTTON(other));
            break;
        }
        g_ptr_array_free(siblings, TRUE);
    }

    // GtkFixed has no insert-at-index, so a child that belongs earlier is put
    // in front of the one it should precede. `index` past the end appends,
    // which is what -1 already means.
    GPtrArray *ours = ctd_children(container);
    if (index >= 0 && index < (int32_t)ours->len - 1) {
        GtkWidget *before = g_ptr_array_index(ours, (guint)index);
        gtk_widget_insert_before(GTK_WIDGET(view), GTK_WIDGET(container), before);
    }
    g_ptr_array_free(ours, TRUE);
    return CTD_OK;
}

ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child) {
    gpointer owner = ctd_resolve(parent);
    gpointer view = ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    GtkFixed *container = ctd_container_of(owner);
    if (!container) return CTD_ERR_KIND;
    if (gtk_widget_get_parent(GTK_WIDGET(view)) != GTK_WIDGET(container))
        return CTD_ERR_RANGE;
    // The table's reference is what keeps this alive: GtkFixed drops its own
    // on removal, and on a widget nobody else names that would be the last.
    gtk_fixed_remove(container, GTK_WIDGET(view));
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    gpointer owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    GtkFixed *container = ctd_container_of(owner);
    if (!container) return CTD_ERR_KIND;
    GPtrArray *ours = ctd_children(container);
    int32_t count = (int32_t)ours->len;
    if (from < 0 || from >= count || to < 0 || to >= count) {
        g_ptr_array_free(ours, TRUE);
        return CTD_ERR_RANGE;
    }
    if (from == to) { g_ptr_array_free(ours, TRUE); return CTD_OK; }

    GtkWidget *moving = g_ptr_array_index(ours, (guint)from);
    // Reparenting, not remove-and-add: GTK4 finalizes a widget the moment its
    // last reference drops on unparent, which is the hazard
    // `ctd_view_move_child` exists to keep out of the layer above. The table
    // holds a reference so it could not happen here, and this is still one
    // operation because it is one intent.
    if (to >= count - 1) {
        gtk_widget_insert_after(moving, GTK_WIDGET(container),
                                g_ptr_array_index(ours, (guint)(count - 1)));
    } else {
        GtkWidget *before = g_ptr_array_index(ours, (guint)(to > from ? to : to));
        if (before != moving)
            gtk_widget_insert_before(moving, GTK_WIDGET(container), before);
    }
    g_ptr_array_free(ours, TRUE);
    return CTD_OK;
}

ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out) {
    gpointer owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    GtkFixed *container = ctd_container_of(owner);
    if (!container) {
        // A control that cannot hold children has none, which is an answer and
        // not a refusal: a tree walk asks this of every node.
        if (out) *out = 0;
        return CTD_OK;
    }
    GPtrArray *ours = ctd_children(container);
    if (out) *out = (int32_t)ours->len;
    g_ptr_array_free(ours, TRUE);
    return CTD_OK;
}

ctd_handle ctd_view_child_at(ctd_handle parent, int32_t index) {
    gpointer owner = ctd_resolve(parent);
    if (!owner) return 0;
    GtkFixed *container = ctd_container_of(owner);
    if (!container) return 0;
    GPtrArray *ours = ctd_children(container);
    ctd_handle found = 0;
    if (index >= 0 && index < (int32_t)ours->len)
        found = ctd_handle_of(g_ptr_array_index(ours, (guint)index));
    g_ptr_array_free(ours, TRUE);
    return found;
}

ctd_handle ctd_view_parent(ctd_handle child) {
    gpointer view = ctd_resolve(child);
    if (!view) return 0;
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(view));
    while (parent && !ctd_is_ours(parent)) {
        parent = gtk_widget_get_parent(parent);
    }
    return parent ? ctd_handle_of(parent) : 0;
}

// -------------------------------------------------------------------- geometry

ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height) {
    gpointer view = ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    // Two calls, because GTK splits what every other platform joins: position
    // belongs to the parent's layout and size is a request the child makes.
    // The request is a *minimum* — GTK will not allocate a widget smaller than
    // it says it needs — which is why `tests/roles.out` carries no frames.
    gtk_widget_set_size_request(GTK_WIDGET(view), (int)width, (int)height);
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(view));
    if (parent && GTK_IS_FIXED(parent)) {
        gtk_fixed_move(GTK_FIXED(parent), GTK_WIDGET(view), x, y);
    }
    return CTD_OK;
}

ctd_status ctd_view_frame(ctd_handle widget, double *out_frame) {
    gpointer view = ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    double x = 0.0, y = 0.0;
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(view));
    if (parent && GTK_IS_FIXED(parent)) {
        gtk_fixed_get_child_position(GTK_FIXED(parent), GTK_WIDGET(view), &x, &y);
    }
    int width = gtk_widget_get_width(GTK_WIDGET(view));
    int height = gtk_widget_get_height(GTK_WIDGET(view));
    // Before the first allocation a widget has no size. What was asked for is
    // the honest answer until GTK has laid out.
    if (width <= 0 || height <= 0) {
        gtk_widget_get_size_request(GTK_WIDGET(view), &width, &height);
        if (width < 0) width = 0;
        if (height < 0) height = 0;
    }
    if (out_frame) {
        out_frame[0] = x;
        out_frame[1] = y;
        out_frame[2] = (double)width;
        out_frame[3] = (double)height;
    }
    return CTD_OK;
}

ctd_status ctd_view_measure(ctd_handle widget, double avail_width, double avail_height,
                            double *out_size) {
    gpointer view = ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    int minimum = 0, natural = 0, ignored = 0;
    gtk_widget_measure(GTK_WIDGET(view), GTK_ORIENTATION_HORIZONTAL, -1,
                       &minimum, &natural, &ignored, &ignored);
    double width = (double)natural;
    if (avail_width >= 0.0 && width > avail_width) width = avail_width;
    // Height for the width just decided: a wrapping label is shorter when it
    // is wider, and asking for both independently gets that wrong.
    gtk_widget_measure(GTK_WIDGET(view), GTK_ORIENTATION_VERTICAL, (int)width,
                       &minimum, &natural, &ignored, &ignored);
    double height = (double)natural;
    if (avail_height >= 0.0 && height > avail_height) height = avail_height;
    if (out_size) {
        out_size[0] = width;
        out_size[1] = height;
    }
    return CTD_OK;
}

// ------------------------------------------------------------------ properties

// The text view inside a text area's scrolled window, or NULL.
static GtkTextView *ctd_text_view(gpointer object) {
    if (!GTK_IS_SCROLLED_WINDOW(object)) return NULL;
    GtkWidget *inner = gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(object));
    return (inner && GTK_IS_TEXT_VIEW(inner)) ? GTK_TEXT_VIEW(inner) : NULL;
}

ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_ENABLED:
            // Every GtkWidget is sensitive, containers included — so unlike
            // the Apple hosts there is nothing here the object system refuses,
            // and the rule has to be applied rather than inherited.
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            gtk_widget_set_sensitive(GTK_WIDGET(object), value ? TRUE : FALSE);
            return CTD_OK;
        case CTD_P_HIDDEN:
            gtk_widget_set_visible(GTK_WIDGET(object), value ? FALSE : TRUE);
            return CTD_OK;
        case CTD_P_CHECKED:
            if (!GTK_IS_CHECK_BUTTON(object)) return CTD_ERR_KIND;
            // GTK4's check button has a real third state, which is why cortado
            // can promise one: `inconsistent` is exactly AppKit's mixed.
            gtk_check_button_set_inconsistent(GTK_CHECK_BUTTON(object), value == 2);
            if (value != 2)
                gtk_check_button_set_active(GTK_CHECK_BUTTON(object), value == 1);
            return CTD_OK;
        case CTD_P_EDITABLE: {
            GtkTextView *text = ctd_text_view(object);
            if (text) {
                gtk_text_view_set_editable(text, value ? TRUE : FALSE);
                return CTD_OK;
            }
            if (GTK_IS_EDITABLE(object)) {
                gtk_editable_set_editable(GTK_EDITABLE(object), value ? TRUE : FALSE);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        }
        case CTD_P_ALIGNMENT: {
            float alignment = value == 1 ? 0.5f : value == 2 ? 1.0f : 0.0f;
            if (GTK_IS_LABEL(object)) {
                gtk_label_set_xalign(GTK_LABEL(object), alignment);
                return CTD_OK;
            }
            if (GTK_IS_ENTRY(object)) {
                gtk_entry_set_alignment(GTK_ENTRY(object), alignment);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        }
        case CTD_P_SELECTED: {
            if (!GTK_IS_DROP_DOWN(object)) return CTD_ERR_KIND;
            GtkDropDown *menu = GTK_DROP_DOWN(object);
            GListModel *items = gtk_drop_down_get_model(menu);
            guint count = items ? g_list_model_get_n_items(items) : 0;
            if (value < 0) {
                gtk_drop_down_set_selected(menu, GTK_INVALID_LIST_POSITION);
                return CTD_OK;
            }
            if ((guint)value >= count) return CTD_ERR_RANGE;
            gtk_drop_down_set_selected(menu, (guint)value);
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE:
            if (!GTK_IS_PROGRESS_BAR(object)) return CTD_ERR_KIND;
            if (value) gtk_progress_bar_pulse(GTK_PROGRESS_BAR(object));
            return CTD_OK;
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    int64_t value = 0;
    switch (key) {
        case CTD_P_ENABLED:
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = gtk_widget_get_sensitive(GTK_WIDGET(object)) ? 1 : 0;
            break;
        case CTD_P_HIDDEN:
            value = gtk_widget_get_visible(GTK_WIDGET(object)) ? 0 : 1;
            break;
        case CTD_P_CHECKED:
            if (!GTK_IS_CHECK_BUTTON(object)) return CTD_ERR_KIND;
            if (gtk_check_button_get_inconsistent(GTK_CHECK_BUTTON(object))) {
                value = 2;
            } else {
                value = gtk_check_button_get_active(GTK_CHECK_BUTTON(object)) ? 1 : 0;
            }
            break;
        case CTD_P_EDITABLE: {
            GtkTextView *text = ctd_text_view(object);
            if (text) { value = gtk_text_view_get_editable(text) ? 1 : 0; break; }
            if (!GTK_IS_EDITABLE(object)) return CTD_ERR_KIND;
            value = gtk_editable_get_editable(GTK_EDITABLE(object)) ? 1 : 0;
            break;
        }
        case CTD_P_SELECTED: {
            if (!GTK_IS_DROP_DOWN(object)) return CTD_ERR_KIND;
            guint chosen = gtk_drop_down_get_selected(GTK_DROP_DOWN(object));
            value = chosen == GTK_INVALID_LIST_POSITION ? -1 : (int64_t)chosen;
            break;
        }
        case CTD_P_INDETERMINATE:
            if (!GTK_IS_PROGRESS_BAR(object)) return CTD_ERR_KIND;
            value = 0;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// A progress bar in GTK is a fraction from 0 to 1 with no range of its own, so
// the range is kept here and the fraction computed — the same shape the iOS
// host needs for the same reason.
static double g_progress_min[CTD_SLOTS];
static double g_progress_max[CTD_SLOTS];

// Font sizes that already have a CSS class on the display, so a second widget
// asking for the same size installs nothing.
static GHashTable *g_font_classes;

ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    switch (key) {
        case CTD_P_FONT_SIZE: {
            // GTK sets fonts with CSS, and since GTK 4.10 a style context is
            // not something a caller may add a provider to. The supported
            // shape is a provider for the whole display and a class on the
            // widget, so each size gets one class — installed once, reused by
            // every widget that asks for it.
            int points = (int)value;
            if (points <= 0) return CTD_ERR_RANGE;
            char class_name[32];
            snprintf(class_name, sizeof class_name, "ctd-fs-%d", points);
            if (!g_font_classes) g_font_classes = g_hash_table_new(NULL, NULL);
            if (!g_hash_table_contains(g_font_classes, GINT_TO_POINTER(points))) {
                char css[128];
                snprintf(css, sizeof css, ".%s { font-size: %dpt; }",
                         class_name, points);
                GtkCssProvider *provider = gtk_css_provider_new();
                gtk_css_provider_load_from_string(provider, css);
                gtk_style_context_add_provider_for_display(
                    gdk_display_get_default(), GTK_STYLE_PROVIDER(provider),
                    GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
                g_object_unref(provider);
                g_hash_table_add(g_font_classes, GINT_TO_POINTER(points));
            }
            gtk_widget_add_css_class(GTK_WIDGET(object), class_name);
            return CTD_OK;
        }
        case CTD_P_MIN:
            if (GTK_IS_RANGE(object)) {
                GtkAdjustment *a = gtk_range_get_adjustment(GTK_RANGE(object));
                gtk_adjustment_set_lower(a, value);
                return CTD_OK;
            }
            if (GTK_IS_PROGRESS_BAR(object)) { g_progress_min[slot] = value; return CTD_OK; }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if (GTK_IS_RANGE(object)) {
                GtkAdjustment *a = gtk_range_get_adjustment(GTK_RANGE(object));
                gtk_adjustment_set_upper(a, value);
                return CTD_OK;
            }
            if (GTK_IS_PROGRESS_BAR(object)) { g_progress_max[slot] = value; return CTD_OK; }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if (GTK_IS_RANGE(object)) {
                gtk_range_set_value(GTK_RANGE(object), value);
                return CTD_OK;
            }
            if (GTK_IS_PROGRESS_BAR(object)) {
                double span = g_progress_max[slot] - g_progress_min[slot];
                double fraction = span > 0.0 ? (value - g_progress_min[slot]) / span : 0.0;
                if (fraction < 0.0) fraction = 0.0;
                if (fraction > 1.0) fraction = 1.0;
                gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(object), fraction);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_STEP:
            if (!GTK_IS_RANGE(object)) return CTD_ERR_KIND;
            gtk_range_set_increments(GTK_RANGE(object), value, value);
            gtk_range_set_round_digits(GTK_RANGE(object), value >= 1.0 ? 0 : 2);
            return CTD_OK;
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    double value = 0.0;
    switch (key) {
        case CTD_P_FONT_SIZE: {
            PangoContext *context = gtk_widget_get_pango_context(GTK_WIDGET(object));
            const PangoFontDescription *font = pango_context_get_font_description(context);
            value = (double)pango_font_description_get_size(font) / PANGO_SCALE;
            break;
        }
        case CTD_P_MIN:
            if (GTK_IS_RANGE(object)) {
                value = gtk_adjustment_get_lower(gtk_range_get_adjustment(GTK_RANGE(object)));
            } else if (GTK_IS_PROGRESS_BAR(object)) { value = g_progress_min[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_MAX:
            if (GTK_IS_RANGE(object)) {
                value = gtk_adjustment_get_upper(gtk_range_get_adjustment(GTK_RANGE(object)));
            } else if (GTK_IS_PROGRESS_BAR(object)) { value = g_progress_max[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_VALUE:
            if (GTK_IS_RANGE(object)) {
                value = gtk_range_get_value(GTK_RANGE(object));
            } else if (GTK_IS_PROGRESS_BAR(object)) {
                double span = g_progress_max[slot] - g_progress_min[slot];
                value = g_progress_min[slot] +
                        span * gtk_progress_bar_get_fraction(GTK_PROGRESS_BAR(object));
            } else return CTD_ERR_KIND;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// ----------------------------------------------------------------------- text

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    char *text = ctd_dup(utf8, len);
    ctd_status answer = CTD_OK;
    GtkTextView *view = ctd_text_view(object);
    if (view) {
        gtk_text_buffer_set_text(gtk_text_view_get_buffer(view), text, -1);
    } else if (GTK_IS_LABEL(object)) {
        gtk_label_set_text(GTK_LABEL(object), text);
    } else if (GTK_IS_BUTTON(object) && !GTK_IS_CHECK_BUTTON(object)) {
        gtk_button_set_label(GTK_BUTTON(object), text);
    } else if (GTK_IS_CHECK_BUTTON(object)) {
        gtk_check_button_set_label(GTK_CHECK_BUTTON(object), text);
    } else if (GTK_IS_EDITABLE(object)) {
        gtk_editable_set_text(GTK_EDITABLE(object), text);
    } else {
        answer = CTD_ERR_KIND;
    }
    g_free(text);
    return answer;
}

int32_t ctd_get_text(ctd_handle widget, char *out, int32_t cap) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkTextView *view = ctd_text_view(object);
    if (view) {
        GtkTextBuffer *buffer = gtk_text_view_get_buffer(view);
        GtkTextIter first, last;
        gtk_text_buffer_get_bounds(buffer, &first, &last);
        char *text = gtk_text_buffer_get_text(buffer, &first, &last, FALSE);
        int32_t needed = ctd_copy_out(text, out, cap);
        g_free(text);
        return needed;
    }
    if (GTK_IS_LABEL(object))
        return ctd_copy_out(gtk_label_get_text(GTK_LABEL(object)), out, cap);
    if (GTK_IS_CHECK_BUTTON(object))
        return ctd_copy_out(gtk_check_button_get_label(GTK_CHECK_BUTTON(object)), out, cap);
    if (GTK_IS_BUTTON(object))
        return ctd_copy_out(gtk_button_get_label(GTK_BUTTON(object)), out, cap);
    if (GTK_IS_EDITABLE(object))
        return ctd_copy_out(gtk_editable_get_text(GTK_EDITABLE(object)), out, cap);
    if (GTK_IS_DROP_DOWN(object)) {
        GtkDropDown *menu = GTK_DROP_DOWN(object);
        guint chosen = gtk_drop_down_get_selected(menu);
        GtkStringList *items = GTK_STRING_LIST(gtk_drop_down_get_model(menu));
        if (items && chosen != GTK_INVALID_LIST_POSITION)
            return ctd_copy_out(gtk_string_list_get_string(items, chosen), out, cap);
    }
    return ctd_copy_out("", out, cap);
}

// ------------------------------------------------------------------ item lists

static GtkStringList *ctd_item_list(gpointer object) {
    if (!GTK_IS_DROP_DOWN(object)) return NULL;
    GListModel *model = gtk_drop_down_get_model(GTK_DROP_DOWN(object));
    return model && GTK_IS_STRING_LIST(model) ? GTK_STRING_LIST(model) : NULL;
}

ctd_status ctd_items_clear(ctd_handle widget) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkStringList *items = ctd_item_list(object);
    if (!items) return CTD_ERR_KIND;
    guint count = g_list_model_get_n_items(G_LIST_MODEL(items));
    if (count > 0) gtk_string_list_splice(items, 0, count, NULL);
    return CTD_OK;
}

ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkStringList *items = ctd_item_list(object);
    if (!items) return CTD_ERR_KIND;
    if (len < 0) return CTD_ERR_RANGE;
    char *text = ctd_dup(utf8, len);
    gtk_string_list_append(items, text);
    g_free(text);
    return CTD_OK;
}

ctd_status ctd_items_count(ctd_handle widget, int32_t *out) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkStringList *items = ctd_item_list(object);
    if (!items) return CTD_ERR_KIND;
    if (out) *out = (int32_t)g_list_model_get_n_items(G_LIST_MODEL(items));
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkStringList *items = ctd_item_list(object);
    if (!items) return CTD_ERR_KIND;
    guint count = g_list_model_get_n_items(G_LIST_MODEL(items));
    if (index < 0 || (guint)index >= count) return CTD_ERR_RANGE;
    return ctd_copy_out(gtk_string_list_get_string(items, (guint)index), out, cap);
}

// ---------------------------------------------------------------------- menus
//
// GTK4 removed the menu-bar widget from the application: a menu is a
// GMenuModel shown by a GtkPopoverMenuBar that lives *inside a window*. So
// `CTD_CAP_MENU_BAR` answers no and `CTD_CAP_WINDOW_MENU` answers yes, and the
// menu calls build a real GMenu that a window can show.
//
// Roles are placed by the platform here as everywhere else, but GTK's idea of
// "placed" is thinner than macOS's: there is no responder chain to hand Cut
// and Copy to, so a role that the platform would handle becomes an ordinary
// command reported to the application. That is a real difference and it is why
// `CommandRole.is_platform_handled` exists rather than being assumed.

static const char *ctd_role_title(int32_t role, const char *fallback) {
    switch (role) {
        case CTD_CMD_ABOUT:       return "About";
        case CTD_CMD_PREFERENCES: return "Preferences";
        case CTD_CMD_QUIT:        return "Quit";
        case CTD_CMD_HIDE:        return "Hide";
        case CTD_CMD_UNDO:        return "Undo";
        case CTD_CMD_REDO:        return "Redo";
        case CTD_CMD_CUT:         return "Cut";
        case CTD_CMD_COPY:        return "Copy";
        case CTD_CMD_PASTE:       return "Paste";
        case CTD_CMD_SELECT_ALL:  return "Select All";
        case CTD_CMD_CLOSE:       return "Close";
        case CTD_CMD_MINIMIZE:    return "Minimize";
        case CTD_CMD_FULLSCREEN:  return "Fullscreen";
        default:                  return fallback;
    }
}

// `mod` is Control here, not Command: that is the whole reason a shortcut is
// written portably rather than as a literal key.
static const char *ctd_role_key(int32_t role, const char *fallback) {
    switch (role) {
        case CTD_CMD_PREFERENCES: return "mod+,";
        case CTD_CMD_QUIT:        return "mod+q";
        case CTD_CMD_UNDO:        return "mod+z";
        case CTD_CMD_REDO:        return "mod+shift+z";
        case CTD_CMD_CUT:         return "mod+x";
        case CTD_CMD_COPY:        return "mod+c";
        case CTD_CMD_PASTE:       return "mod+v";
        case CTD_CMD_SELECT_ALL:  return "mod+a";
        case CTD_CMD_CLOSE:       return "mod+w";
        case CTD_CMD_MINIMIZE:    return "mod+m";
        case CTD_CMD_FULLSCREEN:  return "F11";
        default:                  return fallback;
    }
}

// A menu item's token and its shortcut, kept beside the GMenu because a
// GMenuItem is write-only once added — GTK gives no way to read one back.
typedef struct {
    int64_t token;
    char   *title;
    char   *key;
    int     separator;
    int     enabled;
} CtdCommand;

typedef struct {
    GMenu  *model;
    GArray *commands;   // CtdCommand
} CtdMenu;

static GHashTable *g_menus;   // ctd_handle -> CtdMenu*

static CtdMenu *ctd_menu_of(ctd_handle handle) {
    if (!g_menus) return NULL;
    return g_hash_table_lookup(g_menus, GINT_TO_POINTER((int)(handle & 0xffffffffu)));
}

ctd_handle ctd_menu_new(const char *title, int32_t len) {
    GMenu *model = g_menu_new();
    ctd_handle handle = ctd_track(model, -1);
    if (!handle) { g_object_unref(model); return 0; }
    if (!g_menus) g_menus = g_hash_table_new(g_direct_hash, g_direct_equal);
    CtdMenu *menu = g_new0(CtdMenu, 1);
    menu->model = model;
    menu->commands = g_array_new(FALSE, TRUE, sizeof(CtdCommand));
    g_hash_table_insert(g_menus, GINT_TO_POINTER((int)(handle & 0xffffffffu)), menu);
    char *name = ctd_dup(title, len);
    g_object_set_data_full(G_OBJECT(model), "cortado-title", name, g_free);
    return handle;
}

ctd_status ctd_menu_add_item(ctd_handle handle, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token) {
    if (ctd_has_nul(title, title_len) || ctd_has_nul(key, key_len))
        return CTD_ERR_RANGE;
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (role < 0 || role > CTD_CMD_FULLSCREEN) return CTD_ERR_RANGE;

    char *asked_title = ctd_dup(title, title_len);
    char *asked_key = ctd_dup(key, key_len);
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.token = token;
    command.title = g_strdup(ctd_role_title(role, asked_title));
    command.key = g_strdup(ctd_role_key(role, asked_key));
    command.enabled = 1;
    g_free(asked_title);
    g_free(asked_key);

    char action[64];
    snprintf(action, sizeof action, "app.cortado%lld", (long long)command.token);
    GMenuItem *item = g_menu_item_new(command.title, action);
    g_menu_append_item(menu->model, item);
    g_object_unref(item);
    g_array_append_val(menu->commands, command);
    return CTD_OK;
}

ctd_status ctd_menu_add_separator(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // GTK spells a separator as a section boundary rather than an item, and
    // the item list here mirrors that with a marker so indices line up with
    // what a caller added.
    GMenu *section = g_menu_new();
    g_menu_append_section(menu->model, NULL, G_MENU_MODEL(section));
    g_object_unref(section);
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.separator = 1;
    command.title = g_strdup("-");
    command.key = g_strdup("");
    g_array_append_val(menu->commands, command);
    return CTD_OK;
}

ctd_status ctd_menu_add_submenu(ctd_handle handle, ctd_handle child) {
    CtdMenu *menu = ctd_menu_of(handle);
    CtdMenu *inner = ctd_menu_of(child);
    if (!menu || !inner) return CTD_ERR_STALE;
    const char *title = g_object_get_data(G_OBJECT(inner->model), "cortado-title");
    g_menu_append_submenu(menu->model, title ? title : "",
                          G_MENU_MODEL(inner->model));
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.title = g_strdup(title ? title : "");
    command.key = g_strdup("");
    command.enabled = 1;
    g_array_append_val(menu->commands, command);
    return CTD_OK;
}

ctd_status ctd_menu_item_count(ctd_handle handle, int32_t *out) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = (int32_t)menu->commands->len;
    return CTD_OK;
}

int32_t ctd_menu_item_title(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || (guint)index >= menu->commands->len) return CTD_ERR_RANGE;
    return ctd_copy_out(g_array_index(menu->commands, CtdCommand, index).title, out, cap);
}

int32_t ctd_menu_item_key(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || (guint)index >= menu->commands->len) return CTD_ERR_RANGE;
    return ctd_copy_out(g_array_index(menu->commands, CtdCommand, index).key, out, cap);
}

ctd_status ctd_menu_set_bar(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // There is no application-wide menu bar in GTK4 to install one into, which
    // `ctd_capability(CTD_CAP_MENU_BAR)` already says. A window menu is the
    // GTK shape and is reached by putting a GtkPopoverMenuBar in the window.
    return CTD_ERR_UNSUPPORTED;
}

// Finds a command by token, this menu's own only — a submenu is a separate
// handle here, unlike AppKit where one NSMenu owns the tree.
static CtdCommand *ctd_find_command(CtdMenu *menu, int64_t token) {
    for (guint i = 0; i < menu->commands->len; i++) {
        CtdCommand *command = &g_array_index(menu->commands, CtdCommand, i);
        if (!command->separator && command->token == token) return command;
    }
    return NULL;
}

ctd_status ctd_menu_set_enabled(ctd_handle handle, int64_t token, int32_t on) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    command->enabled = on ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_menu_invoke(ctd_handle handle, int64_t token) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    if (!command->enabled) return CTD_ERR_PLATFORM;
    ctd_emit(CTD_EV_COMMAND, 0, 0, token);
    return CTD_OK;
}

// -------------------------------------------------------------------- dialogs

typedef struct {
    int64_t token;
    int     kind;
} CtdDialog;

static gboolean ctd_answer_dialog(gpointer data) {
    CtdDialog *request = data;
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = CTD_EV_POST;
    event.token = request->token;
    event.index = (request->kind == CTD_DLG_MESSAGE ||
                   request->kind == CTD_DLG_CONFIRM) ? 0 : 1;
    if (g_sink) g_sink(g_sink_context, &event);
    g_free(request);
    return G_SOURCE_REMOVE;
}

ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token) {
    (void)title; (void)title_len; (void)body; (void)body_len;
    if (kind < CTD_DLG_MESSAGE || kind > CTD_DLG_SAVE) return CTD_ERR_RANGE;
    if (parent && !ctd_resolve(parent)) return CTD_ERR_STALE;
    // GTK4's dialogs are GtkAlertDialog and GtkFileDialog, both asynchronous
    // with a GAsyncReadyCallback. Wiring them is real work that has not been
    // done; what is here keeps the contract that matters — **a dialog always
    // answers** — by replying on the next loop turn with the default button,
    // or a cancel for a file dialog. A dialog that answered nothing would
    // leave a caller waiting on a token forever, which is worse than a
    // refusal it can see.
    CtdDialog *request = g_new0(CtdDialog, 1);
    request->token = token;
    request->kind = kind;
    g_idle_add(ctd_answer_dialog, request);
    return CTD_OK;
}

// ----------------------------------------------------------------- appearance

int32_t ctd_appearance(void) {
    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) return 0;
    gboolean dark = FALSE;
    g_object_get(settings, "gtk-application-prefer-dark-theme", &dark, NULL);
    return dark ? 1 : 0;
}

ctd_status ctd_surface_scale(ctd_handle surface, double *out) {
    double scale = 1.0;
    if (surface) {
        gpointer object = ctd_resolve(surface);
        if (!object) return CTD_ERR_STALE;
        if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
        scale = (double)gtk_widget_get_scale_factor(GTK_WIDGET(object));
    }
    if (scale <= 0.0) scale = 1.0;
    if (out) *out = scale;
    return CTD_OK;
}

// ---------------------------------------------------------------------- fonts

// GTK's font comes from the theme as one description string — "Cantarell 11" —
// so the family and the size are pulled out of the same place.
static void ctd_theme_font(char *family, size_t cap, double *size) {
    g_strlcpy(family, "Sans", cap);
    *size = 11.0;
    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) return;
    char *description = NULL;
    g_object_get(settings, "gtk-font-name", &description, NULL);
    if (!description) return;
    PangoFontDescription *font = pango_font_description_from_string(description);
    if (font) {
        const char *name = pango_font_description_get_family(font);
        if (name) g_strlcpy(family, name, cap);
        int points = pango_font_description_get_size(font);
        if (points > 0) *size = (double)points / PANGO_SCALE;
        pango_font_description_free(font);
    }
    g_free(description);
}

int32_t ctd_font_family(int32_t role, char *out, int32_t cap) {
    if (role < CTD_FONT_BODY || role > CTD_FONT_MONO) return CTD_ERR_RANGE;
    if (role == CTD_FONT_MONO) return ctd_copy_out("Monospace", out, cap);
    char family[128];
    double size = 0.0;
    ctd_theme_font(family, sizeof family, &size);
    return ctd_copy_out(family, out, cap);
}

ctd_status ctd_font_size(int32_t role, double *out) {
    if (role < CTD_FONT_BODY || role > CTD_FONT_MONO) return CTD_ERR_RANGE;
    char family[128];
    double size = 0.0;
    ctd_theme_font(family, sizeof family, &size);
    if (role == CTD_FONT_HEADING) size += 4.0;
    if (role == CTD_FONT_CAPTION) size -= 2.0;
    if (out) *out = size;
    return CTD_OK;
}

// ------------------------------------------------------------- introspection

int32_t ctd_native_class(ctd_handle widget, char *out, int32_t cap) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    return ctd_copy_out(G_OBJECT_TYPE_NAME(object), out, cap);
}

int32_t ctd_a11y_role(ctd_handle widget, char *out, int32_t cap) {
    if (!ctd_resolve(widget)) return CTD_ERR_STALE;
    const char *role = "group";
    switch (ctd_slot_kind(widget)) {
        case CTD_W_CONTAINER:    role = "group";       break;
        case CTD_W_LABEL:        role = "text";        break;
        case CTD_W_BUTTON:       role = "button";      break;
        case CTD_W_TEXT_FIELD:   role = "textbox";     break;
        case CTD_W_CHECK_BOX:    role = "checkbox";    break;
        case CTD_W_IMAGE_VIEW:   role = "image";       break;
        case CTD_W_SLIDER:       role = "slider";      break;
        case CTD_W_PROGRESS_BAR: role = "progressbar"; break;
        case CTD_W_SEPARATOR:    role = "separator";   break;
        case CTD_W_TEXT_AREA:    role = "textbox";     break;
        case CTD_W_COMBO_BOX:    role = "combobox";    break;
        case CTD_W_SCROLL_VIEW:  role = "scrollarea";  break;
        case CTD_W_RADIO_BUTTON: role = "radio";       break;
        default:                 role = "group";       break;
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
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (GTK_IS_BUTTON(object) && !GTK_IS_CHECK_BUTTON(object)) {
        // Through GTK's own activation, not by calling the handler: the same
        // path a real click takes.
        g_signal_emit_by_name(object, "clicked");
        return CTD_OK;
    }
    if (GTK_IS_WIDGET(object) && gtk_widget_activate(GTK_WIDGET(object)))
        return CTD_OK;
    return CTD_ERR_KIND;
}

ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    // The setters below are the ordinary ones, and the signal they raise is
    // the platform's own — GTK notifies on a property change whoever made it,
    // which is exactly what "as a user would" means here.
    if (GTK_IS_RANGE(object)) {
        gtk_range_set_value(GTK_RANGE(object), value);
        return CTD_OK;
    }
    if (GTK_IS_CHECK_BUTTON(object)) {
        gtk_check_button_set_inconsistent(GTK_CHECK_BUTTON(object), index == 2);
        if (index != 2)
            gtk_check_button_set_active(GTK_CHECK_BUTTON(object), index == 1);
        return CTD_OK;
    }
    if (GTK_IS_DROP_DOWN(object)) return ctd_set_int(widget, CTD_P_SELECTED, index);
    return CTD_ERR_KIND;
}

ctd_status ctd_widget_synth_text(ctd_handle widget, const char *utf8, int32_t len) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkTextView *view = ctd_text_view(object);
    if (!view && !GTK_IS_EDITABLE(object)) return CTD_ERR_KIND;
    ctd_status wrote = ctd_set_text(widget, utf8, len);
    if (wrote != CTD_OK) return wrote;
    // A typed value is committed when the field is activated, which is the
    // signal a user's Return raises.
    if (GTK_IS_ENTRY(object)) g_signal_emit_by_name(object, "activate");
    return CTD_OK;
}
