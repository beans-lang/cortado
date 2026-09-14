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
 *      The length is the contract: a host reads exactly that many bytes and
 *      never scans for a terminator, so a length is never guessed and a
 *      string is never cut short by one. What it does **not** buy is an
 *      embedded NUL — no platform's text control can hold one, and every
 *      entry point that takes text refuses a zero byte with CTD_ERR_RANGE
 *      rather than passing a string that would be cut in half inside the
 *      platform with nobody able to see where.
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

#define CTD_ABI_VERSION 28

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
#define CTD_ERR_STATE         -8  /* the right call at the wrong moment        */

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
#define CTD_EV_FRAME           23  /* the display is about to show a frame    */

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

/* Runs the loop for at most `seconds` and then returns; ctd_app_stop cuts it
 * short. A program whose work lives in handlers calls ctd_app_run and never
 * this one. What needs it is anything that has to *wait* for the platform with
 * a deadline — a frame clock, an animation that finishes, a permission somebody
 * has to answer — because a gate that waited without one would not fail on a
 * machine with no display. It would hang there for ever. */
ctd_status ctd_app_run_for(double seconds);

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
#define CTD_CAP_GPU             7  /* can draw with shaders; see "the GPU"   */
#define CTD_CAP_TOOLBAR         8  /* a row of commands attached to a window */
#define CTD_CAP_POPOVER         9  /* a small window anchored to a control   */
#define CTD_CAP_WEB            10  /* a browser engine in a rectangle        */
#define CTD_CAP_ICONS          11  /* the system's own icon set; see "icons"  */
#define CTD_CAP_NETWORK        12  /* can say whether anything is reachable   */
#define CTD_CAP_POWER          13  /* can say what is running the machine     */
#define CTD_CAP_LOCATION       14  /* where the machine is                    */
#define CTD_CAP_BLUETOOTH      15  /* what is nearby                          */
#define CTD_CAP_CAPTURE        16  /* cameras and microphones                 */
#define CTD_CAP_SCREEN         17  /* recording the screen                    */
/* Dressing a control: background, rounded corners, border. One capability and
 * not three — one mechanism, and no platform has some of it and not the rest.
 *
 * Which controls accept a background is ctd_kind_has_background, which is
 * cortado's answer; this asks whether there is anything to ask at all. */
#define CTD_CAP_LAYER_STYLE    18  /* background, corner radius, border       */

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

/* ---- the frame clock --------------------------------------------------- */

/* A surface can ask to be told before every frame its display shows.
 *
 * This is the beat everything that moves runs on, and it is a *clock* rather
 * than a timer: the platform's own display link drives it — CVDisplayLink on
 * macOS, CADisplayLink on iOS, the GdkFrameClock on GTK4 — so the ticks are
 * the display's refresh and not an interval somebody guessed. A program
 * written against it is already right on a 120 Hz screen.
 *
 * Every tick raises CTD_EV_FRAME on the UI thread, carrying
 *
 *     target   the surface
 *     token    the word ctd_clock_start was given
 *     index    the frame number, 1 for the first frame after a start
 *     x        seconds since this clock started
 *     y        seconds since the previous frame — since the start, for frame 1
 *
 * Elapsed seconds and not a machine timestamp, because every platform's clock
 * counts from a different moment and none of them means anything to a caller.
 * How far along it is, is what a caller wanted.
 *
 * **No tick is dropped or merged.** A handler that takes longer than a frame
 * gets its frames late and in order, and `y` still sums to `x`, so an
 * animation stepped by `y` lands in the same place whether the machine kept up
 * or not. Skipping to the newest frame is a policy a caller can write from
 * `x`; a host that did it quietly would make a slow handler look fast and lose
 * the one count that proves nothing went missing. */
ctd_status ctd_clock_start(ctd_handle surface, int64_t token);

/* Stops it. Stopping a clock that is not running succeeds, because a teardown
 * path should not have to ask first. Starting one that is already running does
 * not: it answers CTD_ERR_STATE, because a second start would renumber the
 * frames something else is already counting. */
ctd_status ctd_clock_stop(ctd_handle surface);

/* out[0] is 1 while the clock runs, out[1] the frames delivered since it last
 * started, and out[2] where the clock has got to — the `x` the last frame
 * carried, and 0 before the first. Where it has got to rather than what the
 * time is now, so that reading the state twice without a frame in between
 * answers the same thing twice.
 *
 * The count is of frames *handed to the sink*, which is what makes it worth
 * reading at all: a caller that counted the events it received can compare the
 * two, and a delivery path that lost one becomes a failing test instead of a
 * slightly short animation. */
ctd_status ctd_clock_state(ctd_handle surface, double *out);

/* Raises one frame, `seconds` after the previous one, without waiting for a
 * display.
 *
 * The same family as ctd_widget_activate, and there for the same reason: it
 * drives the host down the exact path the display link uses rather than around
 * it. It is how a clock is checked where there is nothing on screen — a
 * headless GTK window is never mapped, so its frame clock never runs, and a
 * suite that insisted on a real display could only ever check the numbering on
 * one host out of four.
 *
 * CTD_ERR_STATE when the clock is not running. CTD_ERR_RANGE when `seconds` is
 * not positive: a frame that took no time is not a frame, and a negative one
 * would run the clock backwards. */
ctd_status ctd_clock_step(ctd_handle surface, double seconds);

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
/* Somewhere a program draws for itself, with a shader. See "the GPU". */
#define CTD_W_CANVAS       13
/* On or off, and the first kind that is not on every platform. Read the note
 * on ctd_widget_supports before adding another like it. */
#define CTD_W_SWITCH       14
/* One line of text the platform shows as dots and keeps out of the
 * pasteboard, out of dictation and off a screen recording. */
#define CTD_W_SECURE_FIELD 15
/* Two little arrows that step a number. CTD_P_MIN, CTD_P_MAX, CTD_P_VALUE and
 * CTD_P_STEP, the same four a slider carries — the difference is that a slider
 * is a position and this is an increment. */
#define CTD_W_STEPPER      16
/* How full something is, drawn rather than typed into: a battery, a signal, a
 * rating. CTD_P_MIN, CTD_P_MAX and CTD_P_VALUE, and no input at all.
 *
 * Two platforms have one and two do not, which is the point of putting it
 * here rather than leaving it out: it is the kind that makes
 * ctd_widget_supports' "no" answer *reachable by the gate*. A switch is
 * missing only on Win32, whose goldens nothing runs, so the refusal path was
 * checked by a table and never executed. A level indicator is missing on iOS,
 * which does run them — so `tests/controls.out` now has a host that takes the
 * refusing branch and still prints the same bytes as one that does not. */
#define CTD_W_LEVEL_INDICATOR 17
/* Rows and columns, filled by asking rather than by building. See "a table". */
#define CTD_W_TABLE        18
/* A text field that says what it is for. CTD_S_HINT is the words it shows
 * while it is empty. */
#define CTD_W_SEARCH_FIELD 19
/* Something is happening and nobody knows for how long. CTD_P_ANIMATING turns
 * it. Not on every platform: the Win32 common controls have no spinner. */
#define CTD_W_SPINNER      20
/* Words that go somewhere. CTD_S_URL is where. */
#define CTD_W_LINK         21
/* One of a few choices, all of them on screen at once. The choices are the
 * item list — the same ctd_items_* a combo box uses — and CTD_P_SELECTED is
 * which. Not on every platform: GTK has no segmented control. */
#define CTD_W_SEGMENTED    22
/* A titled box around a group of controls. Holds children; its text is the
 * title on the frame. Not on every platform: UIKit has nothing that means it. */
#define CTD_W_GROUP_BOX    23
/* A day. CTD_P_DATE is which one, in seconds since 1970-01-01 UTC.
 *
 * **A date and not an instant**, and that is a decision rather than a
 * limitation of any one platform. NSDatePicker and UIDatePicker can show a
 * time, SysDateTimePick32 can show a time, and GtkCalendar cannot — it is a
 * grid of days and has nowhere to put an hour. A kind whose value round-trips
 * on three platforms and loses its afternoon on the fourth is the sort of
 * difference that is found by a user rather than by a gate, so every host
 * floors what is written to midnight UTC of the day it names, and that is what
 * comes back. See ctd_date_floor in cortado_rules.h. */
#define CTD_W_DATE_PICKER  24
/* A colour, and a way to pick another. CTD_P_COLOR is which, packed
 * 0xRRGGBBAA. Not on every platform: the Win32 common controls have no colour
 * well — ChooseColor is a dialog, which is a different control. */
#define CTD_W_COLOR_WELL   25
/* A title you press to show or hide what is under it. Holds children; its
 * text is the title; CTD_P_EXPANDED is whether they are showing.
 *
 * Not on every platform: the Win32 common controls have no disclosure
 * triangle. The other three draw the glyph themselves — AppKit's
 * NSBezelStyleDisclosure, UIKit's chevron symbol, GtkExpander's arrow — and
 * cortado only puts it beside a title, which is what an application does.
 *
 * **A collapsed disclosure still occupies the room its children asked for**,
 * unless the program stops describing them. The host hides the content and
 * reports the header as chrome (see ctd_view_content_inset); what it cannot do
 * is re-run the caller's layout. A screen that wants the column to close up
 * renders no children while it is shut, which in markup is an $if and in code
 * is not adding them. */
#define CTD_W_DISCLOSURE   26
/* One page at a time, with a strip of labels to choose it.
 *
 * **Its children are its pages**, one each, in order — so the tree a program
 * builds and the tree a screen reader walks are the same tree, and a page is
 * a container like any other. The labels are not children: they are set by
 * index with ctd_tab_set_label, the same shape a table's column titles use,
 * because a label is a property of the page and not a control of its own.
 * CTD_P_SELECTED is which page is showing.
 *
 * Not on every platform. UIKit has no tab *view*: UITabBarController is a view
 * controller that owns the whole screen, not a control that goes in a layout,
 * and a segmented control with a container under it would be cortado
 * assembling a substitute out of two other kinds the caller already has. */
#define CTD_W_TAB_VIEW     27
/* Two panes with a handle between them that the user can drag.
 *
 * Exactly two children, and the platform is what positions them: NSSplitView
 * and GtkPaned both lay their own panes out from one number, and neither can
 * be talked out of it. So cortado does not set a pane's frame — it sets
 * CTD_P_DIVIDER and reads the same number back, and the panes' *contents* are
 * laid out by the solver inside the sizes that number implies.
 *
 * CTD_P_AXIS says which way: 0 for side by side, 1 for stacked. The divider's
 * own thickness is reported through ctd_view_content_inset, on the axis it
 * eats — so a layout that already asks a container what it keeps for itself
 * needs nothing new to account for it.
 *
 * Not on every platform. The Win32 common controls have no splitter at all —
 * every Windows application draws its own — and UIKit's split view is a view
 * *controller* that owns the screen rather than a control in a layout. */
#define CTD_W_SPLIT_VIEW   28
/* A browser engine in a rectangle.
 *
 * The one control here that is a whole other system rather than a widget, and
 * it gets a sub-ABI of its own — ctd_web_* below — for the same reason a table
 * did: navigation, script and messages are not properties, and squeezing them
 * into the property bag would make every one of them a special case.
 *
 * Not on every platform, and this is the widest gap in the header. macOS and
 * iOS have WKWebView, which is part of the system. GTK's is WebKitGTK, a
 * separate library that a machine may or may not have, and Windows' is
 * WebView2, a redistributable the user has to have installed. A control that
 * silently became an empty grey box on two platforms would be worse than one
 * that says it is not there, so both refuse. */
#define CTD_W_WEB_VIEW     29

/* A table whose rows are a tree.
 *
 * The difference from CTD_W_TABLE is one question. A table asks "what is at
 * row r"; an outline asks "how many children has this node, which is child i
 * of it, and can it be opened at all" — and the rows a person sees are
 * whichever nodes happen to be open. That is not a table with indentation: the
 * control owns which nodes are showing, so opening one costs the children of
 * one node and nothing else, which is the whole reason a schema with four
 * hundred tables opens instantly.
 *
 * Every desktop platform has one and calls it something different:
 * NSOutlineView, a GtkColumnView over a GtkTreeListModel, a SysTreeView32
 * with TVS_HASBUTTONS. **UIKit does not.** A phone's outline is a collection
 * view with a list layout and section snapshots — a layout, not a control,
 * with a different lifetime and a different data source — and handing one
 * back would be the substitution ctd_widget_supports exists to refuse. So
 * this kind answers 0 there, and a program that needs a tree on a phone
 * builds it out of a table the way examples/cask had to before this existed.
 *
 * See "outlines" below for the data source. */
#define CTD_W_OUTLINE_VIEW 30

/* Whether this host can build a control of this kind.
 *
 * 1 yes, 0 no, CTD_ERR_RANGE when `kind` is not a kind at all — and that third
 * answer is why this is not a boolean. "This platform has no such control" and
 * "there is no such control" are different facts, and a caller that cannot
 * tell them apart reads a typo as a platform difference.
 *
 * **Why cortado needs this at all.** The first fourteen kinds are on every
 * platform, and the shape of this header says so: ask for a button, get a
 * button. That stops being true at CTD_W_SWITCH. A toggle switch is a real
 * control on macOS, iOS and GTK — NSSwitch, UISwitch, GtkSwitch — and the
 * Win32 common controls do not have one. Windows has toggle switches; they
 * live in WinUI, which is a different toolkit and not something an HWND can
 * be.
 *
 * There were three ways out and two of them are worse:
 *
 *   * Draw one. The separator in the Win32 host argues against this in its own
 *     comment: every control here is the platform's own, and an owner-drawn
 *     imitation is a control that is wrong in ways the user can see and the
 *     program cannot.
 *   * Substitute a check box. It behaves the same and looks nothing like it,
 *     so a design reviewed on a Mac ships to Windows as something else. A
 *     silent substitution is a silent no-op one layer up.
 *   * Say so, before the program builds anything.
 *
 * That is the shape cortado already uses for menus, file dialogs and the GPU,
 * through CTD_CAP_*. A capability per control would be a #define per control
 * and a second table to keep in step with the first; a question about a kind
 * needs neither.
 *
 * **Every host answers for every kind, exhaustively.** Not "returns 0 for
 * anything it does not know" — a kind added to this header and forgotten in a
 * host would then read as a platform difference rather than as the omission it
 * is. `tools/check_vocabulary.sh` holds each host's answer to the CTD_W_*
 * list above, the same way it does for accessibility roles.
 *
 * ctd_widget_new answers 0 for a kind this refuses, and asks this first, so
 * the two cannot disagree about the direction that matters. */
int32_t ctd_widget_supports(int32_t kind);

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

/* The surface a widget is in, or zero when it is in none yet.
 *
 * Walking up with ctd_view_parent stops at the root widget, because a surface
 * is not a widget and never appears as one's parent. This is the step past
 * that, and it is in the ABI rather than worked out above it because only the
 * host can ask a control which window it ended up in.
 *
 * What needs it: anything a *control* wants that belongs to a surface. A frame
 * clock is the case that forced it — a canvas that draws itself every frame
 * has to start one, and making the application pass its window down to every
 * control that might want one is plumbing through code that has no other
 * reason to know about windows. */
ctd_handle ctd_view_surface(ctd_handle widget);

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

/* How much of a control's frame the platform keeps for itself, as
 * left, top, right, bottom into out[0..3].
 *
 * Most controls answer four zeros. The ones that do not are the containers a
 * platform draws chrome for: a group box's border and its title band, a
 * disclosure's header, a tab view's tab strip. Their children live inside a
 * view the platform positions, so a child's coordinates already start at that
 * view's corner — what the chrome takes from the caller is *room*, not origin,
 * and that is the whole of what this answers.
 *
 * **It exists because the alternative is a number written in the caller's
 * layout.** Before it, a screen that put a group box on the page added twelve
 * points of padding by eye and was wrong on the other three platforms, whose
 * borders and title bands are not twelve points. AppKit's is seventeen at the
 * top and five at the sides, and it is seventeen because AppKit says so — no
 * host here writes a metric down; each asks its own toolkit and reports the
 * answer.
 *
 * The answer must not depend on the control's current size, because the layout
 * asks before anything has one. */
ctd_status ctd_view_content_inset(ctd_handle widget, double *out_inset);

/* ---- properties -------------------------------------------------------- */

/* Keys for the scalar property bag. Adding a property here costs no new
 * symbol, no new extern declaration and no new interpreter trampoline. */
#define CTD_P_CHECKED      1  /* 0 off, 1 on, 2 mixed                        */
/* Whether the control accepts input. See the rule below: this is the one
 * property whose *set of widgets* is part of the contract. */
#define CTD_P_ENABLED      2
#define CTD_P_HIDDEN       3
#define CTD_P_MIN          4
#define CTD_P_MAX          5
#define CTD_P_VALUE        6
#define CTD_P_EDITABLE     7
#define CTD_P_ALIGNMENT    8  /* 0 leading, 1 center, 2 trailing             */
#define CTD_P_FONT_SIZE    9
#define CTD_P_STEP        10  /* a slider's or stepper's increment; 0 is      \
                              * continuous, and a stepper refuses it         */
/* **A slider's step is write-only, and a stepper's is not.** ctd_get_real
 * answers CTD_ERR_KIND for CTD_P_STEP on anything but CTD_W_STEPPER, on every
 * host, and that is a rule rather than an omission.
 *
 * AppKit has no increment on a slider: a stepped NSSlider is one with tick
 * marks it must land on, so what the host holds is a *count of positions* and
 * not the number the caller wrote. Reconstructing the increment from it is
 * exact only when the step divided the span evenly, and wrong otherwise —
 * quietly, by a fraction. Win32 answers TBM_GETLINESIZE, which is the right
 * number; GTK4 and UIKit answer nothing. Four platforms, three answers, and
 * the one that looks most helpful is the one that can lie.
 *
 * A stepper has a real increment everywhere, so it reads back.
 *
 * **And a slider's step is a capability, not a promise.** AppKit, GTK and
 * Win32 can make a slider land on detents; a UISlider is continuous and has no
 * way to be anything else. So ctd_set_real answers CTD_ERR_UNSUPPORTED there
 * rather than snapping the value in the host — a thumb that jumps in cortado's
 * arithmetic rather than the platform's is a control behaving in a way no
 * other iOS control does, and a caller who asked for detents and silently got
 * none has no way to find out. A stepper is what to reach for when the steps
 * matter: every platform has one.
 *
 * **What CTD_P_VALUE promises: the number that went in comes back out.** Three
 * of the four hosts draw a progress bar from a *fraction* — UIKit a 0..1
 * float, GTK a 0..1 double, Win32 an int in a fixed span — so a value put in
 * and read back out goes through a division and a multiplication and does not
 * survive: 3 in 0..10 is 0.3f on a phone, and 0.3f scaled back is 3.0000001.
 * Those hosts keep the value beside the range, which was already theirs to
 * keep because none of those platforms has a range on a progress bar at all.
 *
 * This is the one place cortado answers from its own copy rather than from the
 * platform, and it is safe for a reason worth naming: a progress bar takes no
 * input, so the program is the only writer and there is no second value for
 * the copy to disagree with. A slider is the opposite case and is read from
 * the control, every time. */
#define CTD_P_SELECTED    11  /* index into an item list; -1 for none        */
#define CTD_P_INDETERMINATE 12 /* a progress bar with no known total         */
/* How opaque the control is, 0.0 to 1.0. Every kind has one, containers
 * included — unlike CTD_P_ENABLED this really is a property of any view, and
 * setting it on a box is a meaningful thing to ask for: it fades the box and
 * everything in it together, which is what a caller wants and what every
 * platform already does.
 *
 * Out of range is CTD_ERR_RANGE rather than a clamp. A caller that computed
 * 1.5 has a bug, and quietly showing them 1.0 hides it. */
#define CTD_P_OPACITY     13
/* Whether a spinner is turning. A spinner that is not turning is a control
 * that looks broken rather than idle, so a program that has nothing to wait
 * for hides it — but stopping it is still the honest way to say "done", and
 * every platform has a stop. */
#define CTD_P_ANIMATING   14
/* Which day a date picker is showing, in seconds since 1970-01-01 UTC.
 *
 * A real rather than an integer because it crosses as one: ctd_set_real and
 * ctd_get_real already exist, and 2^53 seconds is longer than the universe has
 * been running, so nothing is lost. Written through ctd_date_floor on every
 * host, so what comes back names midnight UTC of the day that went in.
 *
 * Before 1970 is a negative number and is as valid as any other; a date picker
 * that refused 1969 would be cortado inventing a limit no platform has. */
#define CTD_P_DATE        15
/* The colour a colour well is showing, packed 0xRRGGBBAA in the low 32 bits.
 *
 * Red in the high byte, alpha in the low one, which is the order a CSS colour
 * is written in and the order widgets/rgba.b already spells. A value with
 * anything above the low 32 bits set is CTD_ERR_RANGE rather than a mask: a
 * caller who computed one has a bug, and quietly dropping their high bits
 * hides it. */
#define CTD_P_COLOR       16
/* Whether a disclosure is showing what is under it. 0 shut, 1 open. */
#define CTD_P_EXPANDED    17
/* Which way a split view divides: 0 side by side, 1 stacked. */
#define CTD_P_AXIS        18
/* Where a split view's divider sits, in points from the leading edge.
 *
 * A real, because it is a coordinate. Out of the control's own bounds is
 * CTD_ERR_RANGE rather than a clamp, for the reason CTD_P_OPACITY refuses 1.5:
 * a caller who computed it has a bug, and quietly moving the divider somewhere
 * else hides it. */
#define CTD_P_DIVIDER     19
/* Which system icon a control shows, as a CTD_ICON_* role.
 *
 * CTD_ICON_NONE takes it away. A role this host has no icon for is
 * CTD_ERR_RANGE and the control keeps whatever it had — refusing rather than
 * showing nothing, because a toolbar of blank squares is harder to diagnose
 * than a call that said no. See "icons" below.
 *
 * Carried by a button and an image view. Not by a label: a label is text, and
 * a platform that draws an image beside it is drawing a different control. */
#define CTD_P_ICON        20

/* ---- how a control is dressed --------------------------------------------
 *
 * These are a layer's properties, and on Apple's platforms that is literally
 * what they are. They are keys rather than entry points for the reason the
 * property bag exists at all: adding one costs no new symbol, no host that
 * must be taught a new call, and no interpreter trampoline.
 *
 * **Which controls honour which of these is not yet written down**, and is
 * deliberately not guessed at here. A bezel is drawn by the platform and may
 * cover a background cortado set behind it; whether it does is a question
 * about AppKit, UIKit, GTK and Win32 rather than about cortado, and the answer
 * belongs in cortado_rules.h beside ctd_kind_has_enabled once it has been
 * looked at rather than assumed. Until then every kind accepts them, which is
 * the honest state: cortado does not yet know.
 */

/* The colour behind the control's own drawing, packed 0xRRGGBBAA like
 * CTD_P_COLOR, with the same refusal above the low 32 bits. */
#define CTD_P_BG_COLOR    21
/* Corner rounding in points; 0 is square, negative is CTD_ERR_RANGE. Past half
 * the shorter side is allowed — that is a capsule, and every platform draws it. */
#define CTD_P_CORNER_RADIUS 22
/* Border thickness in points, drawn inside the bounds — what CALayer, CSS and
 * every design tool mean, and an outside one needs room the layout never gave. */
#define CTD_P_BORDER_WIDTH  23
#define CTD_P_BORDER_COLOR  24

/* ---- a control a program draws itself ------------------------------------
 *
 * Two keys and a string, all about the one control whose contents cortado did
 * not author. A canvas already *receives* a pointer — the hit test finds it
 * like any other view, and the position arrives in its own points — so what is
 * missing is not input. It is that a canvas cannot take the keyboard and
 * cannot say what it is.
 */

/* Whether this control can take the keyboard. Carried by CTD_W_CANVAS alone:
 * every other kind's answer is the platform's, and a canvas holds a program's.
 *
 * Off by default, so no screen changes its tab order. ctd_widget_focus on one
 * that has not asked is CTD_ERR_STATE, not CTD_ERR_UNSUPPORTED. */
#define CTD_P_FOCUSABLE     25

/* What a canvas is, to a screen reader. Four existing words and no new ones:
 * an invented one is a word no screen reader knows.
 *
 * Carried by CTD_W_CANVAS alone, so no control can misdescribe itself. */
#define CTD_P_A11Y_ROLE     26
#define CTD_A11Y_AUTO    0  /* whatever the kind says; the default           */
#define CTD_A11Y_BUTTON  1
#define CTD_A11Y_IMAGE   2
#define CTD_A11Y_GROUP   3

/* **Which widgets carry CTD_P_ENABLED**, because leaving it unsaid cost four
 * hosts four different answers.
 *
 * Each host used to decide from its own class tree, and the trees disagree:
 * AppKit asked `isKindOfClass:[NSControl class]`, which a label is and a
 * progress bar is not; UIKit asked for `UIControl`, which a label is *not*;
 * GTK4 and Win32 made every widget sensitive, containers included. So a
 * program that disabled a label worked on two platforms out of four, and
 * `tests/roles.out` could not see it because it reads the state with a match
 * that treats a refusal and "enabled" the same.
 *
 * The rule is cortado's, not any platform's:
 *
 *   **A widget has an enabled state exactly when it accepts input.**
 *
 * That is CTD_W_BUTTON, CTD_W_TEXT_FIELD, CTD_W_SECURE_FIELD,
 * CTD_W_SEARCH_FIELD, CTD_W_CHECK_BOX, CTD_W_RADIO_BUTTON, CTD_W_SWITCH,
 * CTD_W_SLIDER, CTD_W_STEPPER, CTD_W_COMBO_BOX, CTD_W_SEGMENTED,
 * CTD_W_DATE_PICKER and CTD_W_COLOR_WELL. Every other kind answers CTD_ERR_KIND from both
 * `ctd_set_int` and `ctd_get_int`, on every host.
 *
 * A label, an image, a separator and a progress bar take no input, so there is
 * nothing for "disabled" to turn off; what a caller actually wants for one of
 * those is a dimmed *look*, which is CTD_P_OPACITY and a different question. A
 * container, a scroll view, a group box and a table are refused for a second
 * reason as well: they exist to hold content, and answering for the box would be
 * answering for everything inside it.
 *
 * A table is the one kind where "accepts input" and "has an enabled state"
 * come apart — a row can be selected — and the holding wins. Two of the four
 * hosts track a table as its scroll view, which is not a control on either of
 * them, so there would be nothing there to answer even if the rule said
 * otherwise.
 *
 * `tests/enabled.out` is this paragraph as a golden, one line per kind, and it
 * is a cross-host file — so a host that guesses again prints different bytes.
 */

/* **Which widgets carry CTD_P_CHECKED, and which of those have a third
 * state.** The same sort of rule as CTD_P_ENABLED above, written down for the
 * same reason: four hosts had four answers and nothing in the suite could see
 * it.
 *
 * A widget has a checked state exactly when being checked is what it is:
 * CTD_W_CHECK_BOX, CTD_W_RADIO_BUTTON and CTD_W_SWITCH. A push button is not
 * one of those, and AppKit used to accept it — all three are an NSButton and
 * -setState: is on NSButton — while GTK and Win32 refused. So ticking a button
 * worked on one platform in four, which is worse than it working on none.
 *
 * Of the three, only a check box has the mixed value. "Some of the things this
 * box stands for" is a real answer; a radio is one of a set, and a switch is
 * one thing, and neither has a third position to be in. Writing 2 to either is
 * CTD_ERR_RANGE, on every platform. Before this was written down, AppKit
 * turned mixed into on, UIKit turned it into off, GTK4 held it as a real third
 * state and Win32 refused it: four answers, and a golden that never asked the
 * question.
 *
 * CTD_ERR_RANGE for any other value too. A caller that computed 7 has a bug,
 * and quietly showing them "off" hides it.
 *
 * CTD_ERR_RANGE is deliberately not CTD_ERR_UNSUPPORTED. Unsupported means
 * this platform cannot, which invites a caller to try elsewhere; out of range
 * means nobody can, because the control has no such state anywhere. The
 * distinction earns its keep here: there *is* an unsupported case, and it is
 * a different one. iOS builds a check box out of a UISwitch, because a phone
 * has no check box, so mixed on a check box is honoured on three hosts and
 * refused with CTD_ERR_UNSUPPORTED on the fourth. `tests/checked.out` is these
 * paragraphs as a golden, and it is a cross-host file. */

/* ---- a second string ---------------------------------------------------- */

/* Text a control carries that is not the text it *is*.
 *
 * `ctd_set_text` is a control's own text — a button's title, a field's value.
 * A control can carry more than one: a field has words it shows while it is
 * empty, a link has somewhere it goes. Those are keyed, for the reason the
 * scalar property bag already gives: a new string costs four `switch` cases
 * here rather than four implementations of a new entry point.
 *
 * Same rules as ctd_set_text — UTF-8 with an explicit length, never
 * NUL-terminated, CTD_ERR_RANGE when the bytes contain a zero — and the same
 * two-call shape for reading. CTD_ERR_KIND when this control has no such
 * string. */
#define CTD_S_HINT  1  /* what a field shows while it is empty                */
/* Where a link goes.
 *
 * **A link opens it, and raises nothing.** That is a decision, and the reason
 * is that the four platforms disagree about who opens a link and cortado
 * cannot make them agree without taking the behaviour away from all of them.
 * AppKit opens an NSLinkAttributeName itself, through the user's own browser
 * and the user's own handler registrations; GTK's link button does the same;
 * a Win32 SysLink does not, so that host calls ShellExecute. What none of them
 * can do is let a program *intercept* the click and route it somewhere else,
 * so cortado does not promise an event it could only raise on some of them.
 *
 * A program that wants to handle the click itself wants a Button with a URL
 * in its title — which is a different control and says so. */
#define CTD_S_URL   2  /* where a link goes                                   */
/* What a screen reader calls this control when its own text is not it. A
 * canvas draws no text cortado wrote, so this is how a program names one.
 *
 * Carried by every kind: it is how a toolbar of icons is usable at all.
 *
 * Reading it back answers what a screen reader will say — the label when one
 * was set, the control's own text when none was, so "" means genuinely silent.
 * The other contract would need a side table, for a worse answer. */
#define CTD_S_A11Y_LABEL  3

ctd_status ctd_set_string(ctd_handle widget, int32_t key,
                          const char *utf8, int32_t len);
/* Answers the byte length, writes at most `cap`. Negative is a ctd_status. */
int32_t    ctd_get_string(ctd_handle widget, int32_t key, char *out, int32_t cap);

/* CTD_ERR_RANGE when the bytes contain a zero: see rule 3 at the top. */
ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len);
/* Answers the byte length the text needs, and writes at most `cap` bytes.
 * Call with cap 0 to size the buffer. A negative return is a ctd_status. */
int32_t    ctd_get_text(ctd_handle widget, char *out, int32_t cap);
ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value);
ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out);
ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value);
ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out);

/* Which key space a number is in. They overlap — CTD_P_CHECKED and CTD_S_HINT
 * are both 1 — so anything asking about a key without knowing the call needs
 * to say which. */
#define CTD_KEY_PROPERTY 0  /* CTD_P_*: ctd_set_int and ctd_set_real */
#define CTD_KEY_TEXT     1  /* CTD_S_*: ctd_set_string               */

/* Whether a kind carries a key: 1 carries, 0 does not, CTD_ERR_RANGE for a
 * number that is not a kind, not a key, or not a space.
 *
 * About the control, never the platform. "This control has no such property"
 * is CTD_ERR_KIND and the same everywhere; "this platform cannot" is
 * CTD_ERR_UNSUPPORTED and differs; "this platform has no such control" is
 * ctd_widget_supports. Every host delegates to ctd_rule_carries. */
int32_t ctd_kind_carries(int32_t kind, int32_t space, int32_t key);

/* ---- animation --------------------------------------------------------- */

/* An animation is described here and run by the platform.
 *
 * That split is the whole reason this is a builder and not a "set this value
 * every frame" call. On macOS and iOS a Core Animation runs on the render
 * server: it keeps going at the display's rate while the main thread is busy,
 * and no Beans code runs for any frame of it. A toolkit that interpolated in
 * its own language would stutter exactly when an application is doing
 * something worth animating about.
 *
 * The builder is the shape ctd_menu_* already uses, for the reason rule 1 at
 * the top of this file gives: no descriptor struct can cross by value, so an
 * animation is a handle and a series of calls that fill it in.
 *
 * **What the property reads while it animates.** The value is set to the
 * destination the moment ctd_anim_start is called, and ctd_get_real answers
 * that from then on: the property says where the control is *going*, and the
 * animation is how it is seen to get there. This is Core Animation's model and
 * presentation layers, and it is the only answer that survives a caller
 * reading the property mid-flight — the alternative is a number that means
 * "somewhere between two others, and by the time you act on it, somewhere
 * else". A host without a presentation layer of its own keeps the destination
 * beside the animation and answers from there, so the four agree.
 *
 * **What can be animated** is deliberately narrow to start with: CTD_P_OPACITY
 * and nothing else. ctd_anim_new answers 0 for any other key rather than
 * accepting a description nothing will honour. The keys that describe a
 * layer — corner radius, rotation, scale, translation, colour — are the ones
 * that come next, and each is a key rather than an entry point, so none of
 * this changes when they do.
 */

#define CTD_EV_ANIM_DONE 24  /* an animation ended; `token` says which       */

/* The curves, by name. Every platform has these four and means the same thing
 * by them. A cubic bezier by control points is the general form and can be
 * added later without disturbing these. The default is ease-in-ease-out, which
 * is what an interface almost always wants and what Core Animation does when
 * nothing is said. */
#define CTD_CURVE_LINEAR       0
#define CTD_CURVE_EASE_IN      1
#define CTD_CURVE_EASE_OUT     2
#define CTD_CURVE_EASE_IN_OUT  3

/* A new animation for one scalar property of one widget, or 0.
 *
 * 0 rather than a status, which is what every handle-returning call in this
 * header does. It can be 0 for four reasons: the widget is gone, the handle
 * names something that is not a widget, the property is not one this platform
 * animates, and the handle table is full.
 *
 * A *surface* is one of the things that is not a widget, and it is worth
 * saying because three of the four platforms would otherwise have accepted
 * one: a UIWindow is a UIView and a GtkWindow is a GtkWidget, so only AppKit
 * would have refused on its own. Fading a whole window is a real thing to want
 * and it is not this — a surface has no place in a widget tree, no frame in
 * anybody's coordinate space, and its own answer to what opacity means. */
ctd_handle ctd_anim_new(ctd_handle widget, int32_t property);

/* Where it starts. Optional — with no from, it starts from wherever the
 * property is when ctd_anim_start is called. */
ctd_status ctd_anim_from_real(ctd_handle anim, double value);
/* Where it ends. Required: ctd_anim_start answers CTD_ERR_STATE without one,
 * because an animation to nowhere is a description somebody left half
 * written, and running it would hide that. */
ctd_status ctd_anim_to_real(ctd_handle anim, double value);
/* How long, in seconds. Must be positive — an animation of no duration is a
 * write, and a caller who computed zero should hear about it. Left unsaid it
 * is a quarter of a second, which is what Core Animation uses when nothing is
 * said and what the other hosts therefore use too. */
ctd_status ctd_anim_duration(ctd_handle anim, double seconds);
/* How long to wait before it starts, in seconds. Zero or more. */
ctd_status ctd_anim_delay(ctd_handle anim, double seconds);
ctd_status ctd_anim_curve(ctd_handle anim, int32_t curve);

/* Hands it to the platform.
 *
 * CTD_EV_ANIM_DONE arrives when it ends, carrying the widget in `target`, the
 * `token` given here, 1 in `index` if it ran to the end and 0 if it was
 * cancelled, and the property's value in `x`.
 *
 * The animation's handle is released as it ends, so it is already stale by the
 * time a handler runs. That is deliberate: the event carries everything a
 * handler needs, and a handle that outlived its animation would be a thing to
 * remember to release on a path that runs thousands of times.
 *
 * Starting an animation on a property that is already animating **replaces**
 * the one there, which ends as cancelled. That is what every animation system
 * does and what a pointer moving on and off a control asks for; refusing would
 * make the caller write the cancel every time. */
ctd_status ctd_anim_start(ctd_handle anim, int64_t token);

/* Stops it where it is.
 *
 * The property keeps the value it was *showing*, not the one it was going to.
 * Cancelling an animation half way and watching the control jump to its
 * destination is not what anybody means by cancel. CTD_EV_ANIM_DONE follows,
 * with 0 in `index`.
 *
 * Cancelling an animation that was built and never started is allowed, and is
 * how one is thrown away: it releases the handle and raises nothing. */
ctd_status ctd_anim_cancel(ctd_handle anim);

/* ---- the GPU ----------------------------------------------------------- */

/* Drawing that is not a control.
 *
 * Everything else in this header asks the platform for a control and lets the
 * platform paint it. This is the other thing a program sometimes needs: a
 * rectangle it paints itself, with a shader, on the GPU. A chart with fifty
 * thousand points, a waveform, a map, a game — none of those is a tree of
 * controls, and drawing one by making controls is how a program ends up with
 * fifty thousand views.
 *
 * The shape is WebGPU's rather than any one platform's: a device, resources
 * made on it, a pipeline that says how to draw, and a pass that draws. That
 * shape was designed to sit over Metal, D3D12 and Vulkan at once, which is the
 * same problem this header has. Metal fills it today; nothing below names
 * Metal, and a D3D12 or Vulkan host fills the same declarations.
 *
 * Where there is no such host every call answers CTD_ERR_UNSUPPORTED and
 * ctd_capability(CTD_CAP_GPU) answers 0 — so a program asks once and draws
 * something else, instead of finding out one call at a time.
 *
 * **Shaders are not portable, and this header does not pretend they are.**
 * MSL, HLSL and SPIR-V are three languages. ctd_gpu_shader_langs says which
 * this host accepts and a shader in any other is refused. Translating between
 * them means vendoring a compiler the size of this project, and the result
 * would still not be exact — so the honest ABI is one that says which language
 * it speaks. */

/* The shading languages a host accepts, as bits: a host that took two would
 * have no way to say so otherwise, and a host that takes none answers 0. */
#define CTD_SHADER_MSL    1u  /* Metal Shading Language                      */
#define CTD_SHADER_HLSL   2u  /* Direct3D                                    */
#define CTD_SHADER_SPIRV  4u  /* Vulkan                                      */
#define CTD_SHADER_GLSL   8u

uint32_t   ctd_gpu_shader_langs(void);

/* The GPU this machine draws with. Zero when the platform has no GPU host, or
 * when the machine really has no device — a virtual machine with no passthrough
 * is the case that happens.
 *
 * The system's default one, and only that one. A Mac with two GPUs can be
 * asked for the others, and a program that renders for hours on battery would
 * want to; that is two more entry points which would arrive already untested,
 * because every machine this has run on has exactly one. It is left out
 * deliberately and not forgotten: adding ctd_gpu_device_count and
 * ctd_gpu_device_at later changes nothing about this call or anything made
 * from it. What would have been the mistake is a `which` argument here that
 * three hosts ignore. */
ctd_handle ctd_gpu_device_new(void);

/* The GPU's own name for itself — "Apple M1 Pro", "NVIDIA GeForce RTX 4080".
 * Same two-call shape as every other text reader here. */
int32_t    ctd_gpu_device_name(ctd_handle device, char *out, int32_t cap);

/* What this device can do, one number at a time.
 *
 * Numbers rather than a struct because rule 1 forbids the struct, and one call
 * rather than one per question because each of those would cost four
 * implementations to answer something a program reads once at start-up.
 * CTD_GPU_UNIFIED_MEMORY is a yes-or-no answered as 1 or 0; it is here rather
 * than in a call of its own for the same reason.
 *
 * These three and not a dozen: each is a real number every one of the three
 * backends can answer — Metal from the device, D3D12 from
 * D3D12_FEATURE_DATA_ARCHITECTURE and QueryVideoMemoryInfo, Vulkan from the
 * memory heaps and the physical-device limits — and each is one a program
 * actually branches on. A tier or a feature-set name is none of those things:
 * it means something on one backend and has to be invented on the others.
 *
 * They leave through a double, like every other number in this header, and a
 * double holds a byte count exactly up to 2^53 — eight petabytes, which no GPU
 * will have before this ABI is replaced. CTD_ERR_RANGE for a key this host
 * does not know. */
#define CTD_GPU_UNIFIED_MEMORY    1  /* 1 when CPU and GPU share memory      */
#define CTD_GPU_MAX_BUFFER_BYTES  2  /* the largest single buffer           */
#define CTD_GPU_MEMORY_BYTES      3  /* what the driver asks you to stay under */

ctd_status ctd_gpu_device_limit(ctd_handle device, int32_t which, double *out);

/* Lets go of a GPU object — a device, and later everything made on one.
 *
 * One release for every kind of GPU object rather than one per kind. A buffer,
 * a texture, a shader and a pipeline are released identically and differ only
 * in what the driver does afterwards, so five entry points would be five
 * copies of the same four implementations. ctd_widget_release stays separate
 * because releasing a widget is not the same act: it takes the control out of
 * its parent first, and a GPU object has no parent.
 *
 * CTD_ERR_KIND for a handle that is not a GPU object, which is what a widget
 * passed here gets. A release that quietly accepted anything would make
 * releasing the wrong thing invisible exactly where it is most expensive. */
ctd_status ctd_gpu_release(ctd_handle object);

/* ---- the GPU: what you draw with ---------------------------------------- */

/* A block of floats the GPU can read.
 *
 * Floats, and only floats, everywhere in this section: a buffer's contents,
 * an attribute's offset, a layout's stride, a uniform. That is narrower than
 * any of the three backends, and it is narrow on purpose — the alternative is
 * a byte-addressed API in which the caller computes offsets in bytes for data
 * they wrote in floats, and gets one of them wrong. Beans can hand C a
 * `RawPtr<f32>` and cannot bit-cast a float, so floats are also the only thing
 * that crosses this boundary today without a second representation.
 *
 * Packed colours and 16-bit indices are the reason this will grow, and when
 * they land they arrive as `ctd_gpu_buffer_write_bytes` with byte offsets of
 * its own rather than by changing the meaning of these arguments.
 *
 * `count` is a number of floats, not bytes. Zero or fewer is CTD_ERR_RANGE:
 * a buffer with nothing in it is a description somebody left half written. */
ctd_handle ctd_gpu_buffer_new(ctd_handle device, const float *data, int32_t count);

/* Overwrites `count` floats starting at float `first`. Writing past the end is
 * CTD_ERR_RANGE and never a partial write — a GPU buffer is memory the driver
 * owns, and a clamped write there is a corruption nobody sees until a frame
 * looks wrong. */
ctd_status ctd_gpu_buffer_write(ctd_handle buffer, int32_t first,
                                const float *data, int32_t count);
/* How many floats it holds. */
ctd_status ctd_gpu_buffer_count(ctd_handle buffer, int32_t *out);

/* Somewhere to draw: an off-screen image, 8-bit RGBA.
 *
 * One pixel format, and it is the one `ctd_snapshot` already answers in.
 * A format argument would be the first thing a caller had to decide and the
 * last thing they could check, and every extra format multiplies what a golden
 * has to assert. Wider colour is a real want and it is a later decision with
 * its own capability, not an argument here.
 *
 * Width and height are in pixels, not points: this is an image the program
 * computes, and there is no display involved to have a scale. */
ctd_handle ctd_gpu_target_new(ctd_handle device, int32_t width, int32_t height);

/* Reads the target back as pixels — 8-bit RGBA, row after row, **top row
 * first**, no padding, so the image is exactly width * height * 4 bytes and a
 * pixel is at (y * width + x) * 4. The same layout and the same two-call shape
 * as ctd_snapshot: ask with `cap` 0 for the byte count, then again with a
 * buffer. `out_size` is filled on both calls.
 *
 * Top row first is a promise about the GPU as well as about this call: in clip
 * space y grows *upward*, so the vertex at y = +1 is the one that lands in row
 * zero. Every backend this ABI is shaped for agrees about that, and it is
 * checked rather than assumed — `tests/triangle.b` draws a quad over the top
 * half and asserts which half comes back filled. */
int32_t    ctd_gpu_target_read(ctd_handle target, double *out_size, char *out, int32_t cap);

/* Compiles shader source, at run time, in the language `ctd_gpu_shader_langs`
 * said this host accepts. Anything else is refused rather than attempted.
 *
 * At run time and not as a build step, because there is no build step to put
 * it in: a Beans package declares C sources and frameworks, and nothing that
 * would run `xcrun metal`. Compiling from source costs about two milliseconds
 * cold and nothing at all warm, which is cheaper than the machinery would be.
 *
 * Answers no handle when the source does not compile. **`ctd_gpu_shader_problem`
 * is then how you find out why** — a shader that failed with no message is a
 * blank window and a long evening. */
ctd_handle ctd_gpu_shader_new(ctd_handle device, int32_t language,
                              const char *source, int32_t len);

/* What went wrong the last time this device was asked to compile something,
 * as the platform's own compiler said it — file, line, column and message.
 * Empty when the last compile succeeded.
 *
 * On the device rather than on the shader, because the shader that failed has
 * no handle to ask. That makes it *the last one*, which is the one thing worth
 * being exact about: read it immediately, and never from two threads, which
 * costs nothing here because every call in this header is on the UI thread. */
int32_t    ctd_gpu_shader_problem(ctd_handle device, char *out, int32_t cap);

/* How to draw: which shader functions, how a vertex is laid out, how the
 * result is mixed with what is already there.
 *
 * A builder, the shape `ctd_menu_*` uses, because rule 1 forbids handing a
 * descriptor across by value — and because a pipeline is genuinely a list of
 * decisions rather than four arguments.
 *
 * `vertex` and `fragment` are function names in the shader source. A name that
 * is not in it answers no handle rather than failing later at draw time. */
ctd_handle ctd_gpu_pipeline_new(ctd_handle shader,
                                const char *vertex, int32_t vertex_len,
                                const char *fragment, int32_t fragment_len);

/* One field of a vertex: which `[[attribute(index)]]` it feeds, how many
 * floats it is (1 to 4), and how many floats into the vertex it starts. */
ctd_status ctd_gpu_pipeline_attr(ctd_handle pipeline, int32_t index,
                                 int32_t floats, int32_t offset);
/* How many floats one vertex takes, including any padding between them. */
ctd_status ctd_gpu_pipeline_stride(ctd_handle pipeline, int32_t floats);

/* How a drawn pixel is mixed with the one already there.
 *
 * Three named modes rather than a pair of blend factors. Every backend has
 * these three and means the same by them; a factor pair is eight enums a
 * caller has to get right in a combination nothing checks, to arrive at one of
 * these three anyway. Custom factors are a later call of their own and change
 * nothing about this one. */
#define CTD_BLEND_REPLACE  0  /* the new pixel, whatever was there          */
#define CTD_BLEND_ALPHA    1  /* over: src*a + dst*(1-a) — what a UI wants  */
#define CTD_BLEND_ADD      2  /* src + dst — glows, particles, heat maps    */

ctd_status ctd_gpu_pipeline_blend(ctd_handle pipeline, int32_t blend);

/* Finishes it. Everything above must come first; nothing may change after.
 *
 * CTD_ERR_STATE when no attribute or no stride was given: a pipeline with no
 * vertex layout could only be driven by a shader that indexes a raw buffer
 * itself, which is a second way to write every shader and a second thing for
 * this ABI to describe. One way, and it is checked. */
ctd_status ctd_gpu_pipeline_build(ctd_handle pipeline);

/* Everything drawn into one target between a begin and an end.
 *
 * The target is cleared to the colour given here, because every backend clears
 * as part of starting a pass and a separate "clear" call would be a second
 * pass that costs a whole round trip. Components are 0 to 1.
 *
 * A pass is **synchronous**: `ctd_gpu_pass_end` hands the work to the GPU and
 * waits for it, so the pixels are there to read the moment it returns. That is
 * the right trade for an image a program computes and reads back, which is
 * what this pair of calls is for. It is the wrong trade for a surface being
 * presented sixty times a second, and that is a different call with a
 * different contract rather than a flag on this one. */
ctd_handle ctd_gpu_pass_begin(ctd_handle target, double r, double g, double b, double a);
ctd_status ctd_gpu_pass_pipeline(ctd_handle pass, ctd_handle pipeline);

/* The vertices to read. One buffer, bound where the shader declares
 * `[[buffer(0)]]`; the uniform below is `[[buffer(1)]]`.
 *
 * One, because interleaved data in a single buffer is what a program writes
 * and what every example of this shape does. A second buffer is what instanced
 * drawing wants, and it arrives as a call that names its slot — leaving this
 * one meaning exactly what it says today rather than growing an argument. */
ctd_status ctd_gpu_pass_vertices(ctd_handle pass, ctd_handle buffer);

/* Constants for the draws that follow, read by the shader at `[[buffer(1)]]`.
 *
 * Copied out of the caller's memory as the call is made, not referenced, so
 * the floats may be a local that goes out of scope on the next line. That is
 * the same promise rule 3 makes about text, for the same reason. */
ctd_status ctd_gpu_pass_uniform(ctd_handle pass, const float *data, int32_t count);

#define CTD_SHAPE_TRIANGLES       0
#define CTD_SHAPE_TRIANGLE_STRIP  1
#define CTD_SHAPE_LINES           2
#define CTD_SHAPE_LINE_STRIP      3
#define CTD_SHAPE_POINTS          4

/* Draws `count` vertices starting at `first`. */
ctd_status ctd_gpu_pass_draw(ctd_handle pass, int32_t shape, int32_t first, int32_t count);

/* Ends the pass, runs it, and waits. The pass's handle is released as it ends,
 * the way an animation's is — everything it described has happened, and a
 * handle that outlived it would be a thing to remember to release on a path
 * that runs every frame. */
ctd_status ctd_gpu_pass_end(ctd_handle pass);

/* A widget you draw into yourself.
 *
 * `CTD_W_CANVAS` is an ordinary widget on every host: the solver lays it out,
 * it is in the tree, it has an accessibility role, and `tests/roles.out` names
 * it on all four. What differs is whether anything can be drawn into it —
 * `ctd_gpu_canvas_attach` is where a host without a GPU refuses, and the
 * control is then simply an empty area rather than a missing one.
 *
 * Every frame is three calls: ask the canvas for the frame it is about to
 * show, draw into it as into any other target, and present. A canvas is
 * driven from `CTD_EV_FRAME` — the frame clock is what tells you a frame is
 * wanted, and drawing outside one is drawing the platform will not show.
 *
 * A widget that is not a canvas is CTD_ERR_KIND **on every host, before the
 * host considers whether it has a GPU at all**. "This is not a canvas" is the
 * caller's bug and "this platform has no GPU" is not; a host that answered the
 * second to both would hide the first on three platforms out of four. */
ctd_status ctd_gpu_canvas_attach(ctd_handle widget, ctd_handle device);

/* The target for the frame this canvas is about to show.
 *
 * A target like any other, so the same pass, the same pipelines and the same
 * `ctd_gpu_target_read` all work on it — which is what makes a canvas
 * checkable rather than something you have to look at.
 *
 * It belongs to one frame. Release it when the frame is over (presenting does
 * not release it, so the two lifetimes stay separate and visible), and ask
 * again for the next. Zero when the canvas has nothing to give: no device
 * attached, or a size of nothing. */
ctd_handle ctd_gpu_canvas_next(ctd_handle widget);

/* Ends a pass by putting it on screen rather than by waiting for it.
 *
 * `ctd_gpu_pass_end` waits, because the caller is about to read the pixels.
 * A canvas never reads them; it hands them to the compositor. Waiting there
 * would stall the thread that has to draw the next frame, sixty times a
 * second, for no reason at all.
 *
 * Two calls rather than a flag on one, because a caller who got it wrong
 * should hear about it: CTD_ERR_STATE when the pass is not drawing into a
 * canvas, and again from `ctd_gpu_pass_end` when it is. The pass's handle is
 * released either way. */
ctd_status ctd_gpu_pass_present(ctd_handle pass);

/* Which pixels a pipeline is built to write.
 *
 * Not a format zoo — two answers, because there are two questions. An
 * off-screen target is the 8-bit RGBA `ctd_gpu_target_read` hands back, and
 * every backend can make one. A canvas is whatever the platform's compositor
 * wants, which on Metal is BGRA and on another backend may be something else
 * again; the host knows and the caller does not have to.
 *
 * It matters because a pipeline carries the format it writes, and drawing with
 * one that disagrees with its target is refused by the driver at draw time —
 * far from the line that got it wrong. A pipeline says which it is for, once.
 *
 * Nothing changes in the shader: it writes red, green, blue and alpha in that
 * order whichever this is, and the hardware puts them where they go. */
#define CTD_PIXELS_RGBA8   0  /* what ctd_gpu_target_new makes, and reads back */
#define CTD_PIXELS_SCREEN  1  /* whatever a canvas on this platform shows      */

ctd_status ctd_gpu_pipeline_pixels(ctd_handle pipeline, int32_t pixels);

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

/* ---- toolbars ---------------------------------------------------------- */

/* A row of commands attached to a surface, described by a **menu**.
 *
 * Not a builder of its own, and that is the whole design. `ctd_menu_invoke`
 * already says a command may be offered "from a toolbar"; a second list of
 * titles and tokens would be a second place for the same command to be spelled
 * differently, and the first thing to drift would be which of the two the
 * application remembered to disable.
 *
 * So a toolbar *is* a menu: the same handle, the same tokens, the same
 * ctd_menu_set_enabled. Choosing an item raises CTD_EV_COMMAND carrying the
 * token, exactly as choosing it from the menu bar does, and a program with one
 * command table needs no second one.
 *
 * Where the platform puts it is the platform's business and differs: AppKit
 * puts an NSToolbar in the title bar, GTK a header bar in place of one, and
 * Windows and UIKit a real strip inside the frame. The last two take room from
 * the window, and both report it through ctd_surface_content_size — so a
 * layout that already asks how much room it has needs to know nothing about
 * any of this.
 *
 * CTD_ERR_UNSUPPORTED where ctd_capability(CTD_CAP_TOOLBAR) answers 0. */
ctd_status ctd_toolbar_set(ctd_handle surface, ctd_handle menu);
ctd_status ctd_toolbar_clear(ctd_handle surface);
/* How many items the toolbar ended up showing. Not always the menu's count: a
 * submenu is not a toolbar item on any platform here, and a separator is one
 * on some and not others. A test that asserted the menu's count would be
 * asserting the menu. */
ctd_status ctd_toolbar_count(ctd_handle surface, int32_t *out);
/* What item `index` says, in the two-call text shape: pass a null `out` or a
 * cap of 0 for the length, then a buffer.
 *
 * The count alone is not enough to know a toolbar is right, and that is not a
 * theoretical gap. cortado shipped a toolbar where every item carried the
 * first command's words and the first command's token — four buttons, all of
 * them Reload — and the suite was green, because what it checked was that
 * there were four of them. An item's own label is the smallest fact that
 * distinguishes item 2 from item 0.
 *
 * A separator has no label and answers 0 with an empty buffer, which is the
 * same answer as an item whose title is empty; a caller that needs to tell
 * those apart is asking about the menu, and should ask the menu.
 *
 * Writes at most `cap` bytes and answers the byte length the label needs, the
 * two-call shape every text reader in this header uses. CTD_ERR_RANGE for an
 * index outside the toolbar and for a surface that has none;
 * CTD_ERR_UNSUPPORTED where ctd_capability(CTD_CAP_TOOLBAR) answers 0. */
int32_t ctd_toolbar_label(ctd_handle surface, int32_t index, char *out, int32_t cap);

/* ---- outlines ----------------------------------------------------------- */

/* A tree, asked about a node at a time.
 *
 * This is the table's data source with one idea added: **identity**. A table
 * asks about row 7; an outline asks about a *node*, and a node is an int64 the
 * application chooses — a row id, an index into its own array, a pointer it
 * cast. cortado never looks inside one. The host keeps whatever object its
 * toolkit needs beside it, which is the work this sub-ABI exists to do once
 * rather than in every program.
 *
 * CTD_OUTLINE_ROOT is the node above the top level: its children are the
 * things a person sees first. It is 0, so an application whose own ids start
 * at 0 adds one to them — which is a sentence in a comment, against a scheme
 * where every host would need a second way to spell "nothing".
 *
 * **Two callbacks, not one.** Structure and text are different questions with
 * different answers, and a single function would need seven parameters, one
 * more than a C callback here may have. So the shape function answers an
 * integer and the text function answers bytes, with exactly the rules
 * ctd_table_fn already has: write at most `cap`, answer the length, expect a
 * `cap` of 0 first.
 *
 * **What must not happen inside either.** They run while the platform is
 * drawing, on the UI thread, and they must return. No waiting, no fetching. A
 * node's children are a lookup in something the program already has; if they
 * are not there yet, answer none and call ctd_outline_reload when they
 * arrive. */
#define CTD_OUTLINE_ROOT      0

/* How many children `node` has. `index` is unused. */
#define CTD_OUTLINE_CHILDREN  0
/* Which node is child `index` of `node`. Answers the child's own id. */
#define CTD_OUTLINE_CHILD     1
/* Whether `node` can be opened at all — 1 or 0. Asked separately from the
 * child count because the two differ: a folder that has not been read yet has
 * no children to report and must still draw a twisty, and a table in a
 * database has none and must not. A host that inferred one from the other
 * would make "empty" and "closed" the same thing. */
#define CTD_OUTLINE_EXPANDS   2

typedef int64_t (*ctd_outline_fn)(void *context, ctd_handle outline,
                                  int32_t what, int64_t node, int32_t index);

/* The text of `node` in `column`. Same two-call shape as ctd_table_fn. */
typedef int32_t (*ctd_outline_text_fn)(void *context, ctd_handle outline,
                                       int64_t node, int32_t column,
                                       char *out, int32_t cap);

/* One source for the process, like the event sink and the table source. Not
 * one per control: the hazard at the top of this file applies here exactly as
 * it does to events.
 *
 * **A context each, not one between them.** A binding that reaches a managed
 * language does not pass a plain function pointer — it passes a trampoline
 * plus the context that trampoline looks its closure up in — so two functions
 * sharing one context is two closures with one address, and the second is
 * called as the first. Two fields cost nothing here and make the wrong
 * version impossible to write. */
ctd_status ctd_set_outline_source(ctd_outline_fn shape, void *shape_context,
                                  ctd_outline_text_fn text, void *text_context);

/* The columns, the same three calls a table takes. An outline with one column
 * is a plain tree; the first column is the one that carries the indent and
 * the twisty, on every platform here.
 *
 * **More than one column is not on every platform.** A SysTreeView32 has no
 * columns at all — Windows applications that show a tree with columns either
 * own-draw a list view or buy a control — so the Win32 host takes 1 and
 * answers CTD_ERR_UNSUPPORTED for more. A program that wants to work there
 * asks for one column and puts what it would have put in the second into the
 * text, which is what a Windows tree looks like anyway. */
ctd_status ctd_outline_columns(ctd_handle outline, int32_t count);
ctd_status ctd_outline_column_title(ctd_handle outline, int32_t column,
                                    const char *utf8, int32_t len);
ctd_status ctd_outline_column_width(ctd_handle outline, int32_t column,
                                    double points);

/* Ask again, from the root down. What is open stays open where the same nodes
 * are still there. */
ctd_status ctd_outline_reload(ctd_handle outline);

/* Open or close one node. CTD_ERR_RANGE for a node the control is not
 * showing — which includes a node inside a closed parent, because a control
 * that has not been asked about it does not have it. */
ctd_status ctd_outline_expand(ctd_handle outline, int64_t node, int32_t on);
ctd_status ctd_outline_expanded(ctd_handle outline, int64_t node, int32_t *out);

/* The selected node, or CTD_OUTLINE_ROOT for none — which is unambiguous
 * because the root is never itself a row. */
ctd_status ctd_outline_selected(ctd_handle outline, int64_t *out);
ctd_status ctd_outline_select(ctd_handle outline, int64_t node);

/* What the *platform* has for one cell, asked through its own data source —
 * the round trip ctd_table_cell is for a table, and the only way to check the
 * path at all without a display. */
int32_t    ctd_outline_cell(ctd_handle outline, int64_t node, int32_t column,
                            char *out, int32_t cap);

/* ---- icons -------------------------------------------------------------- */

/* The system's own icon set, named by **role** rather than by name.
 *
 * Every platform here ships a set of icons and no two agree on what anything
 * is called: macOS and iOS have SF Symbols ("arrow.clockwise"), GTK has the
 * freedesktop icon theme ("view-refresh-symbolic"), Windows has the standard
 * toolbar bitmap and the shell's stock icons (STD_FILEOPEN, SIID_FOLDER). A
 * program that named one of those would be a program for one platform.
 *
 * So cortado names the *job*. "Refresh" is a role; what it looks like is the
 * host's business and the person using it already knows their own system's
 * icon for it, which is the whole reason to use the system's set instead of
 * shipping pictures. This is the same trade `ctd_menu_add_item`'s
 * CTD_CMD_* roles already make for commands the platform handles itself.
 *
 * **Not every role exists everywhere, and this API says so rather than
 * drawing a blank.** Windows' standard toolbar bitmap has fifteen images and
 * no "run" or "database" among them; `ctd_icon_name` answers CTD_ERR_RANGE
 * for a role the host cannot draw, and a caller that wants to degrade to text
 * asks before it sets one. `ctd_capability(CTD_CAP_ICONS)` answers whether
 * there is a set here at all.
 *
 * Where an icon goes: CTD_P_ICON on a button or an image view, and
 * `ctd_menu_set_icon` on a menu item — which is how a toolbar gets icons,
 * because a toolbar is a menu. */
#define CTD_ICON_NONE        0  /* no icon; takes one away                    */
#define CTD_ICON_REFRESH     1
#define CTD_ICON_ADD         2
#define CTD_ICON_REMOVE      3
#define CTD_ICON_DELETE      4
#define CTD_ICON_OPEN        5
#define CTD_ICON_SAVE        6
#define CTD_ICON_SEARCH      7
#define CTD_ICON_RUN         8
#define CTD_ICON_STOP        9
#define CTD_ICON_BACK       10
#define CTD_ICON_FORWARD    11
#define CTD_ICON_CUT        12
#define CTD_ICON_COPY       13
#define CTD_ICON_PASTE      14
#define CTD_ICON_UNDO       15
#define CTD_ICON_REDO       16
#define CTD_ICON_PRINT      17
#define CTD_ICON_SETTINGS   18
#define CTD_ICON_INFO       19
#define CTD_ICON_WARNING    20
#define CTD_ICON_ERROR      21
#define CTD_ICON_HELP       22
#define CTD_ICON_DOCUMENT   23
#define CTD_ICON_FOLDER     24
#define CTD_ICON_DATABASE   25
#define CTD_ICON_TABLE      26
#define CTD_ICON_COUNT      27

/* What this host calls `icon`, in the two-call text shape.
 *
 * This exists to be *read*, not to be passed back in. It is what makes the
 * mapping testable — a suite can assert that every role this host claims has
 * a name, and that no two roles share one — and what makes a misdrawn toolbar
 * diagnosable, because "which icon did it actually ask for" is otherwise a
 * question only a screenshot answers.
 *
 * CTD_ERR_RANGE for a role outside the list and for one this host has no icon
 * for; CTD_ERR_UNSUPPORTED where CTD_CAP_ICONS answers 0. The strings name one
 * platform on purpose: "arrow.clockwise" on macOS, "view-refresh-symbolic" on
 * GTK, "STD_FILEOPEN" on Windows. Nothing portable should compare them. */
int32_t    ctd_icon_name(int32_t icon, char *out, int32_t cap);

/* Gives the item carrying `token` the system icon for `icon`.
 *
 * A menu item is not a widget and has no handle, so this takes the menu and
 * the application's own token — the same pair `ctd_menu_set_enabled` takes,
 * and for the same reason: one command, one place to describe it. Setting it
 * on a menu that is also a window's toolbar is what puts icons on the
 * toolbar, and where the platform shows icons in menus it shows them there
 * too.
 *
 * CTD_ICON_NONE takes the icon away. CTD_ERR_RANGE for a token the menu does
 * not have and for a role this host cannot draw. */
ctd_status ctd_menu_set_icon(ctd_handle menu, int64_t token, int32_t icon);

/* ---- popovers ---------------------------------------------------------- */

/* A small window anchored to a control, holding a widget subtree.
 *
 * It is not a widget and never appears as one's child: a popover is its own
 * window on every platform here, which is what lets it draw outside the window
 * that spawned it and take the keyboard while it is up. `content` is an
 * ordinary widget — usually a container — and the popover owns where it goes.
 *
 * **The content is laid out by the caller, into the size that was asked for.**
 * A popover has no layout of its own and no platform here will size one to fit
 * a subtree, so ctd_popover_new takes the size it should be and the caller
 * solves into it. Guessing on the caller's behalf would mean measuring a tree
 * the host cannot see.
 *
 * Dismissing raises CTD_EV_DISMISS with the popover as the target, whether the
 * program closed it or the user clicked away — because the program cannot tell
 * the difference from the outside either, and a state that only updates on one
 * of the two paths is a popover that is shut and thinks it is open.
 *
 * CTD_ERR_UNSUPPORTED where ctd_capability(CTD_CAP_POPOVER) answers 0. */
#define CTD_EDGE_MIN_X  0  /* to the leading side of the anchor  */
#define CTD_EDGE_MIN_Y  1  /* above it                           */
#define CTD_EDGE_MAX_X  2  /* to the trailing side               */
#define CTD_EDGE_MAX_Y  3  /* below it                           */
ctd_handle ctd_popover_new(ctd_handle content, double width, double height);
ctd_status ctd_popover_show(ctd_handle popover, ctd_handle anchor, int32_t edge);
ctd_status ctd_popover_close(ctd_handle popover);
ctd_status ctd_popover_shown(ctd_handle popover, int32_t *out);
ctd_status ctd_popover_release(ctd_handle popover);

/* ---- web views --------------------------------------------------------- */

/* A browser engine's controls. Every one of them refuses with CTD_ERR_KIND on
 * a handle that is not a CTD_W_WEB_VIEW, and with CTD_ERR_UNSUPPORTED on a
 * platform where ctd_capability(CTD_CAP_WEB) answers 0 — where the kind itself
 * cannot be built, so the first refusal a program meets is the honest one from
 * ctd_widget_new.
 *
 * **Everything here is asynchronous and says so.** A page load, a script and a
 * navigation all finish later, on the main thread, as events:
 *
 *   CTD_EV_WEB_STARTED   a load began.    `index` is a serial number.
 *   CTD_EV_WEB_FINISHED  a load finished. `index` is the same serial.
 *   CTD_EV_WEB_FAILED    it did not.      `index` is the serial, `token` the
 *                                         platform's error code.
 *   CTD_EV_WEB_MESSAGE   the page sent something. `token` keys the text.
 *   CTD_EV_WEB_RESULT    a script answered. `token` echoes the call's.
 *
 * The text of a message or a result is read with ctd_web_take, keyed by the
 * token the event carried, and is held until it is read — which is the
 * difference between this and a control's text. A control moves on and its
 * text has to come with the event; a result does not exist until it is ready
 * and cannot be overwritten by anything else. The two-call shape, and then it
 * is gone: reading twice answers empty, because a buffer nobody clears is a
 * leak with a name.
 *
 * **A page cannot reach the program except by saying so.** ctd_web_listen names
 * a channel the page can post to (`window.webkit.messageHandlers.<name>` on
 * WebKit); a page that posts to an unnamed channel is ignored. A web view with
 * no channel named is a viewer, not a bridge, and that is the default. */
ctd_status ctd_web_load(ctd_handle widget, const char *url, int32_t len);
/* Loads markup directly. `base` is the URL relative links resolve against, and
 * may be empty for none. */
ctd_status ctd_web_load_html(ctd_handle widget, const char *html, int32_t html_len,
                             const char *base, int32_t base_len);
/* Runs script in the page. The answer arrives as CTD_EV_WEB_RESULT carrying
 * `token`, and is read with ctd_web_take. */
ctd_status ctd_web_eval(ctd_handle widget, const char *source, int32_t len,
                        int64_t token);
/* Opens a channel the page can post to by name. Empty closes every channel. */
ctd_status ctd_web_listen(ctd_handle widget, const char *name, int32_t len);
/* The text an event's token names, once. Writes at most `cap` bytes and
 * answers the byte length it needs — the two-call shape. Reading twice answers
 * empty; see the note above. */
int32_t    ctd_web_take(ctd_handle widget, int64_t token, char *out, int32_t cap);
/* Where the view is now, and what the page calls itself. Both are the
 * platform's answer and may be empty before a load finishes. */
int32_t    ctd_web_url(ctd_handle widget, char *out, int32_t cap);
int32_t    ctd_web_title(ctd_handle widget, char *out, int32_t cap);
/* 1 or 0 into `out`. */
ctd_status ctd_web_can_go(ctd_handle widget, int32_t back, int32_t *out);
ctd_status ctd_web_go(ctd_handle widget, int32_t back);
ctd_status ctd_web_reload(ctd_handle widget);
ctd_status ctd_web_stop(ctd_handle widget);

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

/* ---- tabs -------------------------------------------------------------- */

/* The words on a tab view's Nth tab.
 *
 * By index rather than through the child, because a label belongs to the page
 * and not to the control on it: a page is an ordinary container, and
 * containers have no text on any platform cortado targets. The same shape as
 * ctd_table_column_title, for the same reason.
 *
 * An index past the last page is CTD_ERR_RANGE. Setting a label does not
 * create a page: a tab view has exactly as many tabs as it has children, and
 * adding a child is what adds a tab. */
ctd_status ctd_tab_set_label(ctd_handle widget, int32_t index,
                             const char *utf8, int32_t len);
/* Writes at most `cap` bytes and answers the byte length the label needs —
 * the two-call shape every text reader in this header uses. */
int32_t    ctd_tab_label(ctd_handle widget, int32_t index, char *out, int32_t cap);
/* Same contract as ctd_get_text: answers the byte length, writes at most cap. */
int32_t    ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap);

/* ---- a table ----------------------------------------------------------- */

/* A table is the one control cortado does not build out of widgets, and the
 * reason is the only one that matters: **a list long enough to need a table is
 * long enough that building it shows.**
 *
 * Everywhere else in this header a control is an object the program makes and
 * keeps. Ten thousand rows of four columns is forty thousand objects, forty
 * thousand frames for the solver to place, and a reconciler pass over all of
 * them every time one cell changes — for a screen that has thirty rows on it.
 * Every native toolkit solves this the same way and has for thirty years: the
 * control asks for the cells it is about to draw, and asks again when it
 * scrolls. NSTableView calls it a data source, Win32 calls it LVS_OWNERDATA,
 * GTK4 calls it a list model, UIKit calls it a table view data source. cortado
 * calls it the same thing all four do.
 *
 * So this is the one place where the platform calls *into* Beans rather than
 * the other way round, and the shape is the same one the event sink uses: one
 * function pointer for the whole process, registered once, routed on the
 * table's handle. Not one per table — the hazard at the top of this file
 * applies here exactly as it does to events, and a stored callback per control
 * is a leak by construction.
 *
 * The cell function answers text the way ctd_get_text does: write at most
 * `cap` bytes, answer the number of bytes the cell needs. The host calls with
 * `cap` 0 first when it wants to size a buffer, and a caller must handle that
 * by answering the length and writing nothing. A negative answer is a status.
 *
 * **What must not happen inside it.** It runs while the platform is drawing,
 * on the UI thread, and it must return: no waiting, no joining, no work that
 * can block. A cell is a lookup in something the program already has. */
typedef int32_t (*ctd_table_fn)(void *context, ctd_handle table,
                                int32_t row, int32_t column,
                                char *out, int32_t cap);

/* One source for the process, like the event sink. */
ctd_status ctd_set_table_source(ctd_table_fn source, void *context);

/* How many columns, and what each is called. Columns are set before rows:
 * a table with no columns has nothing to draw a row into, and every host
 * treats setting them as the structural change it is.
 *
 * **One platform has no second column.** A UITableView is a list — the cell
 * styles that look like two columns are a label and a detail label, not
 * columns you can size, title, or sort. Asking for more than one on iOS is
 * CTD_ERR_UNSUPPORTED rather than four columns quietly collapsed into one,
 * because a program that laid out a spreadsheet and got a list back should be
 * told while it can still do something about it. */
ctd_status ctd_table_columns(ctd_handle table, int32_t count);
ctd_status ctd_table_column_title(ctd_handle table, int32_t column,
                                  const char *utf8, int32_t len);
ctd_status ctd_table_column_width(ctd_handle table, int32_t column, double points);

/* How many rows there are. Pushed rather than pulled, because it is one
 * integer the program already knows and asking for it during a draw would be
 * a call per frame for a number that changes when the program says so. */
ctd_status ctd_table_rows(ctd_handle table, int32_t count);

/* Ask again. The contents changed; the shape did not. */
ctd_status ctd_table_reload(ctd_handle table);

/* What the *platform* has for one cell, asked through its own data source.
 *
 * Same two-call shape as ctd_get_text: answer the byte count, write at most
 * `cap`. It exists for the reason ctd_view_child_count exists — cortado knows
 * what it told the table, and bookkeeping that is never checked against the
 * thing it describes is how a table ends up correct on paper and wrong on
 * screen. This is the round trip: out through ctd_table_fn, into the
 * platform's data source, and back.
 *
 * It is also the only way to check the path at all without a display. A table
 * asks for cells when it draws, and a headless window never draws. */
int32_t    ctd_table_cell(ctd_handle table, int32_t row, int32_t column,
                          char *out, int32_t cap);

/* The selected row, or -1 for none. A status and a row in one return value is
 * how -1 ends up being read as an index, so the row goes in `out`. */
ctd_status ctd_table_selected(ctd_handle table, int32_t *out);
/* -1 clears the selection. A row outside 0..rows-1 is CTD_ERR_RANGE. */
ctd_status ctd_table_select(ctd_handle table, int32_t row);

/* ---- permission -------------------------------------------------------- */

/* What the operating system will let this program do, and how to ask.
 *
 * **This is the one part of cortado where getting it wrong kills the
 * process.** Not an error, not a refusal — macOS's privacy layer terminates a
 * program that touches a gated framework without the matching usage
 * description in its Info.plist, on a *later* turn of the run loop, in
 * unrelated code, with nothing on stderr:
 *
 *     termination namespace TCC: "This app has crashed because it attempted
 *     to access privacy-sensitive data without a usage description."
 *
 * There is no status to turn into a ctd_status, because the process is gone.
 * So the whole design here is one rule: **never touch the framework to answer
 * a question about it.**
 *
 * ctd_permission_status reads two things, both of which a bare binary with no
 * plist can read safely — proven, from a process with no bundle at all, across
 * a turn of the run loop: the Info.plist usage-description key, and the
 * framework's own *static* authorization query. `[CBCentralManager
 * authorization]`, `[AVCaptureDevice authorizationStatusForMediaType:]`,
 * `[CLLocationManager authorizationStatus]` and `CGPreflightScreenCaptureAccess`
 * are class methods and answer without constructing anything. Constructing the
 * manager or starting the session is what kills you, and nothing here does it.
 *
 * **Screen capture has no usage-description key at all** — it is a preflight
 * call and nothing else — so the guard is per permission rather than one
 * lookup with a table of key names.
 *
 * **Outside a bundle, the answer is CTD_ALLOW_UNAVAILABLE, and that is not a
 * limitation cortado could lift.** TCC answers for the *responsible* process:
 * a bare binary run from a terminal reads the terminal's grants. The probe
 * that shaped this read "microphone: authorized" from a program with no usage
 * description of any kind, because Terminal.app holds that grant. A number
 * like that is not this program's status and reporting it would be worse than
 * reporting nothing — so an unbundled process is told, plainly, that there is
 * no answer to be had. Under `beansc run` the process is `beansc`, so this is
 * always what the interpreter leg sees.
 *
 * ctd_permission_request is the other half, and it prompts. It refuses outright
 * where a prompt cannot appear — no bundle, no usage description — because the
 * alternative is the death above. The answer arrives as CTD_EV_PERMISSION with
 * the token that was passed and CTD_ALLOW_* in `index`. */

#define CTD_PERM_BLUETOOTH       1
#define CTD_PERM_LOCATION        2
#define CTD_PERM_CAMERA          3
#define CTD_PERM_MICROPHONE      4
#define CTD_PERM_SCREEN_CAPTURE  5
#define CTD_PERM_PHOTOS          6
#define CTD_PERM_MOTION          7

/* There is no answer to be had: this platform has no such thing, or the
 * process has no bundle and so no privacy identity of its own. */
#define CTD_ALLOW_UNAVAILABLE    0
#define CTD_ALLOW_GRANTED        1
#define CTD_ALLOW_DENIED         2
/* Nobody has been asked yet. ctd_permission_request is how one asks. */
#define CTD_ALLOW_UNDECIDED      3

#define CTD_EV_PERMISSION       25  /* index is CTD_ALLOW_*; token echoes    */
/* A popover went away, whether the program closed it or the user clicked
 * elsewhere. `target` is the popover. */
#define CTD_EV_DISMISS          26
#define CTD_EV_WEB_STARTED      27  /* index is the load's serial            */
#define CTD_EV_WEB_FINISHED     28  /* index is the same serial              */
#define CTD_EV_WEB_FAILED       29  /* index the serial, token the error     */
#define CTD_EV_WEB_MESSAGE      30  /* token keys the text; ctd_web_take     */
#define CTD_EV_WEB_RESULT       31  /* token echoes the eval's               */
#define CTD_EV_NET_CHANGED      32  /* index is CTD_NET_*; x is the flags     */
#define CTD_EV_POWER_CHANGED    33  /* index is CTD_POWER_*; x is the charge  */
/* Where the machine is. x and y are latitude and longitude, width the accuracy
 * in metres, height the heading in degrees or -1 where there is none. */
#define CTD_EV_LOCATION         34
/* Something was seen over Bluetooth, or one that was seen changed. `index` is
 * the device's row, which is what ctd_ble_* take; `x` is the signal strength. */
#define CTD_EV_BLE_FOUND        35
/* A peripheral was connected or dropped. `index` is the row, 1 or 0 in
 * `token` for which. */
#define CTD_EV_BLE_LINK         36
/* A camera or microphone appeared or went. `index` is how many there are. */
#define CTD_EV_CAPTURE_DEVICES  37
/* A frame of the screen is ready, or was not. `token` echoes the request's and
 * `index` is the byte length waiting — 0 where the capture failed. */
#define CTD_EV_SCREEN_FRAME     38
/* One past the last kind. It exists so a host can keep an array per kind —
 * `ctd_listen` is exactly that — and so adding a kind without widening the
 * array is a compile error rather than a write off the end of one. */
#define CTD_EV_COUNT            39

ctd_status ctd_permission_status(int32_t what, int32_t *out);
/* Asks the user. CTD_ERR_UNSUPPORTED where a prompt cannot appear — which is
 * every platform but macOS and iOS today, and on those, any process without a
 * bundle or without the usage description this permission needs.
 * CTD_ERR_RANGE for a number that is not a permission. */
ctd_status ctd_permission_request(int32_t what, int64_t token);

/* ---- introspection ----------------------------------------------------- */

/* The platform's own name for the control: "NSButton", "Button", "GtkButton".
 * Only the host can ask an object what it is, and this is the answer that
 * proves a real native control was built rather than a stand-in. */
int32_t    ctd_native_class(ctd_handle widget, char *out, int32_t cap);
/* The accessibility role in one vocabulary shared by every platform:
 * "button", "checkbox", "text", "textbox", "image", "group". */
int32_t    ctd_a11y_role(ctd_handle widget, char *out, int32_t cap);

/* Reads a widget back as pixels: 8-bit RGBA, one row after another, the top
 * row first, with no padding between rows — so the image is exactly
 * width * height * 4 bytes and a pixel is at (y * width + x) * 4.
 *
 * Same two-call shape as the text readers: ask with `cap` 0 to learn the byte
 * count, then ask again with a buffer that size. `out_size` is filled on both
 * calls, so one call is enough to learn the dimensions. Answers the number of
 * bytes the image needs, or a negative ctd_status.
 *
 * Pixels are in **points, not backing pixels**: a 100-point view answers a
 * 100-pixel-wide image on a Retina display as well as on a plain one, because
 * a test that asserted a pixel would otherwise answer differently depending on
 * which monitor the machine happened to have.
 *
 * This is the only way to find out whether anything was actually *drawn*.
 * Every other query in this header reads a property the program itself set;
 * this one asks the platform what it painted. A widget that is hidden, or
 * whose size is zero, paints nothing and says so with CTD_ERR_RANGE.
 *
 * CTD_ERR_UNSUPPORTED where ctd_capability(CTD_CAP_SNAPSHOT) answers no. */
int32_t    ctd_snapshot(ctd_handle widget, double *out_size, char *out, int32_t cap);

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

/* ---- input -------------------------------------------------------------- */

/* The pointer, the keyboard, and where the keys go.
 *
 * Every kind below was declared in this header from the first version and
 * emitted by nobody: `CTD_EV_POINTER_DOWN`, `CTD_EV_KEY_DOWN` and
 * `CTD_EV_FOCUS` appeared in the header and in no host, no binding and no
 * test. A control could be clicked and would raise `CTD_EV_ACTIVATE`; nothing
 * could say *where* it was clicked, what was typed into it, or which control
 * the keyboard was pointing at. This section is what closes that.
 *
 * **No two of these platforms deliver input the same way, and one of them has
 * no way to fake it at all.**
 *
 *   * AppKit routes everything through -[NSApplication sendEvent:], and a
 *     local event monitor sees every event before any control does. One hook
 *     for the whole application — which is the shape cortado wants anyway,
 *     because the rule here is one sink and a route on an integer.
 *   * GTK4 has no global hook: a GtkEventController is attached to a widget,
 *     so the host attaches one set per control as it builds it.
 *   * Win32 sends WM_LBUTTONDOWN and WM_KEYDOWN to the control, which forwards
 *     to its parent — which is the shape the host already uses for everything
 *     else.
 *   * UIKit is GTK4's shape again, a recognizer per control.
 *
 * **Synthesising input is how this is tested, and the two families differ in
 * what that proves.** AppKit and Win32 take a real event: cortado builds an
 * NSEvent and posts it, or sends a WM_ message, and it travels the path a
 * mouse travels. GTK4 cannot — GdkEvent has public getters and no public
 * constructor, so no program outside GTK can build one — and UIKit will not
 * let a gesture recognizer be fired from outside either. On those two the
 * synthesised call emits the controller's own signal, which is the same
 * handler a real event reaches and one step short of the platform's dispatch.
 * That difference is written here rather than hidden, because a test that
 * proved less than it looked like it proved would be worse than no test. */

/* Which pointer button, in `index` of a pointer event. A trackpad's tap is
 * CTD_BTN_LEFT everywhere, and a two-finger tap is CTD_BTN_RIGHT everywhere,
 * because that is what each platform already calls them. */
#define CTD_BTN_LEFT     1
#define CTD_BTN_RIGHT    2
#define CTD_BTN_MIDDLE   3

/* Which key, in `index` of a key event.
 *
 * **There is no code here for a letter, a digit or a punctuation mark, and
 * that is the design rather than an omission.** A code per character is a
 * keyboard layout written into an ABI: the key to the left of "1" is a
 * different character on a US, a German and a French keyboard, and the key
 * that types "z" on one types "y" on another. What a program wants to know
 * about those keys is what was *typed*, which arrives as `text` — already
 * composed, already through the input method, correct for a Japanese keyboard
 * and for a dead-key accent. So every such key is CTD_KEY_CHARACTER and the
 * news is in `text`.
 *
 * What is enumerated is the keys that type nothing and mean the same thing on
 * every keyboard there is. A program listening for Escape, or for the arrow
 * that moves a selection, is asking about the key and not about a character —
 * and those are the same keys everywhere. */
/* **A control character is not text.** Every platform here reports Escape as
 * U+001B, Tab as U+0009 and Return as U+000D — X11 keysyms carry the ASCII
 * control code and -[NSEvent characters] answers the same — so a host that
 * passed the character through would report that Escape "typed" something,
 * and a field appending what it hears would fill up with control codes. So a
 * key event's `text` is empty for everything below U+0020 and for U+007F, and
 * a key that types nothing says so by saying nothing. Space is U+0020 and is
 * text, which is why the bound is where it is. */
#define CTD_KEY_UNKNOWN     0
#define CTD_KEY_CHARACTER   1  /* the news is in `text`                       */
#define CTD_KEY_ESCAPE      2
#define CTD_KEY_TAB         3
#define CTD_KEY_RETURN      4
#define CTD_KEY_SPACE       5  /* types " ", and is also a button's key       */
#define CTD_KEY_BACKSPACE   6
#define CTD_KEY_DELETE      7
#define CTD_KEY_LEFT        8
#define CTD_KEY_RIGHT       9
#define CTD_KEY_UP         10
#define CTD_KEY_DOWN       11
#define CTD_KEY_HOME       12
#define CTD_KEY_END        13
#define CTD_KEY_PAGE_UP    14
#define CTD_KEY_PAGE_DOWN  15
#define CTD_KEY_F1         16
#define CTD_KEY_F2         17
#define CTD_KEY_F3         18
#define CTD_KEY_F4         19
#define CTD_KEY_F5         20
#define CTD_KEY_F6         21
#define CTD_KEY_F7         22
#define CTD_KEY_F8         23
#define CTD_KEY_F9         24
#define CTD_KEY_F10        25
#define CTD_KEY_F11        26
#define CTD_KEY_F12        27
#define CTD_KEY_COUNT      28

/* cortado's own name for a key — "escape", "page_up", "f7". One word per key
 * and the same word on every platform, which is what a golden can compare and
 * what a `.bx` attribute can spell.
 *
 * It exists for the same reason `ctd_icon_name` does: a table of names is
 * exactly the kind of thing that ends up with two rows sharing a word and
 * nobody noticing, and the only way a suite can check that is to be able to
 * ask. CTD_ERR_RANGE for a number that is not a key. */
int32_t    ctd_key_name(int32_t key, char *out, int32_t cap);

/* Where the keyboard is pointing.
 *
 * A program moves it: a form that opens with the cursor in the first field, a
 * dialog that puts it on the text rather than the button. Doing so raises
 * CTD_EV_BLUR on whatever had it and CTD_EV_FOCUS on what takes it — and
 * unlike every other write in this header **that is not silent**, because
 * focus is not a control's private state. It is one thing the whole window
 * shares, and a program that moved it has by definition changed what every
 * other control shows.
 *
 * CTD_ERR_UNSUPPORTED for a control that cannot take the keyboard at all — a
 * label, an image, a progress bar. */
ctd_status ctd_widget_focus(ctd_handle widget);
/* 1 where this control has the keyboard, 0 where it does not or cannot. */
int32_t    ctd_widget_focused(ctd_handle widget);

/* Clicks and types the way a user would, and raises the events that follow.
 *
 * The pointer pair to `ctd_widget_synth_value`, and the same argument: a
 * program that sets a value should not hear its own write, so a test needs a
 * way in that is not a write. `x` and `y` are in the widget's own space, the
 * same space `ctd_view_set_frame` uses, so a caller that knows where a control
 * is knows where to click it.
 *
 * `what` is CTD_EV_POINTER_DOWN, _UP or _MOVE; anything else is CTD_ERR_RANGE,
 * as is a button that is not a CTD_BTN_*. A move ignores `button`.
 *
 * **A button a platform's pointer does not have is CTD_ERR_UNSUPPORTED.** A
 * finger has one and only one, and there is no gesture on a phone that means
 * "right click" — a long press is a long press, and what it is for is the
 * application's decision. Answering with a left click instead would hand a
 * program an event it did not ask for and cannot tell from a real one. */
ctd_status ctd_widget_synth_pointer(ctd_handle widget, int32_t what,
                                    double x, double y, int32_t button);
/* `what` is CTD_EV_KEY_DOWN or _UP. `key` is a CTD_KEY_*; `text` is what the
 * key typed, which is empty for every key that types nothing and is the whole
 * news for CTD_KEY_CHARACTER. `modifiers` is a CTD_MOD_* mask. */
ctd_status ctd_widget_synth_key(ctd_handle widget, int32_t what, int32_t key,
                                const char *text, int32_t len,
                                uint32_t modifiers);

/* Whether anything is listening for a kind of event.
 *
 * The one call in this header that exists for a cost rather than for a
 * capability, and the cost is real: AppKit does not generate mouse-moved
 * events for a window until it is told to want them, and a pointer that
 * reports a thousand times a second is a thousand crossings into the program
 * per second for something nobody asked about. So the binding tells the host
 * when the first handler for a kind arrives and when the last one goes, and a
 * host asks its platform for only the work somebody wants.
 *
 * It is advice, not permission: a host that cannot turn a kind off answers
 * CTD_OK and keeps delivering, and the binding drops what nobody wants. What
 * it must never do is deliver a kind it was never asked for *and* charge the
 * platform for it. CTD_ERR_RANGE for a number that is not an event kind. */
ctd_status ctd_listen(int32_t kind, int32_t on);

/* ---- what happens to a surface ------------------------------------------ */

/* Four things a window is told and, until now, told nobody.
 *
 * CTD_EV_SURFACE_RESIZED, CTD_EV_SURFACE_CLOSE, CTD_EV_APPEARANCE and
 * CTD_EV_SCALE_CHANGED were declared at the top of this header from its first
 * version. Win32 raised all four; macOS and GTK4 raised none and iOS raised
 * one. A program could not save the size its window was left at, could not ask
 * "are you sure?" before it closed, and could not redraw what it had drawn
 * itself when the system went dark — which `platform/appearance.b` has been
 * promising in a doc comment the whole time.
 *
 * **A resize is the user's, and the program's own is silent.** Every other
 * write in this header is silent for the same reason, and a window is the
 * control where hearing your own write costs the most: a layout that re-solves
 * on a resize it caused re-solves for ever.
 *
 * **CTD_EV_SURFACE_CLOSE is a veto, and what decides it is whether anyone is
 * listening.** A handler cannot answer back — the one callback edge in this
 * ABI has no return value that could carry a yes or a no — so the question is
 * settled before the event is raised, by the only thing the host already
 * knows: `ctd_listen`.
 *
 * A program with no close handler gets the window closed, which is what every
 * platform does on its own and what a user pressing the button expects. A
 * program *with* one gets the event and a window that is still there, and
 * closes it with `ctd_surface_close` when it is ready — after asking "save
 * your changes?", or never. Nothing is lost either way and neither case needs
 * a program to know which platform it is on.
 *
 * The three hosts that can close a window disagreed about this before it was
 * written down: AppKit and GTK4 closed it and Win32 did not. */

/* Drives one of the four the way the platform would, for a test and for a
 * program replaying a session.
 *
 * **Two of these take the real road and two cannot, and the difference is
 * worth knowing before writing a test around it.** A resize really resizes the
 * window, so the platform's own notification is what arrives; a close really
 * asks the window to close. Neither is a shortcut. But no program can change
 * the system's appearance or the scale of a display — those are the system's,
 * and a call that really did it would be a call that reached outside the
 * program — so for those two this raises the event directly. What that proves
 * is everything above the platform: the listen gate, the routing and the
 * payload; what it cannot prove is that the platform calls cortado when a
 * person moves the slider in System Settings.
 *
 * `what` is one of the four kinds; anything else is CTD_ERR_RANGE. `a` and `b`
 * are the new width and height for a resize, `a` is 0 for light and 1 for dark, or the
 * new scale for those two, and both are ignored for a close. */
ctd_status ctd_surface_synth(ctd_handle surface, int32_t what,
                             double a, double b);

/* ---- the machine ------------------------------------------------------- */

/* Two questions an application asks about the computer it is on rather than
 * about anything it drew: **can I reach anything, and what is this costing.**
 *
 * Neither is gated. Proven from a bare binary with no bundle and no usage
 * description, across a turn of the run loop — which is where a privacy death
 * lands — so unlike everything under "permission" these answer for real under
 * `beansc run` and on the ordinary test legs. Nothing here constructs a
 * CoreLocation or CoreBluetooth object, and nothing here can.
 *
 * **The path is a push on one platform and a pull on the others, and this ABI
 * is written for the push.** `nw_path_monitor` has no synchronous read at all:
 * it starts, and some time later it calls back. Windows and Linux can be asked
 * directly and synthesise the push. So `ctd_net_path` answers *the last thing
 * that was heard*, and CTD_NET_UNKNOWN before anything has been — a program
 * asks, lets the loop turn once, and asks again, which is what an application
 * does anyway and what `tests/machine.b` does. The alternative was a blocking
 * read, and a blocking read on the UI thread is a beachball whenever the
 * answer is slow.
 *
 * **`ctd_listen` is the watch.** There is no ctd_net_watch and no
 * ctd_power_watch: a host already learns that somebody wants a kind of event
 * the moment the first handler is registered, and starting the platform's
 * monitor there is the same decision `ctd_listen` was written for — do the
 * work somebody asked for and no other. Asking `ctd_net_path` also starts one,
 * so a program that only ever wants the answer once does not have to register
 * a handler to get it. */

#define CTD_NET_UNKNOWN    0  /* nothing has answered yet                    */
#define CTD_NET_NONE       1  /* answered, and there is no path              */
#define CTD_NET_WIFI       2
#define CTD_NET_WIRED      3
#define CTD_NET_CELLULAR   4
#define CTD_NET_OTHER      5  /* a path over something with no name here     */

/* Flags, because a path is several things at once. */
#define CTD_NET_F_EXPENSIVE    1  /* cellular, or somebody's hotspot         */
#define CTD_NET_F_CONSTRAINED  2  /* Low Data Mode, or a metered connection  */

/* Writes the kind into `out_kind` and the flags into `out_flags`; either may be
 * NULL. CTD_ERR_UNSUPPORTED where CTD_CAP_NETWORK answers 0. */
ctd_status ctd_net_path(int32_t *out_kind, int32_t *out_flags);

#define CTD_POWER_UNKNOWN  0
#define CTD_POWER_MAINS    1
#define CTD_POWER_BATTERY  2

/* What is running the machine. A desktop with no battery answers MAINS. */
ctd_status ctd_power_source(int32_t *out);
/* How full the battery is, 0 to 1. CTD_ERR_UNSUPPORTED where there is no
 * battery at all, which is a real answer and not a missing feature: a desktop
 * has none and a program drawing a meter should draw nothing rather than a
 * full one. */
ctd_status ctd_power_charge(double *out);
/* Whether the system is in its own low-power mode — Low Power Mode, Power
 * Saver, a power profile. 1 or 0. */
ctd_status ctd_power_saving(int32_t *out);

/* How hot the machine is, which is the number that says whether to do less.
 *
 * **Only Apple's platforms have a scale for this**, and inventing one for the
 * others from a temperature in a sysfs file would be inventing a number: what
 * counts as hot depends on the machine, and the scale is the operating
 * system's judgement rather than a reading. So the honest answer elsewhere is
 * CTD_THERMAL_UNKNOWN, and a program that throttles itself asks and does
 * nothing when nobody knows. */
#define CTD_THERMAL_UNKNOWN  0
#define CTD_THERMAL_NOMINAL  1
#define CTD_THERMAL_FAIR     2
#define CTD_THERMAL_SERIOUS  3
#define CTD_THERMAL_CRITICAL 4

ctd_status ctd_thermal_state(int32_t *out);

/* ---- the gated four ---------------------------------------------------- */

/* Where the machine is, what is nearby, what it can see and hear, and what is
 * on its screen.
 *
 * **Every call in this section can end the process, and the guard is the same
 * one for all of them.** macOS does not return an error when a program touches
 * a privacy-gated framework without the matching usage description in its
 * Info.plist — it terminates the program, on a later turn of the run loop, in
 * unrelated code, with nothing on stderr. There is no status to turn into a
 * ctd_status because there is no process left to return one.
 *
 * So nothing here touches a framework until three things are true: the process
 * has a bundle, the bundle declares what it wants the permission for, and the
 * permission is not already denied. All three are read from the Info.plist and
 * from the static authorization queries beside ctd_permission_status, none of
 * which constructs anything. A call that fails any of them answers
 * CTD_ERR_UNSUPPORTED and touches nothing.
 *
 * **That makes every one of these unreachable under `beansc run`**, where the
 * process is `beansc` and carries no such keys, and unreachable from any
 * program that was not built into a bundle. It is not a limitation cortado
 * could lift: TCC answers for the *responsible* process, so a bare binary run
 * from a terminal reads the terminal's grants, and reporting those as the
 * program's own would be worse than reporting nothing. `tools/bundle.sh`
 * builds the bundle these need, and cortado's own suite runs them through it.
 *
 * Windows and Linux answer CTD_ERR_UNSUPPORTED for all of it behind the four
 * CTD_CAP_* above. The shape is here so a host can be written later without
 * this header changing; what is not here is a pretence that one has been. */

/* ---- where the machine is ---- */

/* Starts and stops the platform's own location updates. Answers arrive as
 * CTD_EV_LOCATION. CTD_ERR_UNSUPPORTED where the guard above says no. */
ctd_status ctd_location_start(void);
ctd_status ctd_location_stop(void);
/* The last fix, into out[0..3]: latitude, longitude, accuracy in metres, and
 * heading in degrees — or -1 for a heading this platform does not report. A
 * fix that has not arrived yet is CTD_ERR_STATE rather than four zeroes, which
 * are a real place in the Gulf of Guinea. */
ctd_status ctd_location_last(double *out);

/* ---- what is nearby ---- */

/* Starts and stops a scan. Everything seen is a *row*, numbered from zero in
 * the order it was first seen, and a row keeps its number for as long as the
 * scan does — which is what lets an event name one without carrying a string.
 * CTD_EV_BLE_FOUND when a row appears or its signal changes. */
ctd_status ctd_ble_scan(int32_t on);
/* How many rows there are. */
int32_t    ctd_ble_count(void);
/* The name a peripheral advertises, which is often empty: a device is not
 * obliged to say what it is, and most do not until they are connected. */
int32_t    ctd_ble_name(int32_t row, char *out, int32_t cap);
/* The identifier the platform uses for it, which is stable for this machine
 * and this device and is *not* the hardware address — Apple does not hand that
 * out. It is what a program stores to recognise the same device tomorrow. */
int32_t    ctd_ble_id(int32_t row, char *out, int32_t cap);
/* Signal strength in dBm, which is negative and closer to zero when nearer. */
ctd_status ctd_ble_signal(int32_t row, double *out);
/* Connects or drops. The answer is CTD_EV_BLE_LINK, because a connection takes
 * as long as it takes. */
ctd_status ctd_ble_connect(int32_t row, int32_t on);
/* 1 while connected. */
int32_t    ctd_ble_linked(int32_t row);

/* ---- what it can see and hear ---- */

#define CTD_CAPTURE_CAMERA      0
#define CTD_CAPTURE_MICROPHONE  1

/* How many of a kind there are, and what each is called. The list is the
 * platform's and the order is the platform's; what cortado promises is that a
 * row keeps its number until CTD_EV_CAPTURE_DEVICES says the list changed. */
int32_t    ctd_capture_count(int32_t kind);
int32_t    ctd_capture_name(int32_t kind, int32_t row, char *out, int32_t cap);
/* Whether this is the one the system would pick. A program that offers a list
 * should have it already selected. */
int32_t    ctd_capture_is_default(int32_t kind, int32_t row);

/* ---- what is on the screen ---- */

/* How many displays can be recorded, and the pixel size of one. */
int32_t    ctd_screen_count(void);
ctd_status ctd_screen_size(int32_t display, double *out);

/* One frame of a display, which **takes time and so is asked for rather than
 * returned.**
 *
 * There used to be a plain call for this — `CGDisplayCreateImage` — and macOS
 * 15 removed it, not deprecated it: the symbol is marked unavailable and a
 * program that used it no longer builds. What replaced it is ScreenCaptureKit,
 * where a frame arrives on a queue some time later. So this is the shape the
 * rest of the ABI already uses for anything slow: ask with a token, and the
 * answer arrives as CTD_EV_SCREEN_FRAME carrying it back.
 *
 * `index` on that event is the byte length waiting, or 0 where the capture
 * failed; `ctd_screen_take` reads it, once, and forgets it. Once, because a
 * screen is large — a Retina display is thirty megabytes a frame — and holding
 * the last one for a caller that may never ask would be thirty megabytes this
 * library keeps for nothing. */
ctd_status ctd_screen_capture(int32_t display, int64_t token);
/* The pixels a token is holding, as the same 8-bit RGBA `ctd_snapshot`
 * answers, through the same two-call shape: `out` NULL answers the byte
 * length. Writes the pixel size into out_size[0..1]. A token nobody filled in,
 * or one already taken, is CTD_ERR_STATE. */
int32_t    ctd_screen_take(int64_t token, double *out_size,
                           uint8_t *out, int32_t cap);

#endif /* CORTADO_HOST_H */
