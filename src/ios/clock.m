// The frame clock: the display's own beat, and the one place a frame is raised.
//
// CADisplayLink is the phone's version of the same idea as the Mac's
// CVDisplayLink, and it is the easier one: it is a run-loop source, so its
// callback already arrives on the UI thread and there is no hop to arrange.
// What it adds instead is a target object — a display link wants a selector to
// send, not a function to call — so there is one small class here whose whole
// job is to carry the surface's handle from the link back to this file.

#import "internal.h"
#import <QuartzCore/QuartzCore.h>
#include <time.h>
#include <math.h>

@interface CortadoTick : NSObject
@property (assign) ctd_handle surface;
- (void)tick:(CADisplayLink *)link;
@end

// One surface's clock, in a parallel array over the handle table rather than a
// table of its own. Only a surface has a clock, and indexing by slot means
// there is no second table to keep in step with the first.
typedef struct {
    void    *link;           // CADisplayLink, retained while it exists
    void    *target;         // CortadoTick, retained while it exists
    int64_t  token;
    int64_t  frames;         // delivered to the sink since the last start
    double   started;
    double   last;           // the previous frame's elapsed; 0 before the first
    uint32_t epoch;
    int      running;
} CtdClock;

static CtdClock g_clock[CTD_SLOTS];

// The rate a surface asks its screen for; 0 means the screen's maximum. The
// same three numbers the macOS host keeps, for the same CADisplayLink.
typedef struct {
    double lowest;
    double highest;
    double wanted;
} CtdRate;

static CtdRate g_rate[CTD_SLOTS];

// The screen's top rate, or 60 where the platform will not say. A phone with
// ProMotion answers 120 here and a range is the only way to ask for it.
static double ctd_clock_top(void) {
    NSInteger top = [UIScreen mainScreen].maximumFramesPerSecond;
    return top > 0 ? (double)top : 60.0;
}

// Puts this surface's wish on its link.
static void ctd_clock_apply_rate(ctd_handle surface) {
    uint32_t slot = (uint32_t)(surface & 0xffffffffu);
    CADisplayLink *link = (CADisplayLink *)g_clock[slot].link;
    if (!link) return;
    double top = ctd_clock_top();
    double aim = g_rate[slot].wanted > 0.0 ? g_rate[slot].wanted : top;
    double most = g_rate[slot].highest > 0.0 ? g_rate[slot].highest : top;
    double least = g_rate[slot].lowest > 0.0 ? g_rate[slot].lowest : aim;
    link.preferredFrameRateRange =
        CAFrameRateRangeMake((float)least, (float)most, (float)aim);
}

// Seconds from an arbitrary origin that only ever goes forward. Not the wall
// clock: a frame's time must not move because the phone corrected its date.
static double ctd_monotonic(void) {
    struct timespec reading;
    clock_gettime(CLOCK_MONOTONIC, &reading);
    return (double)reading.tv_sec + (double)reading.tv_nsec / 1000000000.0;
}

// A surface, or the reason this handle is not one. Stricter than "the handle
// resolves" on purpose: a caller who passed a button should be told which
// mistake they made rather than handed a clock that never ticks.
static ctd_status ctd_clock_surface(ctd_handle surface, CtdClock **out) {
    id object = ctd_resolve(surface);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIWindow class]]) return CTD_ERR_KIND;
    *out = &g_clock[(uint32_t)(surface & 0xffffffffu)];
    return CTD_OK;
}

// Raises one frame. Every frame in this host comes through here — the display
// link's and ctd_clock_step's alike — so a synthesized frame is testing the
// same path a real one takes.
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

@implementation CortadoTick
- (void)tick:(CADisplayLink *)link {
    // The rule src/mac/clock.m states. A backgrounded app is suspended here
    // and its link stops with it, so what is left to catch is a hidden window.
    if (g_role != CTD_ROLE_HEADLESS) {
        id object = ctd_resolve(self.surface);
        if (![object isKindOfClass:[UIWindow class]]) return;
        if ([(UIWindow *)object isHidden]) return;
    }
    (void)link;
    uint32_t slot = (uint32_t)(self.surface & 0xffffffffu);
    ctd_clock_deliver(self.surface, g_clock[slot].epoch, ctd_monotonic());
}
@end

ctd_status ctd_clock_start(ctd_handle surface, int64_t token) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (clock->running) return CTD_ERR_STATE;

    if (!clock->link) {
        CortadoTick *target = [[CortadoTick alloc] init];
        [target setSurface:surface];
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:target
                                                          selector:@selector(tick:)];
        if (!link) { [target release]; return CTD_ERR_PLATFORM; }
        // Common modes, not the default one: a phone puts the run loop into
        // tracking mode for the whole of a scroll or a drag, and a clock that
        // stopped for the length of every gesture would stop exactly when
        // something is moving.
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [link setPaused:YES];
        clock->link = [link retain];
        clock->target = target;
    }
    clock->token = token;
    clock->frames = 0;
    clock->last = 0.0;
    clock->started = ctd_monotonic();
    clock->epoch += 1;
    clock->running = 1;
    ctd_clock_apply_rate(surface);
    [(CADisplayLink *)clock->link setPaused:NO];
    return CTD_OK;
}

ctd_status ctd_clock_stop(ctd_handle surface) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (!clock->running) return CTD_OK;
    clock->running = 0;
    clock->epoch += 1;
    if (clock->link) [(CADisplayLink *)clock->link setPaused:YES];
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
    g_rate[slot].lowest = lowest;
    g_rate[slot].highest = highest;
    g_rate[slot].wanted = wanted;
    if (clock->link) ctd_clock_apply_rate(surface);
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
    CtdClock *clock = &g_clock[slot];
    if (clock->link) {
        [(CADisplayLink *)clock->link invalidate];
        [(CADisplayLink *)clock->link release];
    }
    if (clock->target) [(CortadoTick *)clock->target release];
    memset(clock, 0, sizeof *clock);
}
