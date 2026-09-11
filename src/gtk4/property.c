// Text, and the scalar property bag.
//
// Which widgets carry CTD_P_ENABLED is a rule of cortado's rather than of
// GTK's — see `ctd_kind_has_enabled` in ../cortado_rules.h. Every GtkWidget is
// sensitive, containers included, so here the rule is applied rather than
// inherited from the object system.

#include "internal.h"

// The text view inside a text area's scrolled window, or NULL.
GtkTextView *ctd_text_view(gpointer object) {
    if (!GTK_IS_SCROLLED_WINDOW(object)) return NULL;
    GtkWidget *inner = gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(object));
    return (inner && GTK_IS_TEXT_VIEW(inner)) ? GTK_TEXT_VIEW(inner) : NULL;
}

ctd_status ctd_set_int_raising(ctd_handle widget, int32_t key, int64_t value) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_ENABLED:
            // Every GtkWidget is sensitive, containers included — so unlike
            // the Apple hosts there is nothing here the object system refuses,
            // and the rule has to be applied rather than inherited.
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            gtk_widget_set_sensitive(GTK_WIDGET(object), value ? TRUE : FALSE);
            return CTD_OK;
        case CTD_P_HIDDEN:
            gtk_widget_set_visible(GTK_WIDGET(object), value ? FALSE : TRUE);
            return CTD_OK;
        case CTD_P_CHECKED: {
            // By kind, not by class. A radio is a GtkCheckButton here, and a
            // GtkCheckButton has a real third state — so asking the object
            // would have let a radio be mixed on this platform and nowhere
            // else. The rule is beside CTD_P_CHECKED in the header.
            int32_t made_as = ctd_slot_kind(widget);
            if (!ctd_kind_has_checked(made_as)) return CTD_ERR_KIND;
            if (!ctd_checked_in_range(made_as, value)) return CTD_ERR_RANGE;
            if (GTK_IS_SWITCH(object)) {
                gtk_switch_set_active(GTK_SWITCH(object), value == 1);
                return CTD_OK;
            }
            // GTK4's check button has a real third state, which is why cortado
            // can promise one: `inconsistent` is exactly AppKit's mixed.
            gtk_check_button_set_inconsistent(GTK_CHECK_BUTTON(object), value == 2);
            if (value != 2)
                gtk_check_button_set_active(GTK_CHECK_BUTTON(object), value == 1);
            return CTD_OK;
        }
        case CTD_P_EDITABLE: {
            GtkTextView *text = ctd_text_view(object);
            if (text) {
                gtk_text_view_set_editable(text, value ? TRUE : FALSE);
                return CTD_OK;
            }
            if (GTK_IS_EDITABLE(object)) {
                gtk_editable_set_editable(GTK_EDITABLE(object), value ? TRUE : FALSE);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        }
        case CTD_P_ALIGNMENT: {
            float alignment = value == 1 ? 0.5f : value == 2 ? 1.0f : 0.0f;
            if (GTK_IS_LABEL(object)) {
                gtk_label_set_xalign(GTK_LABEL(object), alignment);
                return CTD_OK;
            }
            if (GTK_IS_ENTRY(object)) {
                gtk_entry_set_alignment(GTK_ENTRY(object), alignment);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        }
        case CTD_P_SELECTED: {
            if (!GTK_IS_DROP_DOWN(object)) return CTD_ERR_KIND;
            GtkDropDown *menu = GTK_DROP_DOWN(object);
            GListModel *items = gtk_drop_down_get_model(menu);
            guint count = items ? g_list_model_get_n_items(items) : 0;
            if (value < 0) {
                gtk_drop_down_set_selected(menu, GTK_INVALID_LIST_POSITION);
                return CTD_OK;
            }
            if ((guint)value >= count) return CTD_ERR_RANGE;
            gtk_drop_down_set_selected(menu, (guint)value);
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE:
            if (!GTK_IS_PROGRESS_BAR(object)) return CTD_ERR_KIND;
            if (value) gtk_progress_bar_pulse(GTK_PROGRESS_BAR(object));
            return CTD_OK;
        default: return CTD_ERR_UNSUPPORTED;
    }
}

// The public form. Every write cortado makes on the program's behalf is
// silent, which on this platform takes saying so — see g_writing in
// internal.h.
ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    g_writing++;
    ctd_status status = ctd_set_int_raising(widget, key, value);
    g_writing--;
    return status;
}

ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    int64_t value = 0;
    switch (key) {
        case CTD_P_ENABLED:
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = gtk_widget_get_sensitive(GTK_WIDGET(object)) ? 1 : 0;
            break;
        case CTD_P_HIDDEN:
            value = gtk_widget_get_visible(GTK_WIDGET(object)) ? 0 : 1;
            break;
        case CTD_P_CHECKED:
            if (!ctd_kind_has_checked(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (GTK_IS_SWITCH(object)) {
                value = gtk_switch_get_active(GTK_SWITCH(object)) ? 1 : 0;
            } else if (gtk_check_button_get_inconsistent(GTK_CHECK_BUTTON(object))) {
                value = 2;
            } else {
                value = gtk_check_button_get_active(GTK_CHECK_BUTTON(object)) ? 1 : 0;
            }
            break;
        case CTD_P_EDITABLE: {
            GtkTextView *text = ctd_text_view(object);
            if (text) { value = gtk_text_view_get_editable(text) ? 1 : 0; break; }
            if (!GTK_IS_EDITABLE(object)) return CTD_ERR_KIND;
            value = gtk_editable_get_editable(GTK_EDITABLE(object)) ? 1 : 0;
            break;
        }
        case CTD_P_SELECTED: {
            if (!GTK_IS_DROP_DOWN(object)) return CTD_ERR_KIND;
            guint chosen = gtk_drop_down_get_selected(GTK_DROP_DOWN(object));
            value = chosen == GTK_INVALID_LIST_POSITION ? -1 : (int64_t)chosen;
            break;
        }
        case CTD_P_INDETERMINATE:
            if (!GTK_IS_PROGRESS_BAR(object)) return CTD_ERR_KIND;
            value = 0;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// A progress bar in GTK is a fraction from 0 to 1 with no range of its own, so
// the range is kept here and the fraction computed — the same shape the iOS
// host needs for the same reason.
static double g_progress_min[CTD_SLOTS];
static double g_progress_max[CTD_SLOTS];

// Font sizes that already have a CSS class on the display, so a second widget
// asking for the same size installs nothing.
static GHashTable *g_font_classes;

static ctd_status ctd_set_real_raising(ctd_handle widget, int32_t key, double value) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    switch (key) {
        case CTD_P_OPACITY:
            if (value < 0.0 || value > 1.0) return CTD_ERR_RANGE;
            gtk_widget_set_opacity(GTK_WIDGET(object), value);
            return CTD_OK;
        case CTD_P_FONT_SIZE: {
            // GTK sets fonts with CSS, and since GTK 4.10 a style context is
            // not something a caller may add a provider to. The supported
            // shape is a provider for the whole display and a class on the
            // widget, so each size gets one class — installed once, reused by
            // every widget that asks for it.
            int points = (int)value;
            if (points <= 0) return CTD_ERR_RANGE;
            char class_name[32];
            snprintf(class_name, sizeof class_name, "ctd-fs-%d", points);
            if (!g_font_classes) g_font_classes = g_hash_table_new(NULL, NULL);
            if (!g_hash_table_contains(g_font_classes, GINT_TO_POINTER(points))) {
                char css[128];
                snprintf(css, sizeof css, ".%s { font-size: %dpt; }",
                         class_name, points);
                GtkCssProvider *provider = gtk_css_provider_new();
                gtk_css_provider_load_from_string(provider, css);
                gtk_style_context_add_provider_for_display(
                    gdk_display_get_default(), GTK_STYLE_PROVIDER(provider),
                    GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
                g_object_unref(provider);
                g_hash_table_add(g_font_classes, GINT_TO_POINTER(points));
            }
            gtk_widget_add_css_class(GTK_WIDGET(object), class_name);
            return CTD_OK;
        }
        case CTD_P_MIN:
            if (GTK_IS_RANGE(object)) {
                GtkAdjustment *a = gtk_range_get_adjustment(GTK_RANGE(object));
                gtk_adjustment_set_lower(a, value);
                return CTD_OK;
            }
            if (GTK_IS_PROGRESS_BAR(object)) { g_progress_min[slot] = value; return CTD_OK; }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if (GTK_IS_RANGE(object)) {
                GtkAdjustment *a = gtk_range_get_adjustment(GTK_RANGE(object));
                gtk_adjustment_set_upper(a, value);
                return CTD_OK;
            }
            if (GTK_IS_PROGRESS_BAR(object)) { g_progress_max[slot] = value; return CTD_OK; }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if (GTK_IS_RANGE(object)) {
                gtk_range_set_value(GTK_RANGE(object), value);
                return CTD_OK;
            }
            if (GTK_IS_PROGRESS_BAR(object)) {
                double span = g_progress_max[slot] - g_progress_min[slot];
                double fraction = span > 0.0 ? (value - g_progress_min[slot]) / span : 0.0;
                if (fraction < 0.0) fraction = 0.0;
                if (fraction > 1.0) fraction = 1.0;
                gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(object), fraction);
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_STEP:
            if (!GTK_IS_RANGE(object)) return CTD_ERR_KIND;
            gtk_range_set_increments(GTK_RANGE(object), value, value);
            gtk_range_set_round_digits(GTK_RANGE(object), value >= 1.0 ? 0 : 2);
            return CTD_OK;
        default: return CTD_ERR_UNSUPPORTED;
    }
}

// The public form. Every write cortado makes on the program's behalf is
// silent, which on this platform takes saying so — see g_writing in
// internal.h.
ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    g_writing++;
    ctd_status status = ctd_set_real_raising(widget, key, value);
    g_writing--;
    return status;
}

ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    double value = 0.0;
    // A property that is being animated answers where it is *going*. The
    // widget holds what is on screen this instant, which on this host is the
    // same field; the destination lives beside the animation. The reasoning is
    // beside ctd_anim_start in cortado_host.h.
    if (ctd_anim_destination(widget, key, &value)) {
        if (out) *out = value;
        return CTD_OK;
    }
    switch (key) {
        case CTD_P_OPACITY:
            value = gtk_widget_get_opacity(GTK_WIDGET(object));
            break;
        case CTD_P_FONT_SIZE: {
            PangoContext *context = gtk_widget_get_pango_context(GTK_WIDGET(object));
            const PangoFontDescription *font = pango_context_get_font_description(context);
            value = (double)pango_font_description_get_size(font) / PANGO_SCALE;
            break;
        }
        case CTD_P_MIN:
            if (GTK_IS_RANGE(object)) {
                value = gtk_adjustment_get_lower(gtk_range_get_adjustment(GTK_RANGE(object)));
            } else if (GTK_IS_PROGRESS_BAR(object)) { value = g_progress_min[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_MAX:
            if (GTK_IS_RANGE(object)) {
                value = gtk_adjustment_get_upper(gtk_range_get_adjustment(GTK_RANGE(object)));
            } else if (GTK_IS_PROGRESS_BAR(object)) { value = g_progress_max[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_VALUE:
            if (GTK_IS_RANGE(object)) {
                value = gtk_range_get_value(GTK_RANGE(object));
            } else if (GTK_IS_PROGRESS_BAR(object)) {
                double span = g_progress_max[slot] - g_progress_min[slot];
                value = g_progress_min[slot] +
                        span * gtk_progress_bar_get_fraction(GTK_PROGRESS_BAR(object));
            } else return CTD_ERR_KIND;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}


ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    char *text = ctd_dup(utf8, len);
    ctd_status answer = CTD_OK;
    GtkTextView *view = ctd_text_view(object);
    if (view) {
        gtk_text_buffer_set_text(gtk_text_view_get_buffer(view), text, -1);
    } else if (GTK_IS_LABEL(object)) {
        gtk_label_set_text(GTK_LABEL(object), text);
    } else if (GTK_IS_BUTTON(object) && !GTK_IS_CHECK_BUTTON(object)) {
        gtk_button_set_label(GTK_BUTTON(object), text);
    } else if (GTK_IS_CHECK_BUTTON(object)) {
        gtk_check_button_set_label(GTK_CHECK_BUTTON(object), text);
    } else if (GTK_IS_EDITABLE(object)) {
        gtk_editable_set_text(GTK_EDITABLE(object), text);
    } else {
        answer = CTD_ERR_KIND;
    }
    g_free(text);
    return answer;
}

int32_t ctd_get_text(ctd_handle widget, char *out, int32_t cap) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkTextView *view = ctd_text_view(object);
    if (view) {
        GtkTextBuffer *buffer = gtk_text_view_get_buffer(view);
        GtkTextIter first, last;
        gtk_text_buffer_get_bounds(buffer, &first, &last);
        char *text = gtk_text_buffer_get_text(buffer, &first, &last, FALSE);
        int32_t needed = ctd_copy_out(text, out, cap);
        g_free(text);
        return needed;
    }
    if (GTK_IS_LABEL(object))
        return ctd_copy_out(gtk_label_get_text(GTK_LABEL(object)), out, cap);
    if (GTK_IS_CHECK_BUTTON(object))
        return ctd_copy_out(gtk_check_button_get_label(GTK_CHECK_BUTTON(object)), out, cap);
    if (GTK_IS_BUTTON(object))
        return ctd_copy_out(gtk_button_get_label(GTK_BUTTON(object)), out, cap);
    if (GTK_IS_EDITABLE(object))
        return ctd_copy_out(gtk_editable_get_text(GTK_EDITABLE(object)), out, cap);
    if (GTK_IS_DROP_DOWN(object)) {
        GtkDropDown *menu = GTK_DROP_DOWN(object);
        guint chosen = gtk_drop_down_get_selected(menu);
        GtkStringList *items = GTK_STRING_LIST(gtk_drop_down_get_model(menu));
        if (items && chosen != GTK_INVALID_LIST_POSITION)
            return ctd_copy_out(gtk_string_list_get_string(items, chosen), out, cap);
    }
    return ctd_copy_out("", out, cap);
}
