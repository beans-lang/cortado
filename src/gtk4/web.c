// A browser engine in a rectangle — or rather, the absence of one.

#include "internal.h"

// ------------------------------------------------------------- web views
//
// There is none on this platform, and both halves of that are worth stating.
//
// // GTK's browser engine is WebKitGTK, which is a *separate library* — not part
// of GTK and not on every machine that has GTK. A control that appeared on a
// developer's box and was an empty grey rectangle on a user's would be worse
// than one that says it is not there, and linking a library cortado's manifest
// cannot promise is present is how that happens.
//
// So CTD_W_WEB_VIEW cannot be built here, ctd_capability(CTD_CAP_WEB) answers
// 0, and every call below refuses by kind — which is the refusal a caller gets
// for a handle that is not a web view on every other host too, and is true here
// of every handle there is.
ctd_status ctd_web_load(ctd_handle widget, const char *url, int32_t len) {
    (void)url; (void)len;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_web_load_html(ctd_handle widget, const char *html, int32_t html_len,
                             const char *base, int32_t base_len) {
    (void)html; (void)html_len; (void)base; (void)base_len;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_web_eval(ctd_handle widget, const char *source, int32_t len,
                        int64_t token) {
    (void)source; (void)len; (void)token;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_web_listen(ctd_handle widget, const char *name, int32_t len) {
    (void)name; (void)len;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

int32_t ctd_web_take(ctd_handle widget, int64_t token, char *out, int32_t cap) {
    (void)token; (void)out; (void)cap;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

int32_t ctd_web_url(ctd_handle widget, char *out, int32_t cap) {
    (void)out; (void)cap;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

int32_t ctd_web_title(ctd_handle widget, char *out, int32_t cap) {
    (void)out; (void)cap;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_web_can_go(ctd_handle widget, int32_t back, int32_t *out) {
    (void)back;
    if (out) *out = 0;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_web_go(ctd_handle widget, int32_t back) {
    (void)back;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_web_reload(ctd_handle widget) {
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_web_stop(ctd_handle widget) {
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}
