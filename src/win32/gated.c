// Where the machine is, what is nearby, what it can see and hear, and what is
// on its screen — none of which this host does.
//
// **A refusal that is written down, not a stub that was forgotten.** Every one
// of these exists on Windows: Windows.Devices.Bluetooth speaks Bluetooth, the
// Geolocation API answers where the machine is, Media Foundation enumerates
// cameras, and the Graphics Capture API records the screen. All four are
// WinRT — which means a C++/WinRT toolchain this package does not have, and a
// runtime an older Windows does not carry.
//
// That is a real port, and worth doing. What it is not is something to half-do
// behind an entry point that answers zero: a program asking "how many cameras"
// and hearing "none" cannot tell a machine with no camera from a library that
// never looked. So `ctd_capability` answers 0 for all four, every call here
// refuses by name, and `tests/gated.b` prints the same bytes through this host
// as through the Mac — because what it checks is that nothing here pretends.

#include "internal.h"

ctd_status ctd_location_start(void) { return CTD_ERR_UNSUPPORTED; }
ctd_status ctd_location_stop(void)  { return CTD_ERR_UNSUPPORTED; }

ctd_status ctd_location_last(double *out) {
    (void)out;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_ble_scan(int32_t on) {
    (void)on;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_ble_count(void) { return 0; }

int32_t ctd_ble_name(int32_t row, char *out, int32_t cap) {
    (void)row; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_ble_id(int32_t row, char *out, int32_t cap) {
    (void)row; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_ble_signal(int32_t row, double *out) {
    (void)row; (void)out;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_ble_connect(int32_t row, int32_t on) {
    (void)row; (void)on;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_ble_linked(int32_t row) {
    (void)row;
    return 0;
}

int32_t ctd_capture_count(int32_t kind) {
    (void)kind;
    return 0;
}

int32_t ctd_capture_name(int32_t kind, int32_t row, char *out, int32_t cap) {
    (void)kind; (void)row; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_capture_is_default(int32_t kind, int32_t row) {
    (void)kind; (void)row;
    return 0;
}

int32_t ctd_screen_count(void) { return 0; }

ctd_status ctd_screen_size(int32_t display, double *out) {
    (void)display; (void)out;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_screen_capture(int32_t display, int64_t token) {
    (void)display; (void)token;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_screen_take(int64_t token, double *out_size, uint8_t *out, int32_t cap) {
    (void)token; (void)out_size; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}
