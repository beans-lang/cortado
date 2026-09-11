/* The flat C ABI that every cortado platform implements.
 *
 * Beans binds this header and nothing else. No Objective-C type, no COM
 * interface and no GObject appears in any signature here, which is what lets
 * one Beans binding drive AppKit, Win32, GTK4, UIKit and Android without
 * changing a line of it. It is also a hard requirement rather than a
 * preference: Beans cannot call `objc_msgSend`, because the arm64 ABI wants it
 * cast per call signature and there is no way to spell that from Beans.
 *
 * Five rules hold this file:
 *
 *   1. No struct crosses by value, in either direction. Geometry travels as
 *      loose doubles and comes back through out-pointers. The one exception is
 *      `ctd_event`, which crosses by pointer.
 *   2. A handle is an integer, never an address. It carries a generation, so
 *      using one after its widget is gone is a checked error and not a jump
 *      into freed memory.
 *   3. Text is UTF-8 with an explicit length, never NUL-terminated, and is
 *      always copied at the boundary. Reading text uses the two-call shape:
 *      ask with cap 0 to learn the size, then ask again with a buffer.
 *   4. The host never names a Beans symbol. Everything that calls back into
 *      Beans goes through a function pointer Beans registers at run time.
 *      (The interpreter links this file into a shared library without
 *      `-undefined dynamic_lookup`, so a reference to a Beans export would
 *      link natively and fail under `beansc run`.)
 *   5. Coordinates are top-left origin, y grows downward, in points. Four of
 *      the five target platforms already work this way; the macOS host flips.
 *
 * Anything a platform cannot do answers CTD_ERR_UNSUPPORTED. It never silently
 * does nothing.
 */
#ifndef CORTADO_HOST_H
#define CORTADO_HOST_H

#include <stdint.h>

#define CTD_ABI_VERSION 2

/* A widget, surface or image. High 32 bits are the slot's generation, low 32
 * the slot itself. Zero is "no handle" and is always invalid. */
typedef uint64_t ctd_handle;

/* CTD_OK, or one of the negative codes below. Never a count: a status and a
 * count in one return value is how a caller ends up treating -1 as a length. */
typedef int32_t ctd_status;

#define CTD_OK                 0
#define CTD_ERR_STALE         -1  /* the handle's widget is gone              */
#define CTD_ERR_KIND          -2  /* that operation is wrong for this widget  */
#define CTD_ERR_PLATFORM      -3  /* the OS refused                           */
#define CTD_ERR_THREAD        -4  /* called off the UI thread                 */
#define CTD_ERR_UNSUPPORTED   -5  /* this platform has no such thing          */
#define CTD_ERR_RANGE         -6  /* index or size out of range               */
#define CTD_ERR_ABI           -7  /* host and binding disagree on the version */

/* ---- events ------------------------------------------------------------ */

/* One record for every kind of event. The unused fields of a given kind are
 * zero. A single struct keeps the callback edge to exactly one C signature,
 * which matters because each distinct signature costs the tree interpreter a
 * separately compiled trampoline. */
typedef struct ctd_event {
    uint32_t kind;              /* CTD_EV_*                                   */
    uint32_t modifiers;         /* CTD_MOD_* bits                             */
    uint64_t target;            /* the handle it happened to, 0 for app-wide  */
    int64_t  index;             /* row, tab, selected index, key code         */
    int64_t  token;             /* echoes ctd_post / a dialog's request token */
    double   x, y;              /* pointer position, in the target's space    */
    double   width, height;     /* new size, for resize events                */
    /* The control's text at the moment the event was raised, for the events
     * where that is the news: a value that changed, a field that committed.
     * NULL and 0 for every other kind.
     *
     * It is in the record rather than left for the handler to go and read,
     * because by the time a handler runs the control may already have moved
     * on — a second keystroke, a re-render — and because a handler that had to
     * fetch it would need the widget object, which is exactly the coupling the
     * event exists to avoid. The bytes belong to the host and are valid only
     * for the duration of the call; a binding that keeps them copies them. */
    const char *text;
    int32_t  text_len;
} ctd_event;

#define CTD_EV_ACTIVATE         1  /* button pressed, menu item chosen        */
#define CTD_EV_VALUE_CHANGED    2  /* slider moved, checkbox toggled, typed   */
#define CTD_EV_TEXT_COMMIT      3  /* return pressed, or focus left the field */
#define CTD_EV_SELECTION        4  /* list or table selection moved           */
#define CTD_EV_POINTER_DOWN     5  /* mouse button or finger down             */
#define CTD_EV_POINTER_UP       6
#define CTD_EV_POINTER_MOVE     7
#define CTD_EV_KEY_DOWN         8
#define CTD_EV_KEY_UP           9
#define CTD_EV_FOCUS           10
#define CTD_EV_BLUR            11
#define CTD_EV_SURFACE_RESIZED 12  /* width/height carry the new content size */
#define CTD_EV_SURFACE_CLOSE   13
#define CTD_EV_APPEARANCE      14  /* light/dark, or text size, changed       */
#define CTD_EV_SCALE_CHANGED   15  /* moved to a display with another scale   */
#define CTD_EV_POST            16  /* ctd_post arrived; `token` is its word   */
#define CTD_EV_APP_LAUNCHED    17
#define CTD_EV_APP_FOREGROUND  18
#define CTD_EV_APP_BACKGROUND  19  /* mobile sends these; desktop may ignore  */
#define CTD_EV_APP_WILL_QUIT   20
#define CTD_EV_LOW_MEMORY      21
#define CTD_EV_COMMAND         22  /* a menu command; token identifies which  */

#define CTD_MOD_SHIFT    1u
#define CTD_MOD_CONTROL  2u
#define CTD_MOD_ALT      4u
#define CTD_MOD_COMMAND  8u

/* The one callback edge. `context` is the opaque word the registrar passed. */
typedef void (*ctd_event_fn)(void *context, const ctd_event *event);

/* ---- application ------------------------------------------------------- */

#define CTD_ROLE_GUI        0  /* a normal app: dock icon, menu bar          */
#define CTD_ROLE_ACCESSORY  1  /* runs, but owns no dock icon                */
#define CTD_ROLE_HEADLESS   2  /* builds widgets, never puts one on screen   */

uint32_t   ctd_abi_version(void);
/* Must be called on the process main thread before anything else. Answers
 * CTD_ERR_ABI when `want_abi` is not the version this host implements. */
ctd_status ctd_init(uint32_t want_abi);
ctd_status ctd_app_set_role(int32_t role);
ctd_status ctd_set_event_sink(ctd_event_fn sink, void *context);
void       ctd_shutdown(void);

/* Runs the platform's event loop until ctd_app_stop. On desktop this returns;
 * on iOS UIApplicationMain never does, and on Android there is no loop to run
 * because the activity already owns one — so a program that may run on a phone
 * puts its work in event handlers rather than after this call. */
void       ctd_app_run(void);
void       ctd_app_stop(void);

/* Wakes the UI thread and delivers CTD_EV_POST carrying `token`. The only
 * entry point in this header that is safe to call from another thread, and it
 * takes an integer precisely so nothing else can be smuggled across one. */
void       ctd_post(int64_t token);

/* ---- capabilities ------------------------------------------------------ */

#define CTD_CAP_MENU_BAR        1  /* one menu bar for the whole application */
#define CTD_CAP_WINDOW_MENU     2  /* a menu bar per window                  */
#define CTD_CAP_MULTI_SURFACE   3  /* more than one top-level surface        */
#define CTD_CAP_RESIZABLE       4
#define CTD_CAP_FILE_DIALOG     5
#define CTD_CAP_SNAPSHOT        6  /* can read a widget back as pixels       */

int32_t    ctd_capability(int32_t capability);

/* ---- surfaces ---------------------------------------------------------- */

/* A surface is a window on desktop, a scene on iOS, an activity's content view
 * on Android. Size is content size in points, never including a title bar. */
ctd_handle ctd_surface_new(double width, double height);
ctd_status ctd_surface_set_title(ctd_handle surface, const char *utf8, int32_t len);
int32_t    ctd_surface_title(ctd_handle surface, char *out, int32_t cap);
ctd_status ctd_surface_set_root(ctd_handle surface, ctd_handle root);
ctd_handle ctd_surface_root(ctd_handle surface);
/* Writes width and height into out[0..1]. Sizes and frames leave through a
 * caller-owned buffer rather than one out-pointer per component: it is one
 * argument instead of four, and it lets a caller reuse a single scratch buffer
 * for every read in a layout pass instead of allocating per call. */
ctd_status ctd_surface_content_size(ctd_handle surface, double *out_size);
ctd_status ctd_surface_show(ctd_handle surface);
ctd_status ctd_surface_close(ctd_handle surface);
int32_t    ctd_surface_visible(ctd_handle surface);

/* ---- widgets ----------------------------------------------------------- */

#define CTD_W_CONTAINER     0
#define CTD_W_LABEL         1
#define CTD_W_BUTTON        2
#define CTD_W_TEXT_FIELD    3
#define CTD_W_CHECK_BOX     4
#define CTD_W_IMAGE_VIEW    5
#define CTD_W_SLIDER        6
#define CTD_W_PROGRESS_BAR  7
#define CTD_W_SEPARATOR     8
#define CTD_W_TEXT_AREA     9
#define CTD_W_COMBO_BOX    10
#define CTD_W_SCROLL_VIEW  11
#define CTD_W_RADIO_BUTTON 12

ctd_handle ctd_widget_new(int32_t kind);
int32_t    ctd_widget_kind(ctd_handle widget);   /* -1 when stale */
int32_t    ctd_widget_alive(ctd_handle widget);
ctd_status ctd_widget_release(ctd_handle widget);

/* ---- tree -------------------------------------------------------------- */

/* `index` of -1 appends. */
ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index);
ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child);
/* Reordering is one call on purpose. Remove-then-insert is not equivalent:
 * GTK4 finalizes a widget the moment its last reference drops on unparent, and
 * AppKit takes first-responder status away from a view that leaves its
 * superview mid-edit. The host does whichever dance its platform needs. */
ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to);
ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out);
ctd_handle ctd_view_child_at(ctd_handle parent, int32_t index);
ctd_handle ctd_view_parent(ctd_handle child);

/* ---- geometry ---------------------------------------------------------- */

/* Top-left origin, y downward, in points, relative to the parent's content. */
ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height);
/* Writes x, y, width, height into out[0..3]. */
ctd_status ctd_view_frame(ctd_handle widget, double *out_frame);
/* What this control wants to be, given the space on offer. The layout solver's
 * only dependency on the platform: everything else about layout is arithmetic
 * cortado does itself. Pass a negative available size for "unbounded". */
/* Writes width and height into out[0..1]. */
ctd_status ctd_view_measure(ctd_handle widget, double avail_width, double avail_height,
                            double *out_size);

/* ---- properties -------------------------------------------------------- */

/* Keys for the scalar property bag. Adding a property here costs no new
 * symbol, no new extern declaration and no new interpreter trampoline. */
#define CTD_P_CHECKED      1  /* 0 off, 1 on, 2 mixed                        */
#define CTD_P_ENABLED      2
#define CTD_P_HIDDEN       3
#define CTD_P_MIN          4
#define CTD_P_MAX          5
#define CTD_P_VALUE        6
#define CTD_P_EDITABLE     7
#define CTD_P_ALIGNMENT    8  /* 0 leading, 1 center, 2 trailing             */
#define CTD_P_FONT_SIZE    9
#define CTD_P_STEP        10  /* a slider's increment; 0 for continuous      */
#define CTD_P_SELECTED    11  /* index into an item list; -1 for none        */
#define CTD_P_INDETERMINATE 12 /* a progress bar with no known total         */

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len);
/* Answers the byte length the text needs, and writes at most `cap` bytes.
 * Call with cap 0 to size the buffer. A negative return is a ctd_status. */
int32_t    ctd_get_text(ctd_handle widget, char *out, int32_t cap);
ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value);
ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out);
ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value);
ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out);

/* ---- menus ------------------------------------------------------------- */

/* A command's **role**, and this is the part that makes menus portable.
 *
 * Every desktop platform has opinions about where certain commands live, what
 * they are called and what key they take. About and Preferences belong in the
 * application menu on macOS and under Help and Edit on Windows. Quit is Cmd-Q
 * here and Alt-F4 there. Cut, Copy and Paste must be wired to the platform's
 * own editing machinery — on macOS that means a nil target so the responder
 * chain finds the focused field — or the system text controls stop working
 * inside your own application.
 *
 * So a command with a role is placed, named and keyed by the platform, and its
 * title and key are advisory. A command with no role is an application
 * command and goes exactly where the application puts it. Describing a menu as
 * a tree of titles instead produces a menu that is right on the platform it
 * was written on and wrong everywhere else. */
#define CTD_CMD_NONE         0
#define CTD_CMD_ABOUT        1
#define CTD_CMD_PREFERENCES  2
#define CTD_CMD_QUIT         3
#define CTD_CMD_HIDE         4
#define CTD_CMD_UNDO         5
#define CTD_CMD_REDO         6
#define CTD_CMD_CUT          7
#define CTD_CMD_COPY         8
#define CTD_CMD_PASTE        9
#define CTD_CMD_SELECT_ALL  10
#define CTD_CMD_CLOSE       11
#define CTD_CMD_MINIMIZE    12
#define CTD_CMD_FULLSCREEN  13

ctd_handle ctd_menu_new(const char *title, int32_t len);
/* `key` is a portable shortcut description — "mod+s", "mod+shift+n" — where
 * `mod` is Command on macOS and Control elsewhere. Empty for none.
 *
 * `token` is what comes back on CTD_EV_COMMAND. It is the application's own
 * number: cortado never interprets it, so an application can key its command
 * table however it likes. */
ctd_status ctd_menu_add_item(ctd_handle menu, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token);
ctd_status ctd_menu_add_separator(ctd_handle menu);
ctd_status ctd_menu_add_submenu(ctd_handle menu, ctd_handle child);
ctd_status ctd_menu_item_count(ctd_handle menu, int32_t *out);
/* The item's title as the platform ended up showing it, which for a role is
 * the platform's word and not the one that was passed in. */
int32_t    ctd_menu_item_title(ctd_handle menu, int32_t index, char *out, int32_t cap);
/* The shortcut as the platform ended up assigning it, in the same portable
 * spelling `ctd_menu_add_item` takes. */
int32_t    ctd_menu_item_key(ctd_handle menu, int32_t index, char *out, int32_t cap);
/* Installs `menu` as the application's menu bar. CTD_ERR_UNSUPPORTED where
 * CTD_CAP_MENU_BAR says no. */
ctd_status ctd_menu_set_bar(ctd_handle menu);
ctd_status ctd_menu_set_enabled(ctd_handle menu, int64_t token, int32_t on);
/* Fires a command the way choosing it does, for a test and for a program that
 * offers the same command from a toolbar. */
ctd_status ctd_menu_invoke(ctd_handle menu, int64_t token);

/* ---- dialogs ----------------------------------------------------------- */

/* Dialogs are **asynchronous**, on every platform, and that is not a style
 * choice cortado is making — it is what the platforms do. A macOS sheet runs
 * its own loop and calls back; a GTK dialog is async by construction; and on
 * iOS a modal view controller has no synchronous form at all. A blocking
 * `open_file()` would have to spin an inner event loop, which re-enters
 * everything — including the render this call came out of.
 *
 * So a dialog is asked for with a token and answered with an event carrying
 * that token. `index` says which button, and `text` carries the path or the
 * typed answer where there is one. */
#define CTD_DLG_MESSAGE  0  /* text and buttons                               */
#define CTD_DLG_CONFIRM  1  /* the same, with a cancel                        */
#define CTD_DLG_OPEN     2  /* choose an existing file                        */
#define CTD_DLG_SAVE     3  /* choose a name to write                         */

/* `parent` may be 0 for an application-wide dialog; where the platform can, a
 * dialog with a parent is attached to that surface rather than floating. */
ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token);

/* ---- appearance -------------------------------------------------------- */

/* 0 light, 1 dark. Changes raise CTD_EV_APPEARANCE with the new value in
 * `index`, so a program that draws its own content can follow the system
 * without polling. Native controls follow on their own. */
int32_t    ctd_appearance(void);
/* Backing-store scale for a surface: 1 on a standard display, 2 on a Retina
 * one. Writes the scale into out[0]; a surface that has not been shown yet
 * answers the main display's. Changes raise CTD_EV_SCALE_CHANGED. */
ctd_status ctd_surface_scale(ctd_handle surface, double *out);

/* ---- fonts ------------------------------------------------------------- */

/* The system's own font, by role, so a program does not hard-code a family
 * that is wrong on three platforms out of four. Writes the size into out[0]. */
#define CTD_FONT_BODY     0
#define CTD_FONT_HEADING  1
#define CTD_FONT_CAPTION  2
#define CTD_FONT_MONO     3

int32_t    ctd_font_family(int32_t role, char *out, int32_t cap);
ctd_status ctd_font_size(int32_t role, double *out);

/* ---- item lists -------------------------------------------------------- */

/* A control that offers a list of choices: a combo box today, a list and a
 * segmented control later. The selection is CTD_P_SELECTED, an index, because
 * two items may carry the same text and a selection by text could not tell
 * them apart.
 *
 * Items are replaced wholesale rather than patched. A list that is rebuilt on
 * every render is the common case by far, and an insert-and-move API would
 * mean a second reconciler — with its own bugs — for a control whose contents
 * are strings. When a list grows large enough that rebuilding it shows, the
 * answer is a data-source control, not a diffed item list. */
ctd_status ctd_items_clear(ctd_handle widget);
ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len);
ctd_status ctd_items_count(ctd_handle widget, int32_t *out);
/* Same contract as ctd_get_text: answers the byte length, writes at most cap. */
int32_t    ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap);

/* ---- introspection ----------------------------------------------------- */

/* The platform's own name for the control: "NSButton", "Button", "GtkButton".
 * Only the host can ask an object what it is, and this is the answer that
 * proves a real native control was built rather than a stand-in. */
int32_t    ctd_native_class(ctd_handle widget, char *out, int32_t cap);
/* The accessibility role in one vocabulary shared by every platform:
 * "button", "checkbox", "text", "textbox", "image", "group". */
int32_t    ctd_a11y_role(ctd_handle widget, char *out, int32_t cap);

/* Sends the control's action the way a real click does — through the
 * platform's own dispatch, not by calling the handler directly. This is public
 * API and it is also how every event test drives the framework.
 *
 * It is not usable on every control, and the reason is worth writing down: a
 * click on a pop-up button opens its menu and runs a modal tracking loop, so
 * calling this on one from a test never returns. The two calls below are what
 * a test uses for controls that carry a value. */
ctd_status ctd_widget_activate(ctd_handle widget);

/* Moves a control's value the way a user would, and raises the event that
 * follows.
 *
 * `ctd_set_int` and `ctd_set_real` change a control *silently*, which is
 * right: a program that sets a value should not hear about its own write, or
 * every render would feed itself. These are the other half — what a test needs
 * to drive a control, and what an application needs to replay input.
 *
 * `index` selects for a control with a list and is ignored otherwise; `value`
 * sets the position of a slider. */
ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value);
ctd_status ctd_widget_synth_text(ctd_handle widget, const char *utf8, int32_t len);

#endif /* CORTADO_HOST_H */
