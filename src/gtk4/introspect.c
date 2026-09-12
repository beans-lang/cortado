// What the platform says it built, and driving it from a test.

#include "internal.h"

int32_t ctd_native_class(ctd_handle widget, char *out, int32_t cap) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    return ctd_copy_out(G_OBJECT_TYPE_NAME(object), out, cap);
}

int32_t ctd_a11y_role(ctd_handle widget, char *out, int32_t cap) {
    if (!ctd_resolve(widget)) return CTD_ERR_STALE;
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
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (GTK_IS_BUTTON(object) && !GTK_IS_CHECK_BUTTON(object)) {
        // Through GTK's own activation, not by calling the handler: the same
        // path a real click takes.
        g_signal_emit_by_name(object, "clicked");
        return CTD_OK;
    }
    if (GTK_IS_WIDGET(object) && gtk_widget_activate(GTK_WIDGET(object)))
        return CTD_OK;
    return CTD_ERR_KIND;
}

ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    // The setters below are the ordinary ones, and the signal they raise is
    // the platform's own — GTK notifies on a property change whoever made it,
    // which is exactly what "as a user would" means here.
    if (GTK_IS_SPIN_BUTTON(object)) {
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(object), value);
        return CTD_OK;
    }
    if (GTK_IS_RANGE(object)) {
        gtk_range_set_value(GTK_RANGE(object), value);
        return CTD_OK;
    }
    if (GTK_IS_CHECK_BUTTON(object)) {
        gtk_check_button_set_inconsistent(GTK_CHECK_BUTTON(object), index == 2);
        if (index != 2)
            gtk_check_button_set_active(GTK_CHECK_BUTTON(object), index == 1);
        return CTD_OK;
    }
    if (GTK_IS_SWITCH(object)) {
        gtk_switch_set_active(GTK_SWITCH(object), index == 1);
        return CTD_OK;
    }
    // The raising form: cortado's own writes are silent, and this call is the
    // one that is standing in for a user.
    if (GTK_IS_DROP_DOWN(object))
        return ctd_set_int_raising(widget, CTD_P_SELECTED, index);
    return CTD_ERR_KIND;
}

ctd_status ctd_widget_synth_text(ctd_handle widget, const char *utf8, int32_t len) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkTextView *view = ctd_text_view(object);
    if (!view && !GTK_IS_EDITABLE(object)) return CTD_ERR_KIND;
    ctd_status wrote = ctd_set_text(widget, utf8, len);
    if (wrote != CTD_OK) return wrote;
    // A typed value is committed when the field is activated, which is the
    // signal a user's Return raises.
    if (GTK_IS_ENTRY(object)) g_signal_emit_by_name(object, "activate");
    return CTD_OK;
}
