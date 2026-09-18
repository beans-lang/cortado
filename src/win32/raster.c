#include "internal.h"

typedef struct {
    BITMAPINFO info;
    unsigned char *pixels;
} CortadoRaster;

static LRESULT CALLBACK ctd_raster_proc(HWND window, UINT message, WPARAM wparam,
                                        LPARAM lparam, UINT_PTR id, DWORD_PTR reference) {
    CortadoRaster *frame = (CortadoRaster *)reference;
    if (message == WM_PAINT) {
        PAINTSTRUCT paint;
        HDC dc = BeginPaint(window, &paint);
        RECT rect;
        GetClientRect(window, &rect);
        StretchDIBits(dc, 0, 0, rect.right, rect.bottom, 0, 0,
            frame->info.bmiHeader.biWidth, -frame->info.bmiHeader.biHeight,
            frame->pixels, &frame->info, DIB_RGB_COLORS, SRCCOPY);
        EndPaint(window, &paint);
        return 0;
    }
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_NCDESTROY) {
        RemoveWindowSubclass(window, ctd_raster_proc, id);
        free(frame->pixels);
        free(frame);
    }
    return DefSubclassProc(window, message, wparam, lparam);
}

ctd_status ctd_canvas_set_pixels(ctd_handle handle, int32_t width, int32_t height,
                                 const char *rgba, int32_t length) {
    uint32_t slot = ctd_slot(handle);
    if (!slot) return CTD_ERR_STALE;
    if (ctd_slot_kind(handle) != CTD_W_CANVAS) return CTD_ERR_KIND;
    if (!rgba || width <= 0 || height <= 0 || width > 16384 || height > 16384 ||
        (int64_t)width * height * 4 != length) return CTD_ERR_RANGE;
    /* Desktop surfaces are opaque. Translucent visuals are composited by the
     * renderer before submission, so every platform presents the same frame. */
    for (int32_t at = 3; at < length; at += 4)
        if ((unsigned char)rgba[at] != 255) return CTD_ERR_RANGE;
    HWND window = (HWND)g_object[slot];
    DWORD_PTR reference = 0;
    CortadoRaster *frame;
    if (GetWindowSubclass(window, ctd_raster_proc, 1, &reference)) frame = (CortadoRaster *)reference;
    else {
        frame = calloc(1, sizeof(*frame));
        if (!frame) return CTD_ERR_PLATFORM;
        if (!SetWindowSubclass(window, ctd_raster_proc, 1, (DWORD_PTR)frame)) {
            free(frame); return CTD_ERR_PLATFORM;
        }
    }
    unsigned char *copy = malloc((size_t)length);
    if (!copy) return CTD_ERR_PLATFORM;
    for (int32_t at = 0; at < length; at += 4) {
        copy[at] = (unsigned char)rgba[at + 2];
        copy[at + 1] = (unsigned char)rgba[at + 1];
        copy[at + 2] = (unsigned char)rgba[at];
        copy[at + 3] = (unsigned char)rgba[at + 3];
    }
    free(frame->pixels);
    frame->pixels = copy;
    frame->info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    frame->info.bmiHeader.biWidth = width;
    frame->info.bmiHeader.biHeight = -height;
    frame->info.bmiHeader.biPlanes = 1;
    frame->info.bmiHeader.biBitCount = 32;
    frame->info.bmiHeader.biCompression = BI_RGB;
    InvalidateRect(window, NULL, FALSE);
    return CTD_OK;
}
