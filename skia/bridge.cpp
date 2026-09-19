#include "bridge.h"
#include "gpu_backend.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkData.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkImage.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkRRect.h"
#include "include/core/SkSamplingOptions.h"
#include "include/core/SkStream.h"
#include "include/core/SkSurface.h"
#include "include/gpu/ganesh/SkSurfaceGanesh.h"
#include "include/encode/SkPngEncoder.h"
#include "include/utils/SkParsePath.h"
#include "include/effects/SkGradientShader.h"
#include "include/effects/SkImageFilters.h"
#include "modules/skparagraph/include/FontCollection.h"
#include "modules/skparagraph/include/Paragraph.h"
#include "modules/skparagraph/include/ParagraphBuilder.h"
#include "modules/skparagraph/include/TypefaceFontProvider.h"
#include "modules/skunicode/include/SkUnicode_icu.h"
#ifdef __APPLE__
#include "include/ports/SkFontMgr_mac_ct.h"
#include "include/ports/SkTypeface_mac.h"
#include <CoreText/CoreText.h>
#elif defined(_WIN32)
#include "include/ports/SkTypeface_win.h"
#else
#include "include/ports/SkFontMgr_fontconfig.h"
#include "include/ports/SkFontScanner_FreeType.h"
#endif
#include <algorithm>
#include <cmath>
#include <limits>
#include <memory>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {
using namespace skia::textlayout;
constexpr int32_t invalid = -1;
constexpr int32_t stale = -2;
struct Text {
    std::unique_ptr<Paragraph> paragraph;
    std::string utf8;
    // UTF-16 positions returned by SkParagraph mapped back to UTF-8 boundaries.
    std::vector<int32_t> bytes;
};
struct Image {
    sk_sp<SkImage> pixels;
    std::string source;
    int refs = 1;
};
struct Engine {
    std::thread::id thread = std::this_thread::get_id();
    sk_sp<SkSurface> surface;
    std::unique_ptr<CtdGpuDevice> gpu;
    int32_t backend = 0;
    sk_sp<FontCollection> fonts = sk_make_sp<FontCollection>();
    /* Faces this engine names itself: the per-point-size UI font, and a
     * registered asset. skparagraph resolves by family name, so both have to
     * be in one provider under a name of their own. */
    sk_sp<skia::textlayout::TypefaceFontProvider> provider =
        sk_make_sp<skia::textlayout::TypefaceFontProvider>();
    std::set<std::string> named;
    sk_sp<SkUnicode> unicode = SkUnicodes::ICU::Make();
    std::unordered_map<uint64_t, Text> paragraphs;
    std::unordered_map<uint64_t, Image> images;
    std::unordered_map<std::string, uint64_t> image_cache;
    SkString font_family;
    sk_sp<SkData> font_data;
    uint64_t next = 1;
    uint64_t next_image = 1;
    bool drawing = false;
    int saves = 0;
    ~Engine() { surface.reset(); gpu.reset(); }
};
Engine *engine(void *raw) {
    auto *e = static_cast<Engine *>(raw);
    return e && e->thread == std::this_thread::get_id() ? e : nullptr;
}
SkCanvas *canvas(void *raw) {
    auto *e = engine(raw);
    return e && e->drawing && e->surface ? e->surface->getCanvas() : nullptr;
}
SkColor color(uint32_t rgba) {
    return SkColorSetARGB(rgba & 255, rgba >> 24, (rgba >> 16) & 255, (rgba >> 8) & 255);
}
bool valid_number(double x) { return std::isfinite(x) && std::abs(x) <= 10000000; }
bool rect_ok(double x, double y, double w, double h, double radius) {
    return valid_number(x) && valid_number(y) && valid_number(w) && valid_number(h) && valid_number(radius) && w >= 0 && h >= 0 && radius >= 0;
}
Text *text(void *raw, uint64_t id) {
    auto *e = engine(raw);
    if (!e) return nullptr;
    auto found = e->paragraphs.find(id);
    return found == e->paragraphs.end() ? nullptr : &found->second;
}
bool positions(const char *s, int n, std::vector<int32_t> &out) {
    out.clear();
    int i = 0;
    while (i < n) {
        const auto lead = static_cast<unsigned char>(s[i]);
        int count = lead < 0x80 ? 1 : lead >= 0xc2 && lead <= 0xdf ? 2 :
                    lead >= 0xe0 && lead <= 0xef ? 3 : lead >= 0xf0 && lead <= 0xf4 ? 4 : 0;
        if (!count || i + count > n) return false;
        uint32_t point = lead & (count == 1 ? 0x7f : count == 2 ? 0x1f : count == 3 ? 0xf : 7);
        for (int j = 1; j < count; ++j) {
            auto next = static_cast<unsigned char>(s[i + j]);
            if ((next & 0xc0) != 0x80) return false;
            point = (point << 6) | (next & 0x3f);
        }
        if ((count == 2 && point < 0x80) || (count == 3 && point < 0x800) ||
            (count == 4 && point < 0x10000) || point > 0x10ffff ||
            (point >= 0xd800 && point <= 0xdfff)) return false;
        out.push_back(i);
        if (point > 0xffff) out.push_back(i);
        i += count;
    }
    out.push_back(n);
    return true;
}
bool select_backend(Engine *e, int32_t requested) {
    if (requested < 0 || requested > 4 || e->drawing) return false;
    if (requested == e->backend || (requested == 4 && e->backend != 0)) {
        e->surface.reset();
        return true;
    }
    std::unique_ptr<CtdGpuDevice> next;
    int32_t actual = requested;
    if (requested == 1 || requested == 4) {
        next = ctd_make_metal();
        if (next) actual = 1;
    }
    if (!next && (requested == 2 || requested == 4)) {
        next = ctd_make_vulkan();
        if (next) actual = 2;
    }
    if (!next && (requested == 3 || requested == 4)) {
        next = ctd_make_opengl();
        if (next) actual = 3;
    }
    if (requested != 0 && requested != 4 && !next) return false;
    e->surface.reset();
    e->gpu = std::move(next);
    e->backend = e->gpu ? actual : 0;
    return true;
}
/* Weights the caller may ask for, as SkFontStyle weights. */
SkFontStyle::Weight weight_of(int32_t weight) {
    switch (weight) {
        case 1: return SkFontStyle::kLight_Weight;
        case 2: return SkFontStyle::kNormal_Weight;
        case 3: return SkFontStyle::kMedium_Weight;
        case 4: return SkFontStyle::kSemiBold_Weight;
        case 5: return SkFontStyle::kBold_Weight;
        case 6: return SkFontStyle::kExtraBold_Weight;
        default: return SkFontStyle::kNormal_Weight;
    }
}
#ifdef __APPLE__
CTFontUIFontType ui_type(int32_t weight) { (void)weight; return kCTFontUIFontSystem; }
#endif

/* The typeface a control draws with.
 *
 * A registered asset wins on every platform, which is the only way the same
 * pixels appear on macOS, Windows and Linux. Without one, Apple resolves its UI
 * font per point size so the optical variant matches a native control, and the
 * other platforms name families. */
/* Gives one typeface a family name of its own and hands the name back.
 *
 * Setting a typeface on a TextStyle is not enough: the shaper looks a face up
 * by family, so a UI font left unnamed is resolved again from its family and
 * comes back as a different optical cut — narrower glyphs and a taller line
 * than the control it is copying. */
SkString name_face(Engine *e, sk_sp<SkTypeface> face, const char *prefix, double size, int32_t weight) {
    char buffer[64];
    snprintf(buffer, sizeof buffer, "%s-%d-%d", prefix, (int)llround(size * 100.0), weight);
    SkString alias(buffer);
    if (e->named.insert(std::string(buffer)).second) {
        e->provider->registerTypeface(face, alias);
    }
    return alias;
}

void ui_font(Engine *e, TextStyle &style, double size, int32_t weight) {
    const SkFontStyle wanted(weight_of(weight), SkFontStyle::kNormal_Width,
                             SkFontStyle::kUpright_Slant);
    style.setFontStyle(wanted);
    if (e && !e->font_family.isEmpty()) {
        style.setFontFamilies({e->font_family});
        return;
    }
#ifdef __APPLE__
    CTFontRef face = CTFontCreateUIFontForLanguage(ui_type(weight), size, nullptr);
    if (face) {
        sk_sp<SkTypeface> base = SkMakeTypefaceFromCTFont(face);
        CFRelease(face);
        if (base && weight != 2 && weight != 0) {
            // The UI font is one variable face; ask its manager for the weight.
            sk_sp<SkFontMgr> manager = SkFontMgr_New_CoreText(nullptr);
            SkString family;
            base->getFamilyName(&family);
            sk_sp<SkTypeface> styled(manager->matchFamilyStyle(family.c_str(), wanted));
            if (styled) base = styled;
        }
        if (base && e) {
            style.setFontFamilies({name_face(e, base, "CortadoUI", size, weight)});
            style.setTypeface(base);
            return;
        }
        if (base) { style.setTypeface(base); return; }
    }
    style.setFontFamilies({SkString("Helvetica Neue"), SkString("sans-serif")});
#elif defined(_WIN32)
    style.setFontFamilies({SkString("Segoe UI Variable Text"), SkString("Segoe UI"),
                           SkString("sans-serif")});
#else
    style.setFontFamilies({SkString("Inter"), SkString("Cantarell"), SkString("Noto Sans"),
                           SkString("DejaVu Sans"), SkString("sans-serif")});
#endif
}
}

extern "C" {
void *ctd_skia_new() {
    auto e = std::make_unique<Engine>();
    if (!e->unicode) return nullptr;
#ifdef __APPLE__
    e->fonts->setDefaultFontManager(SkFontMgr_New_CoreText(nullptr));
#elif defined(_WIN32)
    e->fonts->setDefaultFontManager(SkFontMgr_New_DirectWrite());
#else
    e->fonts->setDefaultFontManager(SkFontMgr_New_FontConfig(nullptr, SkFontScanner_Make_FreeType()));
#endif
    e->fonts->setAssetFontManager(e->provider);
    e->fonts->enableFontFallback();
    return e.release();
}
void ctd_skia_delete(void *raw) { delete engine(raw); }
int32_t ctd_skia_backend(void *raw) {
    auto *e = engine(raw); return e ? e->backend : invalid;
}
int32_t ctd_skia_select_backend(void *raw, int32_t preferred) {
    auto *e = engine(raw); return e && select_backend(e, preferred) ? 0 : invalid;
}
int32_t ctd_skia_recover_software(void *raw) {
    auto *e = engine(raw); return e && select_backend(e, 0) ? 0 : invalid;
}
int32_t ctd_skia_begin(void *raw, double width, double height, double scale, uint32_t rgba) {
    auto *e = engine(raw);
    if (!e || e->drawing || !valid_number(width) || !valid_number(height) || !valid_number(scale) ||
        width <= 0 || height <= 0 || scale <= 0) return invalid;
    const double w = std::ceil(width * scale), h = std::ceil(height * scale);
    if (w > 16384 || h > 16384 || w * h > 67108864) return invalid;
    if (e->gpu && e->gpu->context->abandoned()) select_backend(e, 0);
    if (!e->surface || e->surface->width() != w || e->surface->height() != h) {
        const auto info = SkImageInfo::MakeN32Premul(static_cast<int>(w), static_cast<int>(h));
        e->surface = e->gpu ? SkSurfaces::RenderTarget(e->gpu->context.get(), skgpu::Budgeted::kNo,
                                                        info, 0, kTopLeft_GrSurfaceOrigin, nullptr)
                            : SkSurfaces::Raster(info);
        if (!e->surface && e->gpu) {
            select_backend(e, 0);
            e->surface = SkSurfaces::Raster(info);
        }
    }
    if (!e->surface) return invalid;
    auto *c = e->surface->getCanvas();
    c->restoreToCount(1);
    c->resetMatrix();
    c->clear(color(rgba));
    c->scale(scale, scale);
    e->drawing = true;
    e->saves = 0;
    return 0;
}
int32_t ctd_skia_end(void *raw) {
    auto *e = engine(raw);
    if (!e || !e->drawing) return invalid;
    const bool balanced = e->saves == 0;
    e->surface->getCanvas()->restoreToCount(1);
    e->saves = 0;
    e->drawing = false;
    bool lost = false;
    if (e->gpu) {
        e->gpu->context->flushAndSubmit(e->surface.get(), GrSyncCpu::kYes);
        lost = e->gpu->context->abandoned();
        if (lost) select_backend(e, 0);
    }
    return balanced && !lost ? 0 : invalid;
}
int32_t ctd_skia_save(void *raw) {
    auto *c = canvas(raw); if (!c) return invalid;
    c->save(); ++engine(raw)->saves; return 0;
}
int32_t ctd_skia_restore(void *raw) {
    auto *c = canvas(raw); if (!c || engine(raw)->saves == 0) return invalid;
    c->restore(); --engine(raw)->saves; return 0;
}
int32_t ctd_skia_translate(void *raw, double x, double y) {
    auto *c = canvas(raw); if (!c || !valid_number(x) || !valid_number(y)) return invalid;
    c->translate(x, y); return 0;
}
int32_t ctd_skia_rotate(void *raw, double degrees) {
    auto *c = canvas(raw); if (!c || !valid_number(degrees)) return invalid;
    c->rotate(degrees); return 0;
}
int32_t ctd_skia_scale(void *raw, double x, double y) {
    auto *c = canvas(raw); if (!c || !valid_number(x) || !valid_number(y) || x <= 0 || y <= 0) return invalid;
    c->scale(x, y); return 0;
}
int32_t ctd_skia_clip(void *raw, double x, double y, double w, double h, double radius) {
    auto *c = canvas(raw); if (!c || !rect_ok(x, y, w, h, radius)) return invalid;
    c->clipRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), radius, radius), true); return 0;
}
int32_t ctd_skia_rect(void *raw, double x, double y, double w, double h, double radius, uint32_t rgba, double stroke) {
    auto *c = canvas(raw); if (!c || !rect_ok(x, y, w, h, radius) || !valid_number(stroke) || stroke < 0) return invalid;
    SkPaint paint; paint.setAntiAlias(true); paint.setColor(color(rgba));
    SkRect rect = SkRect::MakeXYWH(x, y, w, h);
    if (stroke > 0) {
        stroke = std::min(stroke, std::min(w, h));
        paint.setStyle(SkPaint::kStroke_Style); paint.setStrokeWidth(stroke);
        rect.inset(stroke / 2, stroke / 2);
    }
    c->drawRoundRect(rect, radius, radius, paint); return 0;
}
int32_t ctd_skia_ellipse(void *raw, double x, double y, double w, double h,
                         uint32_t fill, uint32_t outline, double stroke) {
    auto *c = canvas(raw);
    if (!c || !rect_ok(x, y, w, h, 0) || !valid_number(stroke) || stroke < 0) return invalid;
    const auto rect = SkRect::MakeXYWH(x, y, w, h);
    SkPaint paint; paint.setAntiAlias(true);
    if (fill & 255) { paint.setColor(color(fill)); c->drawOval(rect, paint); }
    if (stroke > 0 && (outline & 255)) {
        paint.setColor(color(outline)); paint.setStyle(SkPaint::kStroke_Style); paint.setStrokeWidth(stroke);
        c->drawOval(rect, paint);
    }
    return 0;
}
int32_t ctd_skia_path(void *raw, const char *data, int32_t length,
                      uint32_t fill, uint32_t outline, double stroke) {
    auto *c = canvas(raw);
    if (!c || !data || length <= 0 || length > 1048576 || !valid_number(stroke) || stroke < 0) return invalid;
    std::string source(data, length);
    if (source.find('\0') != std::string::npos) return invalid;
    auto path = SkParsePath::FromSVGString(source.c_str());
    if (!path) return invalid;
    SkPaint paint; paint.setAntiAlias(true);
    if (fill & 255) { paint.setColor(color(fill)); c->drawPath(*path, paint); }
    if (stroke > 0 && (outline & 255)) {
        paint.setColor(color(outline)); paint.setStyle(SkPaint::kStroke_Style); paint.setStrokeWidth(stroke);
        c->drawPath(*path, paint);
    }
    return 0;
}
int32_t ctd_skia_visual(void *raw, int32_t kind, double x, double y, double w, double h,
                        const char *data, int32_t length, uint32_t fill, uint32_t outline,
                        double stroke, uint32_t gradient_start, uint32_t gradient_end,
                        int32_t gradient_enabled,
                        uint32_t shadow_color, double shadow_blur, double shadow_dx,
                        double shadow_dy, double clip_radius,
                        int32_t stroke_cap, int32_t stroke_join) {
    auto *c = canvas(raw);
    if (!c || kind < 0 || kind > 3 || !rect_ok(x, y, w, h, clip_radius) ||
        !valid_number(stroke) || stroke < 0 || !valid_number(shadow_blur) || shadow_blur < 0 ||
        !valid_number(shadow_dx) || !valid_number(shadow_dy) ||
        stroke_cap < 0 || stroke_cap > 2 || stroke_join < 0 || stroke_join > 2) return invalid;
    const SkRect rect = SkRect::MakeXYWH(x, y, w, h);
    SkPath shape;
    if (kind == 0) shape.addRect(rect);
    else if (kind == 1) shape.addOval(rect);
    // kind 3 is a rounded rectangle; clip_radius doubles as its corner radius.
    else if (kind == 3) shape.addRRect(SkRRect::MakeRectXY(rect, clip_radius, clip_radius));
    else {
        if (!data || length <= 0 || length > 1048576) return invalid;
        std::string source(data, length);
        if (source.find('\0') != std::string::npos) return invalid;
        auto parsed = SkParsePath::FromSVGString(source.c_str());
        if (!parsed) return invalid;
        shape = *parsed;
    }
    if (shadow_color & 255) {
        SkPaint shadow;
        shadow.setAntiAlias(true);
        shadow.setColor(SK_ColorWHITE);
        shadow.setImageFilter(SkImageFilters::DropShadowOnly(
            shadow_dx, shadow_dy, shadow_blur, shadow_blur, color(shadow_color), nullptr));
        c->drawPath(shape, shadow);
    }
    c->save();
    if (clip_radius > 0) c->clipRRect(SkRRect::MakeRectXY(rect, clip_radius, clip_radius), true);
    SkPaint paint;
    paint.setAntiAlias(true);
    if (gradient_enabled && h > 0) {
        const SkPoint points[2] = {{static_cast<SkScalar>(x + w / 2), static_cast<SkScalar>(y)},
                                    {static_cast<SkScalar>(x + w / 2), static_cast<SkScalar>(y + h)}};
        const SkColor colors[2] = {color(gradient_start), color(gradient_end)};
        paint.setShader(SkGradientShader::MakeLinear(points, colors, nullptr, 2, SkTileMode::kClamp));
        c->drawPath(shape, paint);
    } else if (fill & 255) {
        paint.setColor(color(fill));
        c->drawPath(shape, paint);
    }
    if (stroke > 0 && (outline & 255)) {
        paint.reset();
        paint.setAntiAlias(true);
        paint.setColor(color(outline));
        paint.setStyle(SkPaint::kStroke_Style);
        paint.setStrokeWidth(stroke);
        paint.setStrokeCap(stroke_cap == 1 ? SkPaint::kRound_Cap
                           : stroke_cap == 2 ? SkPaint::kSquare_Cap : SkPaint::kButt_Cap);
        paint.setStrokeJoin(stroke_join == 1 ? SkPaint::kRound_Join
                            : stroke_join == 2 ? SkPaint::kBevel_Join : SkPaint::kMiter_Join);
        c->drawPath(shape, paint);
    }
    c->restore();
    return 0;
}
uint64_t ctd_skia_image_new(void *raw, const char *source, int32_t length) {
    auto *e = engine(raw);
    if (!e || !source || length <= 0 || length > 4096) return 0;
    std::string path(source, length);
    if (path.find('\0') != std::string::npos) return 0;
    auto cached = e->image_cache.find(path);
    if (cached != e->image_cache.end()) {
        ++e->images[cached->second].refs;
        return cached->second;
    }
    auto encoded = SkData::MakeFromFileName(path.c_str());
    auto decoded = encoded ? SkImages::DeferredFromEncodedData(encoded) : nullptr;
    if (!decoded) return 0;
    const uint64_t id = e->next_image++;
    e->images.emplace(id, Image{std::move(decoded), path, 1});
    e->image_cache.emplace(std::move(path), id);
    return id;
}
int32_t ctd_skia_image_release(void *raw, uint64_t id) {
    auto *e = engine(raw);
    if (!e) return invalid;
    auto found = e->images.find(id);
    if (found == e->images.end()) return stale;
    if (--found->second.refs == 0) {
        e->image_cache.erase(found->second.source);
        e->images.erase(found);
    }
    return 0;
}
int32_t ctd_skia_image_size(void *raw, uint64_t id, double *size) {
    auto *e = engine(raw);
    if (!e || !size) return invalid;
    auto found = e->images.find(id);
    if (found == e->images.end()) return stale;
    size[0] = found->second.pixels->width();
    size[1] = found->second.pixels->height();
    return 0;
}
int32_t ctd_skia_image_draw(void *raw, uint64_t id, double x, double y, double w, double h) {
    auto *e = engine(raw);
    auto *c = canvas(raw);
    if (!e || !c || !rect_ok(x, y, w, h, 0)) return invalid;
    auto found = e->images.find(id);
    if (found == e->images.end()) return stale;
    c->drawImageRect(found->second.pixels, SkRect::MakeXYWH(x, y, w, h),
                     SkSamplingOptions(SkFilterMode::kLinear));
    return 0;
}
uint64_t ctd_skia_paragraph_new(void *raw, const char *s, int32_t n, double size, double width,
                                uint32_t rgba, int32_t weight, double tracking, int32_t align) {
    auto *e = engine(raw);
    if (!e || n < 0 || n > 16777216 || (!s && n) || !valid_number(size) || size <= 0 ||
        !valid_number(width) || !valid_number(tracking) || weight < 0 || weight > 6 ||
        align < 0 || align > 2) return 0;
    Text t;
    if (!positions(s, n, t.bytes)) return 0;
    t.utf8.assign(s ? s : "", n);
    ParagraphStyle style;
    TextStyle font;
    font.setFontSize(size); font.setColor(color(rgba));
    font.setLetterSpacing(static_cast<SkScalar>(tracking));
    ui_font(e, font, size, weight);
    style.setTextStyle(font);
    style.setTextAlign(align == 1 ? TextAlign::kCenter
                       : align == 2 ? TextAlign::kRight : TextAlign::kLeft);
    auto builder = ParagraphBuilder::make(style, e->fonts, e->unicode);
    if (!builder) return 0;
    builder->addText(t.utf8.c_str(), t.utf8.size());
    t.paragraph = builder->Build();
    if (!t.paragraph) return 0;
    t.paragraph->layout(width < 0 ? 10000000 : width);
    uint64_t id = e->next++;
    if (!id) return 0;
    e->paragraphs.emplace(id, std::move(t)); return id;
}
/* Registers one font file as the family every paragraph uses from now on.
 * An empty path clears it and returns to the platform's UI font. Paragraphs
 * already shaped keep the face they were built with. */
int32_t ctd_skia_font_register(void *raw, const char *path, int32_t length) {
    auto *e = engine(raw);
    if (!e || length < 0 || length > 4096 || (!path && length)) return invalid;
    if (!length) { e->font_family.reset(); e->font_data.reset(); return 0; }
    std::string file(path, length);
    sk_sp<SkData> data = SkData::MakeFromFileName(file.c_str());
    if (!data) return invalid;
    sk_sp<SkFontMgr> manager = e->fonts->getFallbackManager();
    if (!manager) return invalid;
    sk_sp<SkTypeface> face = manager->makeFromData(data);
    if (!face) return invalid;
    SkString family;
    face->getFamilyName(&family);
    if (family.isEmpty()) return invalid;
    if (e->provider->registerTypeface(face) == 0) return invalid;
    e->font_family = family;
    e->font_data = std::move(data);
    return 0;
}
/* ascent, descent, line height, and the baseline from the top of the box. */
int32_t ctd_skia_paragraph_metrics(void *raw, uint64_t id, double *out) {
    auto *t = text(raw, id); if (!t || !out) return stale;
    std::vector<skia::textlayout::LineMetrics> lines;
    t->paragraph->getLineMetrics(lines);
    if (lines.empty()) {
        out[0] = t->paragraph->getHeight(); out[1] = 0; out[2] = t->paragraph->getHeight();
        out[3] = t->paragraph->getAlphabeticBaseline();
        return 0;
    }
    out[0] = lines[0].fAscent;
    out[1] = lines[0].fDescent;
    out[2] = lines[0].fHeight;
    /* Where paint() actually puts the first baseline, from the y it is given.
     *
     * Neither getAlphabeticBaseline() nor the line's own fBaseline is that
     * number: the shaper reports the face's metrics and lays the line out on
     * the rounded ones. Painting at the reported baseline put every control's
     * text three quarters of a point low at 13pt. Measured at 8, 9, 10, 11,
     * 12, 13, 14, 17, 22 and 26 point against the painted ink, the baseline
     * paint() uses is the rounded ascent every time — including 17, 22 and 26,
     * where that is not the point size. */
    out[3] = SkScalarRoundToScalar(SkScalarAbs(lines[0].fAscent));
    return 0;
}
int32_t ctd_skia_paragraph_release(void *raw, uint64_t id) {
    auto *e = engine(raw); return e && e->paragraphs.erase(id) ? 0 : stale;
}
int32_t ctd_skia_paragraph_size(void *raw, uint64_t id, double *out) {
    auto *t = text(raw, id); if (!t || !out) return stale;
    out[0] = std::min(t->paragraph->getMaxIntrinsicWidth(), t->paragraph->getMaxWidth());
    out[1] = t->paragraph->getHeight(); return 0;
}
int32_t ctd_skia_paragraph_paint(void *raw, uint64_t id, double x, double y) {
    auto *t = text(raw, id); auto *c = canvas(raw);
    if (!t || !c || !valid_number(x) || !valid_number(y)) return stale;
    t->paragraph->paint(c, x, y); return 0;
}
int32_t ctd_skia_paragraph_hit(void *raw, uint64_t id, double x, double y) {
    auto *t = text(raw, id); if (!t || !valid_number(x) || !valid_number(y)) return stale;
    auto pos = t->paragraph->getGlyphPositionAtCoordinate(x, y).position;
    return t->bytes[std::min<size_t>(pos, t->bytes.size() - 1)];
}
int32_t ctd_skia_paragraph_caret(void *raw, uint64_t id, int32_t offset, double *out) {
    auto *t = text(raw, id); if (!t || !out || offset < 0 || static_cast<size_t>(offset) > t->utf8.size()) return stale;
    auto it = std::lower_bound(t->bytes.begin(), t->bytes.end(), offset);
    if (it == t->bytes.end() || *it != offset) return invalid;
    unsigned pos = static_cast<unsigned>(it - t->bytes.begin());
    auto boxes = t->paragraph->getRectsForRange(pos, pos + 1, RectHeightStyle::kMax, RectWidthStyle::kTight);
    bool after = false;
    if (boxes.empty() && pos > 0) {
        boxes = t->paragraph->getRectsForRange(pos - 1, pos, RectHeightStyle::kMax, RectWidthStyle::kTight);
        after = true;
    }
    out[0] = 0; out[1] = 0; out[2] = 1; out[3] = t->paragraph->getHeight();
    if (!boxes.empty()) {
        const auto &box = after ? boxes.back() : boxes.front();
        const bool right = after != (box.direction == TextDirection::kRtl);
        out[0] = right ? box.rect.right() : box.rect.left();
        out[1] = box.rect.top(); out[3] = box.rect.height();
    }
    return 0;
}
int32_t ctd_skia_paragraph_selection(void *raw, uint64_t id, int32_t first, int32_t last,
                                    double *out, int32_t capacity) {
    auto *t = text(raw, id);
    if (!t || first < 0 || last < first || static_cast<size_t>(last) > t->utf8.size() || capacity < 0) return invalid;
    auto start = std::lower_bound(t->bytes.begin(), t->bytes.end(), first);
    auto end = std::lower_bound(t->bytes.begin(), t->bytes.end(), last);
    if (start == t->bytes.end() || end == t->bytes.end() || *start != first || *end != last) return invalid;
    auto boxes = t->paragraph->getRectsForRange(static_cast<unsigned>(start - t->bytes.begin()),
        static_cast<unsigned>(end - t->bytes.begin()), RectHeightStyle::kMax, RectWidthStyle::kTight);
    if (!out) return static_cast<int32_t>(boxes.size());
    if (static_cast<size_t>(capacity) < boxes.size()) return invalid;
    for (size_t i = 0; i < boxes.size(); ++i) {
        out[i * 4] = boxes[i].rect.left(); out[i * 4 + 1] = boxes[i].rect.top();
        out[i * 4 + 2] = boxes[i].rect.width(); out[i * 4 + 3] = boxes[i].rect.height();
    }
    return static_cast<int32_t>(boxes.size());
}
static int32_t break_offsets(void *raw, const char *s, int32_t n, SkUnicode::BreakType type,
                             int32_t *out, int32_t capacity) {
    auto *e = engine(raw);
    if (!e || n < 0 || n > 16777216 || (!s && n) || capacity < 0) return invalid;
    std::vector<int32_t> valid;
    if (!positions(s, n, valid)) return invalid;
    auto breaks = e->unicode->makeBreakIterator(type);
    if (!breaks || !breaks->setText(s ? s : "", n)) return invalid;
    std::vector<int32_t> offsets;
    for (auto p = breaks->first(); !breaks->isDone(); p = breaks->next()) offsets.push_back(p);
    if (!out) return static_cast<int32_t>(offsets.size());
    if (static_cast<size_t>(capacity) < offsets.size()) return invalid;
    std::copy(offsets.begin(), offsets.end(), out); return static_cast<int32_t>(offsets.size());
}
int32_t ctd_skia_graphemes(void *raw, const char *s, int32_t n, int32_t *out, int32_t capacity) {
    return break_offsets(raw, s, n, SkUnicode::BreakType::kGraphemes, out, capacity);
}
int32_t ctd_skia_words(void *raw, const char *s, int32_t n, int32_t *out, int32_t capacity) {
    return break_offsets(raw, s, n, SkUnicode::BreakType::kWords, out, capacity);
}
int32_t ctd_skia_pixels(void *raw, double *size, char *out, int32_t capacity) {
    auto *e = engine(raw); if (!e || !e->surface || !size || capacity < 0) return invalid;
    const int w = e->surface->width(), h = e->surface->height();
    const int needed = w * h * 4;
    size[0] = w; size[1] = h;
    if (!out) return needed;
    if (capacity < needed) return invalid;
    auto info = SkImageInfo::Make(w, h, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType);
    if (e->surface->readPixels(info, out, w * 4, 0, 0)) return needed;
    if (e->gpu) select_backend(e, 0);
    return invalid;
}
int32_t ctd_skia_png(void *raw, const char *path, int32_t length) {
    auto *e = engine(raw);
    if (!e || !e->surface || !path || length <= 0) return invalid;
    std::string filename(path, length); if (filename.find('\0') != std::string::npos) return invalid;
    const int width = e->surface->width(), height = e->surface->height();
    const auto info = SkImageInfo::Make(width, height, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType);
    std::vector<uint8_t> buffer(static_cast<size_t>(width) * height * 4);
    if (!e->surface->readPixels(info, buffer.data(), static_cast<size_t>(width) * 4, 0, 0)) {
        if (e->gpu) select_backend(e, 0);
        return invalid;
    }
    SkPixmap pixels(info, buffer.data(), static_cast<size_t>(width) * 4);
    SkFILEWStream file(filename.c_str());
    return file.isValid() && SkPngEncoder::Encode(&file, pixels, {}) ? 0 : invalid;
}
}
