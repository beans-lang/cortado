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
        || kind == CTD_W_COMBO_BOX;
}

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
