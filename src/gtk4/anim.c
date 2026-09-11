// Animation: described in Beans, interpolated here.
//
// GTK has no render-server animation to hand a description to. There is no
// CABasicAnimation and nothing behind GTK that will move a property on its own
// thread, so this host does the arithmetic itself, on a timer, on the UI
// thread. The curve it walks is the one written down in `cortado_rules.h`,
// which is the same curve the Apple hosts hand to CAMediaTimingFunction by
// name — so the four agree on the shape even though two of them never compute
// it.
//
// The model and the presentation. Core Animation keeps two values for an
// animating property: where it is going, and what is on screen right now. GTK
// keeps one, so this file keeps the other: while an animation runs the widget
// holds what is shown, `to` holds where it is going, and `ctd_get_real` is
// answered from here rather than from the widget. That is what makes the
// contract beside ctd_anim_start in the header true on a host with no
// presentation layer of its own.

#include "internal.h"

typedef struct {
    ctd_handle handle;       // its own, so a finished animation can let go
    ctd_handle widget;
    int32_t    property;
    double     from;
    double     to;
    double     duration;
    double     delay;
    double     started;      // the monotonic reading when it was handed over
    int64_t    token;
    int32_t    curve;
    int        has_from;
    int        has_to;
    int        live;         // this slot describes an animation
    int        running;
} CtdAnim;

static CtdAnim g_anim[CTD_SLOTS];
static guint   g_anim_tick;   // the one timer every animation shares, or 0

static double ctd_anim_now(void) {
    return (double)g_get_monotonic_time() / 1000000.0;
}

static CtdAnim *ctd_anim_of(ctd_handle anim, ctd_status *problem) {
    gpointer object = ctd_resolve(anim);
    if (!object) { *problem = CTD_ERR_STALE; return NULL; }
    uint32_t slot = (uint32_t)(anim & 0xffffffffu);
    // A plain GObject is what an animation's handle names; anything cortado
    // built as a widget is a GtkWidget and is not this.
    if (G_OBJECT_TYPE(object) != G_TYPE_OBJECT || !g_anim[slot].live) {
        *problem = CTD_ERR_KIND;
        return NULL;
    }
    *problem = CTD_OK;
    return &g_anim[slot];
}

static void ctd_anim_emit(ctd_handle widget, int64_t token, int finished, double value) {
    if (!g_sink) return;
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = CTD_EV_ANIM_DONE;
    event.target = widget;
    event.token = token;
    event.index = finished ? 1 : 0;
    event.x = value;
    g_sink(g_sink_context, &event);
}

static gboolean ctd_anim_advance(gpointer ignored);

// Runs the shared timer exactly while there is something to move. A toolkit
// that left a 60 Hz timer running for the life of the process would keep a
// laptop awake for the sake of an animation that finished an hour ago.
static void ctd_anim_timer_check(void) {
    int busy = 0;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_anim[slot].live && g_anim[slot].running) { busy = 1; break; }
    }
    if (busy && g_anim_tick == 0) {
        g_anim_tick = g_timeout_add(16, ctd_anim_advance, NULL);
    } else if (!busy && g_anim_tick != 0) {
        g_source_remove(g_anim_tick);
        g_anim_tick = 0;
    }
}

// Lets go of the handle and raises the one event an animation ever raises.
// The slot goes back before the event, which is what the header promises.
static void ctd_anim_finish(CtdAnim *anim, int finished, double value) {
    ctd_handle widget = anim->widget;
    ctd_handle handle = anim->handle;
    int64_t token = anim->token;
    memset(anim, 0, sizeof *anim);
    ctd_untrack(handle);
    ctd_anim_emit(widget, token, finished, value);
}

// One step of every animation that is running.
static gboolean ctd_anim_advance(gpointer ignored) {
    double now = ctd_anim_now();
    (void)ignored;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        CtdAnim *anim = &g_anim[slot];
        if (!anim->live || !anim->running) continue;
        double elapsed = now - anim->started - anim->delay;
        if (elapsed < 0.0) continue;              // still waiting out its delay
        double fraction = elapsed / anim->duration;
        if (fraction > 1.0) fraction = 1.0;
        double value = anim->from
                     + (anim->to - anim->from) * ctd_curve_apply(anim->curve, fraction);
        ctd_set_real(anim->widget, anim->property, value);
        if (fraction >= 1.0) {
            ctd_anim_finish(anim, 1, anim->to);
        }
    }
    ctd_anim_timer_check();
    return g_anim_tick == 0 ? G_SOURCE_REMOVE : G_SOURCE_CONTINUE;
}

// Where a property is going, for ctd_get_real to answer with while it moves.
int ctd_anim_destination(ctd_handle widget, int32_t property, double *out) {
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        CtdAnim *anim = &g_anim[slot];
        if (!anim->live || !anim->running) continue;
        if (anim->widget != widget || anim->property != property) continue;
        if (out) *out = anim->to;
        return 1;
    }
    return 0;
}

ctd_handle ctd_anim_new(ctd_handle widget, int32_t property) {
    gpointer object = ctd_resolve(widget);
    if (!object || !GTK_IS_WIDGET(object)) return 0;
    // A widget, not a surface and not another animation: both of those are
    // tracked with no widget kind, and a GtkWindow is a GtkWidget so nothing
    // else here would have told them apart.
    if (ctd_slot_kind(widget) < 0) return 0;
    if (!ctd_property_animates(property)) return 0;

    // A plain GObject, held only so that an animation is a handle in the same
    // table as everything else. The description itself is in g_anim, beside
    // the slot, the way this host keeps a progress bar's range.
    GObject *marker = g_object_new(G_TYPE_OBJECT, NULL);
    ctd_handle handle = ctd_track(marker, -1);
    g_object_unref(marker);
    if (handle == 0) return 0;

    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    CtdAnim *anim = &g_anim[slot];
    memset(anim, 0, sizeof *anim);
    anim->handle = handle;
    anim->widget = widget;
    anim->property = property;
    // What Core Animation uses when nothing is said, so an animation that says
    // only where it is going looks the same on every host.
    anim->duration = 0.25;
    anim->curve = CTD_CURVE_EASE_IN_OUT;
    anim->live = 1;
    return handle;
}

ctd_status ctd_anim_from_real(ctd_handle anim, double value) {
    ctd_status problem;
    CtdAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found->running) return CTD_ERR_STATE;
    found->from = value;
    found->has_from = 1;
    return CTD_OK;
}

ctd_status ctd_anim_to_real(ctd_handle anim, double value) {
    ctd_status problem;
    CtdAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found->running) return CTD_ERR_STATE;
    found->to = value;
    found->has_to = 1;
    return CTD_OK;
}

ctd_status ctd_anim_duration(ctd_handle anim, double seconds) {
    ctd_status problem;
    CtdAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found->running) return CTD_ERR_STATE;
    // A refused comparison rather than `seconds <= 0`, so a NaN is refused
    // too: every comparison with one is false, and a NaN duration would make
    // an animation that never ends.
    if (!(seconds > 0.0)) return CTD_ERR_RANGE;
    found->duration = seconds;
    return CTD_OK;
}

ctd_status ctd_anim_delay(ctd_handle anim, double seconds) {
    ctd_status problem;
    CtdAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found->running) return CTD_ERR_STATE;
    if (!(seconds >= 0.0)) return CTD_ERR_RANGE;
    found->delay = seconds;
    return CTD_OK;
}

ctd_status ctd_anim_curve(ctd_handle anim, int32_t curve) {
    ctd_status problem;
    CtdAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found->running) return CTD_ERR_STATE;
    if (!ctd_curve_is_known(curve)) return CTD_ERR_RANGE;
    found->curve = curve;
    return CTD_OK;
}

ctd_status ctd_anim_start(ctd_handle anim, int64_t token) {
    ctd_status problem;
    CtdAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;
    if (found->running) return CTD_ERR_STATE;
    if (!found->has_to) return CTD_ERR_STATE;
    if (!ctd_resolve(found->widget)) return CTD_ERR_STALE;

    if (!found->has_from) {
        problem = ctd_get_real(found->widget, found->property, &found->from);
        if (problem != CTD_OK) return problem;
    }
    // Whatever was moving this property stops, and reports itself cancelled.
    // Core Animation does this on its own when a second animation is filed
    // under the same key; here it is written out.
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        CtdAnim *other = &g_anim[slot];
        if (other == found || !other->live || !other->running) continue;
        if (other->widget != found->widget || other->property != found->property) continue;
        double shown = 0.0;
        ctd_get_real(other->widget, other->property, &shown);
        ctd_anim_finish(other, 0, shown);
    }

    // The start, shown now. Not the destination: this host has one value per
    // property, and writing the destination into it would make the control
    // jump there and animate back.
    problem = ctd_set_real(found->widget, found->property, found->from);
    if (problem != CTD_OK) return problem;

    found->token = token;
    found->started = ctd_anim_now();
    found->running = 1;
    ctd_anim_timer_check();
    return CTD_OK;
}

ctd_status ctd_anim_cancel(ctd_handle anim) {
    ctd_status problem;
    CtdAnim *found = ctd_anim_of(anim, &problem);
    if (!found) return problem;

    if (!found->running) {
        // Built and never started: this is how one is thrown away. Nothing is
        // raised, because nothing ever ran.
        ctd_handle handle = found->handle;
        memset(found, 0, sizeof *found);
        ctd_untrack(handle);
        return CTD_OK;
    }

    // What it was showing is what the widget already holds, so keeping it is
    // simply not writing anything else.
    double shown = 0.0;
    ctd_get_real(found->widget, found->property, &shown);
    ctd_anim_finish(found, 0, shown);
    ctd_anim_timer_check();
    return CTD_OK;
}

void ctd_anim_forget(uint32_t slot) {
    // The animation this slot *was*, if it was one. Already cleared when it
    // ended on its own, because finishing clears before it lets go.
    if (g_anim[slot].live) {
        memset(&g_anim[slot], 0, sizeof g_anim[slot]);
    }
    // And any animation of the widget this slot held. Its handle is stale from
    // here on, so it can neither move anything nor arrive anywhere; a host
    // that kept ticking would announce four seconds later that it finished.
    for (uint32_t other = 1; other <= g_used; other++) {
        CtdAnim *anim = &g_anim[other];
        if (!anim->live || !anim->running) continue;
        if ((uint32_t)(anim->widget & 0xffffffffu) != slot) continue;
        double shown = 0.0;
        ctd_get_real(anim->widget, anim->property, &shown);
        ctd_anim_finish(anim, 0, shown);
    }
    ctd_anim_timer_check();
}
