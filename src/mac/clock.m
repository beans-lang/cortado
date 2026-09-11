// The frame clock: the display's own beat, and the one place a frame is raised.
//
// Everything that moves runs on this. What makes it a clock rather than a
// timer is CVDisplayLink: the callback comes from the window server at the
// rate the display actually refreshes, so a program written against it is
// already right on a 120 Hz screen and already right when the machine slows
// down.
//
// It is also the only code in this host that runs off the UI thread. The rule
// cortado is built on — Beans is entered from one thread, ever — is kept by
// making the link's callback do nothing but hand the frame to the main queue.

#import "internal.h"
#include <CoreVideo/CoreVideo.h>
#include <time.h>

// CVDisplayLink is deprecated from macOS 15 in favour of
// -[NSWindow displayLinkWithTarget:selector:], and this host keeps calling it
// for one concrete reason: a window that has never been shown is on no screen,
// and a display link bound to a window's screen has no display to follow.
// cortado's whole gate is headless — every case builds a window and never
// orders it front — so the replacement would tick on a desk and go silent on a
// build machine, which is the worst way round for a test to fail. The warning
// is turned off here, in the one file that calls it, and nowhere else.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// One surface's clock, in a parallel array over the handle table rather than a
// table of its own. Only a surface has a clock, and indexing by slot means
// there is no second table to keep in step with the first — the Win32 host
// keeps a progress bar's range the same way.
typedef struct {
    CVDisplayLinkRef link;   // made on the first start, kept until the slot goes
    int64_t  token;
    int64_t  frames;         // delivered to the sink since the last start
    double   started;        // the monotonic reading when it last started
    double   last;           // the previous frame's elapsed; 0 before the first
    uint32_t epoch;          // bumped by every start and every stop
    int      running;
} CtdClock;

static CtdClock g_clock[CTD_SLOTS];

// Seconds from an arbitrary origin that only ever goes forward. Not the wall
// clock: the time a frame arrives must not move because somebody changed the
// date or because the machine came back from sleep to a corrected time.
static double ctd_monotonic(void) {
    struct timespec reading;
    clock_gettime(CLOCK_MONOTONIC, &reading);
    return (double)reading.tv_sec + (double)reading.tv_nsec / 1000000000.0;
}

// A surface, or the reason this handle is not one.
//
// Deliberately stricter than "the handle resolves". A clock belongs to a
// surface, and a caller who passed a button should be told which mistake they
// made rather than handed a clock that never ticks.
static ctd_status ctd_clock_surface(ctd_handle surface, CtdClock **out) {
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSWindow class]]) return CTD_ERR_KIND;
    *out = &g_clock[(uint32_t)(surface & 0xffffffffu)];
    return CTD_OK;
}

// Raises one frame.
//
// Every frame in this host comes through here — the display link's and
// ctd_clock_step's alike — which is the point: a synthesized frame that took a
// second path would be testing that path and not this one.
static void ctd_clock_deliver(ctd_handle surface, uint32_t epoch, double at) {
    if (!ctd_resolve(surface)) return;      // the surface went while this waited
    CtdClock *clock = &g_clock[(uint32_t)(surface & 0xffffffffu)];
    // Stopped, or stopped and started again, since this frame was queued.
    if (!clock->running || clock->epoch != epoch) return;
    // Counted only when it is actually handed over, so the count in
    // ctd_clock_state is the number of events the sink saw and nothing else.
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

// The display link's callback, on the display link's own thread.
//
// It does as little as it is possible to do. Nothing here touches the handle
// table or the sink: both belong to the UI thread, and the frame is handed
// there before anything is decided about it. The epoch is read without a lock
// and checked again on the main thread, where every start and stop happens —
// the worst a stale read can do is queue a frame the delivery then refuses.
static CVReturn ctd_clock_ticked(CVDisplayLinkRef link, const CVTimeStamp *now,
                                 const CVTimeStamp *output, CVOptionFlags flags,
                                 CVOptionFlags *out_flags, void *context) {
    (void)link; (void)now; (void)output; (void)flags; (void)out_flags;
    ctd_handle surface = (ctd_handle)(uintptr_t)context;
    uint32_t epoch = g_clock[(uint32_t)(surface & 0xffffffffu)].epoch;
    double at = ctd_monotonic();
    dispatch_async(dispatch_get_main_queue(), ^{
        ctd_clock_deliver(surface, epoch, at);
    });
    return kCVReturnSuccess;
}

ctd_status ctd_clock_start(ctd_handle surface, int64_t token) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (clock->running) return CTD_ERR_STATE;

    if (!clock->link) {
        // The active displays rather than the one this window is on: a window
        // that has never been shown is on no display at all, and a clock that
        // refused to start until something was on screen could not be used to
        // drive the first frame of what is about to appear.
        if (CVDisplayLinkCreateWithActiveCGDisplays(&clock->link) != kCVReturnSuccess ||
            !clock->link) {
            return CTD_ERR_PLATFORM;
        }
        CVDisplayLinkSetOutputCallback(clock->link, ctd_clock_ticked,
                                       (void *)(uintptr_t)surface);
    }
    clock->token = token;
    clock->frames = 0;
    clock->last = 0.0;
    clock->started = ctd_monotonic();
    clock->epoch += 1;
    clock->running = 1;
    if (CVDisplayLinkStart(clock->link) != kCVReturnSuccess) {
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
    // Frames the link queued before it was told to stop are already on the
    // main queue. Bumping the epoch is what makes those refuse to deliver
    // instead of arriving after the program asked for silence.
    clock->epoch += 1;
    if (clock->link) CVDisplayLinkStop(clock->link);
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
    // Written as a refused comparison rather than `seconds <= 0` so that a NaN
    // is refused too: every comparison with one is false, and a NaN step would
    // poison the elapsed reading for the rest of the run.
    if (!(seconds > 0.0)) return CTD_ERR_RANGE;
    ctd_clock_deliver(surface, clock->epoch, clock->started + clock->last + seconds);
    return CTD_OK;
}

void ctd_clock_forget(uint32_t slot) {
    CtdClock *clock = &g_clock[slot];
    if (clock->link) {
        // Stop before release: CVDisplayLinkStop does not return while its
        // callback is running, so after it the link's thread is out of here.
        CVDisplayLinkStop(clock->link);
        CVDisplayLinkRelease(clock->link);
    }
    memset(clock, 0, sizeof *clock);
}

#pragma clang diagnostic pop
