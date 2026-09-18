/* Graphics-library loading only. This process-wide immutable library handle
 * owns no windows or UI state. The engine contexts themselves are per-window. */
#include "bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#define CTD_LIBRARY "cortado_skia_engine.dll"
static HMODULE library;
static INIT_ONCE library_once = INIT_ONCE_STATIC_INIT;
#else
#include <dlfcn.h>
#include <pthread.h>
#ifdef __APPLE__
#define CTD_LIBRARY "libcortado_skia_engine.dylib"
#else
#define CTD_LIBRARY "libcortado_skia_engine.so"
#endif
static void *library;
static pthread_once_t library_once = PTHREAD_ONCE_INIT;
#endif

static void ctd_skia_load(void) {
    const char *configured = getenv("CORTADO_SKIA_LIBRARY");
    char path[4096];
    if (configured && configured[0]) {
        if (strlen(configured) >= sizeof(path)) return;
        strcpy(path, configured);
    } else {
        /* Package development fallback. Installed apps supply the absolute
         * path of their bundled engine through CORTADO_SKIA_LIBRARY. */
        const char *source = __FILE__;
        const char *tail = strrchr(source, '/');
#ifdef _WIN32
        const char *backslash = strrchr(source, '\\');
        if (backslash && (!tail || backslash > tail)) tail = backslash;
#endif
        if (!tail || (size_t)(tail - source) > sizeof(path) - 80) return;
        snprintf(path, sizeof(path), "%.*s/../build/skia/lib/%s", (int)(tail - source), source, CTD_LIBRARY);
    }
#ifdef _WIN32
    library = LoadLibraryA(path);
#else
    library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
#endif
    if (!library)
        fprintf(stderr, "Cortado: cannot load Skia engine at %s; run tools/prepare_skia.py\n", path);
}
#ifdef _WIN32
static BOOL CALLBACK ctd_skia_load_once(PINIT_ONCE once, PVOID parameter, PVOID *context) {
    (void)once; (void)parameter; (void)context;
    ctd_skia_load();
    return TRUE;
}
#endif
static void *ctd_skia_symbol(const char *symbol) {
#ifdef _WIN32
    InitOnceExecuteOnce(&library_once, ctd_skia_load_once, NULL, NULL);
    return library ? (void *)GetProcAddress(library, symbol) : NULL;
#else
    pthread_once(&library_once, ctd_skia_load);
    return library ? dlsym(library, symbol) : NULL;
#endif
}

void * ctd_skia_new(void) {
    typedef void * (*Function)(void);
    Function function = (Function)ctd_skia_symbol("ctd_skia_new");
    return function ? function() : 0;
}

void ctd_skia_delete(void *context) {
    typedef void (*Function)(void *context);
    Function function = (Function)ctd_skia_symbol("ctd_skia_delete");
    if (function) function(context);
}

int32_t ctd_skia_backend(void *context) {
    typedef int32_t (*Function)(void *);
    Function function = (Function)ctd_skia_symbol("ctd_skia_backend");
    return function ? function(context) : -1;
}

int32_t ctd_skia_select_backend(void *context, int32_t preferred) {
    typedef int32_t (*Function)(void *, int32_t);
    Function function = (Function)ctd_skia_symbol("ctd_skia_select_backend");
    return function ? function(context, preferred) : -1;
}

int32_t ctd_skia_recover_software(void *context) {
    typedef int32_t (*Function)(void *);
    Function function = (Function)ctd_skia_symbol("ctd_skia_recover_software");
    return function ? function(context) : -1;
}

int32_t ctd_skia_begin(void *context, double width, double height, double scale, uint32_t rgba) {
    typedef int32_t (*Function)(void *context, double width, double height, double scale, uint32_t rgba);
    Function function = (Function)ctd_skia_symbol("ctd_skia_begin");
    return function ? function(context, width, height, scale, rgba) : -1;
}

int32_t ctd_skia_end(void *context) {
    typedef int32_t (*Function)(void *context);
    Function function = (Function)ctd_skia_symbol("ctd_skia_end");
    return function ? function(context) : -1;
}

int32_t ctd_skia_save(void *context) {
    typedef int32_t (*Function)(void *context);
    Function function = (Function)ctd_skia_symbol("ctd_skia_save");
    return function ? function(context) : -1;
}

int32_t ctd_skia_restore(void *context) {
    typedef int32_t (*Function)(void *context);
    Function function = (Function)ctd_skia_symbol("ctd_skia_restore");
    return function ? function(context) : -1;
}

int32_t ctd_skia_translate(void *context, double x, double y) {
    typedef int32_t (*Function)(void *context, double x, double y);
    Function function = (Function)ctd_skia_symbol("ctd_skia_translate");
    return function ? function(context, x, y) : -1;
}

int32_t ctd_skia_rotate(void *context, double degrees) {
    typedef int32_t (*Function)(void *, double);
    Function function = (Function)ctd_skia_symbol("ctd_skia_rotate");
    return function ? function(context, degrees) : -1;
}

int32_t ctd_skia_scale(void *context, double x, double y) {
    typedef int32_t (*Function)(void *, double, double);
    Function function = (Function)ctd_skia_symbol("ctd_skia_scale");
    return function ? function(context, x, y) : -1;
}

int32_t ctd_skia_clip(void *context, double x, double y, double width, double height, double radius) {
    typedef int32_t (*Function)(void *context, double x, double y, double width, double height, double radius);
    Function function = (Function)ctd_skia_symbol("ctd_skia_clip");
    return function ? function(context, x, y, width, height, radius) : -1;
}

int32_t ctd_skia_rect(void *context, double x, double y, double width, double height,
                      double radius, uint32_t rgba, double stroke) {
    typedef int32_t (*Function)(void *context, double x, double y, double width, double height,
                      double radius, uint32_t rgba, double stroke);
    Function function = (Function)ctd_skia_symbol("ctd_skia_rect");
    return function ? function(context, x, y, width, height, radius, rgba, stroke) : -1;
}

int32_t ctd_skia_ellipse(void *context, double x, double y, double width, double height,
                         uint32_t fill, uint32_t outline, double stroke) {
    typedef int32_t (*Function)(void *, double, double, double, double, uint32_t, uint32_t, double);
    Function function = (Function)ctd_skia_symbol("ctd_skia_ellipse");
    return function ? function(context, x, y, width, height, fill, outline, stroke) : -1;
}

int32_t ctd_skia_path(void *context, const char *data, int32_t length,
                      uint32_t fill, uint32_t outline, double stroke) {
    typedef int32_t (*Function)(void *, const char *, int32_t, uint32_t, uint32_t, double);
    Function function = (Function)ctd_skia_symbol("ctd_skia_path");
    return function ? function(context, data, length, fill, outline, stroke) : -1;
}

int32_t ctd_skia_visual(void *context, int32_t kind, double x, double y, double width, double height,
                        const char *data, int32_t length, uint32_t fill, uint32_t outline,
                        double stroke, uint32_t gradient_start, uint32_t gradient_end,
                        int32_t gradient_enabled,
                        uint32_t shadow_color, double shadow_blur, double shadow_dx,
                        double shadow_dy, double clip_radius,
                        int32_t stroke_cap, int32_t stroke_join) {
    typedef int32_t (*Function)(void *, int32_t, double, double, double, double, const char *, int32_t,
                                uint32_t, uint32_t, double, uint32_t, uint32_t, int32_t, uint32_t,
                                double, double, double, double, int32_t, int32_t);
    Function function = (Function)ctd_skia_symbol("ctd_skia_visual");
    return function ? function(context, kind, x, y, width, height, data, length, fill, outline,
                               stroke, gradient_start, gradient_end, gradient_enabled,
                               shadow_color, shadow_blur, shadow_dx, shadow_dy, clip_radius,
                               stroke_cap, stroke_join) : -1;
}

uint64_t ctd_skia_image_new(void *context, const char *source, int32_t length) {
    typedef uint64_t (*Function)(void *, const char *, int32_t);
    Function function = (Function)ctd_skia_symbol("ctd_skia_image_new");
    return function ? function(context, source, length) : 0;
}

int32_t ctd_skia_image_release(void *context, uint64_t image) {
    typedef int32_t (*Function)(void *, uint64_t);
    Function function = (Function)ctd_skia_symbol("ctd_skia_image_release");
    return function ? function(context, image) : -1;
}

int32_t ctd_skia_image_size(void *context, uint64_t image, double *size) {
    typedef int32_t (*Function)(void *, uint64_t, double *);
    Function function = (Function)ctd_skia_symbol("ctd_skia_image_size");
    return function ? function(context, image, size) : -1;
}

int32_t ctd_skia_image_draw(void *context, uint64_t image,
                             double x, double y, double width, double height) {
    typedef int32_t (*Function)(void *, uint64_t, double, double, double, double);
    Function function = (Function)ctd_skia_symbol("ctd_skia_image_draw");
    return function ? function(context, image, x, y, width, height) : -1;
}

uint64_t ctd_skia_paragraph_new(void *context, const char *text, int32_t length,
                               double size, double width, uint32_t rgba,
                               int32_t weight, double tracking, int32_t align) {
    typedef uint64_t (*Function)(void *context, const char *text, int32_t length,
                               double size, double width, uint32_t rgba,
                               int32_t weight, double tracking, int32_t align);
    Function function = (Function)ctd_skia_symbol("ctd_skia_paragraph_new");
    return function ? function(context, text, length, size, width, rgba,
                               weight, tracking, align) : 0;
}

int32_t ctd_skia_font_register(void *context, const char *path, int32_t length) {
    typedef int32_t (*Function)(void *context, const char *path, int32_t length);
    Function function = (Function)ctd_skia_symbol("ctd_skia_font_register");
    return function ? function(context, path, length) : -1;
}

int32_t ctd_skia_paragraph_metrics(void *context, uint64_t paragraph, double *out) {
    typedef int32_t (*Function)(void *context, uint64_t paragraph, double *out);
    Function function = (Function)ctd_skia_symbol("ctd_skia_paragraph_metrics");
    return function ? function(context, paragraph, out) : -1;
}

int32_t ctd_skia_paragraph_release(void *context, uint64_t paragraph) {
    typedef int32_t (*Function)(void *context, uint64_t paragraph);
    Function function = (Function)ctd_skia_symbol("ctd_skia_paragraph_release");
    return function ? function(context, paragraph) : -1;
}

int32_t ctd_skia_paragraph_size(void *context, uint64_t paragraph, double *size) {
    typedef int32_t (*Function)(void *context, uint64_t paragraph, double *size);
    Function function = (Function)ctd_skia_symbol("ctd_skia_paragraph_size");
    return function ? function(context, paragraph, size) : -1;
}

int32_t ctd_skia_paragraph_paint(void *context, uint64_t paragraph, double x, double y) {
    typedef int32_t (*Function)(void *context, uint64_t paragraph, double x, double y);
    Function function = (Function)ctd_skia_symbol("ctd_skia_paragraph_paint");
    return function ? function(context, paragraph, x, y) : -1;
}

int32_t ctd_skia_paragraph_hit(void *context, uint64_t paragraph, double x, double y) {
    typedef int32_t (*Function)(void *context, uint64_t paragraph, double x, double y);
    Function function = (Function)ctd_skia_symbol("ctd_skia_paragraph_hit");
    return function ? function(context, paragraph, x, y) : -1;
}

int32_t ctd_skia_paragraph_caret(void *context, uint64_t paragraph, int32_t offset, double *rect) {
    typedef int32_t (*Function)(void *context, uint64_t paragraph, int32_t offset, double *rect);
    Function function = (Function)ctd_skia_symbol("ctd_skia_paragraph_caret");
    return function ? function(context, paragraph, offset, rect) : -1;
}

int32_t ctd_skia_graphemes(void *context, const char *text, int32_t length, int32_t *out, int32_t capacity) {
    typedef int32_t (*Function)(void *context, const char *text, int32_t length, int32_t *out, int32_t capacity);
    Function function = (Function)ctd_skia_symbol("ctd_skia_graphemes");
    return function ? function(context, text, length, out, capacity) : -1;
}

int32_t ctd_skia_paragraph_selection(void *context, uint64_t paragraph, int32_t first,
                                    int32_t last, double *out, int32_t capacity) {
    typedef int32_t (*Function)(void *, uint64_t, int32_t, int32_t, double *, int32_t);
    Function function = (Function)ctd_skia_symbol("ctd_skia_paragraph_selection");
    return function ? function(context, paragraph, first, last, out, capacity) : -1;
}

int32_t ctd_skia_pixels(void *context, double *size, char *out, int32_t capacity) {
    typedef int32_t (*Function)(void *context, double *size, char *out, int32_t capacity);
    Function function = (Function)ctd_skia_symbol("ctd_skia_pixels");
    return function ? function(context, size, out, capacity) : -1;
}

int32_t ctd_skia_png(void *context, const char *path, int32_t length) {
    typedef int32_t (*Function)(void *context, const char *path, int32_t length);
    Function function = (Function)ctd_skia_symbol("ctd_skia_png");
    return function ? function(context, path, length) : -1;
}
