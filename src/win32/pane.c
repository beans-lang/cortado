// The containers a platform draws chrome for.
//
// One of them here, and it is the group box. The common controls have no
// disclosure — see ctd_widget_supports in widget.c — so there is nothing else
// on this platform that keeps part of its own frame.
//
// Windows has no call that answers "how much of a group box is the caption",
// the way AppKit's content view and GTK's measurement do. What it has is the
// two numbers the caption is made of: the height of a line in the dialog font,
// and the size of a window edge. Both are the system's, read at run time, and
// both follow the user's text size and theme — which is the whole reason this
// is not three constants written in this file.

#include "internal.h"

static void ctd_tab_chrome(double *out);

static void ctd_group_chrome(double *out) {
    static double known[4];
    static int asked = 0;
    if (!asked) {
        double edge_x = (double)GetSystemMetrics(SM_CXEDGE);
        double edge_y = (double)GetSystemMetrics(SM_CYEDGE);
        double caption = edge_y;
        HDC canvas = GetDC(NULL);
        if (canvas) {
            HGDIOBJ was = SelectObject(canvas, g_ui_font);
            TEXTMETRICW metrics;
            if (GetTextMetricsW(canvas, &metrics)) {
                caption = (double)metrics.tmHeight;
            }
            SelectObject(canvas, was);
            ReleaseDC(NULL, canvas);
        }
        known[0] = edge_x;
        known[1] = caption;
        known[2] = edge_x;
        known[3] = edge_y;
        asked = 1;
    }
    out[0] = known[0]; out[1] = known[1]; out[2] = known[2]; out[3] = known[3];
}

void ctd_chrome_of(ctd_handle widget, double *out) {
    out[0] = 0.0; out[1] = 0.0; out[2] = 0.0; out[3] = 0.0;
    if (ctd_slot_kind(widget) == CTD_W_GROUP_BOX) ctd_group_chrome(out);
    if (ctd_slot_kind(widget) == CTD_W_TAB_VIEW) ctd_tab_chrome(out);
}

ctd_status ctd_view_content_inset(ctd_handle widget, double *out_inset) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    double chrome[4];
    ctd_chrome_of(widget, chrome);
    if (out_inset) {
        out_inset[0] = chrome[0];
        out_inset[1] = chrome[1];
        out_inset[2] = chrome[2];
        out_inset[3] = chrome[3];
    }
    return CTD_OK;
}

// ------------------------------------------------------------------ tab views
//
// A tab control on Windows is the *strip* and nothing else: it holds a row of
// labels and a current index, and showing the right page is the application's
// job. So a page here is an ordinary child window of the tab control — which
// is also what makes the child walk, the reorder and the tree dump work
// without a special case — and `ctd_tab_sync` is what keeps the strip's item
// count and the pages' visibility in step with it.

static int ctd_tab_is(ctd_handle widget) {
    return ctd_slot_kind(widget) == CTD_W_TAB_VIEW;
}

// Makes the strip agree with the children, and shows exactly one page.
void ctd_tab_sync(ctd_handle widget) {
    HWND tabs = ctd_window(widget);
    if (!tabs || !ctd_tab_is(widget)) return;
    HWND ours[256];
    int32_t count = ctd_own_children(tabs, ours, 256);
    int32_t items = (int32_t)SendMessageW(tabs, TCM_GETITEMCOUNT, 0, 0);
    // Items are added and removed at the end; a label belongs to a page by
    // position, and a page that moves takes its label with it because
    // ctd_view_move_child reorders both.
    while (items < count) {
        TCITEMW blank;
        memset(&blank, 0, sizeof blank);
        blank.mask = TCIF_TEXT;
        blank.pszText = L"";
        SendMessageW(tabs, TCM_INSERTITEMW, (WPARAM)items, (LPARAM)&blank);
        items++;
    }
    while (items > count) {
        items--;
        SendMessageW(tabs, TCM_DELETEITEM, (WPARAM)items, 0);
    }
    int32_t showing = (int32_t)SendMessageW(tabs, TCM_GETCURSEL, 0, 0);
    if (showing < 0 && count > 0) {
        showing = 0;
        SendMessageW(tabs, TCM_SETCURSEL, 0, 0);
    }
    RECT display;
    GetClientRect(tabs, &display);
    SendMessageW(tabs, TCM_ADJUSTRECT, FALSE, (LPARAM)&display);
    for (int32_t at = 0; at < count; at++) {
        ShowWindow(ours[at], at == showing ? SW_SHOW : SW_HIDE);
        SetWindowPos(ours[at], NULL, display.left, display.top,
                     display.right - display.left, display.bottom - display.top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
    }
}

// The strip's own height, from the control rather than from a number here:
// TCM_ADJUSTRECT is what Windows uses to turn a window rect into the rect a
// page gets, and the difference between the two is the chrome.
static void ctd_tab_chrome(double *out) {
    static double known[4];
    static int asked = 0;
    if (!asked) {
        HWND ruler = CreateWindowExW(0, WC_TABCONTROLW, L"", WS_CHILD,
                                     0, 0, 400, 300, g_limbo, NULL,
                                     GetModuleHandleW(NULL), NULL);
        if (ruler) {
            SendMessageW(ruler, WM_SETFONT, (WPARAM)g_ui_font, TRUE);
            TCITEMW one;
            memset(&one, 0, sizeof one);
            one.mask = TCIF_TEXT;
            one.pszText = L"X";
            SendMessageW(ruler, TCM_INSERTITEMW, 0, (LPARAM)&one);
            RECT whole = { 0, 0, 400, 300 };
            RECT inner = whole;
            SendMessageW(ruler, TCM_ADJUSTRECT, FALSE, (LPARAM)&inner);
            known[0] = (double)(inner.left - whole.left);
            known[1] = (double)(inner.top - whole.top);
            known[2] = (double)(whole.right - inner.right);
            known[3] = (double)(whole.bottom - inner.bottom);
            DestroyWindow(ruler);
        }
        asked = 1;
    }
    out[0] = known[0]; out[1] = known[1]; out[2] = known[2]; out[3] = known[3];
}

ctd_status ctd_tab_set_label(ctd_handle widget, int32_t index,
                             const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    HWND tabs = ctd_window(widget);
    if (!tabs) return CTD_ERR_STALE;
    if (!ctd_tab_is(widget)) return CTD_ERR_KIND;
    if (index < 0 || index >= (int32_t)SendMessageW(tabs, TCM_GETITEMCOUNT, 0, 0))
        return CTD_ERR_RANGE;
    WCHAR *wide = ctd_wide(utf8, len);
    if (!wide) return CTD_ERR_PLATFORM;
    TCITEMW item;
    memset(&item, 0, sizeof item);
    item.mask = TCIF_TEXT;
    item.pszText = wide;
    SendMessageW(tabs, TCM_SETITEMW, (WPARAM)index, (LPARAM)&item);
    free(wide);
    return CTD_OK;
}

int32_t ctd_tab_label(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    HWND tabs = ctd_window(widget);
    if (!tabs) return CTD_ERR_STALE;
    if (!ctd_tab_is(widget)) return CTD_ERR_KIND;
    if (index < 0 || index >= (int32_t)SendMessageW(tabs, TCM_GETITEMCOUNT, 0, 0))
        return CTD_ERR_RANGE;
    WCHAR words[512];
    words[0] = L'\0';
    TCITEMW item;
    memset(&item, 0, sizeof item);
    item.mask = TCIF_TEXT;
    item.pszText = words;
    item.cchTextMax = 512;
    SendMessageW(tabs, TCM_GETITEMW, (WPARAM)index, (LPARAM)&item);
    return ctd_copy_wide_out(words, out, cap);
}
