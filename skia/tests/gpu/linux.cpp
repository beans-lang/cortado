#include "../../bridge.h"
#include <GL/gl.h>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <vector>

static void frame(void* engine) {
    assert(ctd_skia_begin(engine, 48, 32, 1, 0xffffffff) == 0);
    assert(ctd_skia_rect(engine, 4, 4, 24, 20, 0, 0x3578dfff, 0) == 0);
    assert(ctd_skia_end(engine) == 0);
    double size[2]{};
    std::vector<char> pixels(48 * 32 * 4);
    assert(ctd_skia_pixels(engine, size, pixels.data(), pixels.size()) == pixels.size());
    assert(size[0] == 48 && size[1] == 32);
    const int at = (12 * 48 + 12) * 4;
    assert(static_cast<unsigned char>(pixels[at]) < 100);
    assert(static_cast<unsigned char>(pixels[at + 2]) > 150);
}

int main() {
    void* engine = ctd_skia_new();
    assert(engine && ctd_skia_backend(engine) == 0);
    frame(engine);
    std::puts("software: rendered and read back");
    assert(ctd_skia_select_backend(engine, 3) == 0);
    assert(ctd_skia_backend(engine) == 3);
    const char* renderer = reinterpret_cast<const char*>(glGetString(GL_RENDERER));
    std::printf("OpenGL renderer: %s\n", renderer ? renderer : "unknown");
    frame(engine);
    std::puts("OpenGL Skia target: rendered and read back");
    assert(ctd_skia_recover_software(engine) == 0);
    assert(ctd_skia_backend(engine) == 0);
    frame(engine);
    std::puts("software recovery: rendered and read back");
    ctd_skia_delete(engine);
}
