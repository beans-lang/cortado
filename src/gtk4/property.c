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

// Declared in internal.h; the note there says why only y/m/d cross.
double ctd_calendar_seconds(GtkCalendar *calendar) {
    GDateTime *shown = gtk_calendar_get_date(calendar);
    if (!shown) return 0.0;
    GDateTime *utc = g_date_time_new_utc(g_date_time_get_year(shown),
                                         g_date_time_get_month(shown),
                                         g_date_time_get_day_of_month(shown),
                                         0, 0, 0.0);
    double seconds = utc ? (double)g_date_time_to_unix(utc) : 0.0;
    if (utc) g_date_time_unref(utc);
    g_date_time_unref(shown);
    return seconds;
}

void ctd_calendar_set_seconds(GtkCalendar *calendar, double seconds) {
    GDateTime *day = g_date_time_new_from_unix_utc((gint64)ctd_date_floor(seconds));
    if (!day) return;
    // Renamed in 4.20 and deprecated under the old name. Both are the same
    // call; the guard is here rather than a pragma because cortado's GTK
    // version is whatever the machine that builds has, and silencing the
    // warning would keep using the old name on a system that has the new one.
#if GTK_CHECK_VERSION(4, 20, 0)
    gtk_calendar_set_date(calendar, day);
#else
    gtk_calendar_select_day(calendar, day);
#endif
    g_date_time_unref(day);
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
        case CTD_P_AXIS:
            if (!ctd_kind_has_divider(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value > 1) return CTD_ERR_RANGE;
            gtk_orientable_set_orientation(GTK_ORIENTABLE(object),
                value == 0 ? GTK_ORIENTATION_HORIZONTAL : GTK_ORIENTATION_VERTICAL);
            return CTD_OK;
        case CTD_P_EXPANDED:
            if (!ctd_kind_has_expanded(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value > 1) return CTD_ERR_RANGE;
            gtk_expander_set_expanded(GTK_EXPANDER(object), value ? TRUE : FALSE);
            return CTD_OK;
        case CTD_P_COLOR: {
            if (!ctd_kind_has_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (!ctd_color_in_range(value)) return CTD_ERR_RANGE;
            GdkRGBA want = { (float)(ctd_color_red(value)   / 255.0),
                             (float)(ctd_color_green(value) / 255.0),
                             (float)(ctd_color_blue(value)  / 255.0),
                             (float)(ctd_color_alpha(value) / 255.0) };
            gtk_color_dialog_button_set_rgba(GTK_COLOR_DIALOG_BUTTON(object), &want);
            return CTD_OK;
        }
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
            // A tab view first: its selection is a page, and -1 means nothing
            // to it because a notebook always shows one of its pages.
            if (GTK_IS_NOTEBOOK(object)) {
                if (value < 0 || value >= gtk_notebook_get_n_pages(GTK_NOTEBOOK(object)))
                    return CTD_ERR_RANGE;
                gtk_notebook_set_current_page(GTK_NOTEBOOK(object), (int)value);
                return CTD_OK;
            }
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
        case CTD_P_ANIMATING:
            if (!ctd_kind_has_animating(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            gtk_spinner_set_spinning(GTK_SPINNER(object), value ? TRUE : FALSE);
            return CTD_OK;
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
        case CTD_P_AXIS:
            if (!ctd_kind_has_divider(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = gtk_orientable_get_orientation(GTK_ORIENTABLE(object)) ==
                    GTK_ORIENTATION_HORIZONTAL ? 0 : 1;
            break;
        case CTD_P_EXPANDED:
            if (!ctd_kind_has_expanded(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = gtk_expander_get_expanded(GTK_EXPANDER(object)) ? 1 : 0;
            break;
        case CTD_P_COLOR: {
            if (!ctd_kind_has_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            const GdkRGBA *shown =
                gtk_color_dialog_button_get_rgba(GTK_COLOR_DIALOG_BUTTON(object));
            if (!shown) return CTD_ERR_UNSUPPORTED;
            value = ctd_color_pack(ctd_color_byte(shown->red),
                                   ctd_color_byte(shown->green),
                                   ctd_color_byte(shown->blue),
                                   ctd_color_byte(shown->alpha));
            break;
        }
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
            if (GTK_IS_NOTEBOOK(object)) {
                value = (int64_t)gtk_notebook_get_current_page(GTK_NOTEBOOK(object));
                break;
            }
            if (!GTK_IS_DROP_DOWN(object)) return CTD_ERR_KIND;
            guint chosen = gtk_drop_down_get_selected(GTK_DROP_DOWN(object));
            value = chosen == GTK_INVALID_LIST_POSITION ? -1 : (int64_t)chosen;
            break;
        }
        case CTD_P_ANIMATING:
            if (!ctd_kind_has_animating(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = gtk_spinner_get_spinning(GTK_SPINNER(object)) ? 1 : 0;
            break;
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
// And the value. A GtkProgressBar holds a 0..1 fraction, so a value put in and
// taken out again comes back through a division and a multiplication: 1 in
// 0..3 is 0.3333333333333333, and that times 3 is 0.9999999999999998. The
// whole triple is cortado's data here for the same reason min and max already
// were — GTK has no range on a progress bar — and nothing but the program
// writes one, so there is no second writer to disagree with.
static double g_progress_value[CTD_SLOTS];
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
            if (!ctd_kind_has_range(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (GTK_IS_RANGE(object)) {
                GtkAdjustment *a = gtk_range_get_adjustment(GTK_RANGE(object));
                gtk_adjustment_set_lower(a, value);
                return CTD_OK;
            }
            if (GTK_IS_SPIN_BUTTON(object)) {
                gtk_adjustment_set_lower(
                    gtk_spin_button_get_adjustment(GTK_SPIN_BUTTON(object)), value);
                return CTD_OK;
            }
            if (GTK_IS_LEVEL_BAR(object)) {
                gtk_level_bar_set_min_value(GTK_LEVEL_BAR(object), value);
                return CTD_OK;
            }
            if (GTK_IS_PROGRESS_BAR(object)) { g_progress_min[slot] = value; return CTD_OK; }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if (!ctd_kind_has_range(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (GTK_IS_RANGE(object)) {
                GtkAdjustment *a = gtk_range_get_adjustment(GTK_RANGE(object));
                gtk_adjustment_set_upper(a, value);
                return CTD_OK;
            }
            if (GTK_IS_SPIN_BUTTON(object)) {
                gtk_adjustment_set_upper(
                    gtk_spin_button_get_adjustment(GTK_SPIN_BUTTON(object)), value);
                return CTD_OK;
            }
            if (GTK_IS_LEVEL_BAR(object)) {
                gtk_level_bar_set_max_value(GTK_LEVEL_BAR(object), value);
                return CTD_OK;
            }
            if (GTK_IS_PROGRESS_BAR(object)) { g_progress_max[slot] = value; return CTD_OK; }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if (!ctd_kind_has_range(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (GTK_IS_SPIN_BUTTON(object)) {
                gtk_spin_button_set_value(GTK_SPIN_BUTTON(object), value);
                return CTD_OK;
            }
            if (GTK_IS_LEVEL_BAR(object)) {
                gtk_level_bar_set_value(GTK_LEVEL_BAR(object), value);
                return CTD_OK;
            }
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
                g_progress_value[slot] = value;
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_DIVIDER: {
            if (!ctd_kind_has_divider(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0.0) return CTD_ERR_RANGE;
            // Bounded by the size cortado gave the control, not by GTK's
            // allocation. An allocation only exists once the widget has been
            // laid out inside a window that is on screen, and a headless run
            // never has one — so bounding by it meant a divider of 9000 was
            // refused on macOS and accepted here, which is a platform
            // difference in a rule that is cortado's.
            int wide = -1, tall = -1;
            gtk_widget_get_size_request(GTK_WIDGET(object), &wide, &tall);
            if (wide < 0) wide = gtk_widget_get_width(GTK_WIDGET(object));
            if (tall < 0) tall = gtk_widget_get_height(GTK_WIDGET(object));
            int along = gtk_orientable_get_orientation(GTK_ORIENTABLE(object)) ==
                        GTK_ORIENTATION_VERTICAL ? tall : wide;
            if (along < 0) along = 0;
            if (value > (double)along) return CTD_ERR_RANGE;
            gtk_paned_set_position(GTK_PANED(object), (int)value);
            return CTD_OK;
        }
        case CTD_P_DATE:
            if (!ctd_kind_has_date(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            ctd_calendar_set_seconds(GTK_CALENDAR(object), value);
            return CTD_OK;
        case CTD_P_STEP:
            if (GTK_IS_SPIN_BUTTON(object)) {
                if (value <= 0.0) return CTD_ERR_RANGE;
                gtk_spin_button_set_increments(GTK_SPIN_BUTTON(object), value, value);
                // A spin button shows the number it holds, so how many decimal
                // places it shows has to follow the increment — a step of 0.25
                // displayed with none reads as four identical clicks.
                gtk_spin_button_set_digits(GTK_SPIN_BUTTON(object),
                                           value >= 1.0 ? 0 : 2);
                return CTD_OK;
            }
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
            } else if (GTK_IS_SPIN_BUTTON(object)) {
                value = gtk_adjustment_get_lower(
                    gtk_spin_button_get_adjustment(GTK_SPIN_BUTTON(object)));
            } else if (GTK_IS_LEVEL_BAR(object)) {
                value = gtk_level_bar_get_min_value(GTK_LEVEL_BAR(object));
            } else if (GTK_IS_PROGRESS_BAR(object)) { value = g_progress_min[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_MAX:
            if (GTK_IS_RANGE(object)) {
                value = gtk_adjustment_get_upper(gtk_range_get_adjustment(GTK_RANGE(object)));
            } else if (GTK_IS_SPIN_BUTTON(object)) {
                value = gtk_adjustment_get_upper(
                    gtk_spin_button_get_adjustment(GTK_SPIN_BUTTON(object)));
            } else if (GTK_IS_LEVEL_BAR(object)) {
                value = gtk_level_bar_get_max_value(GTK_LEVEL_BAR(object));
            } else if (GTK_IS_PROGRESS_BAR(object)) { value = g_progress_max[slot]; }
            else return CTD_ERR_KIND;
            break;
        case CTD_P_VALUE:
            if (GTK_IS_SPIN_BUTTON(object)) {
                value = gtk_spin_button_get_value(GTK_SPIN_BUTTON(object));
            } else if (GTK_IS_LEVEL_BAR(object)) {
                value = gtk_level_bar_get_value(GTK_LEVEL_BAR(object));
            } else if (GTK_IS_RANGE(object)) {
                value = gtk_range_get_value(GTK_RANGE(object));
            } else if (GTK_IS_PROGRESS_BAR(object)) {
                value = g_progress_value[slot];
            } else return CTD_ERR_KIND;
            break;
        case CTD_P_DIVIDER:
            if (!ctd_kind_has_divider(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = (double)gtk_paned_get_position(GTK_PANED(object));
            break;
        case CTD_P_DATE:
            if (!ctd_kind_has_date(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = ctd_calendar_seconds(GTK_CALENDAR(object));
            break;
        case CTD_P_STEP: {
            // Only a stepper reads one back, and only the *step* half of the
            // adjustment: a range's page increment is a different number for a
            // different gesture.
            if (!GTK_IS_SPIN_BUTTON(object)) return CTD_ERR_KIND;
            double page = 0.0;
            gtk_spin_button_get_increments(GTK_SPIN_BUTTON(object), &value, &page);
            break;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}


ctd_status ctd_set_string(ctd_handle widget, int32_t key,
                          const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_S_URL: {
            if (!ctd_kind_has_url(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            char *where = g_strndup(utf8, (gsize)(len < 0 ? 0 : len));
            gtk_link_button_set_uri(GTK_LINK_BUTTON(object), where);
            g_free(where);
            return CTD_OK;
        }
        case CTD_S_HINT: {
            if (!ctd_kind_has_hint(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            // By property name rather than by a typed setter: a GtkEntry and a
            // GtkSearchEntry both have "placeholder-text" and neither is the
            // other's class, so this is the one call that reaches both.
            char *text = g_strndup(utf8, (gsize)(len < 0 ? 0 : len));
            g_object_set(G_OBJECT(object), "placeholder-text", text, NULL);
            g_free(text);
            return CTD_OK;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

int32_t ctd_get_string(ctd_handle widget, int32_t key, char *out, int32_t cap) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_S_URL: {
            if (!ctd_kind_has_url(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            const char *where = gtk_link_button_get_uri(GTK_LINK_BUTTON(object));
            return ctd_copy_out(where ? where : "", out, cap);
        }
        case CTD_S_HINT: {
            if (!ctd_kind_has_hint(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            char *text = NULL;
            g_object_get(G_OBJECT(object), "placeholder-text", &text, NULL);
            int32_t answered = ctd_copy_out(text ? text : "", out, cap);
            g_free(text);
            return answered;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
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
    } else if (GTK_IS_EXPANDER(object)) {
        // A disclosure's text is the title beside the arrow.
        gtk_expander_set_label(GTK_EXPANDER(object), text);
    } else if (GTK_IS_FRAME(object)) {
        // A group box's text is the title on its frame.
        gtk_frame_set_label(GTK_FRAME(object), text[0] ? text : NULL);
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
    if (GTK_IS_EXPANDER(object)) {
        const char *title = gtk_expander_get_label(GTK_EXPANDER(object));
        return ctd_copy_out(title ? title : "", out, cap);
    }
    if (GTK_IS_FRAME(object)) {
        const char *title = gtk_frame_get_label(GTK_FRAME(object));
        return ctd_copy_out(title ? title : "", out, cap);
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
