#include "internal.h"
#include <math.h>
#include <limits.h>

/* GTK's input method receives key events for the one shared canvas. It only
 * translates commits/preedit text; Beans owns the actual editable value. */
#define CTD_IM_KEY "ctd-shared-im"
typedef struct {
    GtkIMContext *context;
    GtkWidget *widget;
    gboolean active;
} CortadoIM;

static void ctd_im_event(CortadoIM *state, uint32_t kind, const char *text,
                         int64_t index, int64_t token) {
    if (!g_sink || !ctd_listening(kind)) return;
    ctd_handle target = ctd_handle_for_widget(state->widget);
    if (!target) return;
    ctd_event event = {0};
    event.kind = kind; event.target = target;
    event.index = index; event.token = token;
    event.text = text; event.text_len = text ? (int32_t)strlen(text) : 0;
    g_sink(g_sink_context, &event);
}

static void ctd_im_commit(GtkIMContext *context, const char *text, gpointer data) {
    (void)context;
    ctd_im_event(data, CTD_EV_TEXT_INPUT, text, -1, -1);
}

static void ctd_im_preedit(GtkIMContext *context, gpointer data) {
    CortadoIM *state = data;
    char *text = NULL;
    PangoAttrList *attrs = NULL;
    int cursor = 0;
    gtk_im_context_get_preedit_string(context, &text, &attrs, &cursor);
    int characters = text ? (int)g_utf8_strlen(text, -1) : 0;
    if (cursor < 0) cursor = 0;
    if (cursor > characters) cursor = characters;
    int64_t byte_cursor = text ? (int64_t)(g_utf8_offset_to_pointer(text, cursor) - text) : 0;
    ctd_im_event(state, CTD_EV_COMPOSITION_UPDATE, text ? text : "", byte_cursor, byte_cursor);
    if (attrs) pango_attr_list_unref(attrs);
    g_free(text);
}

static void ctd_im_free(gpointer data) {
    CortadoIM *state = data;
    if (state->context) {
        gtk_im_context_focus_out(state->context);
        g_object_unref(state->context);
    }
    g_free(state);
}

static CortadoIM *ctd_im_state(GtkWidget *widget, gboolean create) {
    CortadoIM *state = g_object_get_data(G_OBJECT(widget), CTD_IM_KEY);
    if (state || !create) return state;
    state = g_new0(CortadoIM, 1);
    state->widget = widget;
    state->context = gtk_im_multicontext_new();
    gtk_im_context_set_client_widget(state->context, widget);
    g_signal_connect(state->context, "commit", G_CALLBACK(ctd_im_commit), state);
    g_signal_connect(state->context, "preedit-changed", G_CALLBACK(ctd_im_preedit), state);
    g_object_set_data_full(G_OBJECT(widget), CTD_IM_KEY, state, ctd_im_free);
    return state;
}

gboolean ctd_canvas_im_filter(GtkWidget *widget, GdkEvent *event) {
    CortadoIM *state = ctd_im_state(widget, FALSE);
    return state && state->active && event && gtk_im_context_filter_keypress(state->context, event);
}
gboolean ctd_canvas_text_active(GtkWidget *widget) {
    CortadoIM *state = ctd_im_state(widget, FALSE);
    return state && state->active;
}
GtkIMContext *ctd_canvas_im_context(GtkWidget *widget) {
    CortadoIM *state = ctd_im_state(widget, FALSE);
    return state ? state->context : NULL;
}

void ctd_canvas_im_focus(GtkWidget *widget, gboolean focused) {
    CortadoIM *state = ctd_im_state(widget, FALSE);
    if (!state || !state->active) return;
    if (focused) gtk_im_context_focus_in(state->context);
    else gtk_im_context_focus_out(state->context);
}

ctd_status ctd_canvas_text_state(ctd_handle handle, int32_t active,
    const char *utf8, int32_t length, int32_t anchor, int32_t caret,
    double x, double y, double width, double height) {
    gpointer object = ctd_resolve(handle);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(handle) != CTD_W_CANVAS) return CTD_ERR_KIND;
    if (length < 0 || (length && !utf8) || anchor < 0 || caret < 0 ||
        anchor > length || caret > length || !isfinite(x) || !isfinite(y) ||
        !isfinite(width) || !isfinite(height) || width < 0 || height < 0 ||
        width > INT_MAX || height > INT_MAX ||
        x < INT_MIN || y < INT_MIN || x + width > INT_MAX || y + height > INT_MAX ||
        !g_utf8_validate(utf8 ? utf8 : "", length, NULL) ||
        !g_utf8_validate(utf8 ? utf8 : "", anchor, NULL) ||
        !g_utf8_validate(utf8 ? utf8 : "", caret, NULL)) return CTD_ERR_RANGE;
    GtkWidget *widget = GTK_WIDGET(object);
    CortadoIM *state = ctd_im_state(widget, active != 0);
    if (!state) return CTD_OK;
    if (state->active != (active != 0)) {
        state->active = active != 0;
        if (state->active && gtk_widget_has_focus(widget)) gtk_im_context_focus_in(state->context);
        else gtk_im_context_focus_out(state->context);
    }
    GdkRectangle cursor = { (int)x, (int)y, (int)width, (int)height };
    gtk_im_context_set_cursor_location(state->context, &cursor);
    (void)utf8;
    return CTD_OK;
}

ctd_status ctd_clipboard_write(const char *utf8, int32_t length) {
    if (length < 0 || (length && !utf8)) return CTD_ERR_RANGE;
    GdkDisplay *display = gdk_display_get_default();
    if (!display) return CTD_ERR_UNSUPPORTED;
    char *text = g_strndup(utf8 ? utf8 : "", (gsize)length);
    if (!g_utf8_validate(text, -1, NULL)) { g_free(text); return CTD_ERR_RANGE; }
    gdk_clipboard_set_text(gdk_display_get_clipboard(display), text);
    g_free(text);
    return CTD_OK;
}

typedef struct {
    GMainLoop *loop;
    GCancellable *cancel;
    char *text;
    GError *error;
    gboolean timed_out;
    gboolean completed;
} ClipboardRead;
static void ctd_clipboard_done(GObject *source, GAsyncResult *result, gpointer data) {
    ClipboardRead *read = data;
    read->text = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(source), result, &read->error);
    read->completed = TRUE;
    if (read->loop) g_main_loop_quit(read->loop);
    else {
        g_free(read->text);
        if (read->error) g_error_free(read->error);
        g_object_unref(read->cancel);
        g_free(read);
    }
}
static gboolean ctd_clipboard_timeout(gpointer data) {
    ClipboardRead *read = data;
    read->timed_out = TRUE;
    g_cancellable_cancel(read->cancel);
    g_main_loop_quit(read->loop);
    return G_SOURCE_REMOVE;
}
int32_t ctd_reduce_motion(void) {
    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) return 0;
    gboolean animations = TRUE;
    g_object_get(settings, "gtk-enable-animations", &animations, NULL);
    return animations ? 0 : 1;
}
int32_t ctd_clipboard_read(char *out, int32_t cap) {
    if (cap < 0) return CTD_ERR_RANGE;
    GdkDisplay *display = gdk_display_get_default();
    if (!display) return CTD_ERR_UNSUPPORTED;
    ClipboardRead *read = g_new0(ClipboardRead, 1);
    read->loop = g_main_loop_new(NULL, FALSE);
    read->cancel = g_cancellable_new();
    guint timeout = g_timeout_add(2000, ctd_clipboard_timeout, read);
    gdk_clipboard_read_text_async(gdk_display_get_clipboard(display), read->cancel, ctd_clipboard_done, read);
    g_main_loop_run(read->loop);
    if (!read->timed_out) g_source_remove(timeout);
    g_main_loop_unref(read->loop);
    read->loop = NULL;
    if (read->timed_out) {
        if (read->completed) {
            g_free(read->text);
            if (read->error) g_error_free(read->error);
            g_object_unref(read->cancel);
            g_free(read);
        }
        return CTD_ERR_PLATFORM; // a later completion frees the detached request
    }
    if (read->error) { g_error_free(read->error); g_object_unref(read->cancel); g_free(read); return CTD_ERR_PLATFORM; }
    if (!read->text) { g_object_unref(read->cancel); g_free(read); return CTD_ERR_PLATFORM; }
    int32_t length = (int32_t)strlen(read->text);
    if (out && cap < length) { g_free(read->text); g_object_unref(read->cancel); g_free(read); return CTD_ERR_RANGE; }
    if (out && length) memcpy(out, read->text, (size_t)length);
    g_free(read->text);
    g_object_unref(read->cancel);
    g_free(read);
    return length;
}

/* The canvas remains the only painted control. These empty children give GTK's
 * AT-SPI bridge a real tree and export a parameterless action to Beans. */
typedef struct {
    GtkWidget parent;
    GtkWidget *canvas; /* weak; cleared before a snapshot is removed */
    ctd_handle canvas_id;
    uint64_t node_id;
    gboolean active;
    gboolean enabled;
} CortadoAccessible;
typedef struct { GtkWidgetClass parent; } CortadoAccessibleClass;
G_DEFINE_TYPE(CortadoAccessible, ctd_accessible, GTK_TYPE_WIDGET)

static void ctd_accessible_action(GtkWidget *widget, const char *name, GVariant *parameter) {
    (void)name; (void)parameter;
    CortadoAccessible *node = (CortadoAccessible *)widget;
    if (!node->active || !node->enabled || !node->canvas || !g_sink || !ctd_listening(CTD_EV_SEMANTICS_ACTION) ||
        ctd_resolve(node->canvas_id) != node->canvas) return;
    ctd_event event = {0};
    event.kind = CTD_EV_SEMANTICS_ACTION;
    event.target = node->canvas_id;
    event.index = 1;
    event.token = (int64_t)node->node_id;
    g_object_ref(widget); /* Beans may replace this snapshot in the callback. */
    g_sink(g_sink_context, &event);
    g_object_unref(widget);
}
static void ctd_accessible_class_init(CortadoAccessibleClass *klass) {
    (void)klass;
}
static void ctd_accessible_init(CortadoAccessible *node) {
    gtk_widget_set_can_target(GTK_WIDGET(node), FALSE);
    gtk_widget_set_focusable(GTK_WIDGET(node), FALSE);
}
typedef struct { CortadoAccessible parent; } CortadoActionable;
typedef struct { CortadoAccessibleClass parent; } CortadoActionableClass;
G_DEFINE_TYPE(CortadoActionable, ctd_actionable, ctd_accessible_get_type())
static void ctd_actionable_class_init(CortadoActionableClass *klass) {
    gtk_widget_class_install_action(GTK_WIDGET_CLASS(klass), "ctd.activate", NULL,
                                    ctd_accessible_action);
}
static void ctd_actionable_init(CortadoActionable *node) { (void)node; }

typedef struct { GtkWidget *canvas; GPtrArray *nodes; CortadoAccessible *focused; } CortadoTree;
static void ctd_tree_clear(CortadoTree *tree, gboolean unparent) {
    if (!tree) return;
    tree->focused = NULL;
    for (guint i = 0; i < tree->nodes->len; ++i) {
        CortadoAccessible *node = g_ptr_array_index(tree->nodes, i);
        node->active = FALSE;
        node->canvas = NULL;
        if (unparent && gtk_widget_get_parent(GTK_WIDGET(node)) == tree->canvas)
            gtk_fixed_remove(GTK_FIXED(tree->canvas), GTK_WIDGET(node));
    }
    g_ptr_array_set_size(tree->nodes, 0);
}
static void ctd_tree_free(gpointer data) {
    CortadoTree *tree = data;
    ctd_tree_clear(tree, FALSE);
    g_ptr_array_unref(tree->nodes);
    g_free(tree);
}
static CortadoTree *ctd_tree(GtkWidget *canvas, gboolean create) {
    CortadoTree *tree = g_object_get_data(G_OBJECT(canvas), "ctd-accessible-tree");
    if (!tree && create) {
        tree = g_new0(CortadoTree, 1);
        tree->canvas = canvas;
        tree->nodes = g_ptr_array_new_with_free_func(g_object_unref);
        g_object_set_data_full(G_OBJECT(canvas), "ctd-accessible-tree", tree, ctd_tree_free);
    }
    return tree;
}
static GtkAccessibleRole ctd_accessible_role(const char *role) {
    if (!strcmp(role, "button")) return GTK_ACCESSIBLE_ROLE_BUTTON;
    if (!strcmp(role, "checkbox")) return GTK_ACCESSIBLE_ROLE_CHECKBOX;
    if (!strcmp(role, "radio")) return GTK_ACCESSIBLE_ROLE_RADIO;
    if (!strcmp(role, "switch")) return GTK_ACCESSIBLE_ROLE_SWITCH;
    if (!strcmp(role, "textbox") || !strcmp(role, "securetext")) return GTK_ACCESSIBLE_ROLE_TEXT_BOX;
    if (!strcmp(role, "text")) return GTK_ACCESSIBLE_ROLE_LABEL;
    if (!strcmp(role, "option")) return GTK_ACCESSIBLE_ROLE_OPTION;
    if (!strcmp(role, "image")) return GTK_ACCESSIBLE_ROLE_IMG;
    if (!strcmp(role, "slider")) return GTK_ACCESSIBLE_ROLE_SLIDER;
    if (!strcmp(role, "spinbutton")) return GTK_ACCESSIBLE_ROLE_SPIN_BUTTON;
    if (!strcmp(role, "progressbar")) return GTK_ACCESSIBLE_ROLE_PROGRESS_BAR;
    if (!strcmp(role, "meter")) return GTK_ACCESSIBLE_ROLE_METER;
    if (!strcmp(role, "separator")) return GTK_ACCESSIBLE_ROLE_SEPARATOR;
    if (!strcmp(role, "combobox")) return GTK_ACCESSIBLE_ROLE_COMBO_BOX;
    if (!strcmp(role, "radiogroup")) return GTK_ACCESSIBLE_ROLE_RADIO_GROUP;
    if (!strcmp(role, "tablist")) return GTK_ACCESSIBLE_ROLE_TAB_LIST;
    if (!strcmp(role, "table")) return GTK_ACCESSIBLE_ROLE_GRID;
    if (!strcmp(role, "scrollarea")) return GTK_ACCESSIBLE_ROLE_REGION;
    return GTK_ACCESSIBLE_ROLE_GROUP;
}
static gboolean ctd_accessible_actionable(const char *role) {
    return !strcmp(role, "button") || !strcmp(role, "checkbox") ||
           !strcmp(role, "radio") || !strcmp(role, "switch") || !strcmp(role, "option") ||
           !strcmp(role, "combobox");
}
ctd_status ctd_canvas_semantics_clear(ctd_handle canvas) {
    gpointer object = ctd_resolve(canvas);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(canvas) != CTD_W_CANVAS) return CTD_ERR_KIND;
    CortadoTree *tree = ctd_tree(GTK_WIDGET(object), TRUE);
    ctd_tree_clear(tree, TRUE);
    gtk_accessible_reset_relation(GTK_ACCESSIBLE(object), GTK_ACCESSIBLE_RELATION_ACTIVE_DESCENDANT);
    return CTD_OK;
}
ctd_status ctd_canvas_semantics_add(ctd_handle canvas, uint64_t node_id,
    const char *role, int32_t role_len, const char *label, int32_t label_len,
    const char *value, int32_t value_len, double x, double y,
    double width, double height, int32_t enabled, int32_t focused) {
    gpointer object = ctd_resolve(canvas);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(canvas) != CTD_W_CANVAS) return CTD_ERR_KIND;
    if (node_id == 0 || role_len < 0 || label_len < 0 || value_len < 0 ||
        (role_len && !role) || (label_len && !label) || (value_len && !value) ||
        width < 0 || height < 0 || !isfinite(x) || !isfinite(y) ||
        !isfinite(width) || !isfinite(height) || x < INT_MIN || y < INT_MIN ||
        x > INT_MAX || y > INT_MAX || width > INT_MAX - 1 || height > INT_MAX - 1 ||
        x + width > INT_MAX || y + height > INT_MAX) return CTD_ERR_RANGE;
    if (!g_utf8_validate(role ? role : "", role_len, NULL) ||
        !g_utf8_validate(label ? label : "", label_len, NULL) ||
        !g_utf8_validate(value ? value : "", value_len, NULL)) return CTD_ERR_RANGE;
    char *r = g_strndup(role ? role : "", role_len);
    char *l = g_strndup(label ? label : "", label_len);
    char *v = g_strndup(value ? value : "", value_len);
    CortadoTree *tree = ctd_tree(GTK_WIDGET(object), TRUE);
    for (guint i = 0; i < tree->nodes->len; ++i) {
        CortadoAccessible *prior = g_ptr_array_index(tree->nodes, i);
        if (prior->node_id == node_id) { g_free(r); g_free(l); g_free(v); return CTD_ERR_RANGE; }
    }
    CortadoAccessible *node = g_object_new(ctd_accessible_actionable(r) ?
                                           ctd_actionable_get_type() : ctd_accessible_get_type(),
                                           "accessible-role", ctd_accessible_role(r), NULL);
    g_object_ref_sink(node);
    node->canvas = GTK_WIDGET(object);
    node->canvas_id = canvas;
    node->node_id = node_id;
    node->active = TRUE;
    node->enabled = enabled != 0;
    gtk_widget_set_sensitive(GTK_WIDGET(node), node->enabled);
    gtk_accessible_update_property(GTK_ACCESSIBLE(node), GTK_ACCESSIBLE_PROPERTY_LABEL, l,
                                   GTK_ACCESSIBLE_PROPERTY_VALUE_TEXT, v, -1);
    gtk_accessible_update_state(GTK_ACCESSIBLE(node), GTK_ACCESSIBLE_STATE_DISABLED, !enabled, -1);
    if (!strcmp(r, "checkbox") || !strcmp(r, "radio") || !strcmp(r, "switch"))
        gtk_accessible_update_state(GTK_ACCESSIBLE(node), GTK_ACCESSIBLE_STATE_CHECKED,
            !strcmp(v, "mixed") ? GTK_ACCESSIBLE_TRISTATE_MIXED :
            !strcmp(v, "on") ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE, -1);
    if (!strcmp(r, "option"))
        gtk_accessible_update_state(GTK_ACCESSIBLE(node), GTK_ACCESSIBLE_STATE_SELECTED,
                                    !strcmp(v, "selected"), -1);
    gtk_widget_set_size_request(GTK_WIDGET(node), (int)ceil(width), (int)ceil(height));
    gtk_fixed_put(GTK_FIXED(object), GTK_WIDGET(node), x, y);
    g_ptr_array_add(tree->nodes, node);
    if (focused) tree->focused = node;
    g_free(r); g_free(l); g_free(v);
    return CTD_OK;
}
ctd_status ctd_canvas_semantics_end(ctd_handle canvas) {
    gpointer object = ctd_resolve(canvas);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(canvas) != CTD_W_CANVAS) return CTD_ERR_KIND;
    CortadoTree *tree = ctd_tree(GTK_WIDGET(object), FALSE);
    if (tree && tree->focused)
        gtk_accessible_update_relation(GTK_ACCESSIBLE(object), GTK_ACCESSIBLE_RELATION_ACTIVE_DESCENDANT,
                                       GTK_ACCESSIBLE(tree->focused), -1);
    return CTD_OK;
}
