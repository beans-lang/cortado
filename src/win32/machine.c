// What the machine is doing: whether anything is reachable, and what it costs.
//
// Both are a **pull** here, which is the other half of the shape the header
// describes: `GetAdaptersAddresses` and `GetSystemPowerStatus` answer now, and
// the push is synthesised from the messages Windows already sends a window.
//
// **A gateway is not the test for reachability on this host**, and that was
// measured rather than assumed: Wine leaves `FirstGatewayAddress` empty on
// every adapter, so a host that asked for one would report a machine with a
// working network as having none — and would do it only under the emulator
// that cortado's Windows leg runs on, which is the worst place for a
// difference to hide. An adapter that is up and is not the loopback is the
// test.

// **Before internal.h, and that is not a style choice.** `windows.h` pulls in
// Winsock 1, whose sockaddr differs from Winsock 2's, and `iphlpapi.h` is
// written against Winsock 2 — so including it after `windows.h` leaves every
// adapter structure undeclared. Including winsock2 first defines the guard
// that stops `windows.h` bringing the older one in.
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>

#include "internal.h"

// IF_TYPE_WWANPP and IF_TYPE_WWANPP2 are mobile broadband. They are in the
// IANA list rather than in a Windows header worth relying on.
#define CTD_IF_WWANPP   243
#define CTD_IF_WWANPP2  244

static int32_t ctd_kind_now(int32_t *flags) {
    if (flags) *flags = 0;
    ULONG size = 0;
    ULONG want = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                 GAA_FLAG_SKIP_DNS_SERVER;
    GetAdaptersAddresses(AF_UNSPEC, want, NULL, NULL, &size);
    if (size == 0) return CTD_NET_NONE;
    IP_ADAPTER_ADDRESSES *list = (IP_ADAPTER_ADDRESSES *)malloc(size);
    if (!list) return CTD_NET_NONE;
    int32_t kind = CTD_NET_NONE;
    if (GetAdaptersAddresses(AF_UNSPEC, want, NULL, list, &size) == NO_ERROR) {
        for (IP_ADAPTER_ADDRESSES *one = list; one; one = one->Next) {
            if (one->OperStatus != IfOperStatusUp) continue;
            if (one->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
            if (one->IfType == CTD_IF_WWANPP || one->IfType == CTD_IF_WWANPP2) {
                // Mobile broadband costs money by the byte, which is what the
                // two flags are for. It also wins over anything else found, so
                // the search stops.
                if (flags) *flags = CTD_NET_F_EXPENSIVE | CTD_NET_F_CONSTRAINED;
                kind = CTD_NET_CELLULAR;
                break;
            }
            if (one->IfType == IF_TYPE_IEEE80211) kind = CTD_NET_WIFI;
            else if (kind == CTD_NET_NONE)        kind = CTD_NET_WIRED;
        }
    }
    free(list);
    return kind;
}

ctd_status ctd_net_path(int32_t *out_kind, int32_t *out_flags) {
    int32_t flags = 0;
    int32_t kind = ctd_kind_now(&flags);
    if (out_kind)  *out_kind = kind;
    if (out_flags) *out_flags = flags;
    return CTD_OK;
}

// Windows tells a *window* that the network changed, through the same
// WM_SETTINGCHANGE broadcast that carries a theme change, so there is nothing
// to start and nothing to stop: the message arrives whether or not anybody
// asked, and ctd_listening is what decides whether it costs the program
// anything. The pair exists so this host answers the same shape as the others.
void ctd_net_start(void) { }
void ctd_net_stop(void) { }
void ctd_power_start(void) { }
void ctd_power_stop(void) { }

// Raised from the window procedure when Windows says a power state changed.
void ctd_power_changed(void) {
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
}

void ctd_net_changed(void) {
    if (!g_sink || !ctd_listening(CTD_EV_NET_CHANGED)) return;
    int32_t flags = 0;
    int32_t kind = ctd_kind_now(&flags);
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = CTD_EV_NET_CHANGED;
    out.index = kind;
    out.x = (double)flags;
    g_sink(g_sink_context, &out);
}

// ---------------------------------------------------------------- the power

ctd_status ctd_power_source(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    SYSTEM_POWER_STATUS power;
    if (!GetSystemPowerStatus(&power)) { *out = CTD_POWER_UNKNOWN; return CTD_OK; }
    if (power.ACLineStatus == 1) { *out = CTD_POWER_MAINS;   return CTD_OK; }
    if (power.ACLineStatus == 0) { *out = CTD_POWER_BATTERY; return CTD_OK; }
    // 255 is "unknown" in Windows' own words, and a machine with no battery
    // reports it — which is the mains, because the machine is running.
    *out = (power.BatteryFlag & BATTERY_FLAG_NO_BATTERY) ? CTD_POWER_MAINS
                                                         : CTD_POWER_UNKNOWN;
    return CTD_OK;
}

ctd_status ctd_power_charge(double *out) {
    if (!out) return CTD_ERR_RANGE;
    SYSTEM_POWER_STATUS power;
    if (!GetSystemPowerStatus(&power)) return CTD_ERR_UNSUPPORTED;
    if (power.BatteryFlag & BATTERY_FLAG_NO_BATTERY) return CTD_ERR_UNSUPPORTED;
    // 255 means Windows does not know, which is not the same as full and must
    // not be reported as a number.
    if (power.BatteryLifePercent > 100) return CTD_ERR_UNSUPPORTED;
    *out = (double)power.BatteryLifePercent / 100.0;
    return CTD_OK;
}

ctd_status ctd_power_saving(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    SYSTEM_POWER_STATUS power;
    if (!GetSystemPowerStatus(&power)) { *out = 0; return CTD_OK; }
    *out = power.SystemStatusFlag ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_thermal_state(int32_t *out) {
    if (!out) return CTD_ERR_RANGE;
    // Windows has no scale for this. There is a thermal zone in WMI and what
    // counts as hot on one machine is not what counts on another, so turning a
    // temperature into CTD_THERMAL_* would be inventing the judgement rather
    // than reporting one.
    *out = CTD_THERMAL_UNKNOWN;
    return CTD_OK;
}
