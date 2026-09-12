// The pointer, the keyboard, and where the keys go.
//
// Win32's shape again, which is the same one everything else in this host
// follows: a control is a window, its input arrives as messages to that
// window, and cortado subclasses the window to see them. What differs from
// the rest is only which messages — WM_LBUTTONDOWN rather than WM_COMMAND —
// because a click on a button is reported to the button, and the *notification*
// that follows is what is reported to the parent.
//
// This is one of the two hosts that can synthesise real input: SendMessageW
// delivers the same message the driver delivers, through the same window
// procedure. GTK4 and UIKit cannot, and the header says which is which.

#include "internal.h"

// GET_X_LPARAM and GET_Y_LPARAM, which are macros in this header and nowhere
// else — a mouse message packs both coordinates into one LPARAM.
#include <windowsx.h>

// Whether anything is listening, per event kind. The header calls ctd_listen
// advice rather than permission; this is what the advice becomes.
static int g_wanted[CTD_EV_COUNT];

// The handle a window was tracked under. A window property rather than a table
// of cortado's own: Win32 already keeps one per window, the lookup is a hash,
// and it goes away with the window.
#define CTD_HANDLE_PROP L"cortado-handle"

int ctd_listening(uint32_t kind) {
    if (kind >= (uint32_t)CTD_EV_COUNT) return 0;
    return g_wanted[kind];
}

ctd_status ctd_listen(int32_t kind, int32_t on) {
    if (kind < 0 || kind >= CTD_EV_COUNT) return CTD_ERR_RANGE;
    // Win32 sends a control its messages whether or not anyone reads them, so
    // there is nothing to turn off here beyond the crossing into the program —
    // which is what the header allows this call to be: advice.
    g_wanted[kind] = on ? 1 : 0;
    return CTD_OK;
}

ctd_handle ctd_handle_for_window(HWND window) {
    while (window) {
        HANDLE kept = GetPropW(window, CTD_HANDLE_PROP);
        if (kept) return (ctd_handle)(uintptr_t)kept;
        window = GetParent(window);
    }
    return 0;
}

// ----------------------------------------------------------------------- keys

static int32_t ctd_key_of_vk(WPARAM vk) {
    switch (vk) {
        case VK_ESCAPE: return CTD_KEY_ESCAPE;
        case VK_TAB:    return CTD_KEY_TAB;
        case VK_RETURN: return CTD_KEY_RETURN;
        case VK_SPACE:  return CTD_KEY_SPACE;
        case VK_BACK:   return CTD_KEY_BACKSPACE;
        case VK_DELETE: return CTD_KEY_DELETE;
        case VK_LEFT:   return CTD_KEY_LEFT;
        case VK_RIGHT:  return CTD_KEY_RIGHT;
        case VK_UP:     return CTD_KEY_UP;
        case VK_DOWN:   return CTD_KEY_DOWN;
        case VK_HOME:   return CTD_KEY_HOME;
        case VK_END:    return CTD_KEY_END;
        case VK_PRIOR:  return CTD_KEY_PAGE_UP;
        case VK_NEXT:   return CTD_KEY_PAGE_DOWN;
        case VK_F1:     return CTD_KEY_F1;
        case VK_F2:     return CTD_KEY_F2;
        case VK_F3:     return CTD_KEY_F3;
        case VK_F4:     return CTD_KEY_F4;
        case VK_F5:     return CTD_KEY_F5;
        case VK_F6:     return CTD_KEY_F6;
        case VK_F7:     return CTD_KEY_F7;
        case VK_F8:     return CTD_KEY_F8;
        case VK_F9:     return CTD_KEY_F9;
        case VK_F10:    return CTD_KEY_F10;
        case VK_F11:    return CTD_KEY_F11;
        case VK_F12:    return CTD_KEY_F12;
        default:        return CTD_KEY_CHARACTER;
    }
}

static WPARAM ctd_vk_of_key(int32_t key) {
    switch (key) {
        case CTD_KEY_ESCAPE:    return VK_ESCAPE;
        case CTD_KEY_TAB:       return VK_TAB;
        case CTD_KEY_RETURN:    return VK_RETURN;
        case CTD_KEY_SPACE:     return VK_SPACE;
        case CTD_KEY_BACKSPACE: return VK_BACK;
        case CTD_KEY_DELETE:    return VK_DELETE;
        case CTD_KEY_LEFT:      return VK_LEFT;
        case CTD_KEY_RIGHT:     return VK_RIGHT;
        case CTD_KEY_UP:        return VK_UP;
        case CTD_KEY_DOWN:      return VK_DOWN;
        case CTD_KEY_HOME:      return VK_HOME;
        case CTD_KEY_END:       return VK_END;
        case CTD_KEY_PAGE_UP:   return VK_PRIOR;
        case CTD_KEY_PAGE_DOWN: return VK_NEXT;
        case CTD_KEY_F1:        return VK_F1;
        case CTD_KEY_F2:        return VK_F2;
        case CTD_KEY_F3:        return VK_F3;
        case CTD_KEY_F4:        return VK_F4;
        case CTD_KEY_F5:        return VK_F5;
        case CTD_KEY_F6:        return VK_F6;
        case CTD_KEY_F7:        return VK_F7;
        case CTD_KEY_F8:        return VK_F8;
        case CTD_KEY_F9:        return VK_F9;
        case CTD_KEY_F10:       return VK_F10;
        case CTD_KEY_F11:       return VK_F11;
        case CTD_KEY_F12:       return VK_F12;
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

// Which modifier keys are down. Win32 has no modifier field on a mouse or key
// message — WM_LBUTTONDOWN's wParam carries MK_SHIFT and MK_CONTROL and
// nothing about Alt — so the keyboard is asked directly, which is what every
// Windows application does and what gives the same four bits every time.
// The modifiers a synthesised key is carrying, and whether there are any.
//
// Win32 has no modifier field on a key message: WM_KEYDOWN carries the virtual
// key and nothing about Shift, so the handler asks the keyboard. A synthesised
// key has no keyboard behind it, so the handler would report whatever the
// person at the machine happens to be holding — nothing, in a headless run —
// and every test of a modifier would pass for the wrong reason. Set for the
// length of one SendMessageW, which is a single call on the UI thread.
static uint32_t g_synth_modifiers;
static int      g_synth_modifiers_set;

static uint32_t ctd_modifiers_now(void) {
    if (g_synth_modifiers_set) return g_synth_modifiers;
    uint32_t bits = 0;
    if (GetKeyState(VK_SHIFT)   & 0x8000) bits |= CTD_MOD_SHIFT;
    if (GetKeyState(VK_CONTROL) & 0x8000) bits |= CTD_MOD_CONTROL;
    if (GetKeyState(VK_MENU)    & 0x8000) bits |= CTD_MOD_ALT;
    if (GetKeyState(VK_LWIN)    & 0x8000) bits |= CTD_MOD_COMMAND;
    if (GetKeyState(VK_RWIN)    & 0x8000) bits |= CTD_MOD_COMMAND;
    return bits;
}

// The character a virtual key types on this keyboard, or an empty string for a
// key that types nothing. ToUnicode is what Windows itself uses to turn a key
// into text, so a German keyboard's "z" comes out "y" here exactly as it does
// in Notepad.
static void ctd_typed_by(WPARAM vk, char *out, size_t cap) {
    out[0] = '\0';
    BYTE state[256];
    if (!GetKeyboardState(state)) return;
    WCHAR wide[8];
    int written = ToUnicode((UINT)vk, MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_VSC),
                            state, wide, 8, 0);
    if (written <= 0) return;
    // A control character is not text. ToUnicode answers 0x1B for Escape and
    // 0x0D for Return, and a field appending what it hears would fill with
    // control codes. Space is U+0020 and stays.
    if (wide[0] < 0x20 || wide[0] == 0x7f) return;
    WideCharToMultiByte(CP_UTF8, 0, wide, written, out, (int)cap - 1, NULL, NULL);
    out[cap - 1] = '\0';
}

// ---------------------------------------------------------------- the raising

static void ctd_raise_pointer(uint32_t kind, HWND window, LPARAM where,
                              int32_t button) {
    if (!g_sink || !ctd_listening(kind)) return;
    ctd_handle target = ctd_handle_for_window(window);
    if (!target) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = target;
    out.index = button;
    out.modifiers = ctd_modifiers_now();
    // Already in the control's own space: Win32's mouse messages carry client
    // coordinates, which is the same space ctd_view_set_frame uses.
    out.x = (double)GET_X_LPARAM(where);
    out.y = (double)GET_Y_LPARAM(where);
    g_sink(g_sink_context, &out);
}

static void ctd_raise_key(uint32_t kind, HWND window, WPARAM vk) {
    if (!g_sink || !ctd_listening(kind)) return;
    ctd_handle target = ctd_handle_for_window(window);
    if (!target) return;
    char typed[32];
    ctd_typed_by(vk, typed, sizeof typed);
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = target;
    out.index = ctd_key_of_vk(vk);
    out.modifiers = ctd_modifiers_now();
    out.text = typed;
    out.text_len = (int32_t)strlen(typed);
    g_sink(g_sink_context, &out);
}

// ------------------------------------------------------------- the subclass

static LRESULT CALLBACK ctd_input_proc(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam,
                                       UINT_PTR id, DWORD_PTR data) {
    (void)id; (void)data;
    switch (message) {
        case WM_LBUTTONDOWN: ctd_raise_pointer(CTD_EV_POINTER_DOWN, window, lparam, CTD_BTN_LEFT);   break;
        case WM_RBUTTONDOWN: ctd_raise_pointer(CTD_EV_POINTER_DOWN, window, lparam, CTD_BTN_RIGHT);  break;
        case WM_MBUTTONDOWN: ctd_raise_pointer(CTD_EV_POINTER_DOWN, window, lparam, CTD_BTN_MIDDLE); break;
        case WM_LBUTTONUP:   ctd_raise_pointer(CTD_EV_POINTER_UP,   window, lparam, CTD_BTN_LEFT);   break;
        case WM_RBUTTONUP:   ctd_raise_pointer(CTD_EV_POINTER_UP,   window, lparam, CTD_BTN_RIGHT);  break;
        case WM_MBUTTONUP:   ctd_raise_pointer(CTD_EV_POINTER_UP,   window, lparam, CTD_BTN_MIDDLE); break;
        case WM_MOUSEMOVE:   ctd_raise_pointer(CTD_EV_POINTER_MOVE, window, lparam, CTD_BTN_LEFT);   break;
        case WM_KEYDOWN:
        case WM_SYSKEYDOWN:  ctd_raise_key(CTD_EV_KEY_DOWN, window, wparam); break;
        case WM_KEYUP:
        case WM_SYSKEYUP:    ctd_raise_key(CTD_EV_KEY_UP,   window, wparam); break;
        case WM_SETFOCUS:
            if (ctd_listening(CTD_EV_FOCUS)) {
                ctd_handle took = ctd_handle_for_window(window);
                if (took) ctd_emit(CTD_EV_FOCUS, took, 0, 0);
            }
            break;
        case WM_KILLFOCUS:
            if (ctd_listening(CTD_EV_BLUR)) {
                ctd_handle left = ctd_handle_for_window(window);
                if (left) ctd_emit(CTD_EV_BLUR, left, 0, 0);
            }
            break;
        case WM_NCDESTROY:
            RemovePropW(window, CTD_HANDLE_PROP);
            break;
        default: break;
    }
    // Always on to the control. Swallowing a click would stop a button from
    // being a button, and swallowing a key would stop a field from taking
    // what was typed into it.
    return DefSubclassProc(window, message, wparam, lparam);
}

// Called from ctd_track, the one place every control passes through.
void ctd_input_attach(void *object, int32_t type, ctd_handle handle) {
    if (type != CTD_T_WIDGET && type != CTD_T_SURFACE) return;
    HWND window = (HWND)object;
    if (!IsWindow(window)) return;
    SetPropW(window, CTD_HANDLE_PROP, (HANDLE)(uintptr_t)handle);
    // Id 2: id 1 is the edit subclass in widget.c, and two subclasses of one
    // window must not share an id or the second replaces the first.
    SetWindowSubclass(window, ctd_input_proc, 2, 0);
}

// ---------------------------------------------------------------------- focus

ctd_status ctd_widget_focus(ctd_handle widget) {
    HWND window = ctd_window(widget);
    if (!window || !IsWindow(window)) return CTD_ERR_STALE;
    // A control that is disabled or hidden cannot take the keyboard, and Win32
    // says so by refusing rather than by failing.
    if (!IsWindowEnabled(window)) return CTD_ERR_UNSUPPORTED;
    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    if (!(style & WS_TABSTOP)) return CTD_ERR_UNSUPPORTED;
    SetFocus(window);
    return GetFocus() == window ? CTD_OK : CTD_ERR_UNSUPPORTED;
}

int32_t ctd_widget_focused(ctd_handle widget) {
    HWND window = ctd_window(widget);
    if (!window) return 0;
    return GetFocus() == window ? 1 : 0;
}

// ----------------------------------------------------------------- synthesis

ctd_status ctd_widget_synth_pointer(ctd_handle widget, int32_t what,
                                    double x, double y, int32_t button) {
    if (what != CTD_EV_POINTER_DOWN && what != CTD_EV_POINTER_UP &&
        what != CTD_EV_POINTER_MOVE) return CTD_ERR_RANGE;
    if (button < CTD_BTN_LEFT || button > CTD_BTN_MIDDLE) return CTD_ERR_RANGE;
    HWND window = ctd_window(widget);
    if (!window || !IsWindow(window)) return CTD_ERR_STALE;

    UINT message;
    if (what == CTD_EV_POINTER_MOVE)       message = WM_MOUSEMOVE;
    else if (button == CTD_BTN_RIGHT)      message = what == CTD_EV_POINTER_DOWN
                                                       ? WM_RBUTTONDOWN : WM_RBUTTONUP;
    else if (button == CTD_BTN_MIDDLE)     message = what == CTD_EV_POINTER_DOWN
                                                       ? WM_MBUTTONDOWN : WM_MBUTTONUP;
    else                                   message = what == CTD_EV_POINTER_DOWN
                                                       ? WM_LBUTTONDOWN : WM_LBUTTONUP;
    WPARAM held = 0;
    if (what != CTD_EV_POINTER_MOVE) {
        held = button == CTD_BTN_RIGHT ? MK_RBUTTON
             : button == CTD_BTN_MIDDLE ? MK_MBUTTON : MK_LBUTTON;
    }
    // The same message the driver sends, through the same window procedure.
    // No modifiers: a synthesised pointer event carries none, which is what
    // ctd_widget_synth_pointer is given and what every host reports for it.
    g_synth_modifiers = 0;
    g_synth_modifiers_set = 1;
    SendMessageW(window, message, held, MAKELPARAM((int)x, (int)y));
    g_synth_modifiers_set = 0;
    return CTD_OK;
}

ctd_status ctd_widget_synth_key(ctd_handle widget, int32_t what, int32_t key,
                                const char *text, int32_t len,
                                uint32_t modifiers) {
    if (what != CTD_EV_KEY_DOWN && what != CTD_EV_KEY_UP) return CTD_ERR_RANGE;
    if (key < 0 || key >= CTD_KEY_COUNT) return CTD_ERR_RANGE;
    if (ctd_has_nul(text, len)) return CTD_ERR_RANGE;
    HWND window = ctd_window(widget);
    if (!window || !IsWindow(window)) return CTD_ERR_STALE;
    if (GetFocus() != window) {
        ctd_status moved = ctd_widget_focus(widget);
        if (moved != CTD_OK) return moved;
    }

    // A virtual key, because that is what a real key message carries. The
    // character is derived from it by the same ToUnicode the handler uses, so
    // a synthesised key and a pressed one produce the same text.
    WPARAM vk = ctd_vk_of_key(key);
    if (!vk && text && len > 0) {
        WCHAR wide[4] = {0};
        if (MultiByteToWideChar(CP_UTF8, 0, text,
                                len < 4 ? len : 4, wide, 4) > 0) {
            SHORT scanned = VkKeyScanW(wide[0]);
            if (scanned != -1) vk = (WPARAM)(scanned & 0xff);
        }
    }
    g_synth_modifiers = modifiers;
    g_synth_modifiers_set = 1;
    SendMessageW(window, what == CTD_EV_KEY_DOWN ? WM_KEYDOWN : WM_KEYUP, vk, 0);
    g_synth_modifiers_set = 0;
    g_synth_modifiers = 0;
    return CTD_OK;
}
