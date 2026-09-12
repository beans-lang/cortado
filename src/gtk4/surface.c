// Windows: making them, titling them, showing them, and what they contain.

#include "internal.h"

// One of the four things that happen to a surface.
//
// Guarded on ctd_listening for the same reason every input event is: a window
// being dragged by its corner reports a resize on every frame of the drag, and
// a program that is not listening should not be crossed into sixty times a
// second to be told something it does not want.
void ctd_surface_event(uint32_t kind, ctd_handle surface, double a, double b) {
    if (!g_sink || !surface) return;
    if (!ctd_listening(kind)) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = kind;
    out.target = surface;
    if (kind == CTD_EV_SURFACE_RESIZED) {
        out.width = a;
        out.height = b;
    } else if (kind == CTD_EV_APPEARANCE || kind == CTD_EV_SCALE_CHANGED) {
        out.index = (int64_t)a;
        out.x = a;
    }
    g_sink(g_sink_context, &out);
}

// **GTK notifies once per dimension, so a resize arrives twice.** Setting a
// window to 280 by 180 from 300 by 200 fires notify::default-width with the
// size 280 by 200 — a shape the window was never actually at — and then
// notify::default-height with the real one. A host that passed both on would
// hand a program a phantom size on every frame of a drag, and a layout solving
// against it would flicker.
//
// So the report is deferred to the next turn of the loop, by which time both
// have landed and the size is the one the window is at. One event per settled
// size, which is what AppKit's single notification gives for free and what a
// program actually wants.
static gboolean ctd_report_resize(gpointer data) {
    GtkWidget *window = GTK_WIDGET(data);
    g_object_set_data(G_OBJECT(window), "ctd-resize-queued", NULL);
    int width = 0, height = 0;
    gtk_window_get_default_size(GTK_WINDOW(window), &width, &height);
    ctd_surface_event(CTD_EV_SURFACE_RESIZED, ctd_handle_for_widget(window),
                      (double)width, (double)height);
    return G_SOURCE_REMOVE;
}

static void ctd_on_resized(GObject *window, GParamSpec *what, gpointer data) {
    (void)what; (void)data;
    // The header's rule: a write is silent. A window the *program* resized
    // re-solves its own layout on the way out of that call, and a layout that
    // also re-solved on the notification would re-solve for ever.
    if (g_writing) return;
    if (!ctd_listening(CTD_EV_SURFACE_RESIZED)) return;
    // At most one queued at a time, so a drag queues one report per turn of
    // the loop rather than one per pixel.
    if (g_object_get_data(window, "ctd-resize-queued")) return;
    g_object_set_data(window, "ctd-resize-queued", GSIZE_TO_POINTER(1));
    g_idle_add(ctd_report_resize, window);
}

static gboolean ctd_on_close(GtkWindow *window, gpointer data) {
    (void)data;
    ctd_surface_event(CTD_EV_SURFACE_CLOSE,
                      ctd_handle_for_widget(GTK_WIDGET(window)), 0, 0);
    // TRUE is a veto here. A program with a close handler keeps its window and
    // decides; one without gets what GTK does on its own — see the note beside
    // ctd_surface_synth.
    return ctd_listening(CTD_EV_SURFACE_CLOSE) ? TRUE : FALSE;
}

static void ctd_on_scale(GObject *window, GParamSpec *what, gpointer data) {
    (void)what; (void)data;
    ctd_surface_event(CTD_EV_SCALE_CHANGED,
                      ctd_handle_for_widget(GTK_WIDGET(window)),
                      (double)gtk_widget_get_scale_factor(GTK_WIDGET(window)), 0);
}

// The appearance is the *settings object's*, not one window's, and GTK has one
// for the whole display. Every window is told, because a program has a handle
// to a window and not to GtkSettings.
static void ctd_on_theme(GObject *settings, GParamSpec *what, gpointer data) {
    (void)settings; (void)what;
    ctd_surface_event(CTD_EV_APPEARANCE,
                      ctd_handle_for_widget(GTK_WIDGET(data)),
                      (double)ctd_appearance(), 0);
}

ctd_handle ctd_surface_new(double width, double height) {
    GtkWidget *window = gtk_window_new();
    gtk_window_set_default_size(GTK_WINDOW(window), (int)width, (int)height);
    ctd_handle handle = ctd_track(window, -1);
    g_signal_connect(window, "notify::default-width", G_CALLBACK(ctd_on_resized), NULL);
    g_signal_connect(window, "notify::default-height", G_CALLBACK(ctd_on_resized), NULL);
    g_signal_connect(window, "close-request", G_CALLBACK(ctd_on_close), NULL);
    g_signal_connect(window, "notify::scale-factor", G_CALLBACK(ctd_on_scale), NULL);
    GtkSettings *settings = gtk_settings_get_default();
    if (settings) {
        // The *window* is the fourth argument and not the handle, which is
        // what g_signal_connect_object wants: it ties the connection to that
        // object's lifetime and hands it back as the user data. Passing a
        // handle there compiles — it is a gpointer — and crashes the moment
        // GLib treats the number as an object to watch. It did, on the first
        // run of tests/surface.b through this host.
        //
        // Tying it to the window is also the behaviour worth having: a closed
        // window stops hearing about a theme it no longer draws.
        g_signal_connect_object(settings, "notify::gtk-application-prefer-dark-theme",
                                G_CALLBACK(ctd_on_theme), window, 0);
    }
    return handle;
}

ctd_status ctd_surface_synth(ctd_handle surface, int32_t what,
                             double a, double b) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    switch (what) {
        case CTD_EV_SURFACE_RESIZED: {
            if (!(a >= 0.0) || !(b >= 0.0)) return CTD_ERR_RANGE;
            // A real resize, so GTK's own notify is what arrives.
            gtk_window_set_default_size(GTK_WINDOW(object), (int)a, (int)b);
            return CTD_OK;
        }
        case CTD_EV_SURFACE_CLOSE: {
            // The signal itself, not gtk_window_close.
            //
            // gtk_window_close does nothing at all to a window that has never
            // been shown — no close-request, no destroy, no error — so a
            // headless gate driving it would watch nothing happen and have no
            // way to tell that from a host that ignored the call. Emitting the
            // signal is the same handler a real click reaches, and the veto it
            // answers with is the same veto.
            gboolean vetoed = FALSE;
            g_signal_emit_by_name(object, "close-request", &vetoed);
            if (!vetoed) gtk_window_destroy(GTK_WINDOW(object));
            return CTD_OK;
        }
        case CTD_EV_APPEARANCE:
        case CTD_EV_SCALE_CHANGED:
            ctd_surface_event((uint32_t)what, surface, a, b);
            return CTD_OK;
        default:
            return CTD_ERR_RANGE;
    }
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
