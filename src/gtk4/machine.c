// What the machine is doing: whether anything is reachable, and what it costs.
//
// **GIO answers the first question and nothing answers the second portably.**
// `GNetworkMonitor` is GIO's own, it exists on every platform GTK builds for,
// and it carries the two facts a program acts on — is there a path, and is it
// metered. What it does not carry is the *medium*: there is no "this is wifi"
// in GIO, because the backends it wraps do not all know. So a reachable path
// answers CTD_NET_OTHER here, which is what that value is for, and naming the
// medium is deliberately not done: it would need a Linux-only read of
// `/sys/class/net/<if>/wireless`, and this host is built and run on macOS in
// cortado's own gate, where there is no such tree to read and so no leg that
// could ever exercise it.
//
// Power is read from `/sys/class/power_supply`, which is Linux's own answer and
// the only portable one there is — GLib has no battery API and UPower is a
// D-Bus service that may not be running. A machine with no such tree, which
// includes the Mac this host is tested on, has no battery and is on the mains:
// it is running, and nothing else is running it.

#include "internal.h"

#include <stdio.h>
#include <string.h>

static GNetworkMonitor *g_watching;
static gulong           g_watch_id;

static int32_t ctd_kind_now(void) {
    GNetworkMonitor *monitor = g_network_monitor_get_default();
    if (!monitor) return CTD_NET_NONE;
    if (!g_network_monitor_get_network_available(monitor)) return CTD_NET_NONE;
    return CTD_NET_OTHER;
}

static int32_t ctd_flags_now(void) {
    GNetworkMonitor *monitor = g_network_monitor_get_default();
    if (!monitor) return 0;
    // Metered is GIO's word for what the header calls constrained and
    // expensive both: a connection you pay for by the byte is both, and GIO
    // does not tell them apart.
    if (!g_network_monitor_get_network_metered(monitor)) return 0;
    return CTD_NET_F_EXPENSIVE | CTD_NET_F_CONSTRAINED;
}

static void ctd_net_changed(GNetworkMonitor *monitor, gboolean available,
                            gpointer data) {
    (void)monitor; (void)available; (void)data;
    if (!g_sink || !ctd_listening(CTD_EV_NET_CHANGED)) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = CTD_EV_NET_CHANGED;
    out.index = ctd_kind_now();
    out.x = (double)ctd_flags_now();
    g_sink(g_sink_context, &out);
}

void ctd_net_start(void) {
    if (g_watching) return;
    g_watching = g_network_monitor_get_default();
    if (!g_watching) return;
    g_watch_id = g_signal_connect(g_watching, "network-changed",
                                  G_CALLBACK(ctd_net_changed), NULL);
}

void ctd_net_stop(void) {
    if (!g_watching) return;
    if (g_watch_id) g_signal_handler_disconnect(g_watching, g_watch_id);
    g_watch_id = 0;
    g_watching = NULL;
}

ctd_status ctd_net_path(int32_t *out_kind, int32_t *out_flags) {
    // GIO answers now rather than a turn of the loop later, so there is no
    // CTD_NET_UNKNOWN to report here — which is the difference the header
    // describes between a pull and a push, and why a program that wants one
    // golden asks, lets the loop turn, and asks again.
    if (out_kind)  *out_kind = ctd_kind_now();
    if (out_flags) *out_flags = ctd_flags_now();
    return CTD_OK;
}

// ---------------------------------------------------------------- the power

// One whole number out of a sysfs file, or -1 where there is no such file.
static int ctd_sys_int(const char *path) {
    FILE *file = fopen(path, "r");
    if (!file) return -1;
    int value = -1;
    if (fscanf(file, "%d", &value) != 1) value = -1;
    fclose(file);
    return value;
}

// The first battery the kernel lists. Linux numbers them BAT0, BAT1 and so on,
// and a laptop with two reports the one that is charging first — asking about
// both and adding them up would answer about a machine nobody has.
static int ctd_battery_capacity(void) {
    int found = ctd_sys_int("/sys/class/power_supply/BAT0/capacity");
    if (found < 0) found = ctd_sys_int("/sys/class/power_supply/BAT1/capacity");
    return found;
}

ctd_status ctd_power_source(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    int mains = ctd_sys_int("/sys/class/power_supply/AC/online");
    if (mains < 0) mains = ctd_sys_int("/sys/class/power_supply/ACAD/online");
    if (mains < 0) {
        // No such tree: no battery, and a machine that is running is on the
        // mains.
        *out = CTD_POWER_MAINS;
        return CTD_OK;
    }
    *out = mains ? CTD_POWER_MAINS : CTD_POWER_BATTERY;
    return CTD_OK;
}

ctd_status ctd_power_charge(double *out) {
    if (!out) return CTD_ERR_RANGE;
    int capacity = ctd_battery_capacity();
    if (capacity < 0) return CTD_ERR_UNSUPPORTED;
    if (capacity > 100) capacity = 100;
    *out = (double)capacity / 100.0;
    return CTD_OK;
}

ctd_status ctd_power_saving(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    // power-profiles-daemon writes the chosen profile here. It is a D-Bus
    // service and may not be running, in which case there is no file and the
    // answer is no — which is right: a system with no power profiles is not in
    // a saving one.
    FILE *file = fopen("/sys/firmware/acpi/platform_profile", "r");
    if (!file) { *out = 0; return CTD_OK; }
    char word[32] = {0};
    int read = fscanf(file, "%31s", word);
    fclose(file);
    *out = (read == 1 && strcmp(word, "low-power") == 0) ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_thermal_state(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    // A temperature in a sysfs file is a reading; CTD_THERMAL_* is a
    // judgement, and turning one into the other means deciding what counts as
    // hot for a machine this code has never seen. Only Apple's platforms ship
    // that judgement, so the honest answer here is that nobody knows.
    *out = CTD_THERMAL_UNKNOWN;
    return CTD_OK;
}

void ctd_power_start(void) { }
void ctd_power_stop(void) { }
