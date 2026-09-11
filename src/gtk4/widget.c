// Making a control of each kind, and letting one go.

#include "internal.h"

// GTK4 has no radio button class any more: a radio is a GtkCheckButton whose
// group another check button joins. Grouping is by parent here, the same rule
// the macOS and iOS hosts follow, and it is applied when the child is added.

ctd_handle ctd_widget_new(int32_t kind) {
    GtkWidget *widget = NULL;
    switch (kind) {
        case CTD_W_CONTAINER:
            // GtkFixed is the one container that places children where it is
            // told. Every other GTK container negotiates, which is the right
            // model for GTK and the wrong one for a framework that has already
            // computed every frame.
            widget = gtk_fixed_new();
            break;
        case CTD_W_LABEL:
            widget = gtk_label_new("");
            gtk_label_set_xalign(GTK_LABEL(widget), 0.0f);
            break;
        case CTD_W_BUTTON:
            widget = gtk_button_new_with_label("");
            break;
        case CTD_W_TEXT_FIELD:
            widget = gtk_entry_new();
            break;
        case CTD_W_CHECK_BOX:
            widget = gtk_check_button_new();
            break;
        case CTD_W_RADIO_BUTTON:
            widget = gtk_check_button_new();
            break;
        case CTD_W_IMAGE_VIEW:
            widget = gtk_picture_new();
            break;
        case CTD_W_SLIDER:
            widget = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL,
                                              0.0, 1.0, 0.01);
            gtk_scale_set_draw_value(GTK_SCALE(widget), FALSE);
            break;
        case CTD_W_PROGRESS_BAR:
            widget = gtk_progress_bar_new();
            break;
        case CTD_W_SEPARATOR:
            widget = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
            break;
        case CTD_W_TEXT_AREA: {
            GtkWidget *scroller = gtk_scrolled_window_new();
            GtkWidget *text = gtk_text_view_new();
            gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(text), GTK_WRAP_WORD);
            gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), text);
            widget = scroller;
            break;
        }
        case CTD_W_COMBO_BOX: {
            GtkStringList *items = gtk_string_list_new(NULL);
            widget = gtk_drop_down_new(G_LIST_MODEL(items), NULL);
            break;
        }
        case CTD_W_SCROLL_VIEW: {
            GtkWidget *scroller = gtk_scrolled_window_new();
            GtkWidget *content = gtk_fixed_new();
            ctd_tag(content);
            gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), content);
            widget = scroller;
            break;
        }
        default:
            return 0;
    }
    ctd_tag(widget);
    ctd_handle handle = ctd_track(widget, kind);

    // One signal per kind, chosen so the event the control raises is the one
    // it actually is.
    switch (kind) {
        case CTD_W_BUTTON:
            g_signal_connect(widget, "clicked", G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON:
            g_signal_connect(widget, "toggled", G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        case CTD_W_SLIDER:
            g_signal_connect(widget, "value-changed", G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        case CTD_W_TEXT_FIELD:
            g_signal_connect(widget, "activate", G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        case CTD_W_COMBO_BOX:
            // A GtkDropDown has no "changed": the selection is a property, and
            // a property notification is how GObject spells this.
            g_signal_connect(widget, "notify::selected",
                             G_CALLBACK(ctd_on_signal),
                             (gpointer)(uintptr_t)handle);
            break;
        default: break;
    }
    return handle;
}

int32_t ctd_widget_kind(ctd_handle widget) { return ctd_slot_kind(widget); }

int32_t ctd_widget_alive(ctd_handle widget) { return ctd_resolve(widget) ? 1 : 0; }

ctd_status ctd_widget_release(ctd_handle widget) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(object));
    if (parent && GTK_IS_FIXED(parent)) {
        gtk_fixed_remove(GTK_FIXED(parent), GTK_WIDGET(object));
    } else if (parent) {
        gtk_widget_unparent(GTK_WIDGET(object));
    }
    ctd_untrack(widget);
    return CTD_OK;
}
