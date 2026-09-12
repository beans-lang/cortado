// What the machine is doing: whether anything is reachable, and what it costs.
//
// The network half is the Mac's, because it is the same framework and the same
// answer: `nw_path_monitor` is one API across both, and on a phone it is the
// one that also knows about cellular — which is the medium the flags exist for.
//
// The power half is not. A phone has no IOKit power-source list; it has
// `UIDevice`, and `UIDevice` answers nothing at all until battery monitoring
// is turned on. That is switched on once here rather than per call, because
// turning it on and off costs a notification registration each way and the
// answer is wrong for a moment after each.

#import "internal.h"

#include <Network/Network.h>

static _Atomic int32_t g_net_kind  = CTD_NET_UNKNOWN;
static _Atomic int32_t g_net_flags = 0;
static nw_path_monitor_t g_monitor;
static dispatch_queue_t  g_net_queue;

static int32_t ctd_kind_of_path(nw_path_t path) {
    if (nw_path_get_status(path) != nw_path_status_satisfied) return CTD_NET_NONE;
    if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) return CTD_NET_CELLULAR;
    if (nw_path_uses_interface_type(path, nw_interface_type_wifi))     return CTD_NET_WIFI;
    if (nw_path_uses_interface_type(path, nw_interface_type_wired))    return CTD_NET_WIRED;
    return CTD_NET_OTHER;
}

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

// UIDevice answers nothing until this is on: batteryState is
// UIDeviceBatteryStateUnknown and batteryLevel is -1. Turned on once, and left
// on, because switching it costs a notification registration each way and the
// answer is wrong for a moment after each.
static void ctd_battery_ready(void) {
    static int asked;
    if (asked) return;
    asked = 1;
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
}

ctd_status ctd_power_source(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    ctd_battery_ready();
    switch ([[UIDevice currentDevice] batteryState]) {
        case UIDeviceBatteryStateCharging:
        case UIDeviceBatteryStateFull:      *out = CTD_POWER_MAINS;   break;
        case UIDeviceBatteryStateUnplugged: *out = CTD_POWER_BATTERY; break;
        default:
            // The Simulator answers unknown and always will: there is no
            // battery behind it. A phone that answered this would be one whose
            // state nobody can read, and saying so is better than guessing.
            *out = CTD_POWER_UNKNOWN;
            break;
    }
    return CTD_OK;
}

ctd_status ctd_power_charge(double *out) {
    if (!out) return CTD_ERR_RANGE;
    ctd_battery_ready();
    float level = [[UIDevice currentDevice] batteryLevel];
    // -1 is UIKit's "I do not know", which the Simulator always answers. It is
    // not a charge and must not be reported as one.
    if (level < 0.0f) return CTD_ERR_UNSUPPORTED;
    *out = (double)level;
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

static id g_power_watch;
static id g_thermal_watch;
static id g_battery_watch;

void ctd_power_start(void) {
    if (g_power_watch) return;
    ctd_battery_ready();
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
                                         object:nil queue:[NSOperationQueue mainQueue]
                                     usingBlock:tell] retain];
    g_thermal_watch = [[centre addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                                           object:nil queue:[NSOperationQueue mainQueue]
                                       usingBlock:tell] retain];
    // The phone's own, which the Mac has no equivalent of: the battery moved
    // or was plugged in.
    g_battery_watch = [[centre addObserverForName:UIDeviceBatteryStateDidChangeNotification
                                           object:nil queue:[NSOperationQueue mainQueue]
                                       usingBlock:tell] retain];
}

void ctd_power_stop(void) {
    NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
    if (g_power_watch)   { [centre removeObserver:g_power_watch];   [g_power_watch release];   g_power_watch = nil; }
    if (g_thermal_watch) { [centre removeObserver:g_thermal_watch]; [g_thermal_watch release]; g_thermal_watch = nil; }
    if (g_battery_watch) { [centre removeObserver:g_battery_watch]; [g_battery_watch release]; g_battery_watch = nil; }
}
