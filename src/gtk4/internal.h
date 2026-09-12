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
extern int32_t g_kind[CTD_SLOTS];
extern int32_t g_icon[CTD_SLOTS];  // CTD_P_ICON, per slot
extern uint32_t g_generation[CTD_SLOTS];
extern uint32_t g_used;
extern void *g_sink_context;
// How many writes cortado is making on the program's behalf right now.
//
// GTK notifies on a property change whoever made it, and the header is
// explicit that ctd_set_* must not raise anything: a render that heard about
// its own writes would feed itself for as long as the program ran. The other
// three hosts are quiet by construction — BM_SETCHECK sends no BN_CLICKED,
// -setState: sends no action, -setOn: fires no value-changed — so this counter
// is what makes the fourth agree with them. A counter rather than a flag
// because a setter can reach another setter: ctd_widget_synth_value asks
// ctd_set_int to do the work, and the wrong nesting would leave events off.
extern int g_writing;

GtkTextView *ctd_text_view(gpointer object);
char *ctd_dup(const char *utf8, int32_t len);
ctd_handle ctd_handle_of(gpointer object);
ctd_handle ctd_track(gpointer object, int32_t kind);
gboolean ctd_is_ours(GtkWidget *widget);
gpointer ctd_resolve(ctd_handle handle);
int ctd_has_nul(const char *utf8, int32_t len);
int32_t ctd_copy_out(const char *text, char *out, int32_t cap);

// The icon theme's name for a CTD_ICON_* role, or NULL when the installed
// theme does not have it. See src/gtk4/icon.c.
const char *ctd_icon_theme_name(int32_t icon);

// The outline's half of the table's idea, in src/gtk4/outline.c. A
// GtkColumnView is both a table and an outline here, so the tag on the widget
// is what tells them apart.
GtkColumnView *ctd_outline_view(gpointer object);
void           ctd_outline_attach(ctd_handle outline, GtkWidget *scroller);
int32_t ctd_slot_kind(ctd_handle handle);
void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token);

// ------------------------------------------------------------------- input.c

// Gives a widget the controllers input arrives through, and records the handle
// it was tracked under. Called from ctd_track for every control there is.
void ctd_input_attach(gpointer object, ctd_handle handle);
// The handle for the nearest ancestor of a widget that cortado built, starting
// with the widget itself. 0 for anything cortado did not build.
ctd_handle ctd_handle_for_widget(GtkWidget *widget);
// Whether anything asked for this kind. The header calls ctd_listen advice
// rather than permission; this is what the advice becomes on the hot path.
int ctd_listening(uint32_t kind);

// ----------------------------------------------------------------- surface.c

// Raises one of the four things that happen to a surface, if anything asked.
void ctd_surface_event(uint32_t kind, ctd_handle surface, double a, double b);
void ctd_give_back(uint32_t slot);
// Forgets the clock a slot may have had, before the slot is handed out again.
void ctd_clock_forget(uint32_t slot);
// Ends whatever a slot had to do with an animation, before it is handed out
// again: the animation it *was*, and any animation of the widget it held.
void ctd_anim_forget(uint32_t slot);
// Where a property is going while an animation moves it. GTK keeps one value
// per property and Core Animation keeps two, so this is the second one — see
// the model and presentation paragraph beside ctd_anim_start in the header.
int ctd_anim_destination(ctd_handle widget, int32_t property, double *out);
void ctd_untrack(ctd_handle handle);
// The half of ctd_set_int that is allowed to raise an event, for the one
// caller that wants one: ctd_widget_synth_value moves a control the way a user
// would, and the event is the whole point of it.
ctd_status ctd_set_int_raising(ctd_handle widget, int32_t key, int64_t value);
// A table: the scrolled window a handle stands for, and the control inside
// it. Made after the handle exists, because a row object carries the handle
// it belongs to.
void ctd_table_attach(ctd_handle table, GtkWidget *scroller);
GtkColumnView *ctd_table_view(gpointer object);
void ctd_on_signal(GtkWidget *widget, gpointer user);
// A property notification, which hands a callback three arguments rather than
// two: the object, the pspec that changed, and the user data. Connecting
// ctd_on_signal to one of these reads the pspec as the widget's handle.
void ctd_on_notify(GObject *object, GParamSpec *pspec, gpointer user);
void ctd_tag(GtkWidget *widget);

// ------------------------------------------------------------------- pane.c

// What the platform keeps for itself, as left, top, right, bottom. Four zeros
// for everything but the containers that draw chrome. See
// ctd_view_content_inset in ../cortado_host.h.
void ctd_chrome_of(gpointer object, double *out);

// ------------------------------------------------------------------- menu.c

// One menu item's token, words and state. Kept beside the GMenu because a
// GMenuItem is write-only once added — GTK gives no way to read one back.
typedef struct {
    int64_t token;
    char   *title;
    char   *key;
    int     separator;
    int     enabled;
    // A CTD_ICON_* role, or CTD_ICON_NONE. Kept on the command rather than on
    // the button, because a toolbar is built from the command list and the
    // list is what outlives it.
    int32_t icon;
} CtdCommand;

// The items a menu holds. NULL for a handle that is not a menu.
GArray *ctd_menu_commands(ctd_handle handle);

// The GtkNotebook a CTD_W_TAB_VIEW handle stands for; NULL for anything else.
// A tab view's children are its pages, so the ordinary child walk cannot find
// them and every path that adds, removes, counts or names one asks here first.
GtkNotebook *ctd_tab_view(gpointer object);
int          ctd_tab_index_of(GtkNotebook *tabs, GtkWidget *page);
ctd_status   ctd_tab_add_page(GtkNotebook *tabs, GtkWidget *page, int32_t index);

// The GtkPaned a CTD_W_SPLIT_VIEW handle stands for; NULL for anything else.
// Its two panes are children in the ABI's sense and are not children of a
// GtkFixed, so the same paths that special-case a notebook special-case this.
GtkPaned    *ctd_split_view(gpointer object);
int          ctd_split_index_of(GtkPaned *split, GtkWidget *pane);
ctd_status   ctd_split_add_pane(GtkPaned *split, GtkWidget *pane, int32_t index);

// A GtkCalendar's day as CTD_P_DATE carries it, and the way back.
//
// Only the year, month and day cross: GtkCalendar's GDateTime is in the local
// zone, and reading its seconds would make the number cortado answers depend
// on where the machine is. Building a fresh UTC midnight from the three
// numbers it does hold is the whole conversion, and it is the same day on
// every machine.
double ctd_calendar_seconds(GtkCalendar *calendar);
void   ctd_calendar_set_seconds(GtkCalendar *calendar, double seconds);

#endif
