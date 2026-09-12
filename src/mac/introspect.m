// What the platform says it built, what it painted, and driving it from a test.
//
// `ctd_native_class` and `ctd_snapshot` are the two questions in the ABI whose
// answer cortado did not itself write down: one asks an object what class it
// is, the other asks the window server what appeared.

#import "internal.h"

// -------------------------------------------------------------- introspection

int32_t ctd_native_class(ctd_handle widget, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    return ctd_copy_out(NSStringFromClass([object class]), out, cap);
}

int32_t ctd_a11y_role(ctd_handle widget, char *out, int32_t cap) {
    int32_t kind = ctd_slot_kind(widget);
    if (kind < 0 && !ctd_resolve(widget)) return CTD_ERR_STALE;
    NSString *role;
    switch (kind) {
        case CTD_W_CONTAINER:    role = @"group";       break;
        case CTD_W_LABEL:        role = @"text";        break;
        case CTD_W_BUTTON:       role = @"button";      break;
        case CTD_W_TEXT_FIELD:   role = @"textbox";     break;
        case CTD_W_CHECK_BOX:    role = @"checkbox";    break;
        case CTD_W_IMAGE_VIEW:   role = @"image";       break;
        case CTD_W_SLIDER:       role = @"slider";      break;
        case CTD_W_PROGRESS_BAR: role = @"progressbar"; break;
        case CTD_W_SEPARATOR:    role = @"separator";   break;
        case CTD_W_TEXT_AREA:    role = @"textbox";     break;
        case CTD_W_COMBO_BOX:    role = @"combobox";    break;
        case CTD_W_SCROLL_VIEW:  role = @"scrollarea";  break;
        case CTD_W_RADIO_BUTTON: role = @"radio";       break;
        // The vocabulary has no word for "a program draws its own
        // pixels here", and inventing one would be a word no screen
        // reader knows. A group is what it is: an area with content, and
        // a canvas that matters to a user gets a label beside it.
        case CTD_W_CANVAS:       role = @"group";       break;
        // ARIA's own word, and every platform's: a control with two
        // positions that is not a check box.
        case CTD_W_SWITCH:       role = @"switch";      break;
        // There is no ARIA role for a password field — HTML's input type has
        // none either. Every assistive layer under this one does distinguish
        // it (AXSecureTextField, ATSPI "password text", UIA IsPassword), so
        // reporting "textbox" would throw away a fact all four platforms have.
        case CTD_W_SECURE_FIELD: role = @"password";    break;
        // ARIA's words. A spin button is a number you step; a meter is a
        // number you read — the distinction assistive technology needs is
        // "can I change this", and these two are on opposite sides of it.
        case CTD_W_STEPPER:      role = @"spinbutton";  break;
        case CTD_W_LEVEL_INDICATOR: role = @"meter";    break;
        // ARIA's word for rows and columns with a header. A `grid` is the
        // interactive one — cells you can move through — which is what every
        // one of these controls is.
        case CTD_W_TABLE:        role = @"grid";        break;
        default:               role = @"window";   break;
    }
    return ctd_copy_out(role, out, cap);
}

ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[NSStepper class]]) {
        [(NSStepper *)object setDoubleValue:value];
    } else if ([object isKindOfClass:[NSSlider class]]) {
        [(NSSlider *)object setDoubleValue:value];
    } else if ([object isKindOfClass:[NSPopUpButton class]]) {
        NSPopUpButton *menu = (NSPopUpButton *)object;
        if (index < 0 || index >= (int64_t)[menu numberOfItems]) return CTD_ERR_RANGE;
        [menu selectItemAtIndex:(NSInteger)index];
    } else if ([object isKindOfClass:[NSSwitch class]]) {
        if (!ctd_checked_in_range(ctd_slot_kind(widget), index)) return CTD_ERR_RANGE;
        [(NSSwitch *)object setState:index == 1 ? NSControlStateValueOn
                                                : NSControlStateValueOff];
    } else if ([object isKindOfClass:[NSButton class]]) {
        // Through the rule, not around it: this call stands in for a user, and
        // a user cannot put a radio button into the mixed state either.
        if (!ctd_checked_in_range(ctd_slot_kind(widget), index)) return CTD_ERR_RANGE;
        NSControlStateValue state = index == 2 ? NSControlStateValueMixed
                                  : index == 1 ? NSControlStateValueOn
                                               : NSControlStateValueOff;
        [(NSButton *)object setState:state];
    } else {
        return CTD_ERR_KIND;
    }
    ctd_emit_control(widget, object);
    return CTD_OK;
}

ctd_status ctd_widget_synth_text(ctd_handle widget, const char *utf8, int32_t len) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = ctd_string(utf8, len);
    NSTextView *inner = ctd_text_view(object);
    if (inner)                                           [inner setString:text];
    else if ([object isKindOfClass:[NSTextField class]]) [(NSTextField *)object setStringValue:text];
    else return CTD_ERR_KIND;
    ctd_emit_control(widget, object);
    return CTD_OK;
}

// Reads a view back as pixels.
//
// `bitmapImageRepForCachingDisplayInRect:` and `cacheDisplayInRect:` draw into
// a bitmap rather than onto the screen, which is what makes this work in a
// headless run: the window is never ordered front and the controls still
// paint. That is the point of the call — it is what a program that had to
// answer "did anything actually appear" needs, and nothing else in this header
// can answer it.
//
// The bitmap is built explicitly rather than taken from the view, because the
// view's own caching rep follows the display: 8 bits a channel, four channels,
// alpha last, one row after another with no padding. A caller reading
// (y * width + x) * 4 has to be right on every machine.
int32_t ctd_snapshot(ctd_handle widget, double *out_size, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSView class]]) return CTD_ERR_KIND;
    NSView *view = (NSView *)object;
    NSRect bounds = [view bounds];
    int32_t width = (int32_t)bounds.size.width;
    int32_t height = (int32_t)bounds.size.height;
    if (width <= 0 || height <= 0) return CTD_ERR_RANGE;
    if (out_size) {
        out_size[0] = (double)width;
        out_size[1] = (double)height;
    }
    int32_t needed = width * height * 4;
    if (!out || cap <= 0) return needed;

    NSBitmapImageRep *rep =
        [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                 pixelsWide:width
                                                 pixelsHigh:height
                                              bitsPerSample:8
                                            samplesPerPixel:4
                                                   hasAlpha:YES
                                                   isPlanar:NO
                                             colorSpaceName:NSDeviceRGBColorSpace
                                                bitmapFormat:0
                                                bytesPerRow:width * 4
                                               bitsPerPixel:32] autorelease];
    if (!rep) return CTD_ERR_PLATFORM;
    // Every byte, so an untouched pixel is a known value rather than whatever
    // the allocator left behind — otherwise "nothing was drawn here" and
    // "something was drawn and happened to be that" are the same answer.
    memset([rep bitmapData], 0, (size_t)needed);

    NSGraphicsContext *context =
        [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!context) return CTD_ERR_PLATFORM;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [view displayRectIgnoringOpacity:bounds inContext:context];
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    int32_t room = cap < needed ? cap : needed;
    memcpy(out, [rep bitmapData], (size_t)room);
    return needed;
}

ctd_status ctd_widget_activate(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
    [(NSControl *)object performClick:nil];
    return CTD_OK;
}
