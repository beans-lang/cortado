// The containers a platform draws chrome for.
//
// GTK is the one platform of the four that has a real disclosure container:
// GtkExpander holds a child, draws its own arrow and title, and hides the
// child when it is shut. The other three hosts assemble one out of the
// platform's own glyph; this one asks for it by name.
//
// What every host has to answer is how much of its frame the chrome took, so
// the caller's layout can leave room. GTK will not say without a layout pass,
// and a headless gate never has one — so each answer here is measured off a
// *reference* widget with an empty child, once. A measurement of an empty
// container is exactly the chrome, and it is GTK's number rather than one
// written down here.

#include "internal.h"

// The height a GtkExpander takes for its own header, and the border a
// GtkFrame takes for itself.
//
// Measured once. GtkExpander's arrow follows the icon theme and GtkFrame's
// border follows the stylesheet, so both are properties of the machine this
// is running on and neither can be a constant in this file.
static void ctd_pane_reference(int *header, int *frame_x, int *frame_y) {
    static int known_header = 0;
    static int known_x = 0;
    static int known_y = 0;
    static int asked = 0;
    if (!asked) {
        int least = 0, natural = 0;

        GtkWidget *expander = gtk_expander_new("X");
        GtkWidget *empty = gtk_fixed_new();
        gtk_expander_set_child(GTK_EXPANDER(expander), empty);
        gtk_expander_set_expanded(GTK_EXPANDER(expander), TRUE);
        gtk_widget_measure(expander, GTK_ORIENTATION_VERTICAL, -1,
                           &least, &natural, NULL, NULL);
        known_header = least;
        g_object_ref_sink(expander);
        g_object_unref(expander);

        GtkWidget *box = gtk_frame_new("X");
        GtkWidget *inside = gtk_fixed_new();
        gtk_frame_set_child(GTK_FRAME(box), inside);
        gtk_widget_measure(box, GTK_ORIENTATION_HORIZONTAL, -1,
                           &least, &natural, NULL, NULL);
        known_x = least;
        gtk_widget_measure(box, GTK_ORIENTATION_VERTICAL, -1,
                           &least, &natural, NULL, NULL);
        known_y = least;
        g_object_ref_sink(box);
        g_object_unref(box);

        asked = 1;
    }
    if (header) *header = known_header;
    if (frame_x) *frame_x = known_x;
    if (frame_y) *frame_y = known_y;
}

// The height a GtkNotebook takes for its strip of tabs, measured the same way
// and for the same reason: an empty page makes the measurement the chrome.
static void ctd_notebook_reference(int *header) {
    static int known = 0;
    static int asked = 0;
    if (!asked) {
        int least = 0, natural = 0;
        GtkWidget *book = gtk_notebook_new();
        GtkWidget *empty = gtk_fixed_new();
        gtk_notebook_append_page(GTK_NOTEBOOK(book), empty, gtk_label_new("X"));
        gtk_widget_measure(book, GTK_ORIENTATION_VERTICAL, -1,
                           &least, &natural, NULL, NULL);
        known = least;
        g_object_ref_sink(book);
        g_object_unref(book);
        asked = 1;
    }
    if (header) *header = known;
}

void ctd_split_chrome(gpointer object, double *out);

void ctd_chrome_of(gpointer object, double *out) {
    out[0] = 0.0; out[1] = 0.0; out[2] = 0.0; out[3] = 0.0;
    if (GTK_IS_EXPANDER(object)) {
        int header = 0;
        ctd_pane_reference(&header, NULL, NULL);
        out[1] = (double)header;
        return;
    }
    if (GTK_IS_PANED(object)) {
        ctd_split_chrome(object, out);
        return;
    }
    if (GTK_IS_NOTEBOOK(object)) {
        int header = 0;
        ctd_notebook_reference(&header);
        out[1] = (double)header;
        return;
    }
    if (GTK_IS_FRAME(object)) {
        int wide = 0, tall = 0;
        ctd_pane_reference(NULL, &wide, &tall);
        // A frame's border is symmetrical side to side; its label sits in the
        // top edge, so what is left over after the two side borders goes
        // there. Split rather than measured separately because GTK reports a
        // minimum size and not an inset, and the minimum is the sum.
        double side = (double)wide / 2.0;
        out[0] = side;
        out[2] = side;
        out[1] = (double)tall - side;
        out[3] = side;
        return;
    }
}

ctd_status ctd_view_content_inset(ctd_handle widget, double *out_inset) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WIDGET(object)) return CTD_ERR_KIND;
    double chrome[4];
    ctd_chrome_of(object, chrome);
    if (out_inset) {
        out_inset[0] = chrome[0];
        out_inset[1] = chrome[1];
        out_inset[2] = chrome[2];
        out_inset[3] = chrome[3];
    }
    return CTD_OK;
}

// ------------------------------------------------------------------ tab views
//
// GtkNotebook, and the same model as every other host: a tab view's children
// are its pages, one each, in order. A page is not a child of a GtkFixed here
// either — it is a page *of* the notebook, which is what
// `ctd_kind_holds_pages` names.

GtkNotebook *ctd_tab_view(gpointer object) {
    if (GTK_IS_NOTEBOOK(object)) return GTK_NOTEBOOK(object);
    return NULL;
}

int ctd_tab_index_of(GtkNotebook *tabs, GtkWidget *page) {
    int count = gtk_notebook_get_n_pages(tabs);
    for (int at = 0; at < count; at++) {
        if (gtk_notebook_get_nth_page(tabs, at) == page) return at;
    }
    return -1;
}

ctd_status ctd_tab_add_page(GtkNotebook *tabs, GtkWidget *page, int32_t index) {
    GtkWidget *label = gtk_label_new("");
    int count = gtk_notebook_get_n_pages(tabs);
    if (index < 0 || index >= count) {
        gtk_notebook_append_page(tabs, page, label);
    } else {
        gtk_notebook_insert_page(tabs, page, label, index);
    }
    return CTD_OK;
}

ctd_status ctd_tab_set_label(ctd_handle widget, int32_t index,
                             const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkNotebook *tabs = ctd_tab_view(object);
    if (!tabs) return CTD_ERR_KIND;
    if (index < 0 || index >= gtk_notebook_get_n_pages(tabs)) return CTD_ERR_RANGE;
    char *text = ctd_dup(utf8, len);
    gtk_notebook_set_tab_label_text(tabs, gtk_notebook_get_nth_page(tabs, index), text);
    g_free(text);
    return CTD_OK;
}

int32_t ctd_tab_label(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkNotebook *tabs = ctd_tab_view(object);
    if (!tabs) return CTD_ERR_KIND;
    if (index < 0 || index >= gtk_notebook_get_n_pages(tabs)) return CTD_ERR_RANGE;
    const char *words =
        gtk_notebook_get_tab_label_text(tabs, gtk_notebook_get_nth_page(tabs, index));
    return ctd_copy_out(words ? words : "", out, cap);
}

// ---------------------------------------------------------------- split views
//
// GtkPaned, which takes exactly two children and lays them out from one
// number — the same arrangement NSSplitView has, and the reason a split view's
// panes are the platform's to place rather than the solver's.

GtkPaned *ctd_split_view(gpointer object) {
    if (GTK_IS_PANED(object)) return GTK_PANED(object);
    return NULL;
}

// Which pane a child is: 0, 1, or -1 for neither.
int ctd_split_index_of(GtkPaned *split, GtkWidget *pane) {
    if (gtk_paned_get_start_child(split) == pane) return 0;
    if (gtk_paned_get_end_child(split) == pane) return 1;
    return -1;
}

ctd_status ctd_split_add_pane(GtkPaned *split, GtkWidget *pane, int32_t index) {
    int filled = (gtk_paned_get_start_child(split) ? 1 : 0) +
                 (gtk_paned_get_end_child(split) ? 1 : 0);
    if (filled >= 2) return CTD_ERR_RANGE;
    // Index past the end appends, the same as every other container here. The
    // first child added is the first pane whatever index says, because there
    // is nowhere else for it to go.
    if (!gtk_paned_get_start_child(split) && (index <= 0 || filled == 0)) {
        gtk_paned_set_start_child(split, pane);
        return CTD_OK;
    }
    if (!gtk_paned_get_end_child(split)) {
        gtk_paned_set_end_child(split, pane);
        return CTD_OK;
    }
    gtk_paned_set_start_child(split, pane);
    return CTD_OK;
}

// The handle's own thickness, from the widget rather than from a number here.
static int ctd_paned_handle(void) {
    static int known = 0;
    static int asked = 0;
    if (!asked) {
        int least = 0, natural = 0;
        GtkWidget *split = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
        gtk_paned_set_start_child(GTK_PANED(split), gtk_fixed_new());
        gtk_paned_set_end_child(GTK_PANED(split), gtk_fixed_new());
        gtk_widget_measure(split, GTK_ORIENTATION_HORIZONTAL, -1,
                           &least, &natural, NULL, NULL);
        known = least;
        g_object_ref_sink(split);
        g_object_unref(split);
        asked = 1;
    }
    return known;
}

void ctd_split_chrome(gpointer object, double *out) {
    GtkPaned *split = GTK_PANED(object);
    if (gtk_orientable_get_orientation(GTK_ORIENTABLE(split)) ==
        GTK_ORIENTATION_HORIZONTAL) {
        out[2] = (double)ctd_paned_handle();
    } else {
        out[3] = (double)ctd_paned_handle();
    }
}

// ------------------------------------------------------- toolbars and popovers
//
// GTK4 removed GtkToolbar, and it was not replaced by another toolbar: the
// GNOME shape is a header bar *in place of* the title bar, with the window's
// commands in it. That is what this builds — a real GtkHeaderBar set as the
// window's titlebar — so a toolbar here takes no room from the content, the
// same as AppKit's.
//
// A popover is GtkPopover, which is a real widget with a parent rather than a
// window of its own; GTK positions it over whatever it is attached to.

static GtkWidget *ctd_header_of(GtkWindow *window) {
    GtkWidget *bar = gtk_window_get_titlebar(window);
    return (bar && GTK_IS_HEADER_BAR(bar)) ? bar : NULL;
}

static void ctd_toolbar_clicked(GtkButton *button, gpointer user) {
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = CTD_EV_COMMAND;
    event.token = (int64_t)(intptr_t)g_object_get_data(G_OBJECT(button), "ctd-token");
    (void)user;
    if (g_sink) g_sink(g_sink_context, &event);
}

ctd_status ctd_toolbar_set(ctd_handle surface, ctd_handle menu_handle) {
    gpointer window = ctd_resolve(surface);
    gpointer source = ctd_resolve(menu_handle);
    if (!window || !source) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(window)) return CTD_ERR_KIND;
    GArray *items = ctd_menu_commands(menu_handle);
    if (!items) return CTD_ERR_KIND;

    GtkWidget *bar = gtk_header_bar_new();
    gtk_header_bar_set_show_title_buttons(GTK_HEADER_BAR(bar), TRUE);
    int shown = 0;
    for (guint at = 0; at < items->len; at++) {
        CtdCommand *item = &g_array_index(items, CtdCommand, at);
        // A separator is a gap, which a header bar spells by packing nothing.
        if (item->separator) { shown++; continue; }
        GtkWidget *button = gtk_button_new_with_label(item->title ? item->title : "");
        g_object_set_data(G_OBJECT(button), "ctd-token",
                          (gpointer)(intptr_t)item->token);
        g_signal_connect(button, "clicked", G_CALLBACK(ctd_toolbar_clicked), NULL);
        gtk_widget_set_sensitive(button, item->enabled ? TRUE : FALSE);
        gtk_header_bar_pack_start(GTK_HEADER_BAR(bar), button);
        shown++;
    }
    g_object_set_data(G_OBJECT(bar), "ctd-count", (gpointer)(intptr_t)shown);
    gtk_window_set_titlebar(GTK_WINDOW(window), bar);
    return CTD_OK;
}

ctd_status ctd_toolbar_clear(ctd_handle surface) {
    gpointer window = ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(window)) return CTD_ERR_KIND;
    gtk_window_set_titlebar(GTK_WINDOW(window), NULL);
    return CTD_OK;
}

ctd_status ctd_toolbar_count(ctd_handle surface, int32_t *out) {
    gpointer window = ctd_resolve(surface);
    if (!window) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(window)) return CTD_ERR_KIND;
    GtkWidget *bar = ctd_header_of(GTK_WINDOW(window));
    if (out) {
        *out = bar ? (int32_t)(intptr_t)g_object_get_data(G_OBJECT(bar), "ctd-count") : 0;
    }
    return CTD_OK;
}

// ----------------------------------------------------------------- popovers

static void ctd_popover_closed(GtkPopover *popover, gpointer user) {
    (void)popover;
    ctd_emit(CTD_EV_DISMISS, (ctd_handle)(uintptr_t)user, 0, 0);
}

static GtkPopover *ctd_popover_of(ctd_handle handle) {
    gpointer object = ctd_resolve(handle);
    return (object && GTK_IS_POPOVER(object)) ? GTK_POPOVER(object) : NULL;
}

ctd_handle ctd_popover_new(ctd_handle content, double width, double height) {
    gpointer inside = ctd_resolve(content);
    if (!inside || !GTK_IS_WIDGET(inside)) return 0;
    if (width <= 0.0 || height <= 0.0) return 0;
    GtkWidget *popover = gtk_popover_new();
    gtk_popover_set_child(GTK_POPOVER(popover), GTK_WIDGET(inside));
    gtk_widget_set_size_request(GTK_WIDGET(inside), (int)width, (int)height);
    gtk_popover_set_autohide(GTK_POPOVER(popover), TRUE);
    ctd_handle handle = ctd_track(popover, -1);
    if (!handle) return 0;
    g_signal_connect(popover, "closed", G_CALLBACK(ctd_popover_closed),
                     (gpointer)(uintptr_t)handle);
    return handle;
}

ctd_status ctd_popover_show(ctd_handle handle, ctd_handle anchor, int32_t edge) {
    GtkPopover *popover = ctd_popover_of(handle);
    gpointer view = ctd_resolve(anchor);
    if (!popover || !view) return CTD_ERR_STALE;
    if (!GTK_IS_WIDGET(view)) return CTD_ERR_KIND;
    if (edge < CTD_EDGE_MIN_X || edge > CTD_EDGE_MAX_Y) return CTD_ERR_RANGE;
    gtk_widget_set_parent(GTK_WIDGET(popover), GTK_WIDGET(view));
    gtk_popover_set_position(GTK_POPOVER(popover),
        edge == CTD_EDGE_MIN_X ? GTK_POS_LEFT
      : edge == CTD_EDGE_MIN_Y ? GTK_POS_TOP
      : edge == CTD_EDGE_MAX_X ? GTK_POS_RIGHT
                               : GTK_POS_BOTTOM);
    gtk_popover_popup(GTK_POPOVER(popover));
    return CTD_OK;
}

ctd_status ctd_popover_close(ctd_handle handle) {
    GtkPopover *popover = ctd_popover_of(handle);
    if (!popover) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    gtk_popover_popdown(popover);
    return CTD_OK;
}

ctd_status ctd_popover_shown(ctd_handle handle, int32_t *out) {
    GtkPopover *popover = ctd_popover_of(handle);
    if (!popover) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = gtk_widget_get_visible(GTK_WIDGET(popover)) ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_popover_release(ctd_handle handle) {
    GtkPopover *popover = ctd_popover_of(handle);
    if (!popover) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // The content goes back to being an ordinary unparented widget, still
    // named by its own handle: the caller built that tree and may show it
    // again, so the popover must not take it down.
    gtk_popover_set_child(popover, NULL);
    if (gtk_widget_get_parent(GTK_WIDGET(popover)))
        gtk_widget_unparent(GTK_WIDGET(popover));
    ctd_untrack(handle);
    return CTD_OK;
}
