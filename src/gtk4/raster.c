#include "internal.h"

ctd_status ctd_canvas_set_pixels(ctd_handle handle, int32_t width, int32_t height,
                                 const char *rgba, int32_t length) {
    gpointer object = ctd_resolve(handle);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(handle) != CTD_W_CANVAS) return CTD_ERR_KIND;
    if (!rgba || width <= 0 || height <= 0 || width > 16384 || height > 16384 ||
        (int64_t)width * height * 4 != length) return CTD_ERR_RANGE;
    /* Desktop surfaces are opaque. Translucent visuals are composited by the
     * renderer before submission, so every platform presents the same frame. */
    for (int32_t at = 3; at < length; at += 4)
        if ((unsigned char)rgba[at] != 255) return CTD_ERR_RANGE;
    GBytes *bytes = g_bytes_new(rgba, (gsize)length);
    GdkTexture *texture = gdk_memory_texture_new(width, height, GDK_MEMORY_R8G8B8A8,
                                                bytes, (gsize)width * 4);
    g_bytes_unref(bytes);
    /* The Canvas remains one tracked widget. GTK owns this untracked picture. */
    GtkWidget *picture = g_object_get_data(G_OBJECT(object), "cortado-raster-picture");
    if (!picture) {
        picture = g_object_new(GTK_TYPE_PICTURE, "accessible-role",
                               GTK_ACCESSIBLE_ROLE_PRESENTATION, NULL);
        gtk_picture_set_can_shrink(GTK_PICTURE(picture), TRUE);
        gtk_widget_set_can_target(picture, FALSE);
        gtk_fixed_put(GTK_FIXED(object), picture, 0, 0);
        g_object_set_data(G_OBJECT(object), "cortado-raster-picture", picture);
    }
    gtk_picture_set_paintable(GTK_PICTURE(picture), GDK_PAINTABLE(texture));
    int scale = gtk_widget_get_scale_factor(GTK_WIDGET(object));
    gtk_widget_set_size_request(picture, (width + scale - 1) / scale, (height + scale - 1) / scale);
    g_object_unref(texture);
    return CTD_OK;
}
