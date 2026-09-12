// What the machine is doing: whether anything is reachable, and what it costs.
//
// **Nothing here is gated.** Every call below was run from a bare binary with
// no bundle and no usage description of any kind, across a turn of the run
// loop — which is where a TCC death lands — and the process was still alive
// afterwards. That is the whole reason these two services come before the
// other six: they answer for real under `beansc run` and on the ordinary test
// legs, where a bundled leg is not needed and could not help.
//
// **The path is a push, and this file is where that fact lives.**
// `nw_path_monitor` has no synchronous read: it starts, and some time later it
// calls back on a queue. So the last thing it said is kept here and
// `ctd_net_path` answers that — CTD_NET_UNKNOWN until it has said anything.
// The alternative was a blocking read, and a blocking read on the UI thread is
// a beachball whenever the answer is slow.

#import "internal.h"

#include <Network/Network.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

// The last thing the monitor said, and the monitor itself.
//
// Written on the monitor's own queue and read on the UI thread, which is the
// one place in this host where that happens — everything else is main-thread
// by construction. They are two plain 32-bit words and a write of one is
// atomic on every machine cortado builds for, so a reader sees either the old
// value or the new one and never half of each. What it must not do is take a
// lock: this is read on a frame path.
static _Atomic int32_t g_net_kind  = CTD_NET_UNKNOWN;
static _Atomic int32_t g_net_flags = 0;
static nw_path_monitor_t g_monitor;
static dispatch_queue_t  g_net_queue;

static int32_t ctd_kind_of_path(nw_path_t path) {
    if (nw_path_get_status(path) != nw_path_status_satisfied) return CTD_NET_NONE;
    // Asked in the order a program would want to hear: the medium that costs
    // most is the one worth knowing about.
    if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) return CTD_NET_CELLULAR;
    if (nw_path_uses_interface_type(path, nw_interface_type_wifi))     return CTD_NET_WIFI;
    if (nw_path_uses_interface_type(path, nw_interface_type_wired))    return CTD_NET_WIRED;
    return CTD_NET_OTHER;
}

// Starts the monitor if it is not already running.
//
// Called from ctd_listen when the first handler for CTD_EV_NET_CHANGED
// arrives, and from ctd_net_path, so a program that only ever wants the answer
// once does not have to register a handler to get it.
void ctd_net_start(void) {
    if (g_monitor) return;
    g_net_queue = dispatch_queue_create("cortado.net", DISPATCH_QUEUE_SERIAL);
    g_monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(g_monitor, g_net_queue);
    nw_path_monitor_set_update_handler(g_monitor, ^(nw_path_t path) {
        int32_t kind = ctd_kind_of_path(path);
        int32_t flags = 0;
        if (nw_path_is_expensive(path))   flags |= CTD_NET_F_EXPENSIVE;
        if (nw_path_is_constrained(path)) flags |= CTD_NET_F_CONSTRAINED;
        int32_t was_kind = g_net_kind;
        int32_t was_flags = g_net_flags;
        g_net_kind = kind;
        g_net_flags = flags;
        if (was_kind == kind && was_flags == flags) return;
        // Onto the UI thread before Beans is entered, the same hop the frame
        // clock makes. Nothing above this line touches the handle table or the
        // sink, because both belong to the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!g_sink || !ctd_listening(CTD_EV_NET_CHANGED)) return;
            ctd_event out;
            memset(&out, 0, sizeof out);
            out.kind = CTD_EV_NET_CHANGED;
            out.index = kind;
            out.x = (double)flags;
            g_sink(g_sink_context, &out);
        });
    });
    nw_path_monitor_start(g_monitor);
}

void ctd_net_stop(void) {
    if (!g_monitor) return;
    nw_path_monitor_cancel(g_monitor);
    g_monitor = nil;
    g_net_queue = nil;
    // Back to "nothing has answered", because nothing has: keeping the last
    // reading would answer a question about a monitor that is no longer
    // watching, and the longer it stays the wronger it gets.
    g_net_kind = CTD_NET_UNKNOWN;
    g_net_flags = 0;
}

ctd_status ctd_net_path(int32_t *out_kind, int32_t *out_flags) {
    ctd_net_start();
    if (out_kind)  *out_kind = g_net_kind;
    if (out_flags) *out_flags = g_net_flags;
    return CTD_OK;
}

// ---------------------------------------------------------------- the power

// The battery, through IOKit's power-source list.
//
// A blob and a list rather than one call, because a machine can have more than
// one source — a laptop with an attached UPS reports two — and the answer a
// program wants is about the one running it. The internal battery is the one
// that says so.
static int ctd_battery(int *charge, int *full, int *on_mains) {
    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (!blob) return 0;
    CFArrayRef list = IOPSCopyPowerSourcesList(blob);
    int found = 0;
    if (list) {
        for (CFIndex i = 0; i < CFArrayGetCount(list) && !found; i++) {
            CFDictionaryRef one =
                IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(list, i));
            if (!one) continue;
            CFNumberRef number = CFDictionaryGetValue(one, CFSTR(kIOPSCurrentCapacityKey));
            if (number) CFNumberGetValue(number, kCFNumberIntType, charge);
            number = CFDictionaryGetValue(one, CFSTR(kIOPSMaxCapacityKey));
            if (number) CFNumberGetValue(number, kCFNumberIntType, full);
            CFStringRef state = CFDictionaryGetValue(one, CFSTR(kIOPSPowerSourceStateKey));
            *on_mains = state && CFEqual(state, CFSTR(kIOPSACPowerValue));
            found = 1;
        }
        CFRelease(list);
    }
    CFRelease(blob);
    return found;
}

ctd_status ctd_power_source(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    int charge = 0, full = 0, on_mains = 0;
    // A machine with no battery is on the mains by definition: it is running,
    // and nothing else is running it.
    if (!ctd_battery(&charge, &full, &on_mains)) {
        *out = CTD_POWER_MAINS;
        return CTD_OK;
    }
    *out = on_mains ? CTD_POWER_MAINS : CTD_POWER_BATTERY;
    return CTD_OK;
}

ctd_status ctd_power_charge(double *out) {
    if (!out) return CTD_ERR_RANGE;
    int charge = 0, full = 0, on_mains = 0;
    if (!ctd_battery(&charge, &full, &on_mains) || full <= 0) return CTD_ERR_UNSUPPORTED;
    double level = (double)charge / (double)full;
    if (level < 0.0) level = 0.0;
    if (level > 1.0) level = 1.0;
    *out = level;
    return CTD_OK;
}

ctd_status ctd_power_saving(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    *out = [[NSProcessInfo processInfo] isLowPowerModeEnabled] ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_thermal_state(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    switch ([[NSProcessInfo processInfo] thermalState]) {
        case NSProcessInfoThermalStateNominal:  *out = CTD_THERMAL_NOMINAL;  break;
        case NSProcessInfoThermalStateFair:     *out = CTD_THERMAL_FAIR;     break;
        case NSProcessInfoThermalStateSerious:  *out = CTD_THERMAL_SERIOUS;  break;
        case NSProcessInfoThermalStateCritical: *out = CTD_THERMAL_CRITICAL; break;
        default:                                *out = CTD_THERMAL_UNKNOWN;  break;
    }
    return CTD_OK;
}

// Both of the system's own notifications, which is how a program hears that the
// machine changed without polling. Registered when the first handler arrives
// and taken down with the last, which is what ctd_listen is for.
static id g_power_watch;
static id g_thermal_watch;

void ctd_power_start(void) {
    if (g_power_watch) return;
    NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
    void (^tell)(NSNotification *) = ^(NSNotification *note) {
        (void)note;
        if (!g_sink || !ctd_listening(CTD_EV_POWER_CHANGED)) return;
        int32_t source = CTD_POWER_UNKNOWN;
        ctd_power_source(&source);
        double level = -1.0;
        if (ctd_power_charge(&level) != CTD_OK) level = -1.0;
        ctd_event out;
        memset(&out, 0, sizeof out);
        out.kind = CTD_EV_POWER_CHANGED;
        out.index = source;
        out.x = level;
        g_sink(g_sink_context, &out);
    };
    g_power_watch = [[centre addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                                         object:nil
                                          queue:[NSOperationQueue mainQueue]
                                     usingBlock:tell] retain];
    g_thermal_watch = [[centre addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                                           object:nil
                                            queue:[NSOperationQueue mainQueue]
                                       usingBlock:tell] retain];
}

void ctd_power_stop(void) {
    NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
    if (g_power_watch)   { [centre removeObserver:g_power_watch];   [g_power_watch release];   g_power_watch = nil; }
    if (g_thermal_watch) { [centre removeObserver:g_thermal_watch]; [g_thermal_watch release]; g_thermal_watch = nil; }
}
