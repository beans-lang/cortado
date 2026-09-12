// Making a control of each kind, and letting one go.

#include "internal.h"

// Everything in the header except one, and the exception is the reason
// ctd_widget_supports exists at all.
//
// The Win32 common controls have no toggle switch. Windows has them — every
// Settings page is full of them — and they are WinUI, a different toolkit,
// drawn by a XAML compositor into a surface an HWND cannot be. The three ways
// to answer that are argued in the header; this is the third, which is to say
// so before the program builds anything.
int32_t ctd_widget_supports(int32_t kind) {
    switch (kind) {
        case CTD_W_CONTAINER:
        case CTD_W_LABEL:
        case CTD_W_BUTTON:
        case CTD_W_TEXT_FIELD:
        case CTD_W_CHECK_BOX:
        case CTD_W_IMAGE_VIEW:
        case CTD_W_SLIDER:
        case CTD_W_PROGRESS_BAR:
        case CTD_W_SEPARATOR:
        case CTD_W_TEXT_AREA:
        case CTD_W_COMBO_BOX:
        case CTD_W_SCROLL_VIEW:
        case CTD_W_RADIO_BUTTON:
        case CTD_W_CANVAS:
        case CTD_W_SECURE_FIELD:
        case CTD_W_STEPPER:
        case CTD_W_TABLE:
        case CTD_W_SEARCH_FIELD:
        case CTD_W_LINK:
            return 1;
        case CTD_W_SPINNER:
            // The common controls have no spinner. A marquee progress bar is
            // the nearest thing Windows has and it is a different control with
            // a different shape, so this refuses rather than substituting one.
            return 0;
        case CTD_W_SWITCH:
            return 0;
        case CTD_W_LEVEL_INDICATOR:
            // The common controls have no meter. A marquee progress bar is a
            // different idea — work happening with no known end — and drawing
            // a filled rectangle would not be a control at all.
            return 0;
        default:
            return CTD_ERR_RANGE;
    }
}

ctd_handle ctd_widget_new(int32_t kind) {
    // Asked rather than re-decided, so the factory and the question cannot
    // answer differently about the same kind.
    if (ctd_widget_supports(kind) != 1) return 0;
    const WCHAR *class_name = NULL;
    DWORD style = WS_CHILD | WS_VISIBLE;
    DWORD extended = 0;

    switch (kind) {
        case CTD_W_CONTAINER:
            class_name = CTD_CLASS_VIEW;
            style |= WS_CLIPCHILDREN;
            break;
        // A canvas is a plain view, and that is the whole of it here: the
        // platform lays it out and shows it, and everything inside is the
        // program's. On a host with no GPU nothing ever draws into it, and
        // an empty area is the honest shape for that.
        case CTD_W_CANVAS:
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
        case CTD_W_STEPPER:
            // An up-down control on its own: two arrows and nothing else. With
            // UDS_SETBUDDYINT it would drive a neighbouring edit box, which is
            // a spin *field* and a different control.
            class_name = UPDOWN_CLASSW;
            style |= UDS_ARROWKEYS | UDS_ALIGNRIGHT | WS_TABSTOP;
            break;
        case CTD_W_LINK:
            // SysLink, the real one — it draws the blue underline and the
            // hand cursor and reports the click. What it does *not* do is
            // follow the URL, so this host opens it; see the note beside
            // CTD_S_URL in the header.
            class_name = WC_LINK;
            style |= WS_TABSTOP;
            break;
        case CTD_W_SEARCH_FIELD:
            // An edit control with a cue banner, which is what a Windows
            // search box is — Explorer's is exactly that. What it does not
            // have is a clear button, so a program that leans on one offers
            // its own.
            class_name = WC_EDITW;
            style |= ES_LEFT | ES_AUTOHSCROLL | WS_TABSTOP;
            extended = WS_EX_CLIENTEDGE;
            break;
        case CTD_W_SECURE_FIELD:
            // The real thing: an edit control with ES_PASSWORD does not let
            // its text be copied out, and the shell will not read it back.
            class_name = WC_EDITW;
            style |= ES_LEFT | ES_PASSWORD | ES_AUTOHSCROLL | WS_TABSTOP;
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
        case CTD_W_TABLE:
            // LVS_OWNERDATA is the whole design in one style bit: the control
            // holds no items, only a count, and asks the parent for the text
            // of a cell it is about to paint.
            class_name = WC_LISTVIEWW;
            style |= LVS_REPORT | LVS_OWNERDATA | LVS_SINGLESEL
                   | LVS_SHOWSELALWAYS | WS_TABSTOP;
            extended = WS_EX_CLIENTEDGE;
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
    if (kind == CTD_W_TEXT_FIELD || kind == CTD_W_SECURE_FIELD ||
        kind == CTD_W_SEARCH_FIELD) {
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
    g_step_min[slot] = 0.0;
    g_step_max[slot] = 1.0;
    g_step_size[slot] = 1.0;
    if (kind == CTD_W_STEPPER) ctd_stepper_range(window, slot);
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
    if (g_type[slot] == CTD_T_ANIM) {
        // Nothing to destroy: an animation is a description in a table, and
        // handing the slot back is what ends it.
    } else if (g_type[slot] == CTD_T_MENU) {
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
    ctd_untrack(widget);
    return CTD_OK;
}
