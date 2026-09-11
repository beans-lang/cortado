// The handle table, and UTF-8 to UTF-16 and back.
//
// Every string that crosses this host is converted, because Windows is UTF-16
// and the ABI is UTF-8. The `W` entry points are used everywhere.

#include "internal.h"

void     *g_object[CTD_SLOTS];      // HWND, or CtdMenu*
uint32_t  g_generation[CTD_SLOTS];
int32_t   g_kind[CTD_SLOTS];        // CTD_W_*, or -1 for a non-widget
int32_t   g_type[CTD_SLOTS];        // CTD_T_*
double    g_progress_min[CTD_SLOTS];
double    g_progress_max[CTD_SLOTS];
uint32_t  g_used;

ctd_event_fn g_sink;
void        *g_sink_context;
int32_t      g_role = CTD_ROLE_GUI;
int          g_started;
int          g_running;
HWND         g_limbo;               // where a parentless widget lives
HFONT        g_ui_font;
HACCEL       g_accelerators;
HWND         g_accel_window;

// Marks the windows cortado made. Win32 puts children inside controls of its
// own — a combo box owns a list, a scroll view owns its bars — and their
// structure is not API, so a tree walk must not see them.
// The content window inside a scroll view: cortado's, but not a handle of its
// own, so `ctd_view_parent` climbs past it to the scroll view itself.


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
    if (g_recycled_count < CTD_SLOTS) g_recycled[g_recycled_count++] = slot;
}

ctd_handle ctd_track(void *object, int32_t type, int32_t kind) {
    uint32_t slot = ctd_take_slot();
    if (slot == 0) return 0;
    g_object[slot] = object;
    g_type[slot] = type;
    g_kind[slot] = kind;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    return ((uint64_t)g_generation[slot] << 32) | slot;
}

uint32_t ctd_slot(ctd_handle handle) {
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    uint32_t generation = (uint32_t)(handle >> 32);
    if (slot == 0 || slot > g_used) return 0;
    if (g_generation[slot] != generation) return 0;
    if (g_type[slot] == CTD_T_FREE) return 0;
    return slot;
}

// The window a handle names, or NULL when the handle is stale or names a menu.
HWND ctd_window(ctd_handle handle) {
    uint32_t slot = ctd_slot(handle);
    if (!slot) return NULL;
    if (g_type[slot] != CTD_T_WIDGET && g_type[slot] != CTD_T_SURFACE) return NULL;
    return (HWND)g_object[slot];
}

int32_t ctd_slot_kind(ctd_handle handle) {
    uint32_t slot = ctd_slot(handle);
    return slot ? g_kind[slot] : -1;
}

ctd_handle ctd_handle_of(HWND window) {
    if (!window) return 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_type[slot] == CTD_T_FREE) continue;
        if (g_object[slot] == (void *)window)
            return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

BOOL ctd_is_ours(HWND window) {
    return window && GetPropW(window, CTD_TAG) != NULL;
}


// A NUL-terminated UTF-16 copy of a length-delimited UTF-8 string. The ABI
// never NUL-terminates, on purpose, so the terminator is added here and
// nowhere above. Freed with `free`.
WCHAR *ctd_wide(const char *utf8, int32_t len) {
    if (len < 0) len = 0;
    int wide_len = 0;
    if (len > 0) {
        wide_len = MultiByteToWideChar(CP_UTF8, 0, utf8, len, NULL, 0);
        if (wide_len < 0) wide_len = 0;
    }
    WCHAR *out = (WCHAR *)malloc(((size_t)wide_len + 1) * sizeof(WCHAR));
    if (!out) return NULL;
    if (wide_len > 0) MultiByteToWideChar(CP_UTF8, 0, utf8, len, out, wide_len);
    out[wide_len] = 0;
    return out;
}

// The two-call shape the ABI uses everywhere: answer the byte length the text
// needs, and write at most `cap` bytes. A caller asks with cap 0 first.
int32_t ctd_copy_out(const char *text, char *out, int32_t cap) {
    if (!text) text = "";
    int32_t needed = (int32_t)strlen(text);
    if (out && cap > 0) {
        int32_t n = needed < cap ? needed : cap;
        if (n > 0) memcpy(out, text, (size_t)n);
    }
    return needed;
}

int32_t ctd_copy_wide_out(const WCHAR *text, char *out, int32_t cap) {
    if (!text) return ctd_copy_out("", out, cap);
    int needed = WideCharToMultiByte(CP_UTF8, 0, text, -1, NULL, 0, NULL, NULL);
    if (needed <= 1) return ctd_copy_out("", out, cap);
    needed -= 1;                      // WideCharToMultiByte counts the NUL
    if (out && cap > 0) {
        // Converting straight into the caller's buffer would want room for a
        // terminator this ABI does not use, so it goes through a scratch copy.
        char *scratch = (char *)malloc((size_t)needed + 1);
        if (scratch) {
            WideCharToMultiByte(CP_UTF8, 0, text, -1, scratch, needed + 1, NULL, NULL);
            int32_t n = needed < cap ? needed : cap;
            if (n > 0) memcpy(out, scratch, (size_t)n);
            free(scratch);
        }
    }
    return (int32_t)needed;
}

// A window's title as UTF-8. `GetWindowTextW` is how every Win32 control
// carries its text: a button's label, a static's string, an edit's contents.
int32_t ctd_window_text_out(HWND window, char *out, int32_t cap) {
    int length = GetWindowTextLengthW(window);
    if (length <= 0) return ctd_copy_out("", out, cap);
    WCHAR *buffer = (WCHAR *)malloc(((size_t)length + 1) * sizeof(WCHAR));
    if (!buffer) return ctd_copy_out("", out, cap);
    GetWindowTextW(window, buffer, length + 1);
    int32_t needed = ctd_copy_wide_out(buffer, out, cap);
    free(buffer);
    return needed;
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
