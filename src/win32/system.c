// What the system itself says: appearance, scale, and its own fonts.

#include "internal.h"

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
