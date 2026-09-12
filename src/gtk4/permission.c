// What the operating system will let this program do, and how to ask.
//
// This platform has no privacy layer of the kind macOS and iOS have: a Linux
// program that opens a camera is refused by the device node's permissions, and
// there is no per-application grant to read or to request. So every permission
// answers CTD_ALLOW_UNAVAILABLE — "there is no answer to be had" — rather than
// "granted", which would be a promise this host cannot keep, or "denied",
// which would stop a program that would in fact have worked.
//
// The refusal is the point. A program that asks is told; a program that does
// not ask and just opens the device gets the platform's own answer, which is
// the right one here.

#include "internal.h"

ctd_status ctd_permission_status(int32_t what, int32_t *out) {
    if (what < CTD_PERM_BLUETOOTH || what > CTD_PERM_MOTION) return CTD_ERR_RANGE;
    if (out) *out = CTD_ALLOW_UNAVAILABLE;
    return CTD_OK;
}

ctd_status ctd_permission_request(int32_t what, int64_t token) {
    (void)token;
    if (what < CTD_PERM_BLUETOOTH || what > CTD_PERM_MOTION) return CTD_ERR_RANGE;
    // Nothing to prompt with, so nothing is prompted. A caller that treated
    // silence as "asked and waiting" would wait for ever.
    return CTD_ERR_UNSUPPORTED;
}
