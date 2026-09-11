// Windows: making them, titling them, showing them, and what they contain.

#include "internal.h"

ctd_handle ctd_surface_new(double width, double height) {
    GtkWidget *window = gtk_window_new();
    gtk_window_set_default_size(GTK_WINDOW(window), (int)width, (int)height);
    return ctd_track(window, -1);
}

ctd_status ctd_surface_set_title(ctd_handle surface, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    char *title = ctd_dup(utf8, len);
    gtk_window_set_title(GTK_WINDOW(object), title);
    g_free(title);
    return CTD_OK;
}

int32_t ctd_surface_title(ctd_handle surface, char *out, int32_t cap) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    return ctd_copy_out(gtk_window_get_title(GTK_WINDOW(object)), out, cap);
}

ctd_status ctd_surface_set_root(ctd_handle surface, ctd_handle root) {
    gpointer object = ctd_resolve(surface);
    gpointer view = ctd_resolve(root);
    if (!object || !view) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    gtk_window_set_child(GTK_WINDOW(object), GTK_WIDGET(view));
    return CTD_OK;
}

ctd_handle ctd_surface_root(ctd_handle surface) {
    gpointer object = ctd_resolve(surface);
    if (!object || !GTK_IS_WINDOW(object)) return 0;
    GtkWidget *child = gtk_window_get_child(GTK_WINDOW(object));
    return child ? ctd_handle_of(child) : 0;
}

ctd_status ctd_surface_content_size(ctd_handle surface, double *out_size) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    int width = gtk_widget_get_width(GTK_WIDGET(object));
    int height = gtk_widget_get_height(GTK_WIDGET(object));
    // A window that has not been presented has no allocation yet; the default
    // size is what it will get, and is the honest answer until it does.
    if (width <= 0 || height <= 0) {
        gtk_window_get_default_size(GTK_WINDOW(object), &width, &height);
    }
    if (out_size) {
        out_size[0] = (double)width;
        out_size[1] = (double)height;
    }
    return CTD_OK;
}

ctd_status ctd_surface_show(ctd_handle surface) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    if (g_role == CTD_ROLE_HEADLESS) return CTD_OK;
    gtk_window_present(GTK_WINDOW(object));
    return CTD_OK;
}

ctd_status ctd_surface_close(ctd_handle surface) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    gtk_window_close(GTK_WINDOW(object));
    return CTD_OK;
}

int32_t ctd_surface_visible(ctd_handle surface) {
    gpointer object = ctd_resolve(surface);
    if (!object || !GTK_IS_WINDOW(object)) return 0;
    return gtk_widget_get_visible(GTK_WIDGET(object)) ? 1 : 0;
}
