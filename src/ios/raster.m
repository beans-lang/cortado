#import "internal.h"

ctd_status ctd_canvas_set_pixels(ctd_handle canvas, int32_t width, int32_t height,
                                 const char *rgba, int32_t length) {
    (void)canvas; (void)width; (void)height; (void)rgba; (void)length;
    return CTD_ERR_UNSUPPORTED;
}
