// A control that offers a list of choices.

#include "internal.h"

static GtkStringList *ctd_item_list(gpointer object) {
    if (!GTK_IS_DROP_DOWN(object)) return NULL;
    GListModel *model = gtk_drop_down_get_model(GTK_DROP_DOWN(object));
    return model && GTK_IS_STRING_LIST(model) ? GTK_STRING_LIST(model) : NULL;
}

static ctd_status ctd_items_clear_raising(ctd_handle widget) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkStringList *items = ctd_item_list(object);
    if (!items) return CTD_ERR_KIND;
    guint count = g_list_model_get_n_items(G_LIST_MODEL(items));
    if (count > 0) gtk_string_list_splice(items, 0, count, NULL);
    return CTD_OK;
}

// Silent, like every other write cortado makes: changing the model of a
// GtkDropDown moves its selection, and a moved selection notifies.
ctd_status ctd_items_clear(ctd_handle widget) {
    g_writing++;
    ctd_status status = ctd_items_clear_raising(widget);
    g_writing--;
    return status;
}

static ctd_status ctd_items_add_raising(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkStringList *items = ctd_item_list(object);
    if (!items) return CTD_ERR_KIND;
    if (len < 0) return CTD_ERR_RANGE;
    char *text = ctd_dup(utf8, len);
    gtk_string_list_append(items, text);
    g_free(text);
    return CTD_OK;
}

// Silent, like every other write cortado makes: changing the model of a
// GtkDropDown moves its selection, and a moved selection notifies.
ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    g_writing++;
    ctd_status status = ctd_items_add_raising(widget, utf8, len);
    g_writing--;
    return status;
}

ctd_status ctd_items_count(ctd_handle widget, int32_t *out) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkStringList *items = ctd_item_list(object);
    if (!items) return CTD_ERR_KIND;
    if (out) *out = (int32_t)g_list_model_get_n_items(G_LIST_MODEL(items));
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    gpointer object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    GtkStringList *items = ctd_item_list(object);
    if (!items) return CTD_ERR_KIND;
    guint count = g_list_model_get_n_items(G_LIST_MODEL(items));
    if (index < 0 || (guint)index >= count) return CTD_ERR_RANGE;
    return ctd_copy_out(gtk_string_list_get_string(items, (guint)index), out, cap);
}
