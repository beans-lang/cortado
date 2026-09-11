/* The parts of the contract that are the same code on every host.
 *
 * `cortado_host.h` is the contract's *shape* — what each platform must
 * implement. This file is the contract's *decisions*: the questions whose
 * answer is cortado's rather than any platform's, written once so four hosts
 * cannot drift into four answers.
 *
 * It is a separate header rather than a `static inline` in `cortado_host.h`
 * for a mechanical reason: `tools/check_hosts.sh` and `tools/check_abi.sh`
 * read every `ctd_*(` in that file as an entry point every host must define
 * and every binding must bind. A helper there would be demanded of both.
 */
#ifndef CORTADO_RULES_H
#define CORTADO_RULES_H

#include <stdint.h>
#include "cortado_host.h"

/* Whether a kind carries CTD_P_ENABLED — the rule stated in full beside
 * CTD_P_ENABLED in cortado_host.h.
 *
 * A widget has an enabled state exactly when it accepts input. Everything
 * else answers CTD_ERR_KIND, on every host, from both the setter and the
 * getter.
 *
 * Before this existed each host asked its own object system instead, and the
 * object systems disagree: a label is an NSControl and is not a UIControl, and
 * every GtkWidget is sensitive. That is not a difference between platforms, it
 * is four guesses at a question nobody had answered. */
static inline int ctd_kind_has_enabled(int32_t kind) {
    return kind == CTD_W_BUTTON
        || kind == CTD_W_TEXT_FIELD
        || kind == CTD_W_CHECK_BOX
        || kind == CTD_W_RADIO_BUTTON
        || kind == CTD_W_SLIDER
        || kind == CTD_W_COMBO_BOX;
}

#endif
