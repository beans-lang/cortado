/* The parts of the contract that are the same code on every host.
 *
 * `cortado_host.h` is the contract's *shape* — what each platform must
 * implement. This file is the contract's *decisions*: the questions whose
 * answer is cortado's rather than any platform's, written once so four hosts
 * cannot drift into four answers.
 *
 * It is a separate header rather than a `static inline` in `cortado_host.h`
 * for a mechanical reason: `tools/check_hosts.sh` and `tools/check_abi.sh`
 * read every `ctd_*(` in that file as an entry point every host must define
 * and every binding must bind. A helper there would be demanded of both.
 */
#ifndef CORTADO_RULES_H
#define CORTADO_RULES_H

#include <stdint.h>
#include "cortado_host.h"

/* Whether a kind carries CTD_P_ENABLED — the rule stated in full beside
 * CTD_P_ENABLED in cortado_host.h.
 *
 * A widget has an enabled state exactly when it accepts input. Everything
 * else answers CTD_ERR_KIND, on every host, from both the setter and the
 * getter.
 *
 * Before this existed each host asked its own object system instead, and the
 * object systems disagree: a label is an NSControl and is not a UIControl, and
 * every GtkWidget is sensitive. That is not a difference between platforms, it
 * is four guesses at a question nobody had answered. */
static inline int ctd_kind_has_enabled(int32_t kind) {
    return kind == CTD_W_BUTTON
        || kind == CTD_W_TEXT_FIELD
        || kind == CTD_W_SECURE_FIELD
        || kind == CTD_W_SEARCH_FIELD
        || kind == CTD_W_CHECK_BOX
        || kind == CTD_W_RADIO_BUTTON
        || kind == CTD_W_SWITCH
        || kind == CTD_W_SLIDER
        || kind == CTD_W_STEPPER
        || kind == CTD_W_COMBO_BOX
        || kind == CTD_W_SEGMENTED
        || kind == CTD_W_DATE_PICKER
        || kind == CTD_W_COLOR_WELL;
}

/* Why no container is in that list, including the one with a button in it.
 *
 * A disclosure's header is pressed, so "it accepts input" is arguably true of
 * it — and it still answers CTD_ERR_KIND, because the platforms do not agree
 * on what a disabled container *is*. GtkWidget's sensitivity greys the whole
 * subtree, children included; AppKit has no setEnabled: on a plain NSView at
 * all; UIKit has neither. A property that meant "the header is dim" on two
 * platforms and "everything inside is dim" on a third is exactly the kind of
 * per-host answer this file exists to prevent. A screen that wants a shut
 * section disables the controls inside it, which means the same thing
 * everywhere. */

/* Whether a kind shows words while it is empty.
 *
 * Every single-line field does, and nothing else. A text area could —
 * NSTextView and GtkTextView both have a placeholder of sorts — but neither
 * has one cortado could read back, and a string that goes in and does not come
 * out is worse than one that is refused. */
static inline int ctd_kind_has_hint(int32_t kind) {
    return kind == CTD_W_TEXT_FIELD
        || kind == CTD_W_SECURE_FIELD
        || kind == CTD_W_SEARCH_FIELD;
}

/* Whether a kind carries a number in a range — CTD_P_MIN, CTD_P_MAX and
 * CTD_P_VALUE.
 *
 * A slider and a stepper are numbers the user moves; a progress bar and a
 * level indicator are numbers the program shows. Nothing else has one.
 *
 * Written down here because the classes lie. A spinner is an
 * `NSProgressIndicator` on macOS — the same class as a progress bar — so a
 * host that asked the object would let a spinner take a range it has no
 * meaning for, and only on that one platform. A spinner makes no claim about
 * how much is left; that is the whole difference between it and a bar. */
static inline int ctd_kind_has_range(int32_t kind) {
    return kind == CTD_W_SLIDER
        || kind == CTD_W_STEPPER
        || kind == CTD_W_PROGRESS_BAR
        || kind == CTD_W_LEVEL_INDICATOR;
}

/* Whether a kind carries a day. Only a date picker. */
/* Which widgets carry CTD_P_ICON.
 *
 * A button and an image view, and nothing else. A label is text — a platform
 * that draws a picture beside it is drawing a different control, and cortado
 * naming that "a label with an icon" would make one word mean two things on
 * four platforms. A menu item is not a widget and has its own call,
 * ctd_menu_set_icon, which is also how a toolbar gets icons.
 *
 * Here rather than in each host for the reason every rule in this file is
 * here: four hosts deciding separately is four answers. */
static inline int ctd_kind_has_icon(int32_t kind) {
    return kind == CTD_W_BUTTON || kind == CTD_W_IMAGE_VIEW;
}

static inline int ctd_kind_has_date(int32_t kind) {
    return kind == CTD_W_DATE_PICKER;
}

/* Whether a kind carries a colour. Only a colour well.
 *
 * Not the same question as CTD_P_BG_COLOR would be, if it existed: a colour
 * well's colour is its *value*, the thing the user changes, and every other
 * control's colour would be its appearance. */
static inline int ctd_kind_has_color(int32_t kind) {
    return kind == CTD_W_COLOR_WELL;
}

/* Midnight UTC of the day `seconds` falls in.
 *
 * The rule stated beside CTD_W_DATE_PICKER: a date picker holds a day, so a
 * host floors on the way in and every host answers the same number. Written
 * here rather than four times because four floors is four chances to round the
 * wrong way on a negative number — which is the case that bites, since
 * truncating -1 toward zero gives 1969-12-31T00:00 the value of 1970-01-01 and
 * loses a day. This one floors toward minus infinity, so the day before the
 * epoch is the day before the epoch. */
static inline double ctd_date_floor(double seconds) {
    double day = 86400.0;
    double days = seconds / day;
    double whole = (double)(long long)days;
    if (days < 0.0 && whole != days) whole -= 1.0;
    return whole * day;
}

/* Whether `value` is a colour CTD_P_COLOR can hold: 0xRRGGBBAA and nothing
 * above it. */
static inline int ctd_color_in_range(int64_t value) {
    return value >= 0 && value <= 0xFFFFFFFFLL;
}

/* The four channels of a packed colour, and the way back.
 *
 * Here rather than in four hosts because a shift written four times is four
 * chances to spell the order differently, and a host that read alpha out of
 * the top byte would look right in every test that used an opaque colour.
 *
 * `ctd_color_byte` rounds rather than truncates, and it is worth being precise
 * about why, because the obvious reason is not true: a byte written as
 * v/255.0 and read back comes out as v either way, through a float or a
 * double, for all 256 values. Measured, not assumed.
 *
 * Rounding is for the colours cortado did not write. A colour the *user* picks
 * out of the platform's chooser is an arbitrary triple — often in Display P3,
 * converted into sRGB on the way out — and truncating one is a systematic
 * half-a-level bias toward black on every channel of every such colour.
 * Nothing in a headless suite can produce one, so this is a rule kept because
 * it is right rather than because a golden would catch it. */
static inline int32_t ctd_color_red(int64_t c)   { return (int32_t)((c >> 24) & 0xFF); }
static inline int32_t ctd_color_green(int64_t c) { return (int32_t)((c >> 16) & 0xFF); }
static inline int32_t ctd_color_blue(int64_t c)  { return (int32_t)((c >>  8) & 0xFF); }
static inline int32_t ctd_color_alpha(int64_t c) { return (int32_t)( c        & 0xFF); }

static inline int32_t ctd_color_byte(double unit) {
    double scaled = unit * 255.0 + 0.5;
    if (scaled <= 0.0) return 0;
    if (scaled >= 255.0) return 255;
    return (int32_t)scaled;
}

static inline int64_t ctd_color_pack(int32_t r, int32_t g, int32_t b, int32_t a) {
    return ((int64_t)(r & 0xFF) << 24) | ((int64_t)(g & 0xFF) << 16)
         | ((int64_t)(b & 0xFF) <<  8) |  (int64_t)(a & 0xFF);
}

/* Whether a kind can be opened and shut. Only a disclosure.
 *
 * Not the same question as CTD_P_HIDDEN, which every view has: hiding a
 * disclosure takes the whole control away, title and all. This is about what
 * is *under* the title. */
static inline int ctd_kind_has_expanded(int32_t kind) {
    return kind == CTD_W_DISCLOSURE;
}

/* Whether a kind holds children the caller adds.
 *
 * Stated here because four hosts had four ways of deciding it — AppKit asked
 * whether the object was an NSTextView, GTK asked whether it was a GtkFixed,
 * and neither question is "is this a container". A kind that holds children is
 * a fact about the kind. */
static inline int ctd_kind_holds_children(int32_t kind) {
    return kind == CTD_W_CONTAINER
        || kind == CTD_W_SCROLL_VIEW
        || kind == CTD_W_GROUP_BOX
        || kind == CTD_W_DISCLOSURE
        || kind == CTD_W_TAB_VIEW
        || kind == CTD_W_SPLIT_VIEW
        || kind == CTD_W_CANVAS;
}

/* Whether a kind divides its children with a handle the user can drag.
 *
 * Only a split view, and it is the one kind whose children the *platform*
 * positions: NSSplitView and GtkPaned both lay their panes out from the
 * divider's position and neither can be talked out of it. */
static inline int ctd_kind_has_divider(int32_t kind) {
    return kind == CTD_W_SPLIT_VIEW;
}

/* Whether a kind holds its children as pages, one showing at a time.
 *
 * The distinction matters to every host's add-a-child path: a page is not a
 * subview of the control, it is a page *of* it, and the platform owns where it
 * goes and whether it is on screen at all. */
static inline int ctd_kind_holds_pages(int32_t kind) {
    return kind == CTD_W_TAB_VIEW;
}

/* Whether a kind carries somewhere to go. Only a link. */
static inline int ctd_kind_has_url(int32_t kind) {
    return kind == CTD_W_LINK;
}

/* Whether a kind can be turning. Only a spinner: a progress bar's
 * indeterminate mode is CTD_P_INDETERMINATE and means something else — that
 * the *total* is unknown, not that the control is animating. */
static inline int ctd_kind_has_animating(int32_t kind) {
    return kind == CTD_W_SPINNER;
}

/* Whether a kind carries CTD_P_CHECKED — the rule stated in full beside
 * CTD_P_CHECKED in cortado_host.h.
 *
 * Being checked has to be what the control *is*, not something its class
 * happens to support. AppKit makes a push button, a check box, a radio and a
 * switch out of the same two classes, so asking the object answered yes for
 * all four; GTK and Win32 asked a different question and answered differently.
 * This is the question. */
static inline int ctd_kind_has_checked(int32_t kind) {
    return kind == CTD_W_CHECK_BOX
        || kind == CTD_W_RADIO_BUTTON
        || kind == CTD_W_SWITCH;
}

/* Whether a kind has the third, mixed state.
 *
 * Only a check box. A radio is one of a set and a switch is one thing; neither
 * has a third position, so 2 is out of range for them rather than unsupported.
 * Whether the platform can *show* mixed is a separate question with a separate
 * answer — see the CTD_ERR_UNSUPPORTED paragraph in the header. */
static inline int ctd_kind_has_mixed(int32_t kind) {
    return kind == CTD_W_CHECK_BOX;
}

/* Whether `value` is a state CTD_P_CHECKED can hold on this kind.
 *
 * One place, because the three questions it folds together — is it a state at
 * all, is it the third one, does this kind have a third one — are the three
 * each host used to answer for itself. */
static inline int ctd_checked_in_range(int32_t kind, int64_t value) {
    if (value < 0 || value > 2) return 0;
    if (value == 2) return ctd_kind_has_mixed(kind);
    return 1;
}

/* What cortado means by each curve, as a function from 0..1 onto 0..1.
 *
 * A decision rather than a platform's. "Ease in" is a word, and four platforms
 * left to themselves would spell it four ways. On macOS and iOS the name is
 * handed to CAMediaTimingFunction and this arithmetic is never run — but the
 * four curves there are these four curves, which is why the definition belongs
 * in this file even though only two hosts evaluate it.
 *
 * The shapes are the cubic beziers CAMediaTimingFunction uses, solved rather
 * than approximated: ease-in is (0.42, 0) to (1, 1), ease-out (0, 0) to
 * (0.58, 1), and ease-in-ease-out (0.42, 0) to (0.58, 1).
 *
 * What is *not* promised is that two hosts sample the same value at the same
 * instant. They cannot: a Core Animation runs on the render server against its
 * own frame times. What is promised is the same shape, the same start, the
 * same end and the same duration. */
static inline double ctd_bezier_axis(double a, double b, double s) {
    double inv = 1.0 - s;
    return 3.0 * inv * inv * s * a + 3.0 * inv * s * s * b + s * s * s;
}

static inline double ctd_bezier_slope(double a, double b, double s) {
    double inv = 1.0 - s;
    return 3.0 * inv * inv * a
         + 6.0 * inv * s * (b - a)
         + 3.0 * s * s * (1.0 - b);
}

/* The curve parameter at which the bezier's x reaches `t`.
 *
 * Newton first because it converges in three or four steps over almost all of
 * the range, then bisection, because Newton can walk out of [0, 1] where the
 * curve is nearly flat and bisection cannot. Every browser's implementation of
 * cubic-bezier() has the same two halves for the same reason. */
static inline double ctd_bezier_solve(double x1, double x2, double t) {
    double s = t;
    for (int step = 0; step < 8; step++) {
        double error = ctd_bezier_axis(x1, x2, s) - t;
        if (error > -1e-7 && error < 1e-7) return s;
        double slope = ctd_bezier_slope(x1, x2, s);
        if (slope < 1e-7 && slope > -1e-7) break;
        s -= error / slope;
    }
    double low = 0.0;
    double high = 1.0;
    s = t;
    for (int step = 0; step < 32; step++) {
        double x = ctd_bezier_axis(x1, x2, s);
        if (x > t) high = s; else low = s;
        s = (low + high) * 0.5;
    }
    return s;
}

/* How far along a curve is at `t`, where both are fractions from 0 to 1. */
static inline double ctd_curve_apply(int32_t curve, double t) {
    double x1, y1, x2, y2;
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    switch (curve) {
        case CTD_CURVE_EASE_IN:     x1 = 0.42; y1 = 0.0; x2 = 1.00; y2 = 1.0; break;
        case CTD_CURVE_EASE_OUT:    x1 = 0.00; y1 = 0.0; x2 = 0.58; y2 = 1.0; break;
        case CTD_CURVE_EASE_IN_OUT: x1 = 0.42; y1 = 0.0; x2 = 0.58; y2 = 1.0; break;
        default:                    return t;     /* CTD_CURVE_LINEAR */
    }
    return ctd_bezier_axis(y1, y2, ctd_bezier_solve(x1, x2, t));
}

static inline int ctd_curve_is_known(int32_t curve) {
    return curve >= CTD_CURVE_LINEAR && curve <= CTD_CURVE_EASE_IN_OUT;
}

/* Whether a property key names something an animation can move.
 *
 * Stated once here rather than four times, because "what can be animated" is
 * cortado's answer and not a platform's — and because a key one host animated
 * and another refused would be the CTD_P_ENABLED mistake made twice. */
static inline int ctd_property_animates(int32_t property) {
    return property == CTD_P_OPACITY;
}

#endif
