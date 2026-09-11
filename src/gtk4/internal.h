// What the Linux host's translation units share, and nothing else does.
//
// `cortado_host.h` is the contract every platform implements. This is the
// opposite: private to this one platform, naming GObject and GTK types freely,
// included by no other host and seen by no Beans file.
//
// Three things GTK does differently, each of which would be a wrong answer if
// copied from the AppKit host.
//
// **A new widget is floating.** `gtk_button_new()` hands back a reference
// nobody owns yet, and a container takes it over when the widget is added.
// cortado's handle table owns widgets before they are parented, so this host
// calls `g_object_ref_sink` on every widget it creates — without it, the first
// `gtk_fixed_put` would silently claim the table's reference.
//
// **A check box has a real third state.** `GtkCheckButton` carries
// `inconsistent` as a property of its own rather than as a drawing mode, so
// CTD_P_INDETERMINATE maps straight onto it.
//
// **Per-widget style providers are gone in GTK4.** Font size is set by adding
// a CSS class and installing one provider on the display, not by attaching a
// provider to the widget.
//
// ## Frames, and GTK's size negotiation
//
// cortado computes every frame itself and tells the platform where things go.
// `GtkFixed` is the container that allows that, and
// `gtk_widget_set_size_request` asks for a size — but that request is a
// **minimum**, not an exact size, and GTK will not allocate a widget smaller
// than it says it needs. A 20-point button really does come out taller here.
// `tests/roles.out` carries no frames for exactly this reason.
#ifndef CORTADO_GTK4_INTERNAL_H
#define CORTADO_GTK4_INTERNAL_H

#include <gtk/gtk.h>
#include <string.h>
#include <stdio.h>
#include "../cortado_host.h"
#include "../cortado_rules.h"

enum { CTD_SLOTS = 8192 };

extern GObject *g_object[CTD_SLOTS];
extern ctd_event_fn g_sink;
extern int g_started;
extern int32_t g_role;
extern uint32_t g_generation[CTD_SLOTS];
extern void *g_sink_context;

GtkTextView *ctd_text_view(gpointer object);
char *ctd_dup(const char *utf8, int32_t len);
ctd_handle ctd_handle_of(gpointer object);
ctd_handle ctd_track(gpointer object, int32_t kind);
gboolean ctd_is_ours(GtkWidget *widget);
gpointer ctd_resolve(ctd_handle handle);
int ctd_has_nul(const char *utf8, int32_t len);
int32_t ctd_copy_out(const char *text, char *out, int32_t cap);
int32_t ctd_slot_kind(ctd_handle handle);
void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token);
void ctd_give_back(uint32_t slot);
void ctd_on_signal(GtkWidget *widget, gpointer user);
void ctd_tag(GtkWidget *widget);

#endif
