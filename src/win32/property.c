// Text, and the scalar property bag.
//
// Which widgets carry CTD_P_ENABLED is a rule of cortado's rather than of
// Win32's — see `ctd_kind_has_enabled` in ../cortado_rules.h. `EnableWindow`
// works on any HWND, a static label included, so here the rule is applied
// rather than inherited from the platform.

#include "internal.h"

// Declared in internal.h; the note there says why only y/m/d cross.
//
// The civil-date arithmetic is Howard Hinnant's, which is the one every
// standard library uses: it is exact for every year a 64-bit day count can
// name, and it is correct on both sides of the epoch — which matters here,
// because a date picker set to 1969 is as valid as one set to 2026 and the
// naive form of this conversion is off by a day for every date before 1970.
static int64_t ctd_days_from_civil(int64_t y, unsigned m, unsigned d) {
    y -= m <= 2;
    int64_t era = (y >= 0 ? y : y - 399) / 400;
    unsigned yoe = (unsigned)(y - era * 400);
    unsigned doy = (153u * (m + (m > 2 ? -3u : 9u)) + 2u) / 5u + d - 1u;
    unsigned doe = yoe * 365u + yoe / 4u - yoe / 100u + doy;
    return era * 146097 + (int64_t)doe - 719468;
}

static void ctd_civil_from_days(int64_t z, int *year, unsigned *month, unsigned *day) {
    z += 719468;
    int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    unsigned doe = (unsigned)(z - era * 146097);
    unsigned yoe = (doe - doe / 1460u + doe / 36524u - doe / 146096u) / 365u;
    int64_t y = (int64_t)yoe + era * 400;
    unsigned doy = doe - (365u * yoe + yoe / 4u - yoe / 100u);
    unsigned mp = (5u * doy + 2u) / 153u;
    unsigned d = doy - (153u * mp + 2u) / 5u + 1u;
    unsigned m = mp + (mp < 10u ? 3u : (unsigned)-9);
    *year = (int)(y + (m <= 2u));
    *month = m;
    *day = d;
}

void ctd_date_to_system(double seconds, SYSTEMTIME *out) {
    int year = 1970;
    unsigned month = 1, day = 1;
    int64_t whole = (int64_t)ctd_date_floor(seconds) / 86400;
    ctd_civil_from_days(whole, &year, &month, &day);
    memset(out, 0, sizeof *out);
    out->wYear = (WORD)year;
    out->wMonth = (WORD)month;
    out->wDay = (WORD)day;
}

double ctd_date_from_system(const SYSTEMTIME *given) {
    return (double)ctd_days_from_civil((int64_t)given->wYear,
                                       (unsigned)given->wMonth,
                                       (unsigned)given->wDay) * 86400.0;
}

ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int32_t kind = ctd_slot_kind(widget);
    switch (key) {
        case CTD_P_ENABLED:
            // EnableWindow works on any HWND, a static label included, so the
            // rule is applied here rather than inherited from the platform.
            if (!ctd_kind_has_enabled(kind)) return CTD_ERR_KIND;
            EnableWindow(view, value ? TRUE : FALSE);
            return CTD_OK;
        case CTD_P_LINES: {
            if (!ctd_kind_has_lines(kind)) return CTD_ERR_KIND;
            if (value < 0) return CTD_ERR_RANGE;
            // One line is a static that does not wrap and ends in an ellipsis;
            // more than one wraps as before, and ctd_view_measure caps the height.
            LONG_PTR style = GetWindowLongPtrW(view, GWL_STYLE);
            style &= ~(LONG_PTR)(SS_LEFTNOWORDWRAP | SS_ENDELLIPSIS);
            if (value == 1) style |= SS_LEFTNOWORDWRAP | SS_ENDELLIPSIS;
            SetWindowLongPtrW(view, GWL_STYLE, style);
            g_lines[(uint32_t)(widget & 0xffffffffu)] = value;
            InvalidateRect(view, NULL, TRUE);
            return CTD_OK;
        }
        case CTD_P_HIDDEN:
            ShowWindow(view, value ? SW_HIDE : SW_SHOW);
            return CTD_OK;
        case CTD_P_CHECKED: {
            if (!ctd_kind_has_checked(kind)) return CTD_ERR_KIND;
            if (!ctd_checked_in_range(kind, value)) return CTD_ERR_RANGE;
            if (value == 2) {
                // Windows will only hold the third state on a button that has
                // been told it has three, and turning that on also changes what
                // clicking cycles through — the same trade AppKit makes with
                // `allowsMixedState`. So it is switched on when a program asks
                // for mixed and not before.
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
        case CTD_P_ANIMATING:
            // No spinner exists on this platform, so no handle can be one.
            return CTD_ERR_KIND;
        case CTD_P_AXIS:
            // Nor a split view. The kind refusal, because "no control anywhere
            // has this property" is what a caller would be told on every other
            // host too. CTD_P_DIVIDER is a real and is refused in ctd_set_real.
            return CTD_ERR_KIND;
        case CTD_P_FG_COLOR: {
            // Recorded rather than written. A Win32 control asks its parent for
            // a text colour each time it paints, so app.c answers from here.
            if (!ctd_kind_has_fg_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (!ctd_color_in_range(value)) return CTD_ERR_RANGE;
            uint32_t slot = (uint32_t)(widget & 0xffffffffu);
            g_ink[slot] = value;
            g_has_ink[slot] = 1;
            HWND window = ctd_window(widget);
            if (window && IsWindow(window)) InvalidateRect(window, NULL, TRUE);
            return CTD_OK;
        }
        case CTD_P_ICON: {
            if (!ctd_kind_has_icon(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value >= CTD_ICON_COUNT) return CTD_ERR_RANGE;
            // The shell's stock set, because a button and a static control
            // take an HICON — the standard toolbar bitmap is an image list
            // and only a toolbar can draw from it. A role in one set and not
            // the other is therefore refused here and drawn on the toolbar,
            // which is honest about what Windows has rather than uniform
            // about what it does not.
            HICON picture = value == CTD_ICON_NONE
                          ? NULL : ctd_icon_handle((int32_t)value);
            if (value != CTD_ICON_NONE && !picture) return CTD_ERR_RANGE;
            HICON old = NULL;
            if (ctd_slot_kind(widget) == CTD_W_IMAGE_VIEW) {
                old = (HICON)SendMessageW(view, STM_GETICON, 0, 0);
                SendMessageW(view, STM_SETICON, (WPARAM)picture, 0);
            } else {
                old = (HICON)SendMessageW(view, BM_GETIMAGE, IMAGE_ICON, 0);
                LONG_PTR style = GetWindowLongPtrW(view, GWL_STYLE);
                SetWindowLongPtrW(view, GWL_STYLE,
                                  picture ? (style | BS_ICON) : (style & ~BS_ICON));
                SendMessageW(view, BM_SETIMAGE, IMAGE_ICON, (LPARAM)picture);
            }
            // SHGetStockIconInfo hands out a copy per call, so the one this
            // control was showing is this code's to destroy.
            if (old && old != picture) DestroyIcon(old);
            g_icon[(uint32_t)(widget & 0xffffffffu)] = (int32_t)value;
            return CTD_OK;
        }
        case CTD_P_EXPANDED:
            // Nor a disclosure. The kind refusal rather than the platform
            // refusal, because "no control anywhere has this property" is what
            // a caller asking a group box would be told on every other host
            // too.
            return CTD_ERR_KIND;
        case CTD_P_EDITABLE:
            if (kind != CTD_W_TEXT_FIELD && kind != CTD_W_SECURE_FIELD &&
                kind != CTD_W_SEARCH_FIELD && kind != CTD_W_TEXT_AREA)
                return CTD_ERR_KIND;
            SendMessageW(view, EM_SETREADONLY, value ? FALSE : TRUE, 0);
            return CTD_OK;
        case CTD_P_ALIGNMENT: {
            if (value < 0 || value > 2) return CTD_ERR_RANGE;
            LONG_PTR style = GetWindowLongPtrW(view, GWL_STYLE);
            if (kind == CTD_W_LABEL) {
                style &= ~(LONG_PTR)(SS_LEFT | SS_CENTER | SS_RIGHT);
                style |= value == 1 ? SS_CENTER : value == 2 ? SS_RIGHT : SS_LEFT;
            } else if (kind == CTD_W_TEXT_FIELD || kind == CTD_W_SECURE_FIELD ||
                       kind == CTD_W_TEXT_AREA) {
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
            // A tab view first: its selection is a page, and -1 means nothing
            // to it because a tab control always shows one of its pages.
            if (kind == CTD_W_TAB_VIEW) {
                if (value < 0 ||
                    value >= (int64_t)SendMessageW(view, TCM_GETITEMCOUNT, 0, 0))
                    return CTD_ERR_RANGE;
                SendMessageW(view, TCM_SETCURSEL, (WPARAM)value, 0);
                ctd_tab_sync(widget);
                return CTD_OK;
            }
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
            if (!ctd_kind_has_enabled(kind)) return CTD_ERR_KIND;
            value = IsWindowEnabled(view) ? 1 : 0;
            break;
        case CTD_P_LINES:
            if (!ctd_kind_has_lines(kind)) return CTD_ERR_KIND;
            value = g_lines[(uint32_t)(widget & 0xffffffffu)];
            break;
        case CTD_P_HIDDEN:
            // The style bit, not `IsWindowVisible`, which also answers no for
            // every child of a window that has not been shown — and in a
            // headless run that is all of them.
            value = (GetWindowLongPtrW(view, GWL_STYLE) & WS_VISIBLE) ? 0 : 1;
            break;
        case CTD_P_CHECKED: {
            if (!ctd_kind_has_checked(kind)) return CTD_ERR_KIND;
            LRESULT state = SendMessageW(view, BM_GETCHECK, 0, 0);
            value = state == BST_CHECKED ? 1 : state == BST_INDETERMINATE ? 2 : 0;
            break;
        }
        case CTD_P_ANIMATING:
            return CTD_ERR_KIND;
        case CTD_P_AXIS:
        case CTD_P_ICON:
            if (!ctd_kind_has_icon(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            // Kept beside the handle: BM_GETIMAGE answers an HICON and there
            // is no way from one back to the role that asked for it.
            value = g_icon[(uint32_t)(widget & 0xffffffffu)];
            break;
        case CTD_P_FG_COLOR: {
            if (!ctd_kind_has_fg_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            uint32_t slot = (uint32_t)(widget & 0xffffffffu);
            value = g_has_ink[slot] ? g_ink[slot] : 0;
            break;
        }
        case CTD_P_EXPANDED:
            return CTD_ERR_KIND;
        case CTD_P_EDITABLE:
            if (kind != CTD_W_TEXT_FIELD && kind != CTD_W_SECURE_FIELD &&
                kind != CTD_W_SEARCH_FIELD && kind != CTD_W_TEXT_AREA)
                return CTD_ERR_KIND;
            value = (GetWindowLongPtrW(view, GWL_STYLE) & ES_READONLY) ? 0 : 1;
            break;
        case CTD_P_ALIGNMENT: {
            LONG_PTR style = GetWindowLongPtrW(view, GWL_STYLE);
            if (kind == CTD_W_LABEL) {
                value = (style & SS_RIGHT) ? 2 : (style & SS_CENTER) ? 1 : 0;
            } else if (kind == CTD_W_TEXT_FIELD || kind == CTD_W_SECURE_FIELD ||
                       kind == CTD_W_TEXT_AREA) {
                value = (style & ES_RIGHT) ? 2 : (style & ES_CENTER) ? 1 : 0;
            } else {
                return CTD_ERR_KIND;
            }
            break;
        }
        case CTD_P_SELECTED: {
            if (kind == CTD_W_TAB_VIEW) {
                value = (int64_t)SendMessageW(view, TCM_GETCURSEL, 0, 0);
                break;
            }
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


// ---------------------------------------------------------------- a stepper
//
// An up-down control counts in whole numbers and cortado's range is real, so
// the control holds a **tick index** and these three turn it into the number
// the caller asked about: value = min + tick * step. The same shape the
// progress bar already uses for its fraction, and for the same reason — the
// alternative is truncating a caller's 0.25 to zero and never saying so.

void ctd_stepper_range(HWND view, uint32_t slot) {
    double span = g_step_max[slot] - g_step_min[slot];
    double size = g_step_size[slot];
    if (size <= 0.0) size = 1.0;
    int ticks = span > 0.0 ? (int)(span / size + 0.5) : 0;
    SendMessageW(view, UDM_SETRANGE32, 0, (LPARAM)ticks);
}

double ctd_stepper_value(HWND view, uint32_t slot) {
    int position = (int)SendMessageW(view, UDM_GETPOS32, 0, 0);
    double size = g_step_size[slot];
    if (size <= 0.0) size = 1.0;
    return g_step_min[slot] + (double)position * size;
}

ctd_status ctd_stepper_set(HWND view, uint32_t slot, double value) {
    double size = g_step_size[slot];
    if (size <= 0.0) size = 1.0;
    double ticks = (value - g_step_min[slot]) / size;
    // Rounded rather than truncated: a caller who writes the value they just
    // read must get the same tick back, and floating point does not promise
    // that (3 * 0.1 is 0.30000000000000004, and (0.30000000000000004 / 0.1)
    // truncates to 2).
    int position = (int)(ticks + (ticks < 0.0 ? -0.5 : 0.5));
    if (position < 0) position = 0;
    SendMessageW(view, UDM_SETPOS32, 0, (LPARAM)position);
    return CTD_OK;
}

ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    int32_t kind = ctd_slot_kind(widget);
    switch (key) {
        case CTD_P_OPACITY: {
            if (value < 0.0 || value > 1.0) return CTD_ERR_RANGE;
            // A layered *child* window is a Windows 8 feature; before that
            // WS_EX_LAYERED was top-level only and setting it on a control did
            // nothing visible. cortado's floor is Windows 10 (WINVER 0x0A00),
            // so it is simply available — but the style has to be turned on
            // before the attribute takes, and turned off again at full opacity
            // so a control that is not faded is not paying for a layer.
            LONG_PTR style = GetWindowLongPtrW(view, GWL_EXSTYLE);
            if (value >= 1.0) {
                if (style & WS_EX_LAYERED) {
                    SetWindowLongPtrW(view, GWL_EXSTYLE, style & ~WS_EX_LAYERED);
                    RedrawWindow(view, NULL, NULL,
                                 RDW_ERASE | RDW_INVALIDATE | RDW_ALLCHILDREN);
                }
                return CTD_OK;
            }
            if (!(style & WS_EX_LAYERED))
                SetWindowLongPtrW(view, GWL_EXSTYLE, style | WS_EX_LAYERED);
            if (!SetLayeredWindowAttributes(view, 0, (BYTE)(value * 255.0 + 0.5),
                                            LWA_ALPHA))
                return CTD_ERR_PLATFORM;
            return CTD_OK;
        }
        case CTD_P_FONT_SIZE: {
            int points = (int)value;
            if (points <= 0) return CTD_ERR_RANGE;
            HFONT font = ctd_font_at(points);
            if (!font) return CTD_ERR_PLATFORM;
            SendMessageW(view, WM_SETFONT, (WPARAM)font, TRUE);
            return CTD_OK;
        }
        case CTD_P_MIN:
            if (!ctd_kind_has_range(kind)) return CTD_ERR_KIND;
            if (kind == CTD_W_SLIDER) {
                SendMessageW(view, TBM_SETRANGEMIN, TRUE, (LPARAM)(LONG)value);
                return CTD_OK;
            }
            if (kind == CTD_W_PROGRESS_BAR) { g_progress_min[slot] = value; return CTD_OK; }
            if (kind == CTD_W_STEPPER) {
                g_step_min[slot] = value;
                ctd_stepper_range(view, slot);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if (!ctd_kind_has_range(kind)) return CTD_ERR_KIND;
            if (kind == CTD_W_SLIDER) {
                SendMessageW(view, TBM_SETRANGEMAX, TRUE, (LPARAM)(LONG)value);
                return CTD_OK;
            }
            if (kind == CTD_W_PROGRESS_BAR) { g_progress_max[slot] = value; return CTD_OK; }
            if (kind == CTD_W_STEPPER) {
                g_step_max[slot] = value;
                ctd_stepper_range(view, slot);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if (!ctd_kind_has_range(kind)) return CTD_ERR_KIND;
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
                g_progress_value[slot] = value;
                return CTD_OK;
            }
            if (kind == CTD_W_STEPPER) return ctd_stepper_set(view, slot, value);
            return CTD_ERR_KIND;
        case CTD_P_DIVIDER:
            // No split view on this platform, so no handle can be one.
            return CTD_ERR_KIND;
        case CTD_P_DATE: {
            if (!ctd_kind_has_date(kind)) return CTD_ERR_KIND;
            SYSTEMTIME when;
            ctd_date_to_system(value, &when);
            SendMessageW(view, DTM_SETSYSTEMTIME, GDT_VALID, (LPARAM)&when);
            return CTD_OK;
        }
        case CTD_P_STEP:
            if (kind == CTD_W_STEPPER) {
                if (value <= 0.0) return CTD_ERR_RANGE;
                double held = ctd_stepper_value(view, slot);
                g_step_size[slot] = value;
                ctd_stepper_range(view, slot);
                // The tick index means something different now, so the number
                // the control was showing is put back through the new one.
                return ctd_stepper_set(view, slot, held);
            }
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
    // A property that is being animated answers where it is *going*. The
    // control holds what is on screen this instant, which on this host is the
    // same field; the destination lives beside the animation. The reasoning is
    // beside ctd_anim_start in cortado_host.h.
    if (ctd_anim_destination(widget, key, &value)) {
        if (out) *out = value;
        return CTD_OK;
    }
    switch (key) {
        case CTD_P_OPACITY: {
            // A window with no layered style is fully opaque and has no
            // attribute to read — answering the platform's failure here would
            // report "no opacity" for the overwhelmingly common case.
            BYTE alpha = 255;
            DWORD flags = 0;
            if ((GetWindowLongPtrW(view, GWL_EXSTYLE) & WS_EX_LAYERED) &&
                GetLayeredWindowAttributes(view, NULL, &alpha, &flags) &&
                (flags & LWA_ALPHA)) {
                value = (double)alpha / 255.0;
            } else {
                value = 1.0;
            }
            break;
        }
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
            if (!ctd_kind_has_range(kind)) return CTD_ERR_KIND;
            if (kind == CTD_W_SLIDER) {
                value = (double)(LONG)SendMessageW(view, TBM_GETRANGEMIN, 0, 0);
            } else if (kind == CTD_W_PROGRESS_BAR) { value = g_progress_min[slot]; }
            else if (kind == CTD_W_STEPPER) { value = g_step_min[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_MAX:
            if (!ctd_kind_has_range(kind)) return CTD_ERR_KIND;
            if (kind == CTD_W_SLIDER) {
                value = (double)(LONG)SendMessageW(view, TBM_GETRANGEMAX, 0, 0);
            } else if (kind == CTD_W_PROGRESS_BAR) { value = g_progress_max[slot]; }
            else if (kind == CTD_W_STEPPER) { value = g_step_max[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_VALUE:
            if (!ctd_kind_has_range(kind)) return CTD_ERR_KIND;
            if (kind == CTD_W_SLIDER) {
                value = (double)(LONG)SendMessageW(view, TBM_GETPOS, 0, 0);
            } else if (kind == CTD_W_PROGRESS_BAR) {
                value = g_progress_value[slot];
            } else if (kind == CTD_W_STEPPER) {
                value = ctd_stepper_value(view, slot);
            } else return CTD_ERR_KIND;
            break;
        case CTD_P_DIVIDER:
            return CTD_ERR_KIND;
        case CTD_P_DATE: {
            if (!ctd_kind_has_date(kind)) return CTD_ERR_KIND;
            SYSTEMTIME shown;
            if (SendMessageW(view, DTM_GETSYSTEMTIME, 0, (LPARAM)&shown) != GDT_VALID)
                return CTD_ERR_UNSUPPORTED;
            value = ctd_date_from_system(&shown);
            break;
        }
        case CTD_P_STEP:
            // A stepper and nothing else — the paragraph beside CTD_P_STEP in
            // the header says why a slider's is write-only. This host *could*
            // answer TBM_GETLINESIZE, and that is exactly the trap: one
            // platform answering a number the other three cannot is a
            // divergence that reads as a feature.
            if (kind != CTD_W_STEPPER) return CTD_ERR_KIND;
            value = g_step_size[slot];
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}


// A SysLink holds one string with the URL *inside* it —
// `<a href="where">words</a>` — so the words and the target have to be kept
// apart here and composed on every write. Reading the markup back would be
// parsing HTML to answer a question cortado already knows the answer to.
static WCHAR *g_link_words[CTD_SLOTS];
static WCHAR *g_link_where[CTD_SLOTS];

static void ctd_link_hold(WCHAR **slot, const char *utf8, int32_t len) {
    free(*slot);
    *slot = ctd_wide(utf8 ? utf8 : "", utf8 ? len : 0);
}

// The control's one string, rebuilt from the two halves.
static ctd_status ctd_link_compose(HWND view, uint32_t slot) {
    const WCHAR *words = g_link_words[slot] ? g_link_words[slot] : L"";
    const WCHAR *where = g_link_where[slot] ? g_link_where[slot] : L"";
    size_t room = lstrlenW(words) + lstrlenW(where) + 32;
    WCHAR *markup = (WCHAR *)malloc(room * sizeof(WCHAR));
    if (!markup) return CTD_ERR_PLATFORM;
    if (where[0] == L'\0') {
        lstrcpynW(markup, words, (int)room);
    } else {
        wsprintfW(markup, L"<a href=\"%s\">%s</a>", where, words);
    }
    BOOL done = SetWindowTextW(view, markup);
    free(markup);
    return done ? CTD_OK : CTD_ERR_PLATFORM;
}

// A SysLink's words and target, for ctd_set_text and ctd_get_text.
ctd_status ctd_link_set_words(ctd_handle widget, HWND view,
                              const char *utf8, int32_t len) {
    uint32_t slot = ctd_slot(widget);
    ctd_link_hold(&g_link_words[slot], utf8, len);
    return ctd_link_compose(view, slot);
}

int32_t ctd_link_words_out(ctd_handle widget, char *out, int32_t cap) {
    uint32_t slot = ctd_slot(widget);
    return ctd_copy_wide_out(g_link_words[slot] ? g_link_words[slot] : L"", out, cap);
}

// Where a link goes, for the host's own click handler.
const WCHAR *ctd_link_target(ctd_handle widget) {
    return g_link_where[ctd_slot(widget)];
}

ctd_status ctd_set_string(ctd_handle widget, int32_t key,
                          const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    switch (key) {
        case CTD_S_URL: {
            if (!ctd_kind_has_url(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            uint32_t slot = ctd_slot(widget);
            ctd_link_hold(&g_link_where[slot], utf8, len);
            return ctd_link_compose(view, slot);
        }
        case CTD_S_HINT: {
            if (!ctd_kind_has_hint(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            WCHAR *text = ctd_wide(utf8, len);
            if (!text) return CTD_ERR_PLATFORM;
            // TRUE: keep showing it while the field has focus, which is what
            // every other platform's placeholder does.
            LRESULT done = SendMessageW(view, EM_SETCUEBANNER, TRUE, (LPARAM)text);
            free(text);
            return done ? CTD_OK : CTD_ERR_PLATFORM;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

int32_t ctd_get_string(ctd_handle widget, int32_t key, char *out, int32_t cap) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    switch (key) {
        case CTD_S_URL: {
            if (!ctd_kind_has_url(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            const WCHAR *where = g_link_where[ctd_slot(widget)];
            return ctd_copy_wide_out(where ? where : L"", out, cap);
        }
        case CTD_S_HINT: {
            if (!ctd_kind_has_hint(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            WCHAR room[512];
            room[0] = L'\0';
            SendMessageW(view, EM_GETCUEBANNER, (WPARAM)room,
                         (LPARAM)(sizeof room / sizeof room[0]));
            return ctd_copy_wide_out(room, out, cap);
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    switch (ctd_slot_kind(widget)) {
        // A link's words and its target are one string to the control, so the
        // words go through the place that composes both.
        case CTD_W_LINK:
            return ctd_link_set_words(widget, view, utf8, len);
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
    if (ctd_slot_kind(widget) == CTD_W_LINK) {
        // The control's own text is markup with the URL inside it, so the
        // words come back from where they were kept rather than by parsing it.
        return ctd_link_words_out(widget, out, cap);
    }
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
