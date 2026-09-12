// A tree, filled by asking about one node at a time.
//
// GTK4's half of the contract in ../cortado_host.h beside `ctd_outline_fn`.
// This host is the one where the shape of the idea is most visible, because
// GTK spells it out: a GtkColumnView draws a GtkTreeListModel, and a
// GtkTreeListModel is a root GListModel plus a function that, given a row,
// answers the GListModel of its children — or NULL when it has none. That is
// exactly cortado's three questions with the names changed.
//
// The one piece of bookkeeping is a table of node → child model. It exists so
// a reload can change what a node's children are *in place*: rebuilding the
// tree from a fresh root would throw away every GtkTreeListRow, and the
// control would forget which nodes were open — which is the one thing a
// refresh must not do.

#include "internal.h"

static ctd_outline_fn      g_outline_shape;
static void               *g_outline_shape_context;
static ctd_outline_text_fn g_outline_text;
static void               *g_outline_text_context;

static int64_t ctd_outline_ask(ctd_handle outline, int32_t what, int64_t node,
                               int32_t index) {
    if (!g_outline_shape) return 0;
    return g_outline_shape(g_outline_shape_context, outline, what, node, index);
}

// One cell as a freshly allocated UTF-8 string, or NULL. The caller frees it.
static char *ctd_outline_words(ctd_handle outline, int64_t node, int32_t column) {
    if (!g_outline_text) return NULL;
    char small[256];
    int32_t needed = g_outline_text(g_outline_text_context, outline, node, column,
                                    small, (int32_t)sizeof small);
    if (needed <= 0) return NULL;
    if (needed <= (int32_t)sizeof small) return g_strndup(small, (gsize)needed);
    char *big = (char *)g_malloc((gsize)needed + 1);
    int32_t wrote = g_outline_text(g_outline_text_context, outline, node, column,
                                   big, needed);
    if (wrote <= 0) { g_free(big); return NULL; }
    big[wrote < needed ? wrote : needed] = '\0';
    return big;
}

// ----------------------------------------------------------------- a node

// One node, as the lightest object GObject allows: which outline, and which
// node. No text and no children — both are asked for when they are needed,
// which is what makes a tree of a hundred thousand nodes cost what a tree of
// ten costs.
#define CTD_TYPE_NODE (ctd_node_get_type())
G_DECLARE_FINAL_TYPE(CtdNode, ctd_node, CTD, NODE, GObject)

struct _CtdNode {
    GObject parent_instance;
    guint64 outline;
    gint64  node;
};

G_DEFINE_TYPE(CtdNode, ctd_node, G_TYPE_OBJECT)

static void ctd_node_init(CtdNode *self) { (void)self; }
static void ctd_node_class_init(CtdNodeClass *klass) { (void)klass; }

static CtdNode *ctd_node_new(guint64 outline, gint64 node) {
    CtdNode *self = g_object_new(CTD_TYPE_NODE, NULL);
    self->outline = outline;
    self->node = node;
    return self;
}

// ------------------------------------------------------- a node's children

#define CTD_TYPE_KIDS (ctd_kids_get_type())
G_DECLARE_FINAL_TYPE(CtdKids, ctd_kids, CTD, KIDS, GObject)

struct _CtdKids {
    GObject parent_instance;
    guint64 outline;
    gint64  parent_node;
    guint   count;      // cached, because a GListModel's length may only
                        // change when it says so with items-changed
};

static GType ctd_kids_item_type(GListModel *model) {
    (void)model;
    return CTD_TYPE_NODE;
}

static guint ctd_kids_n_items(GListModel *model) {
    return CTD_KIDS(model)->count;
}

static gpointer ctd_kids_get_item(GListModel *model, guint position) {
    CtdKids *self = CTD_KIDS(model);
    if (position >= self->count) return NULL;
    int64_t child = ctd_outline_ask((ctd_handle)self->outline, CTD_OUTLINE_CHILD,
                                    self->parent_node, (int32_t)position);
    return ctd_node_new(self->outline, child);
}

static void ctd_kids_iface_init(GListModelInterface *iface) {
    iface->get_item_type = ctd_kids_item_type;
    iface->get_n_items = ctd_kids_n_items;
    iface->get_item = ctd_kids_get_item;
}

G_DEFINE_TYPE_WITH_CODE(CtdKids, ctd_kids, G_TYPE_OBJECT,
                        G_IMPLEMENT_INTERFACE(G_TYPE_LIST_MODEL,
                                              ctd_kids_iface_init))

static void ctd_kids_init(CtdKids *self) { (void)self; }
static void ctd_kids_class_init(CtdKidsClass *klass) { (void)klass; }

static CtdKids *ctd_kids_new(guint64 outline, gint64 parent_node) {
    CtdKids *self = g_object_new(CTD_TYPE_KIDS, NULL);
    self->outline = outline;
    self->parent_node = parent_node;
    int64_t count = ctd_outline_ask((ctd_handle)outline, CTD_OUTLINE_CHILDREN,
                                    parent_node, 0);
    self->count = count > 0 ? (guint)count : 0;
    return self;
}

// Asks again and tells GTK what moved. Everything is reported as changed
// rather than diffed: cortado does not know which child became which, and a
// wrong diff shows as rows that keep the text of the row that used to be
// there.
static void ctd_kids_refresh(CtdKids *self) {
    guint had = self->count;
    int64_t now = ctd_outline_ask((ctd_handle)self->outline,
                                  CTD_OUTLINE_CHILDREN, self->parent_node, 0);
    self->count = now > 0 ? (guint)now : 0;
    g_list_model_items_changed(G_LIST_MODEL(self), 0, had, self->count);
}

// --------------------------------------------------------- the whole control

// What each outline keeps: the models it has handed GtkTreeListModel, so a
// reload can refresh them in place rather than rebuild the tree.
typedef struct {
    ctd_handle  outline;
    GHashTable *kids;   // gint64 node -> CtdKids*, owned
} CtdOutline;

static void ctd_outline_free(gpointer data) {
    CtdOutline *own = (CtdOutline *)data;
    if (!own) return;
    g_hash_table_destroy(own->kids);
    g_free(own);
}

static CtdOutline *ctd_outline_own(GtkColumnView *view) {
    return (CtdOutline *)g_object_get_data(G_OBJECT(view), "ctd-outline");
}

// GtkTreeListModel asks this for every row it shows: the children of that row,
// or NULL for a leaf. The model is kept so a later reload can refresh it.
static GListModel *ctd_outline_children(gpointer item, gpointer user) {
    CtdOutline *own = (CtdOutline *)user;
    CtdNode *node = CTD_NODE(item);
    if (!own || !node) return NULL;
    if (!ctd_outline_ask(own->outline, CTD_OUTLINE_EXPANDS, node->node, 0)) {
        return NULL;
    }
    CtdKids *kept = g_hash_table_lookup(own->kids, &node->node);
    if (kept) return G_LIST_MODEL(g_object_ref(kept));
    CtdKids *made = ctd_kids_new((guint64)own->outline, node->node);
    gint64 *key = g_new(gint64, 1);
    *key = node->node;
    g_hash_table_insert(own->kids, key, g_object_ref(made));
    return G_LIST_MODEL(made);
}

// ------------------------------------------------------------- the columns

static void ctd_outline_setup_first(GtkSignalListItemFactory *factory,
                                    GtkListItem *item, gpointer user) {
    (void)factory; (void)user;
    // The first column carries the indent and the twisty, on every platform
    // here. In GTK that is a GtkTreeExpander wrapped around the cell.
    GtkWidget *label = gtk_label_new("");
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    GtkWidget *expander = gtk_tree_expander_new();
    gtk_tree_expander_set_child(GTK_TREE_EXPANDER(expander), label);
    gtk_list_item_set_child(item, expander);
}

static void ctd_outline_setup_rest(GtkSignalListItemFactory *factory,
                                   GtkListItem *item, gpointer user) {
    (void)factory; (void)user;
    GtkWidget *label = gtk_label_new("");
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_list_item_set_child(item, label);
}

static void ctd_outline_bind(GtkSignalListItemFactory *factory,
                             GtkListItem *item, gpointer user) {
    (void)factory;
    int32_t column = (int32_t)GPOINTER_TO_INT(user);
    GtkTreeListRow *row = GTK_TREE_LIST_ROW(gtk_list_item_get_item(item));
    GtkWidget *child = gtk_list_item_get_child(item);
    if (!row || !child) return;
    CtdNode *node = CTD_NODE(gtk_tree_list_row_get_item(row));
    if (!node) return;
    GtkWidget *label = child;
    if (GTK_IS_TREE_EXPANDER(child)) {
        gtk_tree_expander_set_list_row(GTK_TREE_EXPANDER(child), row);
        label = gtk_tree_expander_get_child(GTK_TREE_EXPANDER(child));
    }
    if (!GTK_IS_LABEL(label)) { g_object_unref(node); return; }
    char *text = ctd_outline_words((ctd_handle)node->outline, node->node, column);
    gtk_label_set_text(GTK_LABEL(label), text ? text : "");
    g_free(text);
    g_object_unref(node);
}

// --------------------------------------------------------------- the control

GtkColumnView *ctd_outline_view(gpointer object) {
    if (!GTK_IS_SCROLLED_WINDOW(object)) return NULL;
    GtkWidget *inner = gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(object));
    if (!inner || !GTK_IS_COLUMN_VIEW(inner)) return NULL;
    // A table is a GtkColumnView too, so the tag is what tells them apart.
    if (!g_object_get_data(G_OBJECT(inner), "ctd-outline")) return NULL;
    return GTK_COLUMN_VIEW(inner);
}

static GtkTreeListModel *ctd_outline_tree(GtkColumnView *view) {
    GtkSelectionModel *selection = gtk_column_view_get_model(view);
    if (!selection) return NULL;
    GListModel *inner =
        gtk_single_selection_get_model(GTK_SINGLE_SELECTION(selection));
    if (!inner || !GTK_IS_TREE_LIST_MODEL(inner)) return NULL;
    return GTK_TREE_LIST_MODEL(inner);
}

// The GtkTreeListRow standing for a node, or NULL when the control is not
// showing it — which includes a node inside a closed parent, because a row
// GTK has not made is a row that does not exist.
static GtkTreeListRow *ctd_outline_row_of(GtkColumnView *view, gint64 node,
                                          guint *position) {
    GtkTreeListModel *tree = ctd_outline_tree(view);
    if (!tree) return NULL;
    guint count = g_list_model_get_n_items(G_LIST_MODEL(tree));
    for (guint at = 0; at < count; at++) {
        GtkTreeListRow *row =
            GTK_TREE_LIST_ROW(g_list_model_get_item(G_LIST_MODEL(tree), at));
        if (!row) continue;
        CtdNode *item = CTD_NODE(gtk_tree_list_row_get_item(row));
        gboolean hit = item && item->node == node;
        if (item) g_object_unref(item);
        if (hit) {
            if (position) *position = at;
            return row;   // the caller owns this reference
        }
        g_object_unref(row);
    }
    return NULL;
}

static void ctd_outline_selection_changed(GtkSelectionModel *model,
                                          guint position, guint n_items,
                                          gpointer user) {
    (void)position; (void)n_items;
    if (g_writing) return;
    ctd_handle outline = (ctd_handle)(uintptr_t)user;
    guint chosen = gtk_single_selection_get_selected(GTK_SINGLE_SELECTION(model));
    if (chosen == GTK_INVALID_LIST_POSITION) return;
    GtkTreeListRow *row =
        GTK_TREE_LIST_ROW(g_list_model_get_item(G_LIST_MODEL(model), chosen));
    if (!row) return;
    CtdNode *node = CTD_NODE(gtk_tree_list_row_get_item(row));
    if (node) {
        ctd_emit(CTD_EV_SELECTION, outline, (int64_t)node->node, 0);
        g_object_unref(node);
    }
    g_object_unref(row);
}

// Filled in after the handle exists, because every model below carries the
// handle it answers for.
void ctd_outline_attach(ctd_handle outline, GtkWidget *scroller) {
    CtdOutline *own = g_new0(CtdOutline, 1);
    own->outline = outline;
    own->kids = g_hash_table_new_full(g_int64_hash, g_int64_equal,
                                      g_free, g_object_unref);

    CtdKids *root = ctd_kids_new((guint64)outline, CTD_OUTLINE_ROOT);
    GtkTreeListModel *tree =
        gtk_tree_list_model_new(G_LIST_MODEL(root), FALSE, FALSE,
                                ctd_outline_children, own, NULL);
    GtkSingleSelection *selection =
        gtk_single_selection_new(G_LIST_MODEL(tree));
    gtk_single_selection_set_autoselect(selection, FALSE);
    gtk_single_selection_set_can_unselect(selection, TRUE);
    GtkWidget *view = gtk_column_view_new(GTK_SELECTION_MODEL(selection));
    g_object_set_data_full(G_OBJECT(view), "ctd-outline", own, ctd_outline_free);
    g_signal_connect(selection, "selection-changed",
                     G_CALLBACK(ctd_outline_selection_changed),
                     (gpointer)(uintptr_t)outline);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), view);
}

// ---------------------------------------------------------------- entry points

ctd_status ctd_set_outline_source(ctd_outline_fn shape, void *shape_context,
                                  ctd_outline_text_fn text, void *text_context) {
    g_outline_shape = shape;
    g_outline_shape_context = shape_context;
    g_outline_text = text;
    g_outline_text_context = text_context;
    return CTD_OK;
}

static GtkColumnView *ctd_outline_of(ctd_handle outline, ctd_status *problem) {
    gpointer object = ctd_resolve(outline);
    if (!object) { *problem = CTD_ERR_STALE; return NULL; }
    GtkColumnView *view = ctd_outline_view(object);
    if (!view) { *problem = CTD_ERR_KIND; return NULL; }
    *problem = CTD_OK;
    return view;
}

ctd_status ctd_outline_columns(ctd_handle outline, int32_t count) {
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    if (count < 1) return CTD_ERR_RANGE;
    GListModel *columns = gtk_column_view_get_columns(view);
    while ((int32_t)g_list_model_get_n_items(columns) > count) {
        guint last = g_list_model_get_n_items(columns) - 1;
        GtkColumnViewColumn *column =
            GTK_COLUMN_VIEW_COLUMN(g_list_model_get_item(columns, last));
        gtk_column_view_remove_column(view, column);
        g_object_unref(column);
    }
    while ((int32_t)g_list_model_get_n_items(columns) < count) {
        guint at = g_list_model_get_n_items(columns);
        GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
        // The first column is the one with the expander, on every platform
        // here — which is why the factory differs and the bind does not.
        g_signal_connect(factory, "setup",
                         at == 0 ? G_CALLBACK(ctd_outline_setup_first)
                                 : G_CALLBACK(ctd_outline_setup_rest), NULL);
        g_signal_connect(factory, "bind", G_CALLBACK(ctd_outline_bind),
                         GINT_TO_POINTER((int)at));
        GtkColumnViewColumn *column = gtk_column_view_column_new("", factory);
        gtk_column_view_column_set_resizable(column, TRUE);
        gtk_column_view_append_column(view, column);
        g_object_unref(column);
    }
    return CTD_OK;
}

ctd_status ctd_outline_column_title(ctd_handle outline, int32_t column,
                                    const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    GListModel *columns = gtk_column_view_get_columns(view);
    if (column < 0 || column >= (int32_t)g_list_model_get_n_items(columns)) {
        return CTD_ERR_RANGE;
    }
    GtkColumnViewColumn *one =
        GTK_COLUMN_VIEW_COLUMN(g_list_model_get_item(columns, (guint)column));
    char *words = ctd_dup(utf8, len);
    gtk_column_view_column_set_title(one, words ? words : "");
    g_free(words);
    g_object_unref(one);
    return CTD_OK;
}

ctd_status ctd_outline_column_width(ctd_handle outline, int32_t column,
                                    double points) {
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    GListModel *columns = gtk_column_view_get_columns(view);
    if (column < 0 || column >= (int32_t)g_list_model_get_n_items(columns)) {
        return CTD_ERR_RANGE;
    }
    if (points <= 0.0) return CTD_ERR_RANGE;
    GtkColumnViewColumn *one =
        GTK_COLUMN_VIEW_COLUMN(g_list_model_get_item(columns, (guint)column));
    gtk_column_view_column_set_fixed_width(one, (int)points);
    g_object_unref(one);
    return CTD_OK;
}

ctd_status ctd_outline_reload(ctd_handle outline) {
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    GtkTreeListModel *tree = ctd_outline_tree(view);
    if (!tree) return CTD_ERR_STATE;
    // Every model already handed out is refreshed in place, root included, so
    // GtkTreeListModel keeps its rows and the tree stays open where the nodes
    // are still there. Rebuilding from a fresh root would close everything.
    GListModel *root = gtk_tree_list_model_get_model(tree);
    if (root && CTD_IS_KIDS(root)) ctd_kids_refresh(CTD_KIDS(root));
    CtdOutline *own = ctd_outline_own(view);
    if (own) {
        GHashTableIter walk;
        gpointer key, value;
        g_hash_table_iter_init(&walk, own->kids);
        while (g_hash_table_iter_next(&walk, &key, &value)) {
            ctd_kids_refresh(CTD_KIDS(value));
        }
    }
    return CTD_OK;
}

ctd_status ctd_outline_expand(ctd_handle outline, int64_t node, int32_t on) {
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    if (node == CTD_OUTLINE_ROOT) {
        // The root is always open: its children are the top level.
        return on ? CTD_OK : CTD_ERR_RANGE;
    }
    GtkTreeListRow *row = ctd_outline_row_of(view, (gint64)node, NULL);
    if (!row) return CTD_ERR_RANGE;
    g_writing++;
    gtk_tree_list_row_set_expanded(row, on ? TRUE : FALSE);
    g_writing--;
    g_object_unref(row);
    return CTD_OK;
}

ctd_status ctd_outline_expanded(ctd_handle outline, int64_t node, int32_t *out) {
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    if (node == CTD_OUTLINE_ROOT) {
        if (out) *out = 1;
        return CTD_OK;
    }
    GtkTreeListRow *row = ctd_outline_row_of(view, (gint64)node, NULL);
    if (!row) return CTD_ERR_RANGE;
    if (out) *out = gtk_tree_list_row_get_expanded(row) ? 1 : 0;
    g_object_unref(row);
    return CTD_OK;
}

ctd_status ctd_outline_selected(ctd_handle outline, int64_t *out) {
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    GtkSelectionModel *selection = gtk_column_view_get_model(view);
    if (!selection) return CTD_ERR_STATE;
    guint chosen = gtk_single_selection_get_selected(GTK_SINGLE_SELECTION(selection));
    if (out) *out = CTD_OUTLINE_ROOT;
    if (chosen == GTK_INVALID_LIST_POSITION) return CTD_OK;
    GtkTreeListRow *row =
        GTK_TREE_LIST_ROW(g_list_model_get_item(G_LIST_MODEL(selection), chosen));
    if (!row) return CTD_OK;
    CtdNode *node = CTD_NODE(gtk_tree_list_row_get_item(row));
    if (node) {
        if (out) *out = (int64_t)node->node;
        g_object_unref(node);
    }
    g_object_unref(row);
    return CTD_OK;
}

ctd_status ctd_outline_select(ctd_handle outline, int64_t node) {
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    GtkSelectionModel *selection = gtk_column_view_get_model(view);
    if (!selection) return CTD_ERR_STATE;
    if (node == CTD_OUTLINE_ROOT) {
        g_writing++;
        gtk_single_selection_set_selected(GTK_SINGLE_SELECTION(selection),
                                          GTK_INVALID_LIST_POSITION);
        g_writing--;
        return CTD_OK;
    }
    guint at = 0;
    GtkTreeListRow *row = ctd_outline_row_of(view, (gint64)node, &at);
    if (!row) return CTD_ERR_RANGE;
    g_writing++;
    gtk_single_selection_set_selected(GTK_SINGLE_SELECTION(selection), at);
    g_writing--;
    g_object_unref(row);
    return CTD_OK;
}

int32_t ctd_outline_cell(ctd_handle outline, int64_t node, int32_t column,
                         char *out, int32_t cap) {
    ctd_status problem;
    GtkColumnView *view = ctd_outline_of(outline, &problem);
    if (!view) return problem;
    GListModel *columns = gtk_column_view_get_columns(view);
    if (column < 0 || column >= (int32_t)g_list_model_get_n_items(columns)) {
        return CTD_ERR_RANGE;
    }
    // Only a node the control is showing, like every other node-keyed call
    // here. Asking the source directly would answer for a node the control
    // has never heard of, which would make this a second reading of the
    // source rather than the round trip it exists to be.
    if (node != CTD_OUTLINE_ROOT) {
        GtkTreeListRow *row = ctd_outline_row_of(view, (gint64)node, NULL);
        if (!row) return CTD_ERR_RANGE;
        g_object_unref(row);
    }
    // The same call the bind makes, which is what the round trip is: out
    // through ctd_outline_text_fn, into what the cell would show, and back.
    char *text = ctd_outline_words(outline, node, column);
    int32_t wrote = ctd_copy_out(text ? text : "", out, cap);
    g_free(text);
    return wrote;
}
