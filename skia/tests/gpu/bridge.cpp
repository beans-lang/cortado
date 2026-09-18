#include "../../bridge.h"
#include <cassert>
#include <cstdint>
#include <cstring>
#include <vector>

int main() {
    void* engine = ctd_skia_new();
    assert(engine);
    assert(ctd_skia_backend(engine) == 0);
    assert(ctd_skia_select_backend(engine, 99) < 0);
    assert(ctd_skia_backend(engine) == 0);
#ifdef __APPLE__
    assert(ctd_skia_select_backend(engine, 1) == 0);
    assert(ctd_skia_backend(engine) == 1);
    assert(ctd_skia_select_backend(engine, 2) < 0);
    assert(ctd_skia_backend(engine) == 1);
#else
    assert(ctd_skia_select_backend(engine, 4) == 0);
#endif
    assert(ctd_skia_begin(engine, 64, 48, 1, 0xffffffff) == 0);
    assert(ctd_skia_recover_software(engine) < 0);
    assert(ctd_skia_rect(engine, 4, 4, 24, 24, 3, 0xd03020ff, 0) == 0);
    assert(ctd_skia_end(engine) == 0);
    double size[2] = {0, 0};
    assert(ctd_skia_pixels(engine, size, nullptr, 0) == 64 * 48 * 4);
    std::vector<char> pixels(64 * 48 * 4);
    assert(ctd_skia_pixels(engine, size, pixels.data(), pixels.size()) == pixels.size());
    assert(static_cast<unsigned char>(pixels[(12 * 64 + 12) * 4]) !=
           static_cast<unsigned char>(pixels[0]));
    constexpr char path[] = "build/skia-gpu-bridge.png";
    assert(ctd_skia_png(engine, path, sizeof(path) - 1) == 0);
    constexpr char source[] = "examples/rendered/assets/tiles.png";
    const uint64_t image1 = ctd_skia_image_new(engine, source, sizeof(source) - 1);
    const uint64_t image2 = ctd_skia_image_new(engine, source, sizeof(source) - 1);
    assert(image1 != 0 && image1 == image2);
    assert(ctd_skia_image_size(engine, image1, size) == 0);
    assert(size[0] == 48 && size[1] == 48);
    assert(ctd_skia_image_release(engine, image1) == 0);
    assert(ctd_skia_begin(engine, 64, 48, 1, 0xffffffff) == 0);
    assert(ctd_skia_image_draw(engine, image2, 0, 0, 48, 48) == 0);
    assert(ctd_skia_end(engine) == 0);
    assert(ctd_skia_pixels(engine, size, pixels.data(), pixels.size()) == pixels.size());
    assert(static_cast<unsigned char>(pixels[0]) != 255);
    assert(ctd_skia_image_release(engine, image2) == 0);
    assert(ctd_skia_image_size(engine, image2, size) < 0);
    assert(ctd_skia_recover_software(engine) == 0);
    assert(ctd_skia_backend(engine) == 0);
    assert(ctd_skia_begin(engine, 8, 8, 1, 0xffffffff) == 0);
    assert(ctd_skia_end(engine) == 0);
    ctd_skia_delete(engine);
}
