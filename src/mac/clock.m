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
#import <QuartzCore/QuartzCore.h>
#include <time.h>

// **Two links, and which one runs is decided per surface.**
//
// `-[NSView displayLinkWithTarget:selector:]` (macOS 14) is the one to want: it
// follows the screen its view is actually on, so a window dragged to a second
// display changes rate with it, and it takes a `preferredFrameRateRange` — the
// only way to *ask* a ProMotion display for 120 rather than accept whatever
// adaptive rate the system settles on.
//
// It cannot be the only one. A view that is on no screen has no display to
// follow and its link never fires, and cortado's whole gate is headless: every
// case builds a window and never orders it front. A wholesale swap would tick
// on a desk and go silent on a build machine, which is the worst way round for
// a test to fail.
//
// So a surface with a screen gets the view link and the frame rate it asked
// for, and a surface with none keeps CVDisplayLink, which is bound to the
// active displays rather than to a window. `ctd_clock_start` picks, every
// start, because a window gains a screen when it is first shown.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// One surface's clock, in a parallel array over the handle table rather than a
// table of its own. Only a surface has a clock, and indexing by slot means
// there is no second table to keep in step with the first — the Win32 host
// keeps a progress bar's range the same way.
typedef struct {
    CVDisplayLinkRef link;   // the fallback, for a surface on no screen
    void    *view_link;      // CADisplayLink, retained while it exists
    int64_t  token;
    int64_t  frames;         // delivered to the sink since the last start
    double   started;        // the monotonic reading when it last started
    double   last;           // the previous frame's elapsed; 0 before the first
    uint32_t epoch;          // bumped by every start and every stop
    int      running;
} CtdClock;

static CtdClock g_clock[CTD_SLOTS];

// The rate a surface asks its display for: 0 means "whatever the screen runs
// at", which is what every clock starts out wanting.
typedef struct {
    double lowest;
    double highest;
    double wanted;
} CtdRate;

static CtdRate g_rate[CTD_SLOTS];

// The target for the view link's callback. One per surface, retained by the
// link, so the selector has a surface to name without a global.
@interface CortadoBeat : NSObject
@property (assign) ctd_handle surface;
- (void)beat:(id)link;
@end

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

// Whether a frame the display produced is worth delivering.
//
// A frame drives drawing, and drawing into a surface the window server is not
// showing is a full GPU pass nobody sees — six of them, in examples/gradients,
// which is a third of WindowServer on a machine whose owner has the window
// buried. CVDisplayLink belongs to the *display*, not to the window, so it
// keeps firing for a window that is minimised, hidden or entirely covered.
//
// Headless has no window server: nothing there is ever showing, and its frames
// are the program's to drive, so they always land. Time is not stopped either
// way — a window that comes back has skipped the frames, not the seconds.
static int ctd_clock_showing(ctd_handle surface) {
    if (g_role == CTD_ROLE_HEADLESS) return 1;
    id object = ctd_resolve(surface);
    if (![object isKindOfClass:[NSWindow class]]) return 0;
    NSWindow *window = (NSWindow *)object;
    return ([window occlusionState] & NSWindowOcclusionStateVisible) ? 1 : 0;
}

// The frame rate a surface's screen can actually produce, or 60 where the
// platform will not say — every Mac panel does at least that.
static double ctd_clock_top(ctd_handle surface) {
    id object = ctd_resolve(surface);
    if (![object isKindOfClass:[NSWindow class]]) return 60.0;
    NSScreen *screen = [(NSWindow *)object screen];
    if (!screen) screen = [NSScreen mainScreen];
    if (!screen) return 60.0;
    NSInteger top = [screen maximumFramesPerSecond];
    return top > 0 ? (double)top : 60.0;
}

@implementation CortadoBeat
// On the main thread already: a view link is a run-loop source, so unlike
// CVDisplayLink there is no hop and no window in which the surface can go.
- (void)beat:(id)link {
    (void)link;
    ctd_handle surface = self.surface;
    if (!ctd_clock_showing(surface)) return;
    ctd_clock_deliver(surface, g_clock[(uint32_t)(surface & 0xffffffffu)].epoch,
                      ctd_monotonic());
}
@end

// Starts the view link for a surface that is on a screen, or answers 0 when
// there is none to bind to and the CVDisplayLink fallback has to serve.
static int ctd_clock_start_view(ctd_handle surface) {
    if (@available(macOS 14.0, *)) {
        // Headless keeps the older link, and the reason is not tidiness: an
        // NSWindow that was never ordered front still answers a `screen`, so
        // the view link is created and then never fires. tests/frames.b went
        // from five frames to none, which is this rule being discovered.
        if (g_role == CTD_ROLE_HEADLESS) return 0;
        id object = ctd_resolve(surface);
        if (![object isKindOfClass:[NSWindow class]]) return 0;
        NSWindow *window = (NSWindow *)object;
        NSView *view = [window contentView];
        if (!view) return 0;

        uint32_t slot = (uint32_t)(surface & 0xffffffffu);
        CtdClock *clock = &g_clock[slot];
        if (!clock->view_link) {
            CortadoBeat *beat = [[CortadoBeat alloc] init];
            beat.surface = surface;
            CADisplayLink *link = [view displayLinkWithTarget:beat
                                                     selector:@selector(beat:)];
            if (!link) return 0;
            [link addToRunLoop:[NSRunLoop currentRunLoop]
                       forMode:NSRunLoopCommonModes];
            clock->view_link = (void *)CFBridgingRetain(link);
        }
        CADisplayLink *link = (__bridge CADisplayLink *)clock->view_link;
        // What this surface asked for, or the screen's own maximum. A range
        // rather than one number is what the system wants: it may drop below
        // the preferred rate under load, and saying so beats being dropped to
        // a rate the program never considered.
        double top = ctd_clock_top(surface);
        double wanted = g_rate[slot].wanted > 0.0 ? g_rate[slot].wanted : top;
        double highest = g_rate[slot].highest > 0.0 ? g_rate[slot].highest : top;
        // The floor is the wanted rate unless the program said otherwise, and
        // that is not a detail: a range the system is allowed to pick inside
        // is a range it *will* pick inside. Asking for 60 with a floor of 30
        // measured 42 on a 60 Hz panel, steady, for no reason the program
        // could see. A constant animation asks for one rate.
        double lowest = g_rate[slot].lowest > 0.0 ? g_rate[slot].lowest : wanted;
        if (wanted > highest) wanted = highest;
        if (lowest > wanted) lowest = wanted;
        link.preferredFrameRateRange =
            CAFrameRateRangeMake((float)lowest, (float)highest, (float)wanted);
        link.paused = NO;
        return 1;
    }
    return 0;
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
        // On the main thread, which is the only place AppKit may be asked.
        if (!ctd_clock_showing(surface)) return;
        ctd_clock_deliver(surface, epoch, at);
    });
    return kCVReturnSuccess;
}

ctd_status ctd_clock_start(ctd_handle surface, int64_t token) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (clock->running) return CTD_ERR_STATE;

    // Written before either link is started: a view link is a run-loop source
    // and can fire before this function has returned.
    clock->token = token;
    clock->frames = 0;
    clock->last = 0.0;
    clock->started = ctd_monotonic();
    clock->epoch += 1;
    clock->running = 1;

    // The screen's own link where there is a screen, with the rate this
    // surface asked for. Everything below is the fallback.
    if (ctd_clock_start_view(surface)) return CTD_OK;

    if (!clock->link) {
        // The active displays rather than the one this window is on: a window
        // that has never been shown is on no display at all, and a clock that
        // refused to start until something was on screen could not be used to
        // drive the first frame of what is about to appear.
        //
        // **A sleeping screen has no active display and so no display link.**
        // CGGetActiveDisplayList answers zero, CVDisplayLinkCreateWith-
        // ActiveCGDisplays answers -6661, and this refuses — which is correct
        // and reads exactly like a bug in the clock. It cost twenty minutes
        // once: a gate that had been green went red three cases at a time
        // while the Mac running it sat with its screen off. So the two are
        // told apart here, and the machine's state is reported as the
        // machine's state.
        uint32_t awake = 0;
        CGGetActiveDisplayList(0, NULL, &awake);
        if (awake == 0) { clock->running = 0; return CTD_ERR_STATE; }
        if (CVDisplayLinkCreateWithActiveCGDisplays(&clock->link) != kCVReturnSuccess ||
            !clock->link) {
            clock->running = 0;
            return CTD_ERR_PLATFORM;
        }
        CVDisplayLinkSetOutputCallback(clock->link, ctd_clock_ticked,
                                       (void *)(uintptr_t)surface);
    }
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
    if (clock->view_link) {
        if (@available(macOS 14.0, *)) {
            ((__bridge CADisplayLink *)clock->view_link).paused = YES;
        }
    }
    if (clock->link) CVDisplayLinkStop(clock->link);
    return CTD_OK;
}

ctd_status ctd_clock_prefer(ctd_handle surface, double lowest,
                            double highest, double wanted) {
    CtdClock *clock = NULL;
    ctd_status problem = ctd_clock_surface(surface, &clock);
    if (problem != CTD_OK) return problem;
    if (lowest < 0.0 || highest < 0.0 || wanted < 0.0) return CTD_ERR_RANGE;
    if (highest > 0.0 && lowest > highest) return CTD_ERR_RANGE;
    if (wanted > 0.0 && highest > 0.0 && wanted > highest) return CTD_ERR_RANGE;
    if (wanted > 0.0 && lowest > 0.0 && wanted < lowest) return CTD_ERR_RANGE;

    uint32_t slot = (uint32_t)(surface & 0xffffffffu);
    g_rate[slot].lowest = lowest;
    g_rate[slot].highest = highest;
    g_rate[slot].wanted = wanted;
    // A link that is already running takes it now; one that is not will read
    // this when it starts. CVDisplayLink has no rate to set, so a surface on
    // the fallback stores the wish and honours it if it ever gets a view link.
    if (clock->view_link) {
        if (@available(macOS 14.0, *)) {
            double top = ctd_clock_top(surface);
            double aim = wanted > 0.0 ? wanted : top;
            double most = highest > 0.0 ? highest : top;
            double least = lowest > 0.0 ? lowest : aim;
            ((__bridge CADisplayLink *)clock->view_link).preferredFrameRateRange =
                CAFrameRateRangeMake((float)least, (float)most, (float)aim);
        }
    }
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
    if (clock->view_link) {
        // Invalidate takes it off the run loop, which is what makes the
        // retained target go too.
        if (@available(macOS 14.0, *)) {
            CADisplayLink *link = (CADisplayLink *)CFBridgingRelease(clock->view_link);
            [link invalidate];
        }
        clock->view_link = NULL;
    }
    memset(&g_rate[slot], 0, sizeof g_rate[slot]);
    if (clock->link) {
        // Stop before release: CVDisplayLinkStop does not return while its
        // callback is running, so after it the link's thread is out of here.
        CVDisplayLinkStop(clock->link);
        CVDisplayLinkRelease(clock->link);
    }
    memset(clock, 0, sizeof *clock);
}

#pragma clang diagnostic pop
