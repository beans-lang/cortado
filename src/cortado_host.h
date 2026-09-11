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

#define CTD_ABI_VERSION 3

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
#define CTD_P_STEP        10  /* a slider's increment; 0 for continuous      */
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
 * That is CTD_W_BUTTON, CTD_W_TEXT_FIELD, CTD_W_CHECK_BOX, CTD_W_RADIO_BUTTON,
 * CTD_W_SLIDER and CTD_W_COMBO_BOX. Every other kind answers CTD_ERR_KIND from
 * both `ctd_set_int` and `ctd_get_int`, on every host.
 *
 * A label, an image, a separator and a progress bar take no input, so there is
 * nothing for "disabled" to turn off; what a caller actually wants for one of
 * those is a dimmed *look*, which is CTD_P_OPACITY and a different question. A
 * container and a scroll view are refused for a second reason as well: they
 * exist to hold children, and answering for the box would be answering for
 * everything inside it.
 *
 * `tests/enabled.out` is this paragraph as a golden, one line per kind, and it
 * is a cross-host file — so a host that guesses again prints different bytes.
 */

/* CTD_ERR_RANGE when the bytes contain a zero: see rule 3 at the top. */
ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len);
/* Answers the byte length the text needs, and writes at most `cap` bytes.
 * Call with cap 0 to size the buffer. A negative return is a ctd_status. */
int32_t    ctd_get_text(ctd_handle widget, char *out, int32_t cap);
ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value);
ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out);
ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value);
ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out);

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

#endif /* CORTADO_HOST_H */
