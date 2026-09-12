// Rows and columns, filled by asking rather than by building.
//
// GTK4's half of the contract in ../cortado_host.h, and the host where the
// pull is most explicit: a GtkColumnView draws a GListModel, and a GListModel
// is two questions — how many items are there, and give me the one at n. GTK
// asks for the ones it is about to show and no others, so the row objects
// below are made a screenful at a time however long the list is.

#include "internal.h"

static ctd_table_fn g_table_source;
static void        *g_table_context;

// One cell as a freshly allocated UTF-8 string, or NULL. The caller frees it.
static char *ctd_table_text(ctd_handle table, int32_t row, int32_t column) {
    if (!g_table_source) return NULL;
    char small[256];
    int32_t needed = g_table_source(g_table_context, table, row, column,
                                    small, (int32_t)sizeof small);
    if (needed <= 0) return NULL;
    if (needed <= (int32_t)sizeof small) return g_strndup(small, (gsize)needed);
    char *big = (char *)g_malloc((gsize)needed + 1);
    int32_t wrote = g_table_source(g_table_context, table, row, column, big, needed);
    if (wrote <= 0) { g_free(big); return NULL; }
    big[wrote < needed ? wrote : needed] = '\0';
    return big;
}

// ------------------------------------------------------------------ a row

// One row, as the lightest object GObject allows: which table, and which row.
// No cell text — the text is asked for when a label is bound and never kept,
// which is what makes a long list cost what a short one costs.
#define CTD_TYPE_ROW (ctd_row_get_type())
G_DECLARE_FINAL_TYPE(CtdRow, ctd_row, CTD, ROW, GObject)

struct _CtdRow {
    GObject parent_instance;
    guint64 table;
    guint   row;
};

G_DEFINE_TYPE(CtdRow, ctd_row, G_TYPE_OBJECT)

static void ctd_row_init(CtdRow *self) { (void)self; }
static void ctd_row_class_init(CtdRowClass *klass) { (void)klass; }

static CtdRow *ctd_row_new(guint64 table, guint row) {
    CtdRow *self = g_object_new(CTD_TYPE_ROW, NULL);
    self->table = table;
    self->row = row;
    return self;
}

// ---------------------------------------------------------------- the model

#define CTD_TYPE_ROW_MODEL (ctd_row_model_get_type())
G_DECLARE_FINAL_TYPE(CtdRowModel, ctd_row_model, CTD, ROW_MODEL, GObject)

struct _CtdRowModel {
    GObject parent_instance;
    guint64 table;
    guint   rows;
};

static GType ctd_row_model_item_type(GListModel *model) {
    (void)model;
    return CTD_TYPE_ROW;
}

static guint ctd_row_model_n_items(GListModel *model) {
    return CTD_ROW_MODEL(model)->rows;
}

static gpointer ctd_row_model_get_item(GListModel *model, guint position) {
    CtdRowModel *self = CTD_ROW_MODEL(model);
    if (position >= self->rows) return NULL;
    return ctd_row_new(self->table, position);
}

static void ctd_row_model_iface_init(GListModelInterface *iface) {
    iface->get_item_type = ctd_row_model_item_type;
    iface->get_n_items = ctd_row_model_n_items;
    iface->get_item = ctd_row_model_get_item;
}

G_DEFINE_TYPE_WITH_CODE(CtdRowModel, ctd_row_model, G_TYPE_OBJECT,
                        G_IMPLEMENT_INTERFACE(G_TYPE_LIST_MODEL,
                                              ctd_row_model_iface_init))

static void ctd_row_model_init(CtdRowModel *self) { (void)self; }
static void ctd_row_model_class_init(CtdRowModelClass *klass) { (void)klass; }

static CtdRowModel *ctd_row_model_new(guint64 table) {
    CtdRowModel *self = g_object_new(CTD_TYPE_ROW_MODEL, NULL);
    self->table = table;
    self->rows = 0;
    return self;
}

// --------------------------------------------------------------- the columns

static void ctd_cell_setup(GtkSignalListItemFactory *factory,
                           GtkListItem *item, gpointer user) {
    (void)factory; (void)user;
    GtkWidget *label = gtk_label_new("");
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_list_item_set_child(item, label);
}

static void ctd_cell_bind(GtkSignalListItemFactory *factory,
                          GtkListItem *item, gpointer user) {
    (void)factory;
    int32_t column = (int32_t)GPOINTER_TO_INT(user);
    CtdRow *row = CTD_ROW(gtk_list_item_get_item(item));
    GtkWidget *label = gtk_list_item_get_child(item);
    if (!row || !GTK_IS_LABEL(label)) return;
    char *text = ctd_table_text((ctd_handle)row->table, (int32_t)row->row, column);
    gtk_label_set_text(GTK_LABEL(label), text ? text : "");
    g_free(text);
}

// --------------------------------------------------------------- the control

// cortado tracks the scrolled window, because that is the thing with a frame —
// a table that cannot scroll is a table with a hidden bottom — so every call
// here reaches through it.
GtkColumnView *ctd_table_view(gpointer object) {
    if (!GTK_IS_SCROLLED_WINDOW(object)) return NULL;
    GtkWidget *inner = gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(object));
    if (inner && GTK_IS_COLUMN_VIEW(inner)) return GTK_COLUMN_VIEW(inner);
    return NULL;
}

static CtdRowModel *ctd_table_model(GtkColumnView *view) {
    GtkSelectionModel *selection = gtk_column_view_get_model(view);
    if (!selection) return NULL;
    GListModel *inner = gtk_single_selection_get_model(GTK_SINGLE_SELECTION(selection));
    if (!inner || !CTD_IS_ROW_MODEL(inner)) return NULL;
    return CTD_ROW_MODEL(inner);
}

static void ctd_table_selection_changed(GtkSelectionModel *model, guint position,
                                        guint n_items, gpointer user) {
    (void)position; (void)n_items;
    ctd_handle table = (ctd_handle)(uintptr_t)user;
    if (g_writing) return;
    guint chosen = gtk_single_selection_get_selected(GTK_SINGLE_SELECTION(model));
    if (chosen == GTK_INVALID_LIST_POSITION) return;
    ctd_emit(CTD_EV_SELECTION, table, (int64_t)chosen, 0);
}

// Filled in after the handle exists, because a row object carries the handle
// it belongs to and the model is what hands those out. The scrolled window is
// already tracked by then; this puts the control inside it.
void ctd_table_attach(ctd_handle table, GtkWidget *scroller) {
    CtdRowModel *model = ctd_row_model_new((guint64)table);
    GtkSingleSelection *selection = gtk_single_selection_new(G_LIST_MODEL(model));
    gtk_single_selection_set_autoselect(selection, FALSE);
    gtk_single_selection_set_can_unselect(selection, TRUE);
    GtkWidget *view = gtk_column_view_new(GTK_SELECTION_MODEL(selection));
    g_signal_connect(selection, "selection-changed",
                     G_CALLBACK(ctd_table_selection_changed),
                     (gpointer)(uintptr_t)table);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), view);
}

// -------------------------------------------------------------- entry points

ctd_status ctd_set_table_source(ctd_table_fn source, void *context) {
    g_table_source = source;
    g_table_context = context;
    return CTD_OK;
}

ctd_status ctd_table_columns(ctd_handle table, int32_t count) {
    gpointer object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    GtkColumnView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (count < 0) return CTD_ERR_RANGE;
    GListModel *held = gtk_column_view_get_columns(view);
    guint have = g_list_model_get_n_items(held);
    for (guint i = have; i > 0; i--) {
        GtkColumnViewColumn *column = g_list_model_get_item(held, i - 1);
        gtk_column_view_remove_column(view, column);
        g_object_unref(column);
    }
    for (int32_t i = 0; i < count; i++) {
        GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
        g_signal_connect(factory, "setup", G_CALLBACK(ctd_cell_setup), NULL);
        g_signal_connect(factory, "bind", G_CALLBACK(ctd_cell_bind),
                         GINT_TO_POINTER(i));
        GtkColumnViewColumn *column = gtk_column_view_column_new("", factory);
        gtk_column_view_column_set_resizable(column, TRUE);
        gtk_column_view_append_column(view, column);
        g_object_unref(column);
    }
    return CTD_OK;
}

static GtkColumnViewColumn *ctd_table_column(GtkColumnView *view, int32_t column) {
    GListModel *held = gtk_column_view_get_columns(view);
    if (column < 0 || (guint)column >= g_list_model_get_n_items(held)) return NULL;
    return GTK_COLUMN_VIEW_COLUMN(g_list_model_get_item(held, (guint)column));
}

ctd_status ctd_table_column_title(ctd_handle table, int32_t column,
                                  const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    gpointer object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    GtkColumnView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    GtkColumnViewColumn *at = ctd_table_column(view, column);
    if (!at) return CTD_ERR_RANGE;
    char *text = g_strndup(utf8, (gsize)(len < 0 ? 0 : len));
    gtk_column_view_column_set_title(at, text);
    g_free(text);
    g_object_unref(at);
    return CTD_OK;
}

ctd_status ctd_table_column_width(ctd_handle table, int32_t column, double points) {
    gpointer object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    GtkColumnView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (points <= 0.0) return CTD_ERR_RANGE;
    GtkColumnViewColumn *at = ctd_table_column(view, column);
    if (!at) return CTD_ERR_RANGE;
    gtk_column_view_column_set_fixed_width(at, (int)(points + 0.5));
    g_object_unref(at);
    return CTD_OK;
}

ctd_status ctd_table_rows(ctd_handle table, int32_t count) {
    gpointer object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    GtkColumnView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    if (count < 0) return CTD_ERR_RANGE;
    CtdRowModel *model = ctd_table_model(view);
    if (!model) return CTD_ERR_STATE;
    guint was = model->rows;
    model->rows = (guint)count;
    // GTK is told what changed rather than being asked to look: it keeps the
    // widgets for rows that stayed and asks only for the ones that arrived.
    g_list_model_items_changed(G_LIST_MODEL(model), 0, was, (guint)count);
    return CTD_OK;
}

ctd_status ctd_table_reload(ctd_handle table) {
    gpointer object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    GtkColumnView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    CtdRowModel *model = ctd_table_model(view);
    if (!model) return CTD_ERR_STATE;
    guint rows = model->rows;
    g_list_model_items_changed(G_LIST_MODEL(model), 0, rows, rows);
    return CTD_OK;
}

int32_t ctd_table_cell(ctd_handle table, int32_t row, int32_t column,
                       char *out, int32_t cap) {
    gpointer object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    GtkColumnView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    CtdRowModel *model = ctd_table_model(view);
    if (!model) return CTD_ERR_STATE;
    if (row < 0 || (guint)row >= model->rows) return CTD_ERR_RANGE;
    GtkColumnViewColumn *at = ctd_table_column(view, column);
    if (!at) return CTD_ERR_RANGE;
    g_object_unref(at);
    // Through the model's own item, the way a bind does — so what comes back
    // is what a drawn cell would hold rather than what cortado believes.
    CtdRow *item = CTD_ROW(g_list_model_get_item(G_LIST_MODEL(model), (guint)row));
    if (!item) return CTD_ERR_RANGE;
    char *text = ctd_table_text((ctd_handle)item->table, (int32_t)item->row, column);
    g_object_unref(item);
    int32_t answered = ctd_copy_out(text ? text : "", out, cap);
    g_free(text);
    return answered;
}

ctd_status ctd_table_selected(ctd_handle table, int32_t *out) {
    gpointer object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    GtkColumnView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    GtkSelectionModel *selection = gtk_column_view_get_model(view);
    if (!selection) return CTD_ERR_STATE;
    guint chosen = gtk_single_selection_get_selected(GTK_SINGLE_SELECTION(selection));
    if (out) *out = chosen == GTK_INVALID_LIST_POSITION ? -1 : (int32_t)chosen;
    return CTD_OK;
}

ctd_status ctd_table_select(ctd_handle table, int32_t row) {
    gpointer object = ctd_resolve(table);
    if (!object) return CTD_ERR_STALE;
    GtkColumnView *view = ctd_table_view(object);
    if (!view) return CTD_ERR_KIND;
    GtkSelectionModel *selection = gtk_column_view_get_model(view);
    if (!selection) return CTD_ERR_STATE;
    CtdRowModel *model = ctd_table_model(view);
    if (!model) return CTD_ERR_STATE;
    // Silent, like every other write cortado makes on the program's behalf —
    // see g_writing in internal.h. GtkSingleSelection emits
    // "selection-changed" whoever moved the selection, so without this a
    // program that selects a row hears it back as a row the user picked.
    if (row < 0) {
        g_writing++;
        gtk_single_selection_set_selected(GTK_SINGLE_SELECTION(selection),
                                          GTK_INVALID_LIST_POSITION);
        g_writing--;
        return CTD_OK;
    }
    if ((guint)row >= model->rows) return CTD_ERR_RANGE;
    g_writing++;
    gtk_single_selection_set_selected(GTK_SINGLE_SELECTION(selection), (guint)row);
    g_writing--;
    return CTD_OK;
}
