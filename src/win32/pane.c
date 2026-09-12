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
