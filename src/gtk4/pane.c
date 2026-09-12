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

void ctd_chrome_of(gpointer object, double *out) {
    out[0] = 0.0; out[1] = 0.0; out[2] = 0.0; out[3] = 0.0;
    if (GTK_IS_EXPANDER(object)) {
        int header = 0;
        ctd_pane_reference(&header, NULL, NULL);
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
