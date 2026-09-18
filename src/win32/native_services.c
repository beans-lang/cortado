#include "internal.h"
#include <wchar.h>

#define CTD_IM_PROP L"cortado-shared-im"
typedef struct { int active, composing; WCHAR high; } CortadoIM;
static CortadoIM *ctd_im(HWND window) { return (CortadoIM *)GetPropW(window, CTD_IM_PROP); }
int ctd_canvas_text_active(HWND window) { CortadoIM *im = ctd_im(window); return im && im->active; }
void ctd_canvas_im_release(HWND window) { free(RemovePropW(window, CTD_IM_PROP)); }

static void ctd_emit_wide(HWND window, uint32_t kind, const WCHAR *wide,
                          int count, int64_t index, int64_t token) {
    if (!g_sink || !ctd_listening(kind)) return;
    ctd_handle target = ctd_handle_for_window(window);
    if (!target) return;
    int length = count ? WideCharToMultiByte(CP_UTF8, 0, wide, count, NULL, 0, NULL, NULL) : 0;
    if (length < 0) return;
    char *text = malloc((size_t)length + 1);
    if (!text) return;
    if (length) WideCharToMultiByte(CP_UTF8, 0, wide, count, text, length, NULL, NULL);
    text[length] = 0;
    ctd_event event; memset(&event, 0, sizeof event);
    event.kind = kind; event.target = target; event.index = index; event.token = token;
    event.text = text; event.text_len = length;
    g_sink(g_sink_context, &event);
    free(text);
}

static void ctd_ime_text(HWND window, HIMC context, DWORD selector,
                         uint32_t kind, int with_cursor) {
    LONG bytes = ImmGetCompositionStringW(context, selector, NULL, 0);
    if (bytes < 0) return;
    WCHAR *wide = calloc((size_t)bytes + sizeof(WCHAR), 1);
    if (!wide) return;
    if (bytes) ImmGetCompositionStringW(context, selector, wide, (DWORD)bytes);
    int count = (int)(bytes / sizeof(WCHAR));
    int64_t cursor_bytes = 0;
    if (with_cursor) {
        LONG at = ImmGetCompositionStringW(context, GCS_CURSORPOS, NULL, 0);
        if (at > count) at = count;
        if (at > 0) cursor_bytes = WideCharToMultiByte(CP_UTF8, 0, wide, at, NULL, 0, NULL, NULL);
    }
    ctd_emit_wide(window, kind, wide, count,
                  kind == CTD_EV_TEXT_INPUT ? -1 : cursor_bytes,
                  kind == CTD_EV_TEXT_INPUT ? -1 : cursor_bytes);
    free(wide);
}

void ctd_canvas_im_message(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    CortadoIM *im = ctd_im(window);
    if (!im || !im->active) return;
    if (message == WM_CHAR || message == WM_UNICHAR) {
        WCHAR units[2]; int count = 0; WCHAR one = (WCHAR)wparam;
        if (message == WM_UNICHAR && wparam > 0xffff && wparam <= 0x10ffff) {
            uint32_t code = (uint32_t)wparam - 0x10000;
            units[0] = (WCHAR)(0xd800 + (code >> 10));
            units[1] = (WCHAR)(0xdc00 + (code & 0x3ff));
            im->high = 0;
            ctd_emit_wide(window, CTD_EV_TEXT_INPUT, units, 2, -1, -1);
            return;
        }
        if (one < 0x20 || one == 0x7f) return;
        if (one >= 0xd800 && one <= 0xdbff) { im->high = one; return; }
        if (im->high && one >= 0xdc00 && one <= 0xdfff) units[count++] = im->high;
        im->high = 0; units[count++] = one;
        ctd_emit_wide(window, CTD_EV_TEXT_INPUT, units, count, -1, -1);
        return;
    }
    if (message == WM_IME_COMPOSITION) {
        HIMC context = ImmGetContext(window);
        if (!context) return;
        if (lparam & GCS_RESULTSTR) {
            ctd_ime_text(window, context, GCS_RESULTSTR, CTD_EV_TEXT_INPUT, 0);
            im->composing = 0;
        }
        if (lparam & GCS_COMPSTR) {
            ctd_ime_text(window, context, GCS_COMPSTR, CTD_EV_COMPOSITION_UPDATE, 1);
            im->composing = 1;
        }
        ImmReleaseContext(window, context);
        return;
    }
    if (message == WM_IME_ENDCOMPOSITION && im->composing) {
        im->composing = 0;
        ctd_emit_wide(window, CTD_EV_COMPOSITION_CANCEL, L"", 0, 0, 0);
    }
}

ctd_status ctd_canvas_text_state(ctd_handle handle, int32_t active,
    const char *utf8, int32_t length, int32_t anchor, int32_t caret,
    double x, double y, double width, double height) {
    uint32_t slot = ctd_slot(handle);
    if (!slot) return CTD_ERR_STALE;
    if (ctd_slot_kind(handle) != CTD_W_CANVAS) return CTD_ERR_KIND;
    if (length < 0 || (length && !utf8) || anchor < 0 || caret < 0 ||
        anchor > length || caret > length || width < 0 || height < 0) return CTD_ERR_RANGE;
    HWND window = (HWND)g_object[slot];
    CortadoIM *im = ctd_im(window);
    if (!im && active) {
        im = calloc(1, sizeof(*im));
        if (!im || !SetPropW(window, CTD_IM_PROP, im)) { free(im); return CTD_ERR_PLATFORM; }
    }
    if (!im) return CTD_OK;
    im->active = active != 0;
    if (!im->active) { im->composing = 0; im->high = 0; return CTD_OK; }
    HIMC context = ImmGetContext(window);
    if (context) {
        COMPOSITIONFORM composition = { CFS_POINT, { (LONG)x, (LONG)y }, {0,0,0,0} };
        ImmSetCompositionWindow(context, &composition);
        CANDIDATEFORM candidate = { 0, CFS_CANDIDATEPOS, { (LONG)x, (LONG)(y + height) }, {0,0,0,0} };
        ImmSetCandidateWindow(context, &candidate);
        ImmReleaseContext(window, context);
    }
    return CTD_OK;
}

ctd_status ctd_clipboard_write(const char *utf8, int32_t length) {
    if (length < 0 || (length && !utf8)) return CTD_ERR_RANGE;
    WCHAR *wide = ctd_wide(utf8, length);
    if (!wide) return CTD_ERR_PLATFORM;
    if (!OpenClipboard(NULL)) { free(wide); return CTD_ERR_PLATFORM; }
    SIZE_T bytes = (wcslen(wide) + 1) * sizeof(WCHAR);
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!memory) { CloseClipboard(); free(wide); return CTD_ERR_PLATFORM; }
    void *destination = GlobalLock(memory);
    if (!destination) { GlobalFree(memory); CloseClipboard(); free(wide); return CTD_ERR_PLATFORM; }
    memcpy(destination, wide, bytes); GlobalUnlock(memory); free(wide);
    if (!EmptyClipboard() || !SetClipboardData(CF_UNICODETEXT, memory)) {
        GlobalFree(memory); CloseClipboard(); return CTD_ERR_PLATFORM;
    }
    CloseClipboard(); return CTD_OK;
}
int32_t ctd_clipboard_read(char *out, int32_t cap) {
    if (cap < 0) return CTD_ERR_RANGE;
    if (!OpenClipboard(NULL)) return CTD_ERR_PLATFORM;
    HANDLE memory = GetClipboardData(CF_UNICODETEXT);
    if (!memory) { CloseClipboard(); return 0; }
    WCHAR *wide = GlobalLock(memory);
    if (!wide) { CloseClipboard(); return CTD_ERR_PLATFORM; }
    int32_t needed = ctd_copy_wide_out(wide, NULL, 0);
    if (out && cap < needed) { GlobalUnlock(memory); CloseClipboard(); return CTD_ERR_RANGE; }
    if (out && needed) ctd_copy_wide_out(wide, out, cap);
    GlobalUnlock(memory); CloseClipboard(); return needed;
}
