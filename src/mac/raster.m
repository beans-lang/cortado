#import "internal.h"
#import <QuartzCore/QuartzCore.h>

ctd_status ctd_canvas_set_pixels(ctd_handle handle, int32_t width, int32_t height,
                                 const char *rgba, int32_t length) {
    id object = ctd_resolve(handle);
    if (!object) return CTD_ERR_STALE;
    if (ctd_slot_kind(handle) != CTD_W_CANVAS) return CTD_ERR_KIND;
    if (!rgba || width <= 0 || height <= 0 || width > 16384 || height > 16384 ||
        (int64_t)width * height * 4 != length) return CTD_ERR_RANGE;
    /* Desktop surfaces are opaque. Translucent visuals are composited by the
     * renderer before submission, so every platform presents the same frame. */
    for (int32_t at = 3; at < length; at += 4)
        if ((unsigned char)rgba[at] != 255) return CTD_ERR_RANGE;
    NSData *data = [NSData dataWithBytes:rgba length:(NSUInteger)length];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = CGImageCreate(width, height, 8, 32, (size_t)width * 4, space,
        kCGBitmapByteOrder32Big | kCGImageAlphaLast, provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    if (!image) return CTD_ERR_PLATFORM;
    NSView *view = object;
    [view setWantsLayer:YES];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.layer.contents = (id)image;
    view.layer.contentsGravity = kCAGravityResize;
    [CATransaction commit];
    CGImageRelease(image);
    return CTD_OK;
}
