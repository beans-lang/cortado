// The frame clock: a beat for a surface, and the one place a frame is raised.
//
// Windows is the host with no display link in it. There is no CVDisplayLink,
// no CADisplayLink and no GdkFrameClock here — the composition timing the
// desktop window manager keeps is behind DWM and DXGI, which are a swap chain
// away, and cortado does not have one yet. So this is a timer at about sixty
// frames a second, and saying so plainly is the point: it is the one host
// where the beat is an interval somebody chose rather than the rate the screen
// really refreshes.
//
// It still delivers everything the header promises. The numbering, the token,
// the elapsed arithmetic and the refusals are the same bytes here as on the
// three hosts that do have a display link — `tests/clock.out` is the file that
// says so.

#include "internal.h"

// One surface's clock, in a parallel array over the handle table rather than a
// table of its own. Only a surface has a clock, and indexing by slot means
// there is no second table to keep in step with the first — the same shape
// this host already uses for a progress bar's range.
typedef struct {
    int64_t  token;
    int64_t  frames;         // delivered to the sink since the last start
    double   started;
    double   last;           // the previous frame's elapsed; 0 before the first
    uint32_t epoch;
    int      running;
} CtdClock;

static CtdClock g_clock[CTD_SLOTS];

// CTD_CLOCK_PERIOD is sixteen milliseconds, about sixty frames a second.
// USER_TIMER_MINIMUM is ten and a WM_TIMER is not accurate to either, so
// sixteen is the honest name for what a message-queue timer can do.

// Seconds from an arbitrary origin that only ever goes forward. Not
// GetTickCount, whose resolution is the same as the timer's period — a delta
// measured with it would read zero about as often as not.
static double ctd_monotonic(void) {
    LARGE_INTEGER frequency, now;
    if (!QueryPerformanceFrequency(&frequency) || frequency.QuadPart == 0) return 0.0;
    QueryPerformanceCounter(&now);
    return (double)now.QuadPart / (double)frequency.QuadPart;
}

// A surface, or the reason this handle is not one. Stricter than "the handle
// resolves" on purpose: a caller who passed a button should be told which
// mistake they made rather than handed a clock that never ticks.
static ctd_status ctd_clock_surface(ctd_handle surface, CtdClock **out, HWND *window) {
    ctd_status problem;
    HWND found = ctd_surface_window(surface, &problem);
    if (!found) return problem;
    if (window) *window = found;
    *out = &g_clock[(uint32_t)(surface & 0xffffffffu)];
    return CTD_OK;
}

// Raises one frame. Every frame in this host comes through here — the timer's
// and ctd_clock_step's alike — so a synthesized frame is testing the same path
// a real one takes.
static void ctd_clock_deliver(ctd_handle surface, uint32_t epoch, double at) {
    uint32_t slot = (uint32_t)(surface & 0xffffffffu);
    if (!slot || slot >= CTD_SLOTS) return;
    if (g_type[slot] != CTD_T_SURFACE) return;   // released, or never a surface
    if ((uint32_t)(surface >> 32) != g_generation[slot]) return;
    CtdClock *clock = &g_clock[slot];
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

// WM_TIMER, from the surface's own window procedure.
// Whether a frame is worth delivering — the rule src/mac/clock.m states, on
// the host whose timer has the same fault: WM_TIMER keeps arriving for a window
// that is minimised or hidden, so without this a buried window still draws.
static int ctd_clock_showing(HWND window) {
    if (g_role == CTD_ROLE_HEADLESS) return 1;
    return (IsWindowVisible(window) && !IsIconic(window)) ? 1 : 0;
}

void ctd_clock_ticked(HWND window) {
    if (!ctd_clock_showing(window)) return;
    ctd_handle surface = ctd_handle_of(window);
    if (!surface) return;
    uint32_t slot = (uint32_t)(surface & 0xffffffffu);
    ctd_clock_deliver(surface, g_clock[slot].epoch, ctd_monotonic());
}

ctd_status ctd_clock_start(ctd_handle surface, int64_t token) {
    CtdClock *clock = NULL;
    HWND window = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock, &window);
    if (problem != CTD_OK) return problem;
    if (clock->running) return CTD_ERR_STATE;

    clock->token = token;
    clock->frames = 0;
    clock->last = 0.0;
    clock->started = ctd_monotonic();
    clock->epoch += 1;
    clock->running = 1;
    if (!SetTimer(window, CTD_CLOCK_TIMER, CTD_CLOCK_PERIOD, NULL)) {
        clock->running = 0;
        return CTD_ERR_PLATFORM;
    }
    return CTD_OK;
}

ctd_status ctd_clock_stop(ctd_handle surface) {
    CtdClock *clock = NULL;
    HWND window = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock, &window);
    if (problem != CTD_OK) return problem;
    if (!clock->running) return CTD_OK;
    clock->running = 0;
    // A WM_TIMER already in the queue outlives KillTimer. Bumping the epoch is
    // what makes it refuse to deliver rather than arrive after the program
    // asked for silence.
    clock->epoch += 1;
    KillTimer(window, CTD_CLOCK_TIMER);
    return CTD_OK;
}

ctd_status ctd_clock_state(ctd_handle surface, double *out) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock, NULL);
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
    ctd_status problem = ctd_clock_surface(surface, &clock, NULL);
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
    // The timer is not killed here. It belongs to a window that is on its way
    // out, and Windows destroys a window's timers with it; a WM_TIMER that
    // outlives the slot resolves to no surface and is dropped.
    memset(&g_clock[slot], 0, sizeof g_clock[slot]);
}
