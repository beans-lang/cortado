// Animation: described in Beans, run by Core Animation.
//
// Nothing in this file interpolates anything. The description is turned into a
// CABasicAnimation and handed over, and the render server runs it at the
// display's rate on a thread of its own — so an animation keeps its timing
// while the main thread is busy, and no Beans code runs for any frame of it.
// That is the reason the ABI is a builder rather than a "set this value every
// frame" call, and it is most of the reason to use the platform at all.
//
// The model and the presentation. Core Animation splits a layer in two: the
// model layer holds where the property *is going*, and the presentation layer
// holds what is on screen this instant. cortado's contract is the model — the
// value is written to the destination when the animation starts, and
// ctd_get_real answers that from then on. The presentation is read in exactly
// one place, and only because cancelling wants it: stopping half way and
// letting the control jump to its destination is not what anybody means by
// cancel.

#import "internal.h"
#import <QuartzCore/QuartzCore.h>

// The description, and the thing Core Animation reports back to.
//
// One object rather than a struct in a parallel array, unlike the frame
// clock's, because CAAnimation wants a delegate and the delegate has to know
// which animation it belongs to. It is in the handle table like everything
// else, and it retains its own handle so that the callback can find its way
// home.
@interface CortadoAnim : NSObject
@property (assign) ctd_handle slot_handle;
@property (assign) ctd_handle widget;
@property (assign) int32_t property;
@property (assign) double from;
@property (assign) double to;
@property (assign) double duration;
@property (assign) double delay;
@property (assign) int32_t curve;
@property (assign) int64_t token;
@property (assign) int has_from;
@property (assign) int has_to;
@property (assign) int running;
@end

@implementation CortadoAnim
@end

// The key an animation is filed under on its layer. One per property, so two
// properties animate side by side and a second animation of the *same*
// property replaces the first — which is Core Animation's own rule and the one
// the header promises.
static NSString *ctd_anim_key(int32_t property) {
    return [NSString stringWithFormat:@"cortado.%d", (int)property];
}

// The layer key path cortado's property means.
static NSString *ctd_anim_path(int32_t property) {
    switch (property) {
        case CTD_P_OPACITY: return @"opacity";
        default:            return nil;
    }
}

static CAMediaTimingFunction *ctd_anim_timing(int32_t curve) {
    switch (curve) {
        case CTD_CURVE_LINEAR:
            return [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        case CTD_CURVE_EASE_IN:
            return [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        case CTD_CURVE_EASE_OUT:
            return [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        default:
            return [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    }
}

static CortadoAnim *ctd_anim_of(ctd_handle anim, ctd_status *problem) {
    id object = ctd_resolve(anim);
    if (!object) { *problem = CTD_ERR_STALE; return nil; }
    if (![object isKindOfClass:[CortadoAnim class]]) { *problem = CTD_ERR_KIND; return nil; }
    *problem = CTD_OK;
    return (CortadoAnim *)object;
}

// Lets go of the handle and raises the one event an animation ever raises.
//
// The slot goes back before the event, which is what the header promises, so
// the object is held across the call — the table's reference is the only one
// that is certain, and a handler is entitled to start another animation from
// inside this, which would take the slot straight back.
static void ctd_anim_finish(CortadoAnim *anim, int finished, double value) {
    if (!anim.running) return;
    ctd_handle handle = anim.slot_handle;
    ctd_handle widget = anim.widget;
    int64_t token = anim.token;

    [anim retain];                       // the table is about to let go
    anim.running = 0;
    anim.slot_handle = 0;
    ctd_untrack(handle);

    if (g_sink) {
        ctd_event event;
        memset(&event, 0, sizeof event);
        event.kind = CTD_EV_ANIM_DONE;
        event.target = widget;
        event.token = token;
        event.index = finished ? 1 : 0;
        event.x = value;
        g_sink(g_sink_context, &event);
    }
    [anim release];
}

@interface CortadoAnim (Delegate) <CAAnimationDelegate>
@end

@implementation CortadoAnim (Delegate)
// Core Animation reports the end of every animation here, whether it reached
// it or was taken off the layer — which is why cancelling needs no separate
// path: removing the animation *is* how it is cancelled, and this is told.
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)reached {
    (void)animation;
    double value = 0.0;
    ctd_get_real(self.widget, self.property, &value);
    ctd_anim_finish(self, reached ? 1 : 0, value);
}
@end

ctd_handle ctd_anim_new(ctd_handle widget, int32_t property) {
    id object = ctd_resolve(widget);
    if (!object || ![object isKindOfClass:[NSView class]]) return 0;
    // A widget, not a surface and not another animation: both of those are
    // tracked with no widget kind. See ctd_anim_new in the header.
    if (ctd_slot_kind(widget) < 0) return 0;
    if (!ctd_property_animates(property)) return 0;
    if (!ctd_anim_path(property)) return 0;

    CortadoAnim *anim = [[CortadoAnim alloc] init];
    anim.widget = widget;
    anim.property = property;
    // Core Animation's own default when nothing is said, so an animation that
    // says only where it is going still looks like the platform.
    anim.duration = 0.25;
    anim.curve = CTD_CURVE_EASE_IN_OUT;
    ctd_handle handle = ctd_track(anim, -1);
    anim.slot_handle = handle;
    [anim release];
    return handle;
}

ctd_status ctd_anim_from_real(ctd_handle anim, double value) {
    ctd_status problem;
    CortadoAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found.running) return CTD_ERR_STATE;
    found.from = value;
    found.has_from = 1;
    return CTD_OK;
}

ctd_status ctd_anim_to_real(ctd_handle anim, double value) {
    ctd_status problem;
    CortadoAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found.running) return CTD_ERR_STATE;
    found.to = value;
    found.has_to = 1;
    return CTD_OK;
}

ctd_status ctd_anim_duration(ctd_handle anim, double seconds) {
    ctd_status problem;
    CortadoAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found.running) return CTD_ERR_STATE;
    // Written as a refused comparison so a NaN is refused too: every
    // comparison with one is false, and a NaN duration would make an
    // animation that never ends.
    if (!(seconds > 0.0)) return CTD_ERR_RANGE;
    found.duration = seconds;
    return CTD_OK;
}

ctd_status ctd_anim_delay(ctd_handle anim, double seconds) {
    ctd_status problem;
    CortadoAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found.running) return CTD_ERR_STATE;
    if (!(seconds >= 0.0)) return CTD_ERR_RANGE;
    found.delay = seconds;
    return CTD_OK;
}

ctd_status ctd_anim_curve(ctd_handle anim, int32_t curve) {
    ctd_status problem;
    CortadoAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found.running) return CTD_ERR_STATE;
    if (!ctd_curve_is_known(curve)) return CTD_ERR_RANGE;
    found.curve = curve;
    return CTD_OK;
}

ctd_status ctd_anim_start(ctd_handle anim, int64_t token) {
    ctd_status problem;
    CortadoAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found.running) return CTD_ERR_STATE;
    if (!found.has_to) return CTD_ERR_STATE;

    id object = ctd_resolve(found.widget);
    if (!object || ![object isKindOfClass:[NSView class]]) return CTD_ERR_STALE;
    NSView *view = (NSView *)object;

    // Layer-backing is asked for here rather than when the widget was made:
    // a layer costs memory on every control in a window, and only a control
    // that actually animates needs one. It comes first because the property is
    // written through the layer once there is one, and writing it before the
    // layer exists would leave the model and the layer disagreeing.
    [view setWantsLayer:YES];
    CALayer *layer = [view layer];
    if (!layer) return CTD_ERR_PLATFORM;

    double start = found.from;
    if (!found.has_from) {
        problem = ctd_get_real(found.widget, found.property, &start);
        if (problem != CTD_OK) return problem;
    }
    // The destination, written now. From here ctd_get_real answers where the
    // property is going — see the contract beside ctd_anim_start in the header.
    problem = ctd_set_real(found.widget, found.property, found.to);
    if (problem != CTD_OK) return problem;

    CABasicAnimation *motion =
        [CABasicAnimation animationWithKeyPath:ctd_anim_path(found.property)];
    motion.fromValue = @(start);
    motion.toValue = @(found.to);
    motion.duration = found.duration;
    motion.timingFunction = ctd_anim_timing(found.curve);
    motion.removedOnCompletion = YES;
    if (found.delay > 0.0) {
        motion.beginTime = CACurrentMediaTime() + found.delay;
        // Without this the layer shows the destination for the length of the
        // delay and then jumps back to the start to animate from it.
        motion.fillMode = kCAFillModeBackwards;
    }
    motion.delegate = (id<CAAnimationDelegate>)found;

    found.token = token;
    found.running = 1;
    // Replaces whatever was animating this property, and Core Animation tells
    // that one's delegate it did not finish — so the animation being replaced
    // reports itself cancelled with no extra code here.
    [layer addAnimation:motion forKey:ctd_anim_key(found.property)];
    return CTD_OK;
}

ctd_status ctd_anim_cancel(ctd_handle anim) {
    ctd_status problem;
    CortadoAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;

    if (!found.running) {
        // Built and never started: this is how one is thrown away. Nothing is
        // raised, because nothing ever ran.
        ctd_untrack(anim);
        return CTD_OK;
    }

    id object = ctd_resolve(found.widget);
    if (object && [object isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)object;
        CALayer *layer = [view layer];
        CALayer *shown = [layer presentationLayer];
        if (shown) {
            // What it was showing, kept. The one read of the presentation
            // layer in this host, and the reason is in the file header.
            double value = [[shown valueForKeyPath:ctd_anim_path(found.property)] doubleValue];
            ctd_set_real(found.widget, found.property, value);
        }
        // Removing it is what cancels it; the delegate hears finished:NO and
        // raises CTD_EV_ANIM_DONE from there.
        [layer removeAnimationForKey:ctd_anim_key(found.property)];
    }
    if (found.running) {
        // The layer had gone, so nothing told the delegate. Finish it here.
        double value = 0.0;
        ctd_get_real(found.widget, found.property, &value);
        ctd_anim_finish(found, 0, value);
    }
    return CTD_OK;
}
