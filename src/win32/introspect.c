// What the platform says it built, and driving it from a test.

#include "internal.h"

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
        // The vocabulary has no word for "a program draws its own
        // pixels here", and inventing one would be a word no screen
        // reader knows. A group is what it is: an area with content.
        case CTD_W_CANVAS:       role = "group";       break;
        // ARIA's own word, and every platform's: a control with two
        // positions that is not a check box.
        case CTD_W_SWITCH:       role = "switch";      break;
        // There is no ARIA role for a password field — HTML's input type has
        // none either. Every assistive layer under this one does distinguish
        // it (AXSecureTextField, ATSPI "password text", UIA IsPassword), so
        // reporting "textbox" would throw away a fact all four platforms have.
        case CTD_W_SECURE_FIELD: role = "password";    break;
        case CTD_W_STEPPER:      role = "spinbutton";  break;
        case CTD_W_LEVEL_INDICATOR: role = "meter";    break;
        case CTD_W_TABLE:        role = "grid";        break;
        case CTD_W_SEARCH_FIELD: role = "searchbox";   break;
        case CTD_W_SPINNER:      role = "progressbar"; break;
        case CTD_W_LINK:         role = "link";        break;
        case CTD_W_SEGMENTED:    role = "radiogroup";   break;
        case CTD_W_GROUP_BOX:    role = "group";        break;
        // The same word the other three hosts answer — see the note in
        // src/mac/introspect.m. A role that differed per platform would make
        // tests/roles.out a description of this machine.
        case CTD_W_DATE_PICKER:  role = "spinbutton";    break;
        case CTD_W_COLOR_WELL:   role = "button";        break;
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
        case CTD_W_DATE_PICKER: {
            SYSTEMTIME when;
            ctd_date_to_system(value, &when);
            SendMessageW(view, DTM_SETSYSTEMTIME, GDT_VALID, (LPARAM)&when);
            // A picker set by a message does not notify its parent — only a
            // user's edit does — so the notification that edit would have sent
            // is sent here, on the control's behalf.
            ctd_emit_control(widget);
            return CTD_OK;
        }
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
        case CTD_W_STEPPER: {
            uint32_t slot = (uint32_t)(widget & 0xffffffffu);
            ctd_status moved = ctd_stepper_set(view, slot, value);
            if (moved != CTD_OK) return moved;
            // An up-down reports through the scroll messages, like a trackbar.
            SendMessageW(GetParent(view), WM_VSCROLL,
                         MAKEWPARAM(SB_THUMBPOSITION, 0), (LPARAM)view);
            return CTD_OK;
        }
        default: return CTD_ERR_KIND;
    }
}

ctd_status ctd_widget_synth_text(ctd_handle widget, const char *utf8, int32_t len) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int32_t kind = ctd_slot_kind(widget);
    if (kind != CTD_W_TEXT_FIELD && kind != CTD_W_SECURE_FIELD &&
        kind != CTD_W_SEARCH_FIELD && kind != CTD_W_TEXT_AREA) return CTD_ERR_KIND;
    ctd_status wrote = ctd_set_text(widget, utf8, len);
    if (wrote != CTD_OK) return wrote;
    // Typed text is committed when the field is left or Return is pressed, and
    // an edit box reports the first through its parent. This is that message,
    // sent the way the control itself would send it.
    if (kind == CTD_W_TEXT_FIELD || kind == CTD_W_SECURE_FIELD ||
        kind == CTD_W_SEARCH_FIELD) {
        SendMessageW(GetParent(view), WM_COMMAND,
                     MAKEWPARAM(0, EN_KILLFOCUS), (LPARAM)view);
    }
    return CTD_OK;
}
