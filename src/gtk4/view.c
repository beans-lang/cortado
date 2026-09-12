// The view tree: parenting, ordering, frames and measurement.
//
// Everything is placed in a GtkFixed, because it is the one container that
// lets a caller say where a child goes rather than negotiating for it.

#include "internal.h"

// Where a widget's children go. A scroll view's live in its GtkFixed child; a
// text area's scrolled window holds text and can hold nothing else.
static GtkFixed *ctd_container_of(gpointer object) {
    if (GTK_IS_FIXED(object)) return GTK_FIXED(object);
    if (GTK_IS_SCROLLED_WINDOW(object)) {
        GtkWidget *inner = gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(object));
        if (inner && GTK_IS_FIXED(inner)) return GTK_FIXED(inner);
        return NULL;
    }
    // A frame takes one child, and cortado's boxes take many — so the one
    // child is a GtkFixed and the children go in there.
    if (GTK_IS_FRAME(object)) {
        GtkWidget *inner = gtk_frame_get_child(GTK_FRAME(object));
        if (inner && GTK_IS_FIXED(inner)) return GTK_FIXED(inner);
        return NULL;
    }
    // A disclosure's children go under its header. GtkExpander takes one
    // child, the same as a frame, so the one child is a GtkFixed.
    if (GTK_IS_EXPANDER(object)) {
        GtkWidget *inner = gtk_expander_get_child(GTK_EXPANDER(object));
        if (inner && GTK_IS_FIXED(inner)) return GTK_FIXED(inner);
        return NULL;
    }
    if (GTK_IS_WINDOW(object)) {
        GtkWidget *child = gtk_window_get_child(GTK_WINDOW(object));
        if (child && GTK_IS_FIXED(child)) return GTK_FIXED(child);
        return NULL;
    }
    return NULL;
}

// cortado's children of a container, in order, skipping anything GTK put there
// itself.
static GPtrArray *ctd_children(GtkFixed *container) {
    GPtrArray *ours = g_ptr_array_new();
    for (GtkWidget *child = gtk_widget_get_first_child(GTK_WIDGET(container));
         child != NULL;
         child = gtk_widget_get_next_sibling(child)) {
        if (ctd_is_ours(child)) g_ptr_array_add(ours, child);
    }
    return ours;
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    gpointer owner = ctd_resolve(parent);
    gpointer view = ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    // A tab view's children are its pages, and a page is not a child of a
    // GtkFixed: it belongs to the notebook, which shows and hides it as the
    // selection moves. Asked first, because a notebook would otherwise fall
    // through to `ctd_container_of` and be refused as holding nothing.
    GtkNotebook *tabs = ctd_tab_view(owner);
    if (tabs) return ctd_tab_add_page(tabs, GTK_WIDGET(view), index);
    // A split view's two panes are children in the ABI's sense and children of
    // no GtkFixed: GtkPaned holds one at each end and lays both out itself.
    GtkPaned *split = ctd_split_view(owner);
    if (split) return ctd_split_add_pane(split, GTK_WIDGET(view), index);
    GtkFixed *container = ctd_container_of(owner);
    if (!container) return CTD_ERR_KIND;

    gtk_fixed_put(container, GTK_WIDGET(view), 0, 0);

    // A radio button joins the group of the first radio already under this
    // parent. GTK4 has no radio class; a group is a chain of check buttons,
    // and "the same parent is one group" is the rule every host here follows.
    if (ctd_slot_kind(child) == CTD_W_RADIO_BUTTON) {
        GPtrArray *siblings = ctd_children(container);
        for (guint i = 0; i < siblings->len; i++) {
            GtkWidget *other = g_ptr_array_index(siblings, i);
            if (other == GTK_WIDGET(view)) continue;
            if (ctd_slot_kind(ctd_handle_of(other)) != CTD_W_RADIO_BUTTON) continue;
            gtk_check_button_set_group(GTK_CHECK_BUTTON(view),
                                       GTK_CHECK_BUTTON(other));
            break;
        }
        g_ptr_array_free(siblings, TRUE);
    }

    // GtkFixed has no insert-at-index, so a child that belongs earlier is put
    // in front of the one it should precede. `index` past the end appends,
    // which is what -1 already means.
    GPtrArray *ours = ctd_children(container);
    if (index >= 0 && index < (int32_t)ours->len - 1) {
        GtkWidget *before = g_ptr_array_index(ours, (guint)index);
        gtk_widget_insert_before(GTK_WIDGET(view), GTK_WIDGET(container), before);
    }
    g_ptr_array_free(ours, TRUE);
    return CTD_OK;
}

ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child) {
    gpointer owner = ctd_resolve(parent);
    gpointer view = ctd_resolve(child);
    if (!owner || !view) return CTD_ERR_STALE;
    GtkNotebook *tabs = ctd_tab_view(owner);
    if (tabs) {
        int at = ctd_tab_index_of(tabs, GTK_WIDGET(view));
        if (at < 0) return CTD_ERR_RANGE;
        gtk_notebook_remove_page(tabs, at);
        return CTD_OK;
    }
    GtkPaned *split = ctd_split_view(owner);
    if (split) {
        int at = ctd_split_index_of(split, GTK_WIDGET(view));
        if (at < 0) return CTD_ERR_RANGE;
        if (at == 0) gtk_paned_set_start_child(split, NULL);
        else         gtk_paned_set_end_child(split, NULL);
        return CTD_OK;
    }
    GtkFixed *container = ctd_container_of(owner);
    if (!container) return CTD_ERR_KIND;
    if (gtk_widget_get_parent(GTK_WIDGET(view)) != GTK_WIDGET(container))
        return CTD_ERR_RANGE;
    // The table's reference is what keeps this alive: GtkFixed drops its own
    // on removal, and on a widget nobody else names that would be the last.
    gtk_fixed_remove(container, GTK_WIDGET(view));
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    gpointer owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    GtkPaned *split = ctd_split_view(owner);
    if (split) {
        GtkWidget *first = gtk_paned_get_start_child(split);
        GtkWidget *last = gtk_paned_get_end_child(split);
        if (from < 0 || from > 1 || to < 0 || to > 1) return CTD_ERR_RANGE;
        if (!first || !last) return CTD_ERR_RANGE;
        if (from == to) return CTD_OK;
        // Both references are held by the handle table, so unparenting one
        // cannot finalize it — which is the hazard ctd_view_move_child exists
        // to keep out of the layer above.
        g_object_ref(first);
        g_object_ref(last);
        gtk_paned_set_start_child(split, NULL);
        gtk_paned_set_end_child(split, NULL);
        gtk_paned_set_start_child(split, last);
        gtk_paned_set_end_child(split, first);
        g_object_unref(first);
        g_object_unref(last);
        return CTD_OK;
    }
    GtkNotebook *tabs = ctd_tab_view(owner);
    if (tabs) {
        int count = gtk_notebook_get_n_pages(tabs);
        if (from < 0 || from >= count || to < 0 || to >= count) return CTD_ERR_RANGE;
        if (from == to) return CTD_OK;
        // GtkNotebook has a real reorder, which keeps the page's label and its
        // widget together and never unparents anything — the hazard
        // ctd_view_move_child exists to keep out of the layer above.
        gtk_notebook_reorder_child(tabs, gtk_notebook_get_nth_page(tabs, from), to);
        return CTD_OK;
    }
    GtkFixed *container = ctd_container_of(owner);
    if (!container) return CTD_ERR_KIND;
    GPtrArray *ours = ctd_children(container);
    int32_t count = (int32_t)ours->len;
    if (from < 0 || from >= count || to < 0 || to >= count) {
        g_ptr_array_free(ours, TRUE);
        return CTD_ERR_RANGE;
    }
    if (from == to) { g_ptr_array_free(ours, TRUE); return CTD_OK; }

    GtkWidget *moving = g_ptr_array_index(ours, (guint)from);
    // Reparenting, not remove-and-add: GTK4 finalizes a widget the moment its
    // last reference drops on unparent, which is the hazard
    // `ctd_view_move_child` exists to keep out of the layer above. The table
    // holds a reference so it could not happen here, and this is still one
    // operation because it is one intent.
    if (to >= count - 1) {
        gtk_widget_insert_after(moving, GTK_WIDGET(container),
                                g_ptr_array_index(ours, (guint)(count - 1)));
    } else {
        GtkWidget *before = g_ptr_array_index(ours, (guint)(to > from ? to : to));
        if (before != moving)
            gtk_widget_insert_before(moving, GTK_WIDGET(container), before);
    }
    g_ptr_array_free(ours, TRUE);
    return CTD_OK;
}

ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out) {
    gpointer owner = ctd_resolve(parent);
    if (!owner) return CTD_ERR_STALE;
    GtkNotebook *tabs = ctd_tab_view(owner);
    if (tabs) {
        if (out) *out = gtk_notebook_get_n_pages(tabs);
        return CTD_OK;
    }
    GtkPaned *split = ctd_split_view(owner);
    if (split) {
        if (out) *out = (gtk_paned_get_start_child(split) ? 1 : 0) +
                        (gtk_paned_get_end_child(split) ? 1 : 0);
        return CTD_OK;
    }
    GtkFixed *container = ctd_container_of(owner);
    if (!container) {
        // A control that cannot hold children has none, which is an answer and
        // not a refusal: a tree walk asks this of every node.
        if (out) *out = 0;
        return CTD_OK;
    }
    GPtrArray *ours = ctd_children(container);
    if (out) *out = (int32_t)ours->len;
    g_ptr_array_free(ours, TRUE);
    return CTD_OK;
}

ctd_handle ctd_view_child_at(ctd_handle parent, int32_t index) {
    gpointer owner = ctd_resolve(parent);
    if (!owner) return 0;
    GtkNotebook *tabs = ctd_tab_view(owner);
    if (tabs) {
        if (index < 0 || index >= gtk_notebook_get_n_pages(tabs)) return 0;
        return ctd_handle_of(gtk_notebook_get_nth_page(tabs, index));
    }
    GtkPaned *split = ctd_split_view(owner);
    if (split) {
        GtkWidget *pane = index == 0 ? gtk_paned_get_start_child(split)
                        : index == 1 ? gtk_paned_get_end_child(split) : NULL;
        return pane ? ctd_handle_of(pane) : 0;
    }
    GtkFixed *container = ctd_container_of(owner);
    if (!container) return 0;
    GPtrArray *ours = ctd_children(container);
    ctd_handle found = 0;
    if (index >= 0 && index < (int32_t)ours->len)
        found = ctd_handle_of(g_ptr_array_index(ours, (guint)index));
    g_ptr_array_free(ours, TRUE);
    return found;
}

ctd_handle ctd_view_parent(ctd_handle child) {
    gpointer view = ctd_resolve(child);
    if (!view) return 0;
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(view));
    while (parent && !ctd_is_ours(parent)) {
        parent = gtk_widget_get_parent(parent);
    }
    return parent ? ctd_handle_of(parent) : 0;
}


ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height) {
    gpointer view = ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    // Two calls, because GTK splits what every other platform joins: position
    // belongs to the parent's layout and size is a request the child makes.
    // The request is a *minimum* — GTK will not allocate a widget smaller than
    // it says it needs — which is why `tests/roles.out` carries no frames.
    // A pane and a page are both the platform's to place, and for the same
    // reason: the control owns where its child goes. GtkPaned lays both panes
    // out from the divider's position, and GtkNotebook allocates a page to
    // the area under the tab strip — a size request on either fights the
    // control and wins only until the next allocation, which is the worst of
    // both: the number cortado reads back is not the number GTK draws.
    GtkWidget *owner_widget = gtk_widget_get_parent(GTK_WIDGET(view));
    if (owner_widget && GTK_IS_PANED(owner_widget)) return CTD_OK;
    // A page is not the notebook's direct child — GTK4 puts a stack between
    // them — so the question has to be asked of the notebook rather than of
    // the parent: gtk_notebook_page_num answers -1 for a widget that is not
    // one of its pages, which also keeps this from catching everything that
    // merely *sits inside* a page.
    GtkWidget *book = gtk_widget_get_ancestor(GTK_WIDGET(view), GTK_TYPE_NOTEBOOK);
    if (book && gtk_notebook_page_num(GTK_NOTEBOOK(book), GTK_WIDGET(view)) >= 0) {
        return CTD_OK;
    }
    gtk_widget_set_size_request(GTK_WIDGET(view), (int)width, (int)height);
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(view));
    if (parent && GTK_IS_FIXED(parent)) {
        gtk_fixed_move(GTK_FIXED(parent), GTK_WIDGET(view), x, y);
    }
    return CTD_OK;
}

ctd_status ctd_view_frame(ctd_handle widget, double *out_frame) {
    gpointer view = ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    double x = 0.0, y = 0.0;
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(view));
    if (parent && GTK_IS_FIXED(parent)) {
        gtk_fixed_get_child_position(GTK_FIXED(parent), GTK_WIDGET(view), &x, &y);
    }
    int width = gtk_widget_get_width(GTK_WIDGET(view));
    int height = gtk_widget_get_height(GTK_WIDGET(view));
    // Before the first allocation a widget has no size. What was asked for is
    // the honest answer until GTK has laid out.
    if (width <= 0 || height <= 0) {
        gtk_widget_get_size_request(GTK_WIDGET(view), &width, &height);
        if (width < 0) width = 0;
        if (height < 0) height = 0;
    }
    if (out_frame) {
        out_frame[0] = x;
        out_frame[1] = y;
        out_frame[2] = (double)width;
        out_frame[3] = (double)height;
    }
    return CTD_OK;
}

// **The size cache the macOS host keeps is deliberately not here**, and the
// reason is one line below: `gtk_widget_measure` takes a `for_size`, and the
// height is asked for the width just decided. That is height-for-width working
// correctly — a wrapping label is shorter when it is wider — and it means the
// answer belongs to the pair and not to the widget, so a cache keyed on the
// widget alone would hand back the height for somebody else's width.
//
// It is also not needed. Measured, on this host, with `examples/bench.b`:
// asking a control how big it wants to be is under a microsecond here and a
// two-hundred-control solve takes 62 us, because GTK4 keeps a size-request
// cache of its own. AppKit keeps none, which is why the Mac has one and this
// does not.
ctd_status ctd_view_measure(ctd_handle widget, double avail_width, double avail_height,
                            double *out_size) {
    gpointer view = ctd_resolve(widget);
    if (!view) return CTD_ERR_STALE;
    int minimum = 0, natural = 0, ignored = 0;
    gtk_widget_measure(GTK_WIDGET(view), GTK_ORIENTATION_HORIZONTAL, -1,
                       &minimum, &natural, &ignored, &ignored);
    double width = (double)natural;
    if (avail_width >= 0.0 && width > avail_width) width = avail_width;
    // Height for the width just decided: a wrapping label is shorter when it
    // is wider, and asking for both independently gets that wrong.
    gtk_widget_measure(GTK_WIDGET(view), GTK_ORIENTATION_VERTICAL, (int)width,
                       &minimum, &natural, &ignored, &ignored);
    double height = (double)natural;
    if (avail_height >= 0.0 && height > avail_height) height = avail_height;
    if (out_size) {
        out_size[0] = width;
        out_size[1] = height;
    }
    return CTD_OK;
}

// The surface a widget is in.
//
// `gtk_widget_get_root` answers the GtkRoot, which for cortado is always the
// GtkWindow a surface was made as. `ctd_handle_of` turns it back into a
// handle; this host already had that lookup.
ctd_handle ctd_view_surface(ctd_handle widget) {
    gpointer object = ctd_resolve(widget);
    if (!object || !GTK_IS_WIDGET(object)) return 0;
    GtkRoot *root = gtk_widget_get_root(GTK_WIDGET(object));
    if (!root) return 0;
    return ctd_handle_of(root);
}
