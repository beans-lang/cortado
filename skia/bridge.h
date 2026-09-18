#ifndef CORTADO_SKIA_BRIDGE_H
#define CORTADO_SKIA_BRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Private engine ABI. No widget state, layout or control behavior belongs here.
 * Strings are length-delimited UTF-8. Text positions are UTF-8 byte offsets.
 * Contexts and their resources are confined to the creating thread. */
void *ctd_skia_new(void);
void ctd_skia_delete(void *context);
/* software=0, metal=1, vulkan=2, opengl=3, automatic=4.
 * Query reports the actual active backend, never automatic. */
int32_t ctd_skia_backend(void *context);
int32_t ctd_skia_select_backend(void *context, int32_t preferred);
int32_t ctd_skia_recover_software(void *context);
int32_t ctd_skia_begin(void *context, double width, double height, double scale, uint32_t rgba);
int32_t ctd_skia_end(void *context);
int32_t ctd_skia_save(void *context);
int32_t ctd_skia_restore(void *context);
int32_t ctd_skia_translate(void *context, double x, double y);
int32_t ctd_skia_rotate(void *context, double degrees);
int32_t ctd_skia_scale(void *context, double x, double y);
int32_t ctd_skia_clip(void *context, double x, double y, double width, double height, double radius);
int32_t ctd_skia_rect(void *context, double x, double y, double width, double height,
                      double radius, uint32_t rgba, double stroke);
int32_t ctd_skia_ellipse(void *context, double x, double y, double width, double height,
                         uint32_t fill, uint32_t outline, double stroke);
int32_t ctd_skia_path(void *context, const char *data, int32_t length,
                      uint32_t fill, uint32_t outline, double stroke);
/* kind: 0 rectangle, 1 ellipse, 2 path, 3 rounded rectangle. */
int32_t ctd_skia_visual(void *context, int32_t kind, double x, double y, double width, double height,
                        const char *data, int32_t length, uint32_t fill, uint32_t outline,
                        double stroke, uint32_t gradient_start, uint32_t gradient_end,
                        int32_t gradient_enabled,
                        uint32_t shadow_color, double shadow_blur, double shadow_dx,
                        double shadow_dy, double clip_radius,
                        int32_t stroke_cap, int32_t stroke_join);
uint64_t ctd_skia_image_new(void *context, const char *source, int32_t length);
int32_t ctd_skia_image_release(void *context, uint64_t image);
int32_t ctd_skia_image_size(void *context, uint64_t image, double *size);
int32_t ctd_skia_image_draw(void *context, uint64_t image,
                             double x, double y, double width, double height);
/* weight: 0 default, 1 light, 2 regular, 3 medium, 4 semibold, 5 bold, 6 heavy.
 * align: 0 leading, 1 centre, 2 trailing. tracking is in points. */
uint64_t ctd_skia_paragraph_new(void *context, const char *text, int32_t length,
                               double size, double width, uint32_t rgba,
                               int32_t weight, double tracking, int32_t align);
/* Registers one font file as the family every later paragraph uses, on every
 * platform. An empty path returns to the platform's own UI font. */
int32_t ctd_skia_font_register(void *context, const char *path, int32_t length);
/* ascent, descent, line height, baseline from the top. Four doubles. */
int32_t ctd_skia_paragraph_metrics(void *context, uint64_t paragraph, double *out);
int32_t ctd_skia_paragraph_release(void *context, uint64_t paragraph);
int32_t ctd_skia_paragraph_size(void *context, uint64_t paragraph, double *size);
int32_t ctd_skia_paragraph_paint(void *context, uint64_t paragraph, double x, double y);
int32_t ctd_skia_paragraph_hit(void *context, uint64_t paragraph, double x, double y);
int32_t ctd_skia_paragraph_caret(void *context, uint64_t paragraph, int32_t offset, double *rect);
/* Returns rectangle count, or a negative error. Capacity counts rectangles;
 * each rectangle uses four doubles: x, y, width, height. Null out probes size. */
int32_t ctd_skia_paragraph_selection(void *context, uint64_t paragraph, int32_t first,
                                    int32_t last, double *out, int32_t capacity);
int32_t ctd_skia_graphemes(void *context, const char *text, int32_t length, int32_t *out, int32_t capacity);
int32_t ctd_skia_pixels(void *context, double *size, char *out, int32_t capacity);
int32_t ctd_skia_png(void *context, const char *path, int32_t length);
#ifdef __cplusplus
}
#endif
#endif
