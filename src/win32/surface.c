// Windows: making them, titling them, showing them, and what they contain.

#include "internal.h"

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

HWND ctd_surface_window(ctd_handle handle, ctd_status *problem) {
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

// One of the four things that happen to a surface.
//
// Guarded on ctd_listening for the same reason every input event is: a window
// being dragged by its corner sends WM_SIZE on every frame of the drag, and a
// program that is not listening should not be crossed into sixty times a
// second to be told something it does not want.
void ctd_surface_event(uint32_t kind, ctd_handle surface, double a, double b) {
    if (!g_sink || !surface) return;
    if (!ctd_listening(kind)) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = surface;
    if (kind == CTD_EV_SURFACE_RESIZED) {
        out.width = a;
        out.height = b;
    } else if (kind == CTD_EV_APPEARANCE || kind == CTD_EV_SCALE_CHANGED) {
        out.index = (int64_t)a;
        out.x = a;
    }
    g_sink(g_sink_context, &out);
}

ctd_status ctd_surface_synth(ctd_handle surface, int32_t what,
                             double a, double b) {
    HWND window = ctd_window(surface);
    if (!window || !IsWindow(window)) return CTD_ERR_STALE;
    switch (what) {
        case CTD_EV_SURFACE_RESIZED: {
            if (!(a >= 0.0) || !(b >= 0.0)) return CTD_ERR_RANGE;
            // A real resize, so WM_SIZE is what arrives — and outside
            // g_writing, because this stands in for the user dragging the
            // corner and not for the program.
            RECT want = { 0, 0, (LONG)a, (LONG)b };
            AdjustWindowRect(&want, (DWORD)GetWindowLongPtrW(window, GWL_STYLE), FALSE);
            SetWindowPos(window, NULL, 0, 0,
                         want.right - want.left, want.bottom - want.top,
                         SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
            return CTD_OK;
        }
        case CTD_EV_SURFACE_CLOSE:
            // WM_CLOSE is the title bar's button, which is the road a real
            // click takes.
            SendMessageW(window, WM_CLOSE, 0, 0);
            return CTD_OK;
        case CTD_EV_APPEARANCE:
        case CTD_EV_SCALE_CHANGED:
            ctd_surface_event((uint32_t)what, surface, a, b);
            return CTD_OK;
        default:
            return CTD_ERR_RANGE;
    }
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
