// The handle table, and the two conversions every entry point does.
//
// A widget is ref-sunk the moment the table takes it: GTK hands back a
// floating reference, and a container would otherwise claim the one the table
// is holding.

#include "internal.h"

GObject  *g_object[CTD_SLOTS];
uint32_t  g_generation[CTD_SLOTS];
int32_t   g_kind[CTD_SLOTS];
int32_t   g_icon[CTD_SLOTS];  // CTD_P_ICON, per slot; see icon.*
// How far the table has ever been filled. Shared, because anything that has to
// walk every live slot — the frame clock, the animations — needs to know where
// to stop, and slot 0 is reserved for "no handle".
uint32_t  g_used;

ctd_event_fn g_sink;
void        *g_sink_context;
int32_t      g_role = CTD_ROLE_GUI;
int          g_started;

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

void ctd_give_back(uint32_t slot) {
    // Whatever the slot was doing stops being done. A frame clock left running
    // on a recycled slot would tick for whichever widget lands there next, and
    // an animation of a widget that has gone would report, four seconds later,
    // that it finished.
    ctd_clock_forget(slot);
    ctd_anim_forget(slot);
    if (g_recycled_count < CTD_SLOTS) g_recycled[g_recycled_count++] = slot;
}

// Takes a handle out of the table.
//
// The slot is cleared, its generation is bumped so that every copy of the
// handle answers CTD_ERR_STALE from here on rather than reaching whatever
// lands in the slot next, and the table gives up its own reference. Every
// release path in this host ends here, so there is one description of what
// releasing means and not one per kind of thing.
void ctd_untrack(ctd_handle handle) {
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    if (slot == 0 || slot > g_used) return;
    if (g_generation[slot] != (uint32_t)(handle >> 32)) return;
    GObject *object = g_object[slot];
    g_object[slot] = NULL;
    g_kind[slot] = -1;
    g_icon[slot] = CTD_ICON_NONE;
    g_generation[slot] = g_generation[slot] + 1;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    ctd_give_back(slot);
    if (object) g_object_unref(object);
}

ctd_handle ctd_track(gpointer object, int32_t kind) {
    uint32_t slot = ctd_take_slot();
    if (slot == 0) return 0;
    g_object[slot] = G_OBJECT(g_object_ref_sink(object));
    g_kind[slot] = kind;
    g_icon[slot] = CTD_ICON_NONE;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    ctd_handle handle = ((uint64_t)g_generation[slot] << 32) | slot;
    // GTK4 has no application-wide hook for input: a controller belongs to a
    // widget. So every control gets its set here, which is the one place every
    // control passes through — and the handle goes on the widget first, so a
    // signal that arrives while the window is still being built already has
    // something to report.
    ctd_input_attach(object, handle);
    return handle;
}

gpointer ctd_resolve(ctd_handle handle) {
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    uint32_t generation = (uint32_t)(handle >> 32);
    if (slot == 0 || slot > g_used) return NULL;
    if (g_generation[slot] != generation) return NULL;
    return g_object[slot];
}

int32_t ctd_slot_kind(ctd_handle handle) {
    if (!ctd_resolve(handle)) return -1;
    return g_kind[(uint32_t)(handle & 0xffffffffu)];
}

ctd_handle ctd_handle_of(gpointer object) {
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

void ctd_tag(GtkWidget *widget) {
    g_object_set_data(G_OBJECT(widget), CTD_TAG, GINT_TO_POINTER(1));
}

gboolean ctd_is_ours(GtkWidget *widget) {
    return g_object_get_data(G_OBJECT(widget), CTD_TAG) != NULL;
}

int32_t ctd_copy_out(const char *text, char *out, int32_t cap) {
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
char *ctd_dup(const char *utf8, int32_t len) {
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
int ctd_has_nul(const char *utf8, int32_t len) {
    if (!utf8 || len <= 0) return 0;
    for (int32_t i = 0; i < len; i++) {
        if (utf8[i] == 0) return 1;
    }
    return 0;
}
