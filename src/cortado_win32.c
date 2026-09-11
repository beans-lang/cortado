// The Windows host: real Win32 controls behind the same flat C ABI.
//
// The fourth implementation of `src/cortado_host.h`, and the one that is least
// like the other three. AppKit, UIKit and GTK all hand you an object with
// methods on it; Win32 hands you a window handle and a message queue. There is
// no object system here at all — a control is an `HWND`, its state is set by
// sending it a message, and it reports what happened by sending a message
// *back to its parent*. That last one is the structural difference that shapes
// this file: in the other three hosts a widget carries its own callback, and
// here a container has to recognise the events of children it did not create.
//
// Coordinates are top-left with y downward, which is already Windows'
// convention, so there is no flip.
//
// ## Three Win32 facts this file is built around
//
// **A child window needs a parent at creation.** `CreateWindowEx` with
// `WS_CHILD` will not make a parentless window. cortado creates widgets before
// it knows where they go, so every widget is born in a hidden holder window
// and `SetParent`ed when it is added. That is also how the platform's own
// dialog editors work.
//
// **Child order is z-order.** Win32 keeps no list of children; the order is
// the stacking order, walked with `GetWindow`. A new child goes on *top*, so
// appending means sending it to the bottom, and the enumeration is reversed to
// get insertion order back. Index 0 is the bottom of the stack — the child
// drawn first — which is what `addSubview:` and `gtk_fixed_put` also mean.
//
// **Notifications go to the parent, not to the control.** A button press
// arrives as `WM_COMMAND` on the parent's window procedure with the button's
// `HWND` in `lParam`; a trackbar move arrives as `WM_HSCROLL`. So the window
// procedure registered here is where every event is born, and it looks the
// sender up in the handle table to find out what it was.
//
// ## Text
//
// Windows is UTF-16 and this ABI is UTF-8, so every string crosses a
// conversion. The `W` entry points are used everywhere — the `A` ones would
// silently mangle anything outside the active code page, which is exactly the
// class of bug the ABI's "UTF-8 with an explicit length" rule exists to
// prevent.

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef WINVER
#define WINVER 0x0A00
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <commdlg.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "cortado_host.h"

// ---------------------------------------------------------------- the table

enum { CTD_SLOTS = 8192 };

// What a slot holds. A handle names a widget, a surface or a menu, and the
// three are not interchangeable: asking a menu for its frame has to be
// CTD_ERR_KIND and not a cast.
enum { CTD_T_FREE = 0, CTD_T_WIDGET, CTD_T_SURFACE, CTD_T_MENU };

typedef struct CtdMenu CtdMenu;

static void     *g_object[CTD_SLOTS];      // HWND, or CtdMenu*
static uint32_t  g_generation[CTD_SLOTS];
static int32_t   g_kind[CTD_SLOTS];        // CTD_W_*, or -1 for a non-widget
static int32_t   g_type[CTD_SLOTS];        // CTD_T_*
static double    g_progress_min[CTD_SLOTS];
static double    g_progress_max[CTD_SLOTS];
static uint32_t  g_used;

static ctd_event_fn g_sink;
static void        *g_sink_context;
static int32_t      g_role = CTD_ROLE_GUI;
static int          g_started;
static int          g_running;
static HWND         g_limbo;               // where a parentless widget lives
static HFONT        g_ui_font;
static HACCEL       g_accelerators;
static HWND         g_accel_window;

// Marks the windows cortado made. Win32 puts children inside controls of its
// own — a combo box owns a list, a scroll view owns its bars — and their
// structure is not API, so a tree walk must not see them.
#define CTD_TAG   L"cortado"
// The content window inside a scroll view: cortado's, but not a handle of its
// own, so `ctd_view_parent` climbs past it to the scroll view itself.
#define CTD_INNER L"cortado-inner"


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

static ctd_handle ctd_track(void *object, int32_t type, int32_t kind) {
    uint32_t slot = ctd_take_slot();
    if (slot == 0) return 0;
    g_object[slot] = object;
    g_type[slot] = type;
    g_kind[slot] = kind;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    return ((uint64_t)g_generation[slot] << 32) | slot;
}

static uint32_t ctd_slot(ctd_handle handle) {
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    uint32_t generation = (uint32_t)(handle >> 32);
    if (slot == 0 || slot > g_used) return 0;
    if (g_generation[slot] != generation) return 0;
    if (g_type[slot] == CTD_T_FREE) return 0;
    return slot;
}

// The window a handle names, or NULL when the handle is stale or names a menu.
static HWND ctd_window(ctd_handle handle) {
    uint32_t slot = ctd_slot(handle);
    if (!slot) return NULL;
    if (g_type[slot] != CTD_T_WIDGET && g_type[slot] != CTD_T_SURFACE) return NULL;
    return (HWND)g_object[slot];
}

static int32_t ctd_slot_kind(ctd_handle handle) {
    uint32_t slot = ctd_slot(handle);
    return slot ? g_kind[slot] : -1;
}

static ctd_handle ctd_handle_of(HWND window) {
    if (!window) return 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_type[slot] == CTD_T_FREE) continue;
        if (g_object[slot] == (void *)window)
            return ((uint64_t)g_generation[slot] << 32) | slot;
    }
    return 0;
}

static BOOL ctd_is_ours(HWND window) {
    return window && GetPropW(window, CTD_TAG) != NULL;
}

// ------------------------------------------------------------------ strings

// A NUL-terminated UTF-16 copy of a length-delimited UTF-8 string. The ABI
// never NUL-terminates, on purpose, so the terminator is added here and
// nowhere above. Freed with `free`.
static WCHAR *ctd_wide(const char *utf8, int32_t len) {
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
static int32_t ctd_copy_out(const char *text, char *out, int32_t cap) {
    if (!text) text = "";
    int32_t needed = (int32_t)strlen(text);
    if (out && cap > 0) {
        int32_t n = needed < cap ? needed : cap;
        if (n > 0) memcpy(out, text, (size_t)n);
    }
    return needed;
}

static int32_t ctd_copy_wide_out(const WCHAR *text, char *out, int32_t cap) {
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
static int32_t ctd_window_text_out(HWND window, char *out, int32_t cap) {
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

// The same rule the other three hosts follow: a control that carries a value
// says the value changed; a control that is a command says it was activated.
// Win32 makes this the host's job in a way the others do not — every one of
// these arrives on the parent as WM_COMMAND, so only the kind the control was
// created as can tell them apart.
static void ctd_emit_control(ctd_handle target) {
    if (!g_sink) return;
    HWND window = ctd_window(target);
    if (!window) return;

    uint32_t kind = CTD_EV_ACTIVATE;
    int64_t index = 0;
    char *text = NULL;
    int32_t text_len = 0;

    switch (ctd_slot_kind(target)) {
        case CTD_W_SLIDER:
            kind = CTD_EV_VALUE_CHANGED;
            index = (int64_t)SendMessageW(window, TBM_GETPOS, 0, 0);
            break;
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON: {
            kind = CTD_EV_VALUE_CHANGED;
            LRESULT state = SendMessageW(window, BM_GETCHECK, 0, 0);
            index = state == BST_CHECKED ? 1 : state == BST_INDETERMINATE ? 2 : 0;
            break;
        }
        case CTD_W_COMBO_BOX:
            kind = CTD_EV_VALUE_CHANGED;
            index = (int64_t)SendMessageW(window, CB_GETCURSEL, 0, 0);
            if (index == CB_ERR) index = -1;
            break;
        case CTD_W_TEXT_FIELD:
            kind = CTD_EV_TEXT_COMMIT;
            break;
        default: break;
    }

    // The control's text at the moment the event was raised, for the kinds
    // where that is the news. The bytes belong to the host and live only for
    // the duration of the call, which is what the header promises.
    if (kind == CTD_EV_VALUE_CHANGED || kind == CTD_EV_TEXT_COMMIT) {
        int32_t needed = ctd_get_text(target, NULL, 0);
        if (needed > 0) {
            text = (char *)malloc((size_t)needed);
            if (text) {
                ctd_get_text(target, text, needed);
                text_len = needed;
            }
        }
    }

    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = kind;
    event.target = target;
    event.index = index;
    event.text = text;
    event.text_len = text_len;
    g_sink(g_sink_context, &event);
    free(text);
}

// ------------------------------------------------------------------- menus

// A menu item's token and its portable shortcut, kept beside the HMENU. Win32
// can be asked for an item's display string but not for the spelling the
// caller used, and the display string carries the accelerator baked into it
// after a tab, so reading one back would answer something nobody wrote.
typedef struct {
    int64_t token;
    char   *title;      // UTF-8, as the platform ended up showing it
    char   *key;        // the portable spelling: "mod+z"
    int32_t role;
    int     separator;
    int     enabled;
    UINT    id;         // the 16-bit WM_COMMAND id, 0 for a separator
} CtdCommand;

struct CtdMenu {
    HMENU       handle;
    CtdCommand *commands;
    int32_t     count;
    int32_t     capacity;
    char       *title;
};

// Win32 identifies a menu item by a 16-bit number in WM_COMMAND, and cortado's
// token is 64 bits and the application's own, so the two are kept in a table.
typedef struct {
    UINT       id;
    ctd_handle menu;
    int64_t    token;
} CtdMenuId;

static CtdMenuId *g_menu_ids;
static int32_t    g_menu_id_count;
static int32_t    g_menu_id_capacity;
static UINT       g_next_menu_id = 0x1000;   // above the standard control ids

static CtdMenu *ctd_menu_of(ctd_handle handle) {
    uint32_t slot = ctd_slot(handle);
    if (!slot || g_type[slot] != CTD_T_MENU) return NULL;
    return (CtdMenu *)g_object[slot];
}

static UINT ctd_register_menu_id(ctd_handle menu, int64_t token) {
    if (g_menu_id_count == g_menu_id_capacity) {
        int32_t grown = g_menu_id_capacity ? g_menu_id_capacity * 2 : 32;
        CtdMenuId *bigger = (CtdMenuId *)realloc(g_menu_ids,
                                                 (size_t)grown * sizeof(CtdMenuId));
        if (!bigger) return 0;
        g_menu_ids = bigger;
        g_menu_id_capacity = grown;
    }
    UINT id = g_next_menu_id++;
    g_menu_ids[g_menu_id_count].id = id;
    g_menu_ids[g_menu_id_count].menu = menu;
    g_menu_ids[g_menu_id_count].token = token;
    g_menu_id_count++;
    return id;
}

static const CtdMenuId *ctd_menu_id(UINT id) {
    for (int32_t i = 0; i < g_menu_id_count; i++) {
        if (g_menu_ids[i].id == id) return &g_menu_ids[i];
    }
    return NULL;
}

static CtdCommand *ctd_command_by_id(UINT id) {
    const CtdMenuId *entry = ctd_menu_id(id);
    if (!entry) return NULL;
    CtdMenu *menu = ctd_menu_of(entry->menu);
    if (!menu) return NULL;
    for (int32_t i = 0; i < menu->count; i++) {
        if (menu->commands[i].id == id) return &menu->commands[i];
    }
    return NULL;
}

// Cut, Copy, Paste, Undo and Select All must reach the control that has focus,
// or the system's own text boxes stop working inside the application. On macOS
// that means a nil target so the responder chain finds the field; Windows has
// no responder chain, and the equivalent is sending the editing message to the
// focused window. Either way the application never hears about it, which is
// the point: it is the platform's command, not the program's.
static int ctd_dispatch_editing(int32_t role) {
    HWND focus = GetFocus();
    if (!focus) return 0;
    switch (role) {
        case CTD_CMD_CUT:   SendMessageW(focus, WM_CUT, 0, 0); return 1;
        case CTD_CMD_COPY:  SendMessageW(focus, WM_COPY, 0, 0); return 1;
        case CTD_CMD_PASTE: SendMessageW(focus, WM_PASTE, 0, 0); return 1;
        case CTD_CMD_UNDO:  SendMessageW(focus, WM_UNDO, 0, 0); return 1;
        case CTD_CMD_SELECT_ALL:
            SendMessageW(focus, EM_SETSEL, 0, (LPARAM)-1);
            return 1;
        default: return 0;
    }
}

// ------------------------------------------------------------ window classes

#define CTD_WM_POST   (WM_APP + 1)
#define CTD_WM_DIALOG (WM_APP + 2)

static const WCHAR *CTD_CLASS_VIEW    = L"cortado_view";
static const WCHAR *CTD_CLASS_SURFACE = L"cortado_surface";

static void ctd_run_dialog(void *request);

// Every notification a cortado container or surface can receive from a child.
// One function because a container and a top-level window see exactly the same
// messages from the controls inside them.
static LRESULT ctd_common_message(HWND window, UINT message,
                                  WPARAM wparam, LPARAM lparam, int *handled) {
    (void)window;   // every case here is about the sender, not the receiver
    *handled = 1;
    switch (message) {
        case WM_COMMAND:
            // A control notification carries the control's HWND; a menu
            // command carries zero. That is how Win32 tells them apart, and
            // there is no other way: the id space overlaps.
            if (lparam != 0) {
                HWND control = (HWND)lparam;
                WORD notification = HIWORD(wparam);
                ctd_handle target = ctd_handle_of(control);
                if (!target) break;
                switch (ctd_slot_kind(target)) {
                    case CTD_W_BUTTON:
                    case CTD_W_CHECK_BOX:
                    case CTD_W_RADIO_BUTTON:
                        if (notification == BN_CLICKED) ctd_emit_control(target);
                        break;
                    case CTD_W_COMBO_BOX:
                        if (notification == CBN_SELCHANGE) ctd_emit_control(target);
                        break;
                    case CTD_W_TEXT_FIELD:
                        // "Return pressed, or focus left the field" is what the
                        // header calls a commit. An edit box reports the second
                        // and not the first, so Return is caught in the
                        // subclass below and turned into the same event.
                        if (notification == EN_KILLFOCUS) ctd_emit_control(target);
                        break;
                    default: break;
                }
                return 0;
            } else {
                UINT id = LOWORD(wparam);
                CtdCommand *command = ctd_command_by_id(id);
                const CtdMenuId *entry = ctd_menu_id(id);
                if (command && entry) {
                    if (!command->enabled) return 0;
                    if (ctd_dispatch_editing(command->role)) return 0;
                    ctd_emit(CTD_EV_COMMAND, 0, 0, entry->token);
                    return 0;
                }
            }
            break;

        case WM_HSCROLL:
        case WM_VSCROLL:
            // A trackbar reports through the scroll messages rather than
            // WM_COMMAND, which is the one place Win32's "notify the parent"
            // rule uses a different message for the same idea.
            if (lparam != 0) {
                ctd_handle target = ctd_handle_of((HWND)lparam);
                if (target && ctd_slot_kind(target) == CTD_W_SLIDER) {
                    ctd_emit_control(target);
                    return 0;
                }
            }
            break;

        case CTD_WM_POST:
            ctd_emit(CTD_EV_POST, 0, 0, (int64_t)lparam);
            return 0;

        case CTD_WM_DIALOG:
            ctd_run_dialog((void *)lparam);
            return 0;

        default: break;
    }
    *handled = 0;
    return 0;
}

// A scroll view's content window, offset by however far it is scrolled.
static void ctd_scroll_to(HWND scroller, int which, int position) {
    HWND content = NULL;
    for (HWND child = GetWindow(scroller, GW_CHILD); child;
         child = GetWindow(child, GW_HWNDNEXT)) {
        if (GetPropW(child, CTD_INNER)) { content = child; break; }
    }
    if (!content) return;
    RECT frame;
    GetWindowRect(content, &frame);
    MapWindowPoints(HWND_DESKTOP, scroller, (POINT *)&frame, 2);
    int x = which == SB_HORZ ? -position : frame.left;
    int y = which == SB_HORZ ? frame.top : -position;
    SetWindowPos(content, NULL, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    SetScrollPos(scroller, which, position, TRUE);
}

static LRESULT CALLBACK ctd_view_proc(HWND window, UINT message,
                                      WPARAM wparam, LPARAM lparam) {
    // A scroll view is a view with bars, and the bar messages arrive with a
    // zero lParam — a trackbar's carry its HWND — so they are separated here
    // before the shared handler sees them.
    if ((message == WM_VSCROLL || message == WM_HSCROLL) && lparam == 0) {
        int which = message == WM_VSCROLL ? SB_VERT : SB_HORZ;
        SCROLLINFO info;
        memset(&info, 0, sizeof info);
        info.cbSize = sizeof info;
        info.fMask = SIF_ALL;
        GetScrollInfo(window, which, &info);
        int position = info.nPos;
        switch (LOWORD(wparam)) {
            case SB_LINEUP:   position -= 16; break;
            case SB_LINEDOWN: position += 16; break;
            case SB_PAGEUP:   position -= (int)info.nPage; break;
            case SB_PAGEDOWN: position += (int)info.nPage; break;
            case SB_THUMBTRACK:
            case SB_THUMBPOSITION: position = info.nTrackPos; break;
            default: break;
        }
        if (position < info.nMin) position = info.nMin;
        if (position > info.nMax) position = info.nMax;
        ctd_scroll_to(window, which, position);
        return 0;
    }
    int handled = 0;
    LRESULT answer = ctd_common_message(window, message, wparam, lparam, &handled);
    if (handled) return answer;
    // A child window draws nothing of its own; without this it shows whatever
    // was behind it.
    if (message == WM_ERASEBKGND) {
        HDC device = (HDC)wparam;
        RECT client;
        GetClientRect(window, &client);
        FillRect(device, &client, (HBRUSH)(COLOR_BTNFACE + 1));
        return 1;
    }
    if (message == WM_CTLCOLORSTATIC) {
        SetBkMode((HDC)wparam, TRANSPARENT);
        return (LRESULT)GetSysColorBrush(COLOR_BTNFACE);
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

static LRESULT CALLBACK ctd_surface_proc(HWND window, UINT message,
                                         WPARAM wparam, LPARAM lparam) {
    int handled = 0;
    LRESULT answer = ctd_common_message(window, message, wparam, lparam, &handled);
    if (handled) return answer;
    switch (message) {
        case WM_SIZE: {
            ctd_handle surface = ctd_handle_of(window);
            if (surface && g_sink) {
                ctd_event event;
                memset(&event, 0, sizeof event);
                event.kind = CTD_EV_SURFACE_RESIZED;
                event.target = surface;
                event.width = (double)LOWORD(lparam);
                event.height = (double)HIWORD(lparam);
                g_sink(g_sink_context, &event);
            }
            return 0;
        }
        case WM_CLOSE:
            ctd_emit(CTD_EV_SURFACE_CLOSE, ctd_handle_of(window), 0, 0);
            // The application decides whether a close request closes anything.
            // Destroying the window here would take the decision away, and the
            // handle would go stale under a program that meant to refuse.
            return 0;
        case WM_DPICHANGED: {
            ctd_handle surface = ctd_handle_of(window);
            const RECT *suggested = (const RECT *)lparam;
            SetWindowPos(window, NULL, suggested->left, suggested->top,
                         suggested->right - suggested->left,
                         suggested->bottom - suggested->top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            if (g_sink) {
                ctd_event event;
                memset(&event, 0, sizeof event);
                event.kind = CTD_EV_SCALE_CHANGED;
                event.target = surface;
                event.x = (double)LOWORD(wparam) / 96.0;
                g_sink(g_sink_context, &event);
            }
            return 0;
        }
        case WM_SETTINGCHANGE:
            // Light and dark live in a user setting, and this is the broadcast
            // that says one changed. Windows names the key rather than the
            // thing, so the value is read back rather than taken from here.
            if (lparam && wcscmp((const WCHAR *)lparam, L"ImmersiveColorSet") == 0)
                ctd_emit(CTD_EV_APPEARANCE, 0, ctd_appearance(), 0);
            return 0;
        default: break;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

// An edit box does not report Return; it reports losing focus. The header
// promises both, so Return is caught here and turned into the same commit.
static LRESULT CALLBACK ctd_edit_proc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
    (void)id; (void)data;
    if (message == WM_CHAR && wparam == VK_RETURN) {
        ctd_handle target = ctd_handle_of(window);
        if (target) ctd_emit_control(target);
        return 0;                 // and no beep, which is what the default does
    }
    if (message == WM_NCDESTROY) {
        RemoveWindowSubclass(window, ctd_edit_proc, 1);
    }
    return DefSubclassProc(window, message, wparam, lparam);
}

// ---------------------------------------------------------------- lifecycle

uint32_t ctd_abi_version(void) { return CTD_ABI_VERSION; }

static HFONT ctd_make_ui_font(void) {
    NONCLIENTMETRICSW metrics;
    memset(&metrics, 0, sizeof metrics);
    metrics.cbSize = sizeof metrics;
    if (SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof metrics, &metrics, 0))
        return CreateFontIndirectW(&metrics.lfMessageFont);
    return (HFONT)GetStockObject(DEFAULT_GUI_FONT);
}

ctd_status ctd_init(uint32_t want_abi) {
    if (want_abi != CTD_ABI_VERSION) return CTD_ERR_ABI;
    if (g_started) return CTD_OK;

    // Per-monitor v2 so `ctd_surface_scale` answers the display the window is
    // actually on. Without it Windows lies to the process and scales its
    // output, and every frame cortado computed would be stretched by the
    // system instead of laid out at the real size.
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    INITCOMMONCONTROLSEX controls;
    controls.dwSize = sizeof controls;
    controls.dwICC = ICC_STANDARD_CLASSES | ICC_BAR_CLASSES | ICC_PROGRESS_CLASS;
    if (!InitCommonControlsEx(&controls)) return CTD_ERR_PLATFORM;

    g_ui_font = ctd_make_ui_font();

    WNDCLASSEXW view;
    memset(&view, 0, sizeof view);
    view.cbSize = sizeof view;
    view.lpfnWndProc = ctd_view_proc;
    view.hInstance = GetModuleHandleW(NULL);
    view.hCursor = LoadCursorW(NULL, IDC_ARROW);
    view.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    view.lpszClassName = CTD_CLASS_VIEW;
    if (!RegisterClassExW(&view)) return CTD_ERR_PLATFORM;

    WNDCLASSEXW surface = view;
    surface.lpfnWndProc = ctd_surface_proc;
    surface.lpszClassName = CTD_CLASS_SURFACE;
    if (!RegisterClassExW(&surface)) return CTD_ERR_PLATFORM;

    // Where a widget lives before it is added to anything. `CreateWindowEx`
    // refuses to make a WS_CHILD window with no parent, and cortado creates a
    // control before it knows where the control goes.
    g_limbo = CreateWindowExW(0, CTD_CLASS_VIEW, L"", WS_POPUP,
                              0, 0, 0, 0, NULL, NULL,
                              GetModuleHandleW(NULL), NULL);
    if (!g_limbo) return CTD_ERR_PLATFORM;

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

void ctd_app_run(void) {
    if (g_role == CTD_ROLE_HEADLESS) return;
    g_running = 1;
    ctd_emit(CTD_EV_APP_LAUNCHED, 0, 0, 0);
    MSG message;
    while (g_running && GetMessageW(&message, NULL, 0, 0) > 0) {
        // Accelerators first, then dialog navigation: without the second, Tab
        // and the arrow keys do nothing between controls, because a plain
        // message loop never offers them to the control group.
        if (g_accelerators && g_accel_window &&
            TranslateAcceleratorW(g_accel_window, g_accelerators, &message)) {
            continue;
        }
        HWND root = GetAncestor(message.hwnd, GA_ROOT);
        if (root && IsDialogMessageW(root, &message)) continue;
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
}

void ctd_app_stop(void) {
    g_running = 0;
    PostQuitMessage(0);
}

void ctd_post(int64_t token) {
    // The one entry point that is safe off the UI thread, and PostMessage is
    // what makes that true: it puts a message on the target thread's queue and
    // returns, touching none of this file's state from the caller's thread.
    if (g_limbo) PostMessageW(g_limbo, CTD_WM_POST, 0, (LPARAM)token);
}

int32_t ctd_capability(int32_t capability) {
    switch (capability) {
        // Windows has no application-wide menu bar: a menu belongs to a
        // window, and `SetMenu` is a per-window call. That is the same answer
        // GTK4 gives, for a different reason, and it is exactly the
        // distinction the two capabilities were written for.
        case CTD_CAP_MENU_BAR:      return 0;
        case CTD_CAP_WINDOW_MENU:   return 1;
        case CTD_CAP_MULTI_SURFACE: return 1;
        case CTD_CAP_RESIZABLE:     return 1;
        case CTD_CAP_FILE_DIALOG:   return 1;
        case CTD_CAP_SNAPSHOT:      return 0;
        default:                    return 0;
    }
}

// ---------------------------------------------------------------- surfaces

ctd_handle ctd_surface_new(double width, double height) {
    // The size asked for is the *content* size, and a Win32 window's size
    // includes its frame, so the frame is added back. Otherwise every window
    // is a title bar shorter than the program asked for.
    RECT wanted = { 0, 0, (LONG)width, (LONG)height };
    AdjustWindowRectEx(&wanted, WS_OVERLAPPEDWINDOW, FALSE, 0);
    HWND window = CreateWindowExW(0, CTD_CLASS_SURFACE, L"", WS_OVERLAPPEDWINDOW,
                                  CW_USEDEFAULT, CW_USEDEFAULT,
                                  wanted.right - wanted.left,
                                  wanted.bottom - wanted.top,
                                  NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (!window) return 0;
    SetPropW(window, CTD_TAG, (HANDLE)1);
    return ctd_track(window, CTD_T_SURFACE, -1);
}

static HWND ctd_surface_window(ctd_handle handle, ctd_status *problem) {
    uint32_t slot = ctd_slot(handle);
    if (!slot) { *problem = CTD_ERR_STALE; return NULL; }
    if (g_type[slot] != CTD_T_SURFACE) { *problem = CTD_ERR_KIND; return NULL; }
    *problem = CTD_OK;
    return (HWND)g_object[slot];
}

ctd_status ctd_surface_set_title(ctd_handle surface, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    ctd_status problem;
    HWND window = ctd_surface_window(surface, &problem);
    if (!window) return problem;
    WCHAR *title = ctd_wide(utf8, len);
    if (!title) return CTD_ERR_PLATFORM;
    SetWindowTextW(window, title);
    free(title);
    return CTD_OK;
}

int32_t ctd_surface_title(ctd_handle surface, char *out, int32_t cap) {
    ctd_status problem;
    HWND window = ctd_surface_window(surface, &problem);
    if (!window) return problem;
    return ctd_window_text_out(window, out, cap);
}

ctd_status ctd_surface_set_root(ctd_handle surface, ctd_handle root) {
    ctd_status problem;
    HWND window = ctd_surface_window(surface, &problem);
    if (!window) return problem;
    HWND view = ctd_window(root);
    if (!view) return CTD_ERR_STALE;
    SetParent(view, window);
    RECT client;
    GetClientRect(window, &client);
    SetWindowPos(view, HWND_BOTTOM, 0, 0, client.right, client.bottom,
                 SWP_NOACTIVATE);
    return CTD_OK;
}

ctd_handle ctd_surface_root(ctd_handle surface) {
    ctd_status problem;
    HWND window = ctd_surface_window(surface, &problem);
    if (!window) return 0;
    for (HWND child = GetWindow(window, GW_CHILD); child;
         child = GetWindow(child, GW_HWNDNEXT)) {
        if (ctd_is_ours(child)) return ctd_handle_of(child);
    }
    return 0;
}

ctd_status ctd_surface_content_size(ctd_handle surface, double *out_size) {
    ctd_status problem;
    HWND window = ctd_surface_window(surface, &problem);
    if (!window) return problem;
    RECT client;
    GetClientRect(window, &client);
    if (out_size) {
        out_size[0] = (double)(client.right - client.left);
        out_size[1] = (double)(client.bottom - client.top);
    }
    return CTD_OK;
}

ctd_status ctd_surface_show(ctd_handle surface) {
    ctd_status problem;
    HWND window = ctd_surface_window(surface, &problem);
    if (!window) return problem;
    if (g_role == CTD_ROLE_HEADLESS) return CTD_OK;
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);
    SetForegroundWindow(window);
    return CTD_OK;
}

ctd_status ctd_surface_close(ctd_handle surface) {
    ctd_status problem;
    HWND window = ctd_surface_window(surface, &problem);
    if (!window) return problem;
    ShowWindow(window, SW_HIDE);
    return CTD_OK;
}

int32_t ctd_surface_visible(ctd_handle surface) {
    ctd_status problem;
    HWND window = ctd_surface_window(surface, &problem);
    if (!window) return 0;
    return IsWindowVisible(window) ? 1 : 0;
}

// ------------------------------------------------------------------ widgets

// Win32 overloads a combo box's window height: the number passed to
// `CreateWindow` or `MoveWindow` is how tall the control is *with its list
// dropped down*, not how tall it looks closed. Every other platform means the
// closed height, and so does cortado, so the room for the list is added on the
// way in and taken off on the way out.
enum { CTD_COMBO_DROP = 160 };

ctd_handle ctd_widget_new(int32_t kind) {
    const WCHAR *class_name = NULL;
    DWORD style = WS_CHILD | WS_VISIBLE;
    DWORD extended = 0;

    switch (kind) {
        case CTD_W_CONTAINER:
            class_name = CTD_CLASS_VIEW;
            style |= WS_CLIPCHILDREN;
            break;
        case CTD_W_LABEL:
            class_name = WC_STATICW;
            style |= SS_LEFT | SS_NOPREFIX;
            break;
        case CTD_W_BUTTON:
            class_name = WC_BUTTONW;
            style |= BS_PUSHBUTTON | WS_TABSTOP;
            break;
        case CTD_W_TEXT_FIELD:
            class_name = WC_EDITW;
            style |= ES_LEFT | ES_AUTOHSCROLL | WS_TABSTOP;
            extended = WS_EX_CLIENTEDGE;
            break;
        case CTD_W_TEXT_AREA:
            class_name = WC_EDITW;
            style |= ES_LEFT | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN
                   | WS_VSCROLL | WS_TABSTOP;
            extended = WS_EX_CLIENTEDGE;
            break;
        case CTD_W_CHECK_BOX:
            class_name = WC_BUTTONW;
            style |= BS_AUTOCHECKBOX | WS_TABSTOP;
            break;
        case CTD_W_RADIO_BUTTON:
            class_name = WC_BUTTONW;
            style |= BS_AUTORADIOBUTTON | WS_TABSTOP;
            break;
        case CTD_W_IMAGE_VIEW:
            class_name = WC_STATICW;
            style |= SS_BITMAP | SS_CENTERIMAGE;
            break;
        case CTD_W_SLIDER:
            class_name = TRACKBAR_CLASSW;
            style |= TBS_HORZ | TBS_NOTICKS | WS_TABSTOP;
            break;
        case CTD_W_PROGRESS_BAR:
            class_name = PROGRESS_CLASSW;
            style |= PBS_SMOOTH;
            break;
        case CTD_W_SEPARATOR:
            // A horizontal rule is a static control with an etched edge. There
            // is no separator class outside a menu, and drawing one would break
            // the rule that every control here is the platform's own.
            class_name = WC_STATICW;
            style |= SS_ETCHEDHORZ;
            break;
        case CTD_W_COMBO_BOX:
            class_name = WC_COMBOBOXW;
            style |= CBS_DROPDOWNLIST | WS_VSCROLL | WS_TABSTOP;
            break;
        case CTD_W_SCROLL_VIEW:
            class_name = CTD_CLASS_VIEW;
            style |= WS_VSCROLL | WS_HSCROLL | WS_CLIPCHILDREN;
            break;
        default:
            return 0;
    }

    int height = kind == CTD_W_COMBO_BOX ? CTD_COMBO_DROP : 0;
    HWND window = CreateWindowExW(extended, class_name, L"", style,
                                  0, 0, 0, height, g_limbo, NULL,
                                  GetModuleHandleW(NULL), NULL);
    if (!window) return 0;
    SetPropW(window, CTD_TAG, (HANDLE)1);
    SendMessageW(window, WM_SETFONT, (WPARAM)g_ui_font, TRUE);

    if (kind == CTD_W_SCROLL_VIEW) {
        // Children of a scroll view go into a content window that the bars
        // move, not into the scroll view itself. It is cortado's, so it is
        // tagged; it is not a handle, so it carries the inner mark too and a
        // tree walk climbs past it.
        HWND content = CreateWindowExW(0, CTD_CLASS_VIEW, L"",
                                       WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
                                       0, 0, 0, 0, window, NULL,
                                       GetModuleHandleW(NULL), NULL);
        if (content) {
            SetPropW(content, CTD_TAG, (HANDLE)1);
            SetPropW(content, CTD_INNER, (HANDLE)1);
        }
    }
    if (kind == CTD_W_TEXT_FIELD) {
        SetWindowSubclass(window, ctd_edit_proc, 1, 0);
    }
    if (kind == CTD_W_PROGRESS_BAR) {
        // The control counts in whole numbers and cortado's range is real, so
        // the range is kept here and the position scaled into a fixed span.
        SendMessageW(window, PBM_SETRANGE32, 0, 10000);
    }

    ctd_handle handle = ctd_track(window, CTD_T_WIDGET, kind);
    if (!handle) { DestroyWindow(window); return 0; }
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    g_progress_min[slot] = 0.0;
    g_progress_max[slot] = 1.0;
    return handle;
}

int32_t ctd_widget_kind(ctd_handle widget) {
    uint32_t slot = ctd_slot(widget);
    if (!slot || g_type[slot] != CTD_T_WIDGET) return -1;
    return g_kind[slot];
}

int32_t ctd_widget_alive(ctd_handle widget) { return ctd_slot(widget) ? 1 : 0; }

ctd_status ctd_widget_release(ctd_handle widget) {
    uint32_t slot = ctd_slot(widget);
    if (!slot) return CTD_ERR_STALE;
    if (g_type[slot] == CTD_T_MENU) {
        CtdMenu *menu = (CtdMenu *)g_object[slot];
        for (int32_t i = 0; i < menu->count; i++) {
            free(menu->commands[i].title);
            free(menu->commands[i].key);
        }
        free(menu->commands);
        free(menu->title);
        DestroyMenu(menu->handle);
        free(menu);
    } else {
        DestroyWindow((HWND)g_object[slot]);
    }
    g_object[slot] = NULL;
    g_type[slot] = CTD_T_FREE;
    g_kind[slot] = -1;
    g_generation[slot] = g_generation[slot] + 1;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    ctd_give_back(slot);
    return CTD_OK;
}

// --------------------------------------------------------------------- tree

// Where a widget's children go. A scroll view's live in its content window; a
// text area holds text and can hold nothing else.
static HWND ctd_container_of(ctd_handle handle) {
    uint32_t slot = ctd_slot(handle);
    if (!slot) return NULL;
    if (g_type[slot] == CTD_T_SURFACE) return (HWND)g_object[slot];
    if (g_type[slot] != CTD_T_WIDGET) return NULL;
    HWND window = (HWND)g_object[slot];
    if (g_kind[slot] == CTD_W_CONTAINER) return window;
    if (g_kind[slot] == CTD_W_SCROLL_VIEW) {
        for (HWND child = GetWindow(window, GW_CHILD); child;
             child = GetWindow(child, GW_HWNDNEXT)) {
            if (GetPropW(child, CTD_INNER)) return child;
        }
        return NULL;
    }
    return NULL;
}

// cortado's children of a container, in insertion order.
//
// Win32 keeps no list of children — the order is the stacking order, and
// `GetWindow` walks it from the top down. Appending puts a window at the
// bottom, so the walk comes back reversed and is flipped here. Index 0 is the
// bottom of the stack, the child drawn first, which is what `addSubview:` and
// `gtk_fixed_put` also mean by "first".
static int32_t ctd_children(HWND container, HWND *out, int32_t cap) {
    HWND stack[256];
    int32_t found = 0;
    for (HWND child = GetWindow(container, GW_CHILD); child;
         child = GetWindow(child, GW_HWNDNEXT)) {
        if (!ctd_is_ours(child)) continue;
        if (GetPropW(child, CTD_INNER)) continue;
        if (found < (int32_t)(sizeof stack / sizeof stack[0])) stack[found] = child;
        found++;
    }
    int32_t kept = found < (int32_t)(sizeof stack / sizeof stack[0])
                 ? found : (int32_t)(sizeof stack / sizeof stack[0]);
    if (out) {
        for (int32_t i = 0; i < kept && i < cap; i++) out[i] = stack[kept - 1 - i];
    }
    return kept;
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    HWND container = ctd_container_of(parent);
    HWND view = ctd_window(child);
    if (!ctd_slot(parent) || !view) return CTD_ERR_STALE;
    if (!container) return CTD_ERR_KIND;

    SetParent(view, container);
    // Appending is sending the new child to the bottom of the stack, because
    // Win32 puts a freshly parented window on top.
    SetWindowPos(view, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

    if (index >= 0) {
        HWND ours[256];
        int32_t count = ctd_children(container, ours, 256);
        if (index < count - 1) {
            // In front of the one it should precede: "after" in z-order terms
            // is the window just below it, and index 0 is the bottom.
            HWND below = index == 0 ? HWND_BOTTOM : ours[index - 1];
            SetWindowPos(view, below, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }

    // A radio button joins the group of the radios already under this parent.
    // Windows groups auto-radio buttons by the WS_GROUP style and the tab
    // order: the first radio in a group carries WS_GROUP and the rest do not,
    // and clicking one clears its neighbours. "The same parent is one group"
    // is the rule every host here follows, and this is how Windows spells it.
    if (ctd_slot_kind(child) == CTD_W_RADIO_BUTTON) {
        HWND ours[256];
        int32_t count = ctd_children(container, ours, 256);
        int first = 1;
        for (int32_t i = 0; i < count; i++) {
            if (ctd_slot_kind(ctd_handle_of(ours[i])) != CTD_W_RADIO_BUTTON) continue;
            LONG_PTR style = GetWindowLongPtrW(ours[i], GWL_STYLE);
            if (first) style |= WS_GROUP; else style &= ~(LONG_PTR)WS_GROUP;
            SetWindowLongPtrW(ours[i], GWL_STYLE, style);
            first = 0;
        }
    }
    return CTD_OK;
}

ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child) {
    HWND container = ctd_container_of(parent);
    HWND view = ctd_window(child);
    if (!ctd_slot(parent) || !view) return CTD_ERR_STALE;
    if (!container) return CTD_ERR_KIND;
    if (GetParent(view) != container) return CTD_ERR_RANGE;
    // Back to the holder, not destroyed: the handle still names it, and a
    // widget that was removed so it could be added somewhere else must survive
    // the trip.
    SetParent(view, g_limbo);
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    HWND container = ctd_container_of(parent);
    if (!ctd_slot(parent)) return CTD_ERR_STALE;
    if (!container) return CTD_ERR_KIND;
    HWND ours[256];
    int32_t count = ctd_children(container, ours, 256);
    if (from < 0 || from >= count || to < 0 || to >= count) return CTD_ERR_RANGE;
    if (from == to) return CTD_OK;

    // Restacking, not remove-and-add. On Windows the hazard the header names
    // is focus rather than lifetime: `SetParent` on the focused control takes
    // focus away mid-edit, and a reorder that did it would silently cancel the
    // user's typing. A z-order change touches neither parent nor focus.
    HWND moving = ours[from];
    HWND below = to == 0 ? HWND_BOTTOM : ours[to > from ? to : to - 1];
    SetWindowPos(moving, below, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    return CTD_OK;
}

ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out) {
    if (!ctd_slot(parent)) return CTD_ERR_STALE;
    HWND container = ctd_container_of(parent);
    // A control that cannot hold children has none, which is an answer and not
    // a refusal: a tree walk asks this of every node.
    if (out) *out = container ? ctd_children(container, NULL, 0) : 0;
    return CTD_OK;
}

ctd_handle ctd_view_child_at(ctd_handle parent, int32_t index) {
    HWND container = ctd_container_of(parent);
    if (!container) return 0;
    HWND ours[256];
    int32_t count = ctd_children(container, ours, 256);
    if (index < 0 || index >= count) return 0;
    return ctd_handle_of(ours[index]);
}

ctd_handle ctd_view_parent(ctd_handle child) {
    HWND view = ctd_window(child);
    if (!view) return 0;
    HWND parent = GetParent(view);
    while (parent && parent != g_limbo && GetPropW(parent, CTD_INNER)) {
        parent = GetParent(parent);
    }
    if (!parent || parent == g_limbo) return 0;
    return ctd_handle_of(parent);
}

// ----------------------------------------------------------------- geometry

ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int tall = (int)height;
    if (ctd_slot_kind(widget) == CTD_W_COMBO_BOX) tall += CTD_COMBO_DROP;
    SetWindowPos(view, NULL, (int)x, (int)y, (int)width, tall,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    if (ctd_slot_kind(widget) == CTD_W_SCROLL_VIEW) {
        // The content window is as wide as the viewport and as tall as it
        // needs to be; the scroll range is what is left over.
        HWND content = ctd_container_of(widget);
        if (content) {
            RECT bounds = { 0, 0, 0, 0 };
            HWND ours[256];
            int32_t count = ctd_children(content, ours, 256);
            for (int32_t i = 0; i < count; i++) {
                RECT frame;
                GetWindowRect(ours[i], &frame);
                MapWindowPoints(HWND_DESKTOP, content, (POINT *)&frame, 2);
                if (frame.right > bounds.right) bounds.right = frame.right;
                if (frame.bottom > bounds.bottom) bounds.bottom = frame.bottom;
            }
            SetWindowPos(content, NULL, 0, 0,
                         bounds.right > (int)width ? bounds.right : (int)width,
                         bounds.bottom > (int)height ? bounds.bottom : (int)height,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            SCROLLINFO info;
            memset(&info, 0, sizeof info);
            info.cbSize = sizeof info;
            info.fMask = SIF_RANGE | SIF_PAGE;
            info.nMin = 0;
            info.nMax = bounds.bottom;
            info.nPage = (UINT)height;
            SetScrollInfo(view, SB_VERT, &info, TRUE);
            info.nMax = bounds.right;
            info.nPage = (UINT)width;
            SetScrollInfo(view, SB_HORZ, &info, TRUE);
        }
    }
    return CTD_OK;
}

ctd_status ctd_view_frame(ctd_handle widget, double *out_frame) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    RECT frame;
    GetWindowRect(view, &frame);
    HWND parent = GetParent(view);
    MapWindowPoints(HWND_DESKTOP, parent ? parent : HWND_DESKTOP,
                    (POINT *)&frame, 2);
    double height = (double)(frame.bottom - frame.top);
    if (ctd_slot_kind(widget) == CTD_W_COMBO_BOX) height -= CTD_COMBO_DROP;
    if (out_frame) {
        out_frame[0] = (double)frame.left;
        out_frame[1] = (double)frame.top;
        out_frame[2] = (double)(frame.right - frame.left);
        out_frame[3] = height;
    }
    return CTD_OK;
}

// How wide and tall a string is in a control's own font. Win32 has no
// "measure yourself" message for most classes, so the text is measured and the
// control's own chrome added on top — which is what the classes that *do* have
// one (a button's BCM_GETIDEALSIZE) also do internally.
static void ctd_text_extent(HWND view, int wrap_width, SIZE *out) {
    out->cx = 0;
    out->cy = 0;
    int length = GetWindowTextLengthW(view);
    HDC device = GetDC(view);
    if (!device) return;
    HFONT font = (HFONT)SendMessageW(view, WM_GETFONT, 0, 0);
    if (!font) font = g_ui_font;
    HGDIOBJ previous = SelectObject(device, font);

    TEXTMETRICW metrics;
    GetTextMetricsW(device, &metrics);
    out->cy = metrics.tmHeight;

    if (length > 0) {
        WCHAR *text = (WCHAR *)malloc(((size_t)length + 1) * sizeof(WCHAR));
        if (text) {
            GetWindowTextW(view, text, length + 1);
            RECT box = { 0, 0, wrap_width > 0 ? wrap_width : 0, 0 };
            UINT format = DT_CALCRECT | DT_NOPREFIX |
                          (wrap_width > 0 ? DT_WORDBREAK : DT_SINGLELINE);
            DrawTextW(device, text, length, &box, format);
            out->cx = box.right - box.left;
            out->cy = box.bottom - box.top;
            free(text);
        }
    }
    SelectObject(device, previous);
    ReleaseDC(view, device);
}

ctd_status ctd_view_measure(ctd_handle widget, double avail_width, double avail_height,
                            double *out_size) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int wrap = avail_width >= 0.0 ? (int)avail_width : 0;
    SIZE text;
    ctd_text_extent(view, 0, &text);
    double width = (double)text.cx;
    double height = (double)text.cy;

    switch (ctd_slot_kind(widget)) {
        case CTD_W_BUTTON: {
            // The one class that answers for itself, and only with common
            // controls v6 behind it; a v5 button answers zero, so the measured
            // text is the fallback rather than a wrong small number.
            SIZE ideal = { 0, 0 };
            if (SendMessageW(view, BCM_GETIDEALSIZE, 0, (LPARAM)&ideal) &&
                ideal.cx > 0 && ideal.cy > 0) {
                width = (double)ideal.cx;
                height = (double)ideal.cy;
            } else {
                width += 24.0;
                height += 10.0;
            }
            break;
        }
        case CTD_W_LABEL:
            if (wrap > 0) {
                ctd_text_extent(view, wrap, &text);
                width = (double)text.cx;
                height = (double)text.cy;
            }
            break;
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON:
            // The box or the dot, plus the gap Windows leaves before the label.
            width += (double)GetSystemMetrics(SM_CXMENUCHECK) + 8.0;
            if (height < 17.0) height = 17.0;
            break;
        case CTD_W_TEXT_FIELD:
            width += 8.0;
            height += 8.0;
            break;
        case CTD_W_TEXT_AREA:
            width = avail_width >= 0.0 ? avail_width : width + 8.0;
            height = height * 3.0 + 8.0;
            break;
        case CTD_W_COMBO_BOX:
            width += (double)GetSystemMetrics(SM_CXVSCROLL) + 16.0;
            height += 9.0;
            break;
        case CTD_W_SLIDER:
            width = avail_width >= 0.0 ? avail_width : 100.0;
            height = 25.0;
            break;
        case CTD_W_PROGRESS_BAR:
            width = avail_width >= 0.0 ? avail_width : 100.0;
            height = 20.0;
            break;
        case CTD_W_SEPARATOR:
            width = avail_width >= 0.0 ? avail_width : 100.0;
            height = 2.0;
            break;
        case CTD_W_CONTAINER:
        case CTD_W_SCROLL_VIEW:
            // A box is as big as it is told to be. Its children were measured
            // by the solver, which is the layer that knows how they are
            // arranged.
            width = 0.0;
            height = 0.0;
            break;
        default: break;
    }

    if (avail_width >= 0.0 && width > avail_width) width = avail_width;
    if (avail_height >= 0.0 && height > avail_height) height = avail_height;
    if (out_size) {
        out_size[0] = width;
        out_size[1] = height;
    }
    return CTD_OK;
}

// --------------------------------------------------------------- properties

ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int32_t kind = ctd_slot_kind(widget);
    switch (key) {
        case CTD_P_ENABLED:
            EnableWindow(view, value ? TRUE : FALSE);
            return CTD_OK;
        case CTD_P_HIDDEN:
            ShowWindow(view, value ? SW_HIDE : SW_SHOW);
            return CTD_OK;
        case CTD_P_CHECKED: {
            if (kind != CTD_W_CHECK_BOX && kind != CTD_W_RADIO_BUTTON)
                return CTD_ERR_KIND;
            if (value == 2) {
                // Windows will only hold the third state on a button that has
                // been told it has three, and turning that on also changes what
                // clicking cycles through — the same trade AppKit makes with
                // `allowsMixedState`. So it is switched on when a program asks
                // for mixed and not before.
                if (kind != CTD_W_CHECK_BOX) return CTD_ERR_UNSUPPORTED;
                LONG_PTR style = GetWindowLongPtrW(view, GWL_STYLE);
                style = (style & ~(LONG_PTR)BS_AUTOCHECKBOX) | BS_AUTO3STATE;
                SetWindowLongPtrW(view, GWL_STYLE, style);
                SendMessageW(view, BM_SETCHECK, BST_INDETERMINATE, 0);
                return CTD_OK;
            }
            SendMessageW(view, BM_SETCHECK,
                         value == 1 ? BST_CHECKED : BST_UNCHECKED, 0);
            return CTD_OK;
        }
        case CTD_P_EDITABLE:
            if (kind != CTD_W_TEXT_FIELD && kind != CTD_W_TEXT_AREA)
                return CTD_ERR_KIND;
            SendMessageW(view, EM_SETREADONLY, value ? FALSE : TRUE, 0);
            return CTD_OK;
        case CTD_P_ALIGNMENT: {
            if (value < 0 || value > 2) return CTD_ERR_RANGE;
            LONG_PTR style = GetWindowLongPtrW(view, GWL_STYLE);
            if (kind == CTD_W_LABEL) {
                style &= ~(LONG_PTR)(SS_LEFT | SS_CENTER | SS_RIGHT);
                style |= value == 1 ? SS_CENTER : value == 2 ? SS_RIGHT : SS_LEFT;
            } else if (kind == CTD_W_TEXT_FIELD || kind == CTD_W_TEXT_AREA) {
                style &= ~(LONG_PTR)(ES_LEFT | ES_CENTER | ES_RIGHT);
                style |= value == 1 ? ES_CENTER : value == 2 ? ES_RIGHT : ES_LEFT;
            } else {
                return CTD_ERR_KIND;
            }
            SetWindowLongPtrW(view, GWL_STYLE, style);
            InvalidateRect(view, NULL, TRUE);
            return CTD_OK;
        }
        case CTD_P_SELECTED: {
            if (kind != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
            LRESULT count = SendMessageW(view, CB_GETCOUNT, 0, 0);
            if (value < 0) {
                SendMessageW(view, CB_SETCURSEL, (WPARAM)-1, 0);
                return CTD_OK;
            }
            if (value >= count) return CTD_ERR_RANGE;
            SendMessageW(view, CB_SETCURSEL, (WPARAM)value, 0);
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE: {
            if (kind != CTD_W_PROGRESS_BAR) return CTD_ERR_KIND;
            LONG_PTR style = GetWindowLongPtrW(view, GWL_STYLE);
            if (value) style |= PBS_MARQUEE; else style &= ~(LONG_PTR)PBS_MARQUEE;
            SetWindowLongPtrW(view, GWL_STYLE, style);
            SendMessageW(view, PBM_SETMARQUEE, value ? TRUE : FALSE, 30);
            return CTD_OK;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int32_t kind = ctd_slot_kind(widget);
    int64_t value = 0;
    switch (key) {
        case CTD_P_ENABLED:
            value = IsWindowEnabled(view) ? 1 : 0;
            break;
        case CTD_P_HIDDEN:
            // The style bit, not `IsWindowVisible`, which also answers no for
            // every child of a window that has not been shown — and in a
            // headless run that is all of them.
            value = (GetWindowLongPtrW(view, GWL_STYLE) & WS_VISIBLE) ? 0 : 1;
            break;
        case CTD_P_CHECKED: {
            if (kind != CTD_W_CHECK_BOX && kind != CTD_W_RADIO_BUTTON)
                return CTD_ERR_KIND;
            LRESULT state = SendMessageW(view, BM_GETCHECK, 0, 0);
            value = state == BST_CHECKED ? 1 : state == BST_INDETERMINATE ? 2 : 0;
            break;
        }
        case CTD_P_EDITABLE:
            if (kind != CTD_W_TEXT_FIELD && kind != CTD_W_TEXT_AREA)
                return CTD_ERR_KIND;
            value = (GetWindowLongPtrW(view, GWL_STYLE) & ES_READONLY) ? 0 : 1;
            break;
        case CTD_P_ALIGNMENT: {
            LONG_PTR style = GetWindowLongPtrW(view, GWL_STYLE);
            if (kind == CTD_W_LABEL) {
                value = (style & SS_RIGHT) ? 2 : (style & SS_CENTER) ? 1 : 0;
            } else if (kind == CTD_W_TEXT_FIELD || kind == CTD_W_TEXT_AREA) {
                value = (style & ES_RIGHT) ? 2 : (style & ES_CENTER) ? 1 : 0;
            } else {
                return CTD_ERR_KIND;
            }
            break;
        }
        case CTD_P_SELECTED: {
            if (kind != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
            LRESULT chosen = SendMessageW(view, CB_GETCURSEL, 0, 0);
            value = chosen == CB_ERR ? -1 : (int64_t)chosen;
            break;
        }
        case CTD_P_INDETERMINATE:
            if (kind != CTD_W_PROGRESS_BAR) return CTD_ERR_KIND;
            value = (GetWindowLongPtrW(view, GWL_STYLE) & PBS_MARQUEE) ? 1 : 0;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// Font sizes already made, so a second control asking for the same size gets
// the same HFONT rather than another GDI object. Fonts are a limited resource
// on Windows in a way they are not elsewhere.
enum { CTD_FONT_CACHE = 32 };
static int   g_font_points[CTD_FONT_CACHE];
static HFONT g_font_cache[CTD_FONT_CACHE];

static HFONT ctd_font_at(int points) {
    for (int i = 0; i < CTD_FONT_CACHE; i++) {
        if (g_font_points[i] == points) return g_font_cache[i];
    }
    NONCLIENTMETRICSW metrics;
    memset(&metrics, 0, sizeof metrics);
    metrics.cbSize = sizeof metrics;
    if (!SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof metrics, &metrics, 0))
        return NULL;
    HDC screen = GetDC(NULL);
    int dpi = screen ? GetDeviceCaps(screen, LOGPIXELSY) : 96;
    if (screen) ReleaseDC(NULL, screen);
    // Windows measures a font in device units, and a point is a seventy-second
    // of an inch; this is the conversion the platform's own documentation uses.
    metrics.lfMessageFont.lfHeight = -MulDiv(points, dpi, 72);
    HFONT font = CreateFontIndirectW(&metrics.lfMessageFont);
    if (!font) return NULL;
    for (int i = 0; i < CTD_FONT_CACHE; i++) {
        if (g_font_points[i] == 0) {
            g_font_points[i] = points;
            g_font_cache[i] = font;
            break;
        }
    }
    return font;
}

ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    int32_t kind = ctd_slot_kind(widget);
    switch (key) {
        case CTD_P_FONT_SIZE: {
            int points = (int)value;
            if (points <= 0) return CTD_ERR_RANGE;
            HFONT font = ctd_font_at(points);
            if (!font) return CTD_ERR_PLATFORM;
            SendMessageW(view, WM_SETFONT, (WPARAM)font, TRUE);
            return CTD_OK;
        }
        case CTD_P_MIN:
            if (kind == CTD_W_SLIDER) {
                SendMessageW(view, TBM_SETRANGEMIN, TRUE, (LPARAM)(LONG)value);
                return CTD_OK;
            }
            if (kind == CTD_W_PROGRESS_BAR) { g_progress_min[slot] = value; return CTD_OK; }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if (kind == CTD_W_SLIDER) {
                SendMessageW(view, TBM_SETRANGEMAX, TRUE, (LPARAM)(LONG)value);
                return CTD_OK;
            }
            if (kind == CTD_W_PROGRESS_BAR) { g_progress_max[slot] = value; return CTD_OK; }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if (kind == CTD_W_SLIDER) {
                SendMessageW(view, TBM_SETPOS, TRUE, (LPARAM)(LONG)value);
                return CTD_OK;
            }
            if (kind == CTD_W_PROGRESS_BAR) {
                double span = g_progress_max[slot] - g_progress_min[slot];
                double fraction = span > 0.0 ? (value - g_progress_min[slot]) / span : 0.0;
                if (fraction < 0.0) fraction = 0.0;
                if (fraction > 1.0) fraction = 1.0;
                SendMessageW(view, PBM_SETPOS, (WPARAM)(int)(fraction * 10000.0), 0);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_STEP:
            if (kind != CTD_W_SLIDER) return CTD_ERR_KIND;
            SendMessageW(view, TBM_SETLINESIZE, 0, (LPARAM)(LONG)value);
            SendMessageW(view, TBM_SETPAGESIZE, 0, (LPARAM)(LONG)value);
            return CTD_OK;
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    int32_t kind = ctd_slot_kind(widget);
    double value = 0.0;
    switch (key) {
        case CTD_P_FONT_SIZE: {
            HFONT font = (HFONT)SendMessageW(view, WM_GETFONT, 0, 0);
            if (!font) font = g_ui_font;
            LOGFONTW description;
            if (!GetObjectW(font, sizeof description, &description))
                return CTD_ERR_PLATFORM;
            HDC screen = GetDC(NULL);
            int dpi = screen ? GetDeviceCaps(screen, LOGPIXELSY) : 96;
            if (screen) ReleaseDC(NULL, screen);
            LONG height = description.lfHeight < 0 ? -description.lfHeight
                                                   : description.lfHeight;
            value = (double)MulDiv(height, 72, dpi);
            break;
        }
        case CTD_P_MIN:
            if (kind == CTD_W_SLIDER) {
                value = (double)(LONG)SendMessageW(view, TBM_GETRANGEMIN, 0, 0);
            } else if (kind == CTD_W_PROGRESS_BAR) { value = g_progress_min[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_MAX:
            if (kind == CTD_W_SLIDER) {
                value = (double)(LONG)SendMessageW(view, TBM_GETRANGEMAX, 0, 0);
            } else if (kind == CTD_W_PROGRESS_BAR) { value = g_progress_max[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_VALUE:
            if (kind == CTD_W_SLIDER) {
                value = (double)(LONG)SendMessageW(view, TBM_GETPOS, 0, 0);
            } else if (kind == CTD_W_PROGRESS_BAR) {
                double span = g_progress_max[slot] - g_progress_min[slot];
                double position = (double)SendMessageW(view, PBM_GETPOS, 0, 0);
                value = g_progress_min[slot] + span * (position / 10000.0);
            } else return CTD_ERR_KIND;
            break;
        case CTD_P_STEP:
            if (kind != CTD_W_SLIDER) return CTD_ERR_KIND;
            value = (double)(LONG)SendMessageW(view, TBM_GETLINESIZE, 0, 0);
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// --------------------------------------------------------------------- text

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    switch (ctd_slot_kind(widget)) {
        case CTD_W_CONTAINER:
        case CTD_W_SCROLL_VIEW:
        case CTD_W_SLIDER:
        case CTD_W_PROGRESS_BAR:
        case CTD_W_SEPARATOR:
        case CTD_W_COMBO_BOX:
            // A combo box's text is whichever item is chosen, so writing it
            // would be writing the selection through the wrong door.
            return CTD_ERR_KIND;
        default: break;
    }
    WCHAR *text = ctd_wide(utf8, len);
    if (!text) return CTD_ERR_PLATFORM;
    SetWindowTextW(view, text);
    free(text);
    return CTD_OK;
}

int32_t ctd_get_text(ctd_handle widget, char *out, int32_t cap) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) == CTD_W_COMBO_BOX) {
        // A drop-down list keeps no window text of its own: the answer is the
        // chosen item, and `GetWindowText` on one returns nothing at all.
        LRESULT chosen = SendMessageW(view, CB_GETCURSEL, 0, 0);
        if (chosen == CB_ERR) return ctd_copy_out("", out, cap);
        LRESULT length = SendMessageW(view, CB_GETLBTEXTLEN, (WPARAM)chosen, 0);
        if (length <= 0) return ctd_copy_out("", out, cap);
        WCHAR *item = (WCHAR *)malloc(((size_t)length + 1) * sizeof(WCHAR));
        if (!item) return ctd_copy_out("", out, cap);
        SendMessageW(view, CB_GETLBTEXT, (WPARAM)chosen, (LPARAM)item);
        int32_t needed = ctd_copy_wide_out(item, out, cap);
        free(item);
        return needed;
    }
    return ctd_window_text_out(view, out, cap);
}

// --------------------------------------------------------------- item lists

ctd_status ctd_items_clear(ctd_handle widget) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    SendMessageW(view, CB_RESETCONTENT, 0, 0);
    return CTD_OK;
}

ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    if (len < 0) return CTD_ERR_RANGE;
    WCHAR *text = ctd_wide(utf8, len);
    if (!text) return CTD_ERR_PLATFORM;
    LRESULT added = SendMessageW(view, CB_ADDSTRING, 0, (LPARAM)text);
    free(text);
    return added == CB_ERR || added == CB_ERRSPACE ? CTD_ERR_PLATFORM : CTD_OK;
}

ctd_status ctd_items_count(ctd_handle widget, int32_t *out) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    LRESULT count = SendMessageW(view, CB_GETCOUNT, 0, 0);
    if (out) *out = count == CB_ERR ? 0 : (int32_t)count;
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    LRESULT count = SendMessageW(view, CB_GETCOUNT, 0, 0);
    if (index < 0 || count == CB_ERR || index >= (int32_t)count) return CTD_ERR_RANGE;
    LRESULT length = SendMessageW(view, CB_GETLBTEXTLEN, (WPARAM)index, 0);
    if (length <= 0) return ctd_copy_out("", out, cap);
    WCHAR *item = (WCHAR *)malloc(((size_t)length + 1) * sizeof(WCHAR));
    if (!item) return CTD_ERR_PLATFORM;
    SendMessageW(view, CB_GETLBTEXT, (WPARAM)index, (LPARAM)item);
    int32_t needed = ctd_copy_wide_out(item, out, cap);
    free(item);
    return needed;
}

// -------------------------------------------------------------------- menus
//
// Windows has no application menu bar — a menu belongs to a window, which is
// what `ctd_capability(CTD_CAP_MENU_BAR)` answering no already says. The rest
// of the menu API builds a real HMENU that a window can carry.
//
// The roles are where the platforms visibly part company, and that is the
// point of having them. Preferences is "Options" here and lives under Tools,
// not under an application menu that does not exist. Quit is "Exit" and has no
// menu accelerator, because Alt+F4 is a window command rather than a menu one.
// Redo is Ctrl+Y, not Ctrl+Shift+Z. A menu described as a tree of titles would
// have got every one of those wrong.

static const char *ctd_role_title(int32_t role, const char *fallback) {
    switch (role) {
        case CTD_CMD_ABOUT:       return "About";
        case CTD_CMD_PREFERENCES: return "Options";
        case CTD_CMD_QUIT:        return "Exit";
        case CTD_CMD_HIDE:        return "Minimize to Taskbar";
        case CTD_CMD_UNDO:        return "Undo";
        case CTD_CMD_REDO:        return "Redo";
        case CTD_CMD_CUT:         return "Cut";
        case CTD_CMD_COPY:        return "Copy";
        case CTD_CMD_PASTE:       return "Paste";
        case CTD_CMD_SELECT_ALL:  return "Select All";
        case CTD_CMD_CLOSE:       return "Close";
        case CTD_CMD_MINIMIZE:    return "Minimize";
        case CTD_CMD_FULLSCREEN:  return "Full Screen";
        default:                  return fallback;
    }
}

// `mod` is Control here, not Command — which is the whole reason a shortcut is
// written portably rather than as a literal key.
static const char *ctd_role_key(int32_t role, const char *fallback) {
    switch (role) {
        case CTD_CMD_UNDO:       return "mod+z";
        case CTD_CMD_REDO:       return "mod+y";
        case CTD_CMD_CUT:        return "mod+x";
        case CTD_CMD_COPY:       return "mod+c";
        case CTD_CMD_PASTE:      return "mod+v";
        case CTD_CMD_SELECT_ALL: return "mod+a";
        case CTD_CMD_CLOSE:      return "mod+w";
        case CTD_CMD_FULLSCREEN: return "F11";
        // About, Options, Exit, Hide and Minimize carry no accelerator on
        // Windows. Inventing one would put a key in the golden that no Windows
        // program has.
        default:                 return fallback;
    }
}

// "mod+shift+z" as Windows shows it in a menu: "Ctrl+Shift+Z", after a tab.
static void ctd_display_key(const char *portable, WCHAR *out, size_t cap) {
    out[0] = 0;
    if (!portable || !*portable) return;
    char shown[64];
    size_t at = 0;
    const char *scan = portable;
    while (*scan && at + 8 < sizeof shown) {
        if (strncmp(scan, "mod+", 4) == 0) {
            memcpy(shown + at, "Ctrl+", 5); at += 5; scan += 4; continue;
        }
        if (strncmp(scan, "shift+", 6) == 0) {
            memcpy(shown + at, "Shift+", 6); at += 6; scan += 6; continue;
        }
        if (strncmp(scan, "alt+", 4) == 0) {
            memcpy(shown + at, "Alt+", 4); at += 4; scan += 4; continue;
        }
        // The key itself, capitalised the way a menu shows it.
        shown[at++] = (char)(scan[0] >= 'a' && scan[0] <= 'z'
                             ? scan[0] - 'a' + 'A' : scan[0]);
        scan++;
    }
    shown[at] = 0;
    MultiByteToWideChar(CP_UTF8, 0, shown, -1, out, (int)cap);
}

// The accelerator table, rebuilt whenever a menu becomes a window's menu bar.
static void ctd_rebuild_accelerators(CtdMenu *menu, HWND window) {
    ACCEL entries[128];
    int count = 0;
    for (int32_t i = 0; i < menu->count && count < 128; i++) {
        CtdCommand *command = &menu->commands[i];
        if (command->separator || !command->key || !*command->key) continue;
        BYTE flags = FVIRTKEY;
        const char *scan = command->key;
        WORD key = 0;
        while (*scan) {
            if (strncmp(scan, "mod+", 4) == 0)   { flags |= FCONTROL; scan += 4; continue; }
            if (strncmp(scan, "shift+", 6) == 0) { flags |= FSHIFT;   scan += 6; continue; }
            if (strncmp(scan, "alt+", 4) == 0)   { flags |= FALT;     scan += 4; continue; }
            if (scan[0] == 'F' && scan[1] >= '1' && scan[1] <= '9') {
                key = (WORD)(VK_F1 + atoi(scan + 1) - 1);
            } else {
                key = (WORD)(scan[0] >= 'a' && scan[0] <= 'z'
                             ? scan[0] - 'a' + 'A' : scan[0]);
            }
            break;
        }
        if (!key) continue;
        entries[count].fVirt = flags;
        entries[count].key = key;
        entries[count].cmd = (WORD)command->id;
        count++;
    }
    if (g_accelerators) DestroyAcceleratorTable(g_accelerators);
    g_accelerators = count > 0 ? CreateAcceleratorTable(entries, count) : NULL;
    g_accel_window = window;
}

static int ctd_menu_grow(CtdMenu *menu) {
    if (menu->count < menu->capacity) return 1;
    int32_t grown = menu->capacity ? menu->capacity * 2 : 8;
    CtdCommand *bigger = (CtdCommand *)realloc(menu->commands,
                                               (size_t)grown * sizeof(CtdCommand));
    if (!bigger) return 0;
    menu->commands = bigger;
    menu->capacity = grown;
    return 1;
}

static char *ctd_dup_utf8(const char *utf8, int32_t len) {
    if (len < 0) len = 0;
    char *copy = (char *)malloc((size_t)len + 1);
    if (!copy) return NULL;
    if (len > 0) memcpy(copy, utf8, (size_t)len);
    copy[len] = 0;
    return copy;
}

ctd_handle ctd_menu_new(const char *title, int32_t len) {
    CtdMenu *menu = (CtdMenu *)calloc(1, sizeof(CtdMenu));
    if (!menu) return 0;
    // A popup, not a bar: a bar can only be a window's, and this becomes one
    // when `ctd_menu_set_bar` is called on it or it is added as a submenu.
    menu->handle = CreatePopupMenu();
    menu->title = ctd_dup_utf8(title, len);
    if (!menu->handle || !menu->title) {
        if (menu->handle) DestroyMenu(menu->handle);
        free(menu->title);
        free(menu);
        return 0;
    }
    ctd_handle handle = ctd_track(menu, CTD_T_MENU, -1);
    if (!handle) {
        DestroyMenu(menu->handle);
        free(menu->title);
        free(menu);
        return 0;
    }
    return handle;
}

ctd_status ctd_menu_add_item(ctd_handle handle, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token) {
    if (ctd_has_nul(title, title_len) || ctd_has_nul(key, key_len))
        return CTD_ERR_RANGE;
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (role < 0 || role > CTD_CMD_FULLSCREEN) return CTD_ERR_RANGE;
    if (!ctd_menu_grow(menu)) return CTD_ERR_PLATFORM;

    char *asked_title = ctd_dup_utf8(title, title_len);
    char *asked_key = ctd_dup_utf8(key, key_len);
    if (!asked_title || !asked_key) {
        free(asked_title); free(asked_key);
        return CTD_ERR_PLATFORM;
    }
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.token = token;
    command.role = role;
    command.enabled = 1;
    command.title = ctd_dup_utf8(ctd_role_title(role, asked_title), -1);
    command.key = ctd_dup_utf8(ctd_role_key(role, asked_key), -1);
    {
        const char *chosen_title = ctd_role_title(role, asked_title);
        const char *chosen_key = ctd_role_key(role, asked_key);
        free(command.title);
        free(command.key);
        command.title = ctd_dup_utf8(chosen_title, (int32_t)strlen(chosen_title));
        command.key = ctd_dup_utf8(chosen_key, (int32_t)strlen(chosen_key));
    }
    free(asked_title);
    free(asked_key);
    if (!command.title || !command.key) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }

    command.id = ctd_register_menu_id(handle, token);
    if (!command.id) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }

    // Windows shows the accelerator inside the item's own string, after a tab.
    // It is display only — the key itself comes from the accelerator table.
    WCHAR shown[128];
    WCHAR accelerator[64];
    ctd_display_key(command.key, accelerator, 64);
    WCHAR *wide_title = ctd_wide(command.title, (int32_t)strlen(command.title));
    if (!wide_title) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }
    if (accelerator[0]) {
        _snwprintf(shown, 128, L"%s\t%s", wide_title, accelerator);
    } else {
        _snwprintf(shown, 128, L"%s", wide_title);
    }
    shown[127] = 0;
    free(wide_title);

    AppendMenuW(menu->handle, MF_STRING, command.id, shown);
    menu->commands[menu->count++] = command;
    return CTD_OK;
}

ctd_status ctd_menu_add_separator(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (!ctd_menu_grow(menu)) return CTD_ERR_PLATFORM;
    AppendMenuW(menu->handle, MF_SEPARATOR, 0, NULL);
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.separator = 1;
    command.role = CTD_CMD_NONE;
    command.title = ctd_dup_utf8("-", 1);
    command.key = ctd_dup_utf8("", 0);
    if (!command.title || !command.key) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }
    menu->commands[menu->count++] = command;
    return CTD_OK;
}

ctd_status ctd_menu_add_submenu(ctd_handle handle, ctd_handle child) {
    CtdMenu *menu = ctd_menu_of(handle);
    CtdMenu *inner = ctd_menu_of(child);
    if (!menu || !inner) return CTD_ERR_STALE;
    if (!ctd_menu_grow(menu)) return CTD_ERR_PLATFORM;
    WCHAR *title = ctd_wide(inner->title, (int32_t)strlen(inner->title));
    if (!title) return CTD_ERR_PLATFORM;
    AppendMenuW(menu->handle, MF_POPUP, (UINT_PTR)inner->handle, title);
    free(title);
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.enabled = 1;
    command.role = CTD_CMD_NONE;
    command.title = ctd_dup_utf8(inner->title, (int32_t)strlen(inner->title));
    command.key = ctd_dup_utf8("", 0);
    if (!command.title || !command.key) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }
    menu->commands[menu->count++] = command;
    return CTD_OK;
}

ctd_status ctd_menu_item_count(ctd_handle handle, int32_t *out) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = menu->count;
    return CTD_OK;
}

int32_t ctd_menu_item_title(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= menu->count) return CTD_ERR_RANGE;
    return ctd_copy_out(menu->commands[index].title, out, cap);
}

int32_t ctd_menu_item_key(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= menu->count) return CTD_ERR_RANGE;
    return ctd_copy_out(menu->commands[index].key, out, cap);
}

ctd_status ctd_menu_set_bar(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // There is no application-wide menu bar on Windows to install one into,
    // which `ctd_capability(CTD_CAP_MENU_BAR)` already says. A window menu is
    // the Windows shape, and the accelerators are rebuilt for whichever window
    // gets one so the keys work without a menu ever being opened.
    HWND window = NULL;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_type[slot] == CTD_T_SURFACE) { window = (HWND)g_object[slot]; break; }
    }
    if (window) ctd_rebuild_accelerators(menu, window);
    return CTD_ERR_UNSUPPORTED;
}

static CtdCommand *ctd_find_command(CtdMenu *menu, int64_t token) {
    for (int32_t i = 0; i < menu->count; i++) {
        if (!menu->commands[i].separator && menu->commands[i].token == token)
            return &menu->commands[i];
    }
    return NULL;
}

ctd_status ctd_menu_set_enabled(ctd_handle handle, int64_t token, int32_t on) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    command->enabled = on ? 1 : 0;
    EnableMenuItem(menu->handle, command->id,
                   MF_BYCOMMAND | (on ? MF_ENABLED : MF_GRAYED));
    return CTD_OK;
}

ctd_status ctd_menu_invoke(ctd_handle handle, int64_t token) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    if (!command->enabled) return CTD_ERR_PLATFORM;
    if (ctd_dispatch_editing(command->role)) return CTD_OK;
    ctd_emit(CTD_EV_COMMAND, 0, 0, token);
    return CTD_OK;
}

// ------------------------------------------------------------------ dialogs

typedef struct {
    int64_t token;
    int32_t kind;
    HWND    parent;
    WCHAR  *title;
    WCHAR  *body;
} CtdDialogRequest;

static void ctd_run_dialog(void *data) {
    CtdDialogRequest *request = (CtdDialogRequest *)data;
    int64_t index = 0;
    WCHAR path[MAX_PATH];
    path[0] = 0;

    int visible = request->parent && IsWindowVisible(request->parent);
    if (g_role == CTD_ROLE_HEADLESS || !visible) {
        // With nothing on screen to attach to, a dialog answers its default
        // rather than putting a window somewhere nobody asked for. The contract
        // that matters is that **a dialog always answers**: a caller waiting on
        // a token that never arrives is worse than an answer it can see.
        index = (request->kind == CTD_DLG_MESSAGE ||
                 request->kind == CTD_DLG_CONFIRM) ? 0 : 1;
    } else if (request->kind == CTD_DLG_MESSAGE || request->kind == CTD_DLG_CONFIRM) {
        UINT buttons = request->kind == CTD_DLG_CONFIRM ? MB_OKCANCEL : MB_OK;
        int answer = MessageBoxW(request->parent, request->body, request->title,
                                 buttons | MB_ICONINFORMATION);
        index = answer == IDCANCEL ? 1 : 0;
    } else {
        OPENFILENAMEW chooser;
        memset(&chooser, 0, sizeof chooser);
        chooser.lStructSize = sizeof chooser;
        chooser.hwndOwner = request->parent;
        chooser.lpstrFile = path;
        chooser.nMaxFile = MAX_PATH;
        chooser.lpstrTitle = request->title;
        chooser.Flags = OFN_EXPLORER | OFN_NOCHANGEDIR |
                        (request->kind == CTD_DLG_OPEN ? OFN_FILEMUSTEXIST
                                                       : OFN_OVERWRITEPROMPT);
        BOOL chose = request->kind == CTD_DLG_OPEN ? GetOpenFileNameW(&chooser)
                                                   : GetSaveFileNameW(&chooser);
        index = chose ? 0 : 1;
        if (!chose) path[0] = 0;
    }

    if (g_sink) {
        char *text = NULL;
        int32_t text_len = 0;
        if (path[0]) {
            int needed = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
            if (needed > 1) {
                text = (char *)malloc((size_t)needed);
                if (text) {
                    WideCharToMultiByte(CP_UTF8, 0, path, -1, text, needed, NULL, NULL);
                    text_len = needed - 1;
                }
            }
        }
        ctd_event event;
        memset(&event, 0, sizeof event);
        event.kind = CTD_EV_POST;
        event.token = request->token;
        event.index = index;
        event.text = text;
        event.text_len = text_len;
        g_sink(g_sink_context, &event);
        free(text);
    }
    free(request->title);
    free(request->body);
    free(request);
}

ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token) {
    if (kind < CTD_DLG_MESSAGE || kind > CTD_DLG_SAVE) return CTD_ERR_RANGE;
    HWND owner = NULL;
    if (parent) {
        ctd_status problem;
        owner = ctd_surface_window(parent, &problem);
        if (!owner) return problem;
    }
    CtdDialogRequest *request =
        (CtdDialogRequest *)calloc(1, sizeof(CtdDialogRequest));
    if (!request) return CTD_ERR_PLATFORM;
    request->token = token;
    request->kind = kind;
    request->parent = owner;
    request->title = ctd_wide(title, title_len);
    request->body = ctd_wide(body, body_len);
    if (!request->title || !request->body) {
        free(request->title); free(request->body); free(request);
        return CTD_ERR_PLATFORM;
    }
    // Posted, not run here. `MessageBox` and the file choosers each run a loop
    // of their own, and running one inside this call would re-enter everything
    // above it — including the render the call came out of.
    if (g_role == CTD_ROLE_HEADLESS || !g_limbo) {
        ctd_run_dialog(request);
        return CTD_OK;
    }
    PostMessageW(g_limbo, CTD_WM_DIALOG, 0, (LPARAM)request);
    return CTD_OK;
}

// --------------------------------------------------------------- appearance

int32_t ctd_appearance(void) {
    // Light and dark are a user setting rather than an API on Windows, and
    // this is where the shell keeps it. Zero means dark, which reads backwards
    // and is what the value is called: AppsUseLightTheme.
    HKEY key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                      0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) {
        return 0;
    }
    DWORD light = 1;
    DWORD size = sizeof light;
    DWORD type = 0;
    LSTATUS read = RegQueryValueExW(key, L"AppsUseLightTheme", NULL, &type,
                                    (LPBYTE)&light, &size);
    RegCloseKey(key);
    if (read != ERROR_SUCCESS || type != REG_DWORD) return 0;
    return light ? 0 : 1;
}

ctd_status ctd_surface_scale(ctd_handle surface, double *out) {
    double scale = 1.0;
    if (surface) {
        ctd_status problem;
        HWND window = ctd_surface_window(surface, &problem);
        if (!window) return problem;
        UINT dpi = GetDpiForWindow(window);
        if (dpi > 0) scale = (double)dpi / 96.0;
    } else {
        HDC screen = GetDC(NULL);
        if (screen) {
            scale = (double)GetDeviceCaps(screen, LOGPIXELSX) / 96.0;
            ReleaseDC(NULL, screen);
        }
    }
    if (scale <= 0.0) scale = 1.0;
    if (out) *out = scale;
    return CTD_OK;
}

// -------------------------------------------------------------------- fonts

int32_t ctd_font_family(int32_t role, char *out, int32_t cap) {
    if (role < CTD_FONT_BODY || role > CTD_FONT_MONO) return CTD_ERR_RANGE;
    // Consolas is the system's monospace face and has been since Vista.
    if (role == CTD_FONT_MONO) return ctd_copy_out("Consolas", out, cap);
    NONCLIENTMETRICSW metrics;
    memset(&metrics, 0, sizeof metrics);
    metrics.cbSize = sizeof metrics;
    if (!SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof metrics, &metrics, 0))
        return ctd_copy_out("Segoe UI", out, cap);
    return ctd_copy_wide_out(metrics.lfMessageFont.lfFaceName, out, cap);
}

ctd_status ctd_font_size(int32_t role, double *out) {
    if (role < CTD_FONT_BODY || role > CTD_FONT_MONO) return CTD_ERR_RANGE;
    double size = 9.0;
    NONCLIENTMETRICSW metrics;
    memset(&metrics, 0, sizeof metrics);
    metrics.cbSize = sizeof metrics;
    if (SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof metrics, &metrics, 0)) {
        HDC screen = GetDC(NULL);
        int dpi = screen ? GetDeviceCaps(screen, LOGPIXELSY) : 96;
        if (screen) ReleaseDC(NULL, screen);
        LONG height = metrics.lfMessageFont.lfHeight;
        if (height < 0) height = -height;
        if (height > 0) size = (double)MulDiv(height, 72, dpi);
    }
    if (role == CTD_FONT_HEADING) size += 4.0;
    if (role == CTD_FONT_CAPTION) size -= 2.0;
    if (out) *out = size;
    return CTD_OK;
}

// ------------------------------------------------------------ introspection

int32_t ctd_native_class(ctd_handle widget, char *out, int32_t cap) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    WCHAR name[128];
    // The class the window was registered under, which for a control is the
    // system's own name for it — "Button", "Edit", "msctls_trackbar32". Only
    // the host can ask, and this is the answer that proves a real native
    // control was built rather than something drawn.
    if (GetClassNameW(view, name, 128) <= 0) return CTD_ERR_PLATFORM;
    return ctd_copy_wide_out(name, out, cap);
}

int32_t ctd_a11y_role(ctd_handle widget, char *out, int32_t cap) {
    if (!ctd_slot(widget)) return CTD_ERR_STALE;
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
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    switch (ctd_slot_kind(widget)) {
        case CTD_W_BUTTON:
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON:
            // Through the platform's own dispatch: BM_CLICK makes the control
            // behave exactly as a mouse press does, including notifying its
            // parent, which is where cortado's event is born.
            SendMessageW(view, BM_CLICK, 0, 0);
            return CTD_OK;
        default:
            // A combo box cannot be clicked from here for the reason the header
            // gives: opening its list runs a modal tracking loop that never
            // returns to a test. `ctd_widget_synth_value` is the other half.
            return CTD_ERR_KIND;
    }
}

ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    ctd_handle target = widget;
    switch (ctd_slot_kind(widget)) {
        case CTD_W_SLIDER:
            SendMessageW(view, TBM_SETPOS, TRUE, (LPARAM)(LONG)value);
            // A trackbar told to move by a message does not notify its parent —
            // only a drag does — so the notification a drag would have sent is
            // sent here, on the control's behalf and through the same message.
            SendMessageW(GetParent(view), WM_HSCROLL,
                         MAKEWPARAM(SB_THUMBPOSITION, (WORD)(LONG)value),
                         (LPARAM)view);
            return CTD_OK;
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON: {
            ctd_status wrote = ctd_set_int(widget, CTD_P_CHECKED, index);
            if (wrote != CTD_OK) return wrote;
            ctd_emit_control(target);
            return CTD_OK;
        }
        case CTD_W_COMBO_BOX: {
            ctd_status wrote = ctd_set_int(widget, CTD_P_SELECTED, index);
            if (wrote != CTD_OK) return wrote;
            SendMessageW(GetParent(view), WM_COMMAND,
                         MAKEWPARAM(0, CBN_SELCHANGE), (LPARAM)view);
            return CTD_OK;
        }
        default: return CTD_ERR_KIND;
    }
}

ctd_status ctd_widget_synth_text(ctd_handle widget, const char *utf8, int32_t len) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int32_t kind = ctd_slot_kind(widget);
    if (kind != CTD_W_TEXT_FIELD && kind != CTD_W_TEXT_AREA) return CTD_ERR_KIND;
    ctd_status wrote = ctd_set_text(widget, utf8, len);
    if (wrote != CTD_OK) return wrote;
    // Typed text is committed when the field is left or Return is pressed, and
    // an edit box reports the first through its parent. This is that message,
    // sent the way the control itself would send it.
    if (kind == CTD_W_TEXT_FIELD) {
        SendMessageW(GetParent(view), WM_COMMAND,
                     MAKEWPARAM(0, EN_KILLFOCUS), (LPARAM)view);
    }
    return CTD_OK;
}
