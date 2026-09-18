#include "../src/gtk4/internal.h"
#include <assert.h>
#include <stdio.h>

static ctd_event last;
static int received;
static void receive(void *context, const ctd_event *event) {
    (void)context;
    last = *event;
    received++;
}

int main(void) {
    assert(ctd_init(CTD_ABI_VERSION) == CTD_OK);
    assert(ctd_set_event_sink(receive, NULL) == CTD_OK);
    assert(ctd_listen(CTD_EV_SEMANTICS_ACTION, 1) == CTD_OK);
    ctd_handle canvas = ctd_widget_new(CTD_W_CANVAS);
    assert(canvas);
    GtkWidget *widget = GTK_WIDGET(ctd_resolve(canvas));
    assert(ctd_listen(CTD_EV_POINTER_MOVE, 1) == CTD_OK);
    GtkEventController *motion = g_object_get_data(G_OBJECT(widget), "ctd-motion");
    assert(motion);
    g_signal_emit_by_name(motion, "leave");
    assert(last.kind == CTD_EV_POINTER_MOVE && last.target == canvas &&
           last.x == -1.0 && last.y == -1.0);
    assert(ctd_listen(CTD_EV_POINTER_DOWN, 1) == CTD_OK);
    assert(ctd_listen(CTD_EV_POINTER_UP, 1) == CTD_OK);
    GtkGesture *click = g_object_get_data(G_OBJECT(widget), "ctd-click");
    assert(click);
    g_signal_emit_by_name(click, "pressed", 2, 10.0, 11.0);
    assert(last.kind == CTD_EV_POINTER_DOWN && last.token == 2);
    g_signal_emit_by_name(click, "released", 2, 10.0, 11.0);
    assert(last.kind == CTD_EV_POINTER_UP && last.token == 2);
    received = 0;
    assert(ctd_listen(CTD_EV_TEXT_INPUT, 1) == CTD_OK);
    assert(ctd_canvas_text_state(canvas, 1, "ab", 2, 1, 1, 2, 3, 1, 12) == CTD_OK);
    GtkIMContext *im = ctd_canvas_im_context(widget);
    assert(im);
    g_signal_emit_by_name(im, "commit", "x");
    assert(last.kind == CTD_EV_TEXT_INPUT && last.index == -1 && last.token == -1);
    received = 0;
    assert(ctd_canvas_semantics_clear(canvas) == CTD_OK);
    assert(ctd_canvas_semantics_add(canvas, 17, "button", 6, "Order", 5, "", 0,
                                    4, 5, 80, 24, 1, 0) == CTD_OK);
    assert(ctd_canvas_semantics_add(canvas, 18, "option", 6, "Tea", 3, "selected", 8,
                                    4, 35, 80, 24, 1, 1) == CTD_OK);
    assert(ctd_canvas_semantics_end(canvas) == CTD_OK);
    GtkWidget *button = gtk_widget_get_first_child(widget);
    GtkWidget *option = gtk_widget_get_next_sibling(button);
    assert(button && option);
    assert(gtk_accessible_get_first_accessible_child(GTK_ACCESSIBLE(widget)) == GTK_ACCESSIBLE(button));
    assert(gtk_accessible_get_next_accessible_sibling(GTK_ACCESSIBLE(button)) == GTK_ACCESSIBLE(option));
    assert(gtk_accessible_get_accessible_role(GTK_ACCESSIBLE(button)) == GTK_ACCESSIBLE_ROLE_BUTTON);
    assert(gtk_accessible_get_accessible_role(GTK_ACCESSIBLE(option)) == GTK_ACCESSIBLE_ROLE_OPTION);
    assert(gtk_widget_activate_action(button, "ctd.activate", NULL));
    assert(received == 1 && last.kind == CTD_EV_SEMANTICS_ACTION &&
           last.token == 17 && last.index == 1);
    g_object_ref(button);
    assert(ctd_canvas_semantics_clear(canvas) == CTD_OK);
    assert(!gtk_widget_activate_action(button, "ctd.activate", NULL) || received == 1);
    assert(received == 1);
    g_object_unref(button);
    assert(ctd_canvas_semantics_add(canvas, 19, "button", 6, "Blocked", 7, "", 0,
                                    0, 0, 60, 20, 0, 0) == CTD_OK);
    assert(ctd_canvas_semantics_end(canvas) == CTD_OK);
    GtkWidget *disabled = gtk_widget_get_first_child(widget);
    assert(!gtk_widget_is_sensitive(disabled));
    assert(!gtk_widget_activate_action(disabled, "ctd.activate", NULL) || received == 1);
    assert(received == 1);
    ctd_handle label = ctd_widget_new(CTD_W_LABEL);
    assert(ctd_canvas_semantics_clear(label) == CTD_ERR_KIND);
    assert(ctd_widget_release(label) == CTD_OK);
    assert(ctd_widget_release(canvas) == CTD_OK);
    assert(ctd_canvas_semantics_clear(canvas) == CTD_ERR_STALE);
    ctd_shutdown();
    puts("gtk shared accessibility tree and stale actions: true");
    return 0;
}
