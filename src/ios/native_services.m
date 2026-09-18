#import "internal.h"

/* The shared canvas is desktop-only. iOS keeps its native text controls and
 * explicitly refuses these opt-in desktop services. */
ctd_status ctd_canvas_text_state(ctd_handle canvas, int32_t active,
    const char *utf8, int32_t length, int32_t anchor, int32_t caret,
    double x, double y, double width, double height) {
    (void)canvas; (void)active; (void)utf8; (void)length; (void)anchor; (void)caret;
    (void)x; (void)y; (void)width; (void)height;
    return CTD_ERR_UNSUPPORTED;
}
int32_t ctd_reduce_motion(void) {
    return UIAccessibilityIsReduceMotionEnabled() ? 1 : 0;
}
ctd_status ctd_clipboard_write(const char *utf8, int32_t length) {
    (void)utf8; (void)length;
    return CTD_ERR_UNSUPPORTED;
}
int32_t ctd_clipboard_read(char *out, int32_t cap) {
    (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}
ctd_status ctd_canvas_semantics_clear(ctd_handle canvas) {
    (void)canvas;
    return CTD_ERR_UNSUPPORTED;
}
ctd_status ctd_canvas_semantics_add(ctd_handle canvas, uint64_t node_id,
    const char *role, int32_t role_len, const char *label, int32_t label_len,
    const char *value, int32_t value_len, double x, double y,
    double width, double height, int32_t enabled, int32_t focused) {
    (void)canvas; (void)node_id; (void)role; (void)role_len; (void)label;
    (void)label_len; (void)value; (void)value_len; (void)x; (void)y;
    (void)width; (void)height; (void)enabled; (void)focused;
    return CTD_ERR_UNSUPPORTED;
}
ctd_status ctd_canvas_semantics_end(ctd_handle canvas) {
    (void)canvas;
    return CTD_ERR_UNSUPPORTED;
}
