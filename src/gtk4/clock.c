// The frame clock: the display's own beat, and the one place a frame is raised.
//
// GTK has the idea built in. A GdkFrameClock belongs to a mapped window and
// This host gets for free what src/mac/clock.m and src/win32/clock.c each had
// to be told: a tick callback does not run while its widget is off screen, so
// a buried window here never drew in the first place.
//
// drives every animation GTK does itself, and `gtk_widget_add_tick_callback`
// is how a program joins in — so this host does not reach past the toolkit for
// a display link the way the Apple ones do.
//
// It costs one honesty: a tick callback only runs while its widget is on
// screen, and cortado's own gate never puts anything on screen. That is what
// `ctd_clock_step` is for, and it is why the numbering and the arithmetic are
// tested through it on every host rather than through a display on one.

#include "internal.h"
#include <math.h>

// One surface's clock, in a parallel array over the handle table rather than a
// table of its own. Only a surface has a clock, and indexing by slot means
// there is no second table to keep in step with the first.
typedef struct {
    guint    tick;           // the tick callback's id, 0 when there is none
    int64_t  token;
    int64_t  frames;         // delivered to the sink since the last start
    double   started;
    double   last;           // the previous frame's elapsed; 0 before the first
    uint32_t epoch;
    int      running;
} CtdClock;

static CtdClock g_clock[CTD_SLOTS];

// The rate a surface asks its display for; 0 is the screen's own maximum,
// which is what every clock wants until told otherwise.
typedef struct {
    double lowest;
    double highest;
    double wanted;
    double due;              // when the next paced frame is owed, monotonic
} CtdRate;

static CtdRate g_rate[CTD_SLOTS];

// Seconds from an arbitrary origin that only ever goes forward. Not the wall
// clock: a frame's time must not move because somebody corrected the date.
static double ctd_monotonic(void) {
    return (double)g_get_monotonic_time() / 1000000.0;
}

// A surface, or the reason this handle is not one. Stricter than "the handle
// resolves" on purpose: a caller who passed a button should be told which
// mistake they made rather than handed a clock that never ticks.
static ctd_status ctd_clock_surface(ctd_handle surface, CtdClock **out) {
    gpointer object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (!GTK_IS_WINDOW(object)) return CTD_ERR_KIND;
    *out = &g_clock[(uint32_t)(surface & 0xffffffffu)];
    return CTD_OK;
}

// Raises one frame. Every frame in this host comes through here — the tick
// callback's and ctd_clock_step's alike — so a synthesized frame is testing
// the same path a real one takes.
static void ctd_clock_deliver(ctd_handle surface, uint32_t epoch, double at) {
    if (!ctd_resolve(surface)) return;
    CtdClock *clock = &g_clock[(uint32_t)(surface & 0xffffffffu)];
    if (!clock->running || clock->epoch != epoch) return;
    // Counted only when it is handed over, so the count ctd_clock_state
    // answers is the number of events the sink saw and nothing else.
    if (!g_sink) return;

    double elapsed = at - clock->started;
    if (elapsed < clock->last) elapsed = clock->last;   // a clock never goes back
    double delta = elapsed - clock->last;
    clock->last = elapsed;
    clock->frames += 1;

    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = CTD_EV_FRAME;
    event.target = surface;
    event.index = clock->frames;
    event.token = clock->token;
    event.x = elapsed;
    event.y = delta;
    g_sink(g_sink_context, &event);
}

// How long one display frame lasts, or 0 where the compositor will not say.
static double ctd_clock_interval(GdkFrameClock *frame_clock) {
    GdkFrameTimings *timings = frame_clock
        ? gdk_frame_clock_get_current_timings(frame_clock) : NULL;
    gint64 interval = timings ? gdk_frame_timings_get_refresh_interval(timings) : 0;
    return interval > 0 ? (double)interval / 1000000.0 : 0.0;
}

// Whether a display tick at `now` is owed a frame. A GdkFrameClock takes no
// instruction, so a rate is asked for by dropping the ticks in between.
static int ctd_clock_owed(uint32_t slot, double now, double interval) {
    double wanted = g_rate[slot].wanted;
    if (!(wanted > 0.0)) return 1;              // the screen's own maximum
    double period = 1.0 / wanted;
    // Ticks land an interval apart, so one within half an interval of due is
    // the nearest the display will get.
    if (now + interval * 0.5 < g_rate[slot].due) return 0;
    double next = g_rate[slot].due + period;
    // Re-based, not caught up: a gap must not pay out the frames it owed.
    g_rate[slot].due = next > now ? next : now + period;
    return 1;
}

static gboolean ctd_clock_ticked(GtkWidget *widget, GdkFrameClock *frame_clock,
                                 gpointer data) {
    (void)widget;
    ctd_handle surface = (ctd_handle)(uintptr_t)data;
    uint32_t slot = (uint32_t)(surface & 0xffffffffu);
    double now = ctd_monotonic();
    if (!ctd_clock_owed(slot, now, ctd_clock_interval(frame_clock))) {
        return G_SOURCE_CONTINUE;
    }
    ctd_clock_deliver(surface, g_clock[slot].epoch, now);
    return G_SOURCE_CONTINUE;
}

ctd_status ctd_clock_start(ctd_handle surface, int64_t token) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (clock->running) return CTD_ERR_STATE;

    clock->token = token;
    clock->frames = 0;
    clock->last = 0.0;
    clock->started = ctd_monotonic();
    clock->epoch += 1;
    clock->running = 1;
    g_rate[(uint32_t)(surface & 0xffffffffu)].due = clock->started;
    clock->tick = gtk_widget_add_tick_callback(GTK_WIDGET(ctd_resolve(surface)),
                                               ctd_clock_ticked,
                                               (gpointer)(uintptr_t)surface, NULL);
    if (clock->tick == 0) {
        clock->running = 0;
        return CTD_ERR_PLATFORM;
    }
    return CTD_OK;
}

ctd_status ctd_clock_stop(ctd_handle surface) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (!clock->running) return CTD_OK;
    clock->running = 0;
    clock->epoch += 1;
    if (clock->tick) {
        gtk_widget_remove_tick_callback(GTK_WIDGET(ctd_resolve(surface)), clock->tick);
        clock->tick = 0;
    }
    return CTD_OK;
}

ctd_status ctd_clock_prefer(ctd_handle surface, double lowest,
                            double highest, double wanted) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    // A rate that is not a finite number passes every comparison below —
    // NaN is not less than, greater than or equal to anything — and then
    // reaches arithmetic that has no answer. Refused first, and by name.
    if (!isfinite(lowest) || !isfinite(highest) || !isfinite(wanted)) {
        return CTD_ERR_RANGE;
    }
    if (lowest < 0.0 || highest < 0.0 || wanted < 0.0) return CTD_ERR_RANGE;
    if (highest > 0.0 && lowest > highest) return CTD_ERR_RANGE;
    if (wanted > 0.0 && highest > 0.0 && wanted > highest) return CTD_ERR_RANGE;
    if (wanted > 0.0 && lowest > 0.0 && wanted < lowest) return CTD_ERR_RANGE;
    uint32_t slot = (uint32_t)(surface & 0xffffffffu);
    // No call asks a GdkFrameClock for a rate, so this host paces its own tick
    // instead; the ends are kept for a compositor that one day takes a range.
    g_rate[slot].lowest = lowest;
    g_rate[slot].highest = highest;
    g_rate[slot].wanted = wanted;
    // From now, not from the clock's start: a rate asked for mid-run owes its
    // next frame a period away.
    g_rate[slot].due = ctd_monotonic();
    return CTD_OK;
}

ctd_status ctd_clock_state(ctd_handle surface, double *out) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (out) {
        out[0] = clock->running ? 1.0 : 0.0;
        out[1] = (double)clock->frames;
        out[2] = clock->last;
    }
    return CTD_OK;
}

ctd_status ctd_clock_step(ctd_handle surface, double seconds) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (!clock->running) return CTD_ERR_STATE;
    // A refused comparison rather than `seconds <= 0`, so that a NaN is
    // refused too: every comparison with one is false, and a NaN step would
    // poison the elapsed reading for the rest of the run.
    if (!(seconds > 0.0)) return CTD_ERR_RANGE;
    ctd_clock_deliver(surface, clock->epoch, clock->started + clock->last + seconds);
    return CTD_OK;
}

void ctd_clock_forget(uint32_t slot) {
    // The tick callback is not removed: GTK drops it with the widget, and one
    // that outlives the slot carries a handle, so its delivery resolves none.
    memset(&g_clock[slot], 0, sizeof g_clock[slot]);
    memset(&g_rate[slot], 0, sizeof g_rate[slot]);
}
