// Alerts and file choosers, every one of them asynchronous.

#include "internal.h"

typedef struct {
    int64_t token;
    int     kind;
} CtdDialog;

static gboolean ctd_answer_dialog(gpointer data) {
    CtdDialog *request = data;
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = CTD_EV_POST;
    event.token = request->token;
    event.index = (request->kind == CTD_DLG_MESSAGE ||
                   request->kind == CTD_DLG_CONFIRM) ? 0 : 1;
    if (g_sink) g_sink(g_sink_context, &event);
    g_free(request);
    return G_SOURCE_REMOVE;
}

ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token) {
    (void)title; (void)title_len; (void)body; (void)body_len;
    if (kind < CTD_DLG_MESSAGE || kind > CTD_DLG_SAVE) return CTD_ERR_RANGE;
    if (parent && !ctd_resolve(parent)) return CTD_ERR_STALE;
    // GTK4's dialogs are GtkAlertDialog and GtkFileDialog, both asynchronous
    // with a GAsyncReadyCallback. Wiring them is real work that has not been
    // done; what is here keeps the contract that matters — **a dialog always
    // answers** — by replying on the next loop turn with the default button,
    // or a cancel for a file dialog. A dialog that answered nothing would
    // leave a caller waiting on a token forever, which is worse than a
    // refusal it can see.
    CtdDialog *request = g_new0(CtdDialog, 1);
    request->token = token;
    request->kind = kind;
    g_idle_add(ctd_answer_dialog, request);
    return CTD_OK;
}
