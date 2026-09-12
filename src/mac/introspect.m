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
        // ARIA's word for a tree with columns. A `tree` is one
        // column of nodes; this is rows and columns where the
        // rows nest, which is what an outline view is.
        case CTD_W_OUTLINE_VIEW: role = @"treegrid";    break;
        // ARIA's word for a field that searches, and a spinner is a progress
        // bar with no total — which is what "progressbar" means to every
        // assistive layer under this one.
        case CTD_W_SEARCH_FIELD: role = @"searchbox";   break;
        case CTD_W_SPINNER:      role = @"progressbar"; break;
        case CTD_W_LINK:         role = @"link";        break;
        // ARIA: a set of buttons where one is chosen, and a titled box.
        case CTD_W_SEGMENTED:    role = @"radiogroup";   break;
        case CTD_W_GROUP_BOX:    role = @"group";        break;
        // ARIA has no date picker, and the honest reading of its table is that
        // a day chosen from a calendar is a spin button with three fields.
        // Every platform underneath agrees: AXDatePicker, ATSPI "date editor"
        // and UIA's Calendar all report something steppable.
        case CTD_W_DATE_PICKER:  role = @"spinbutton";    break;
        // ARIA has no colour well either. "button" is what it is: a thing you
        // press that opens a chooser.
        case CTD_W_COLOR_WELL:   role = @"button";        break;
        // ARIA's word for a header that opens and shuts what is under it.
        case CTD_W_DISCLOSURE:   role = @"group";         break;
        // ARIA's word for a strip of tabs with pages behind it.
        case CTD_W_TAB_VIEW:     role = @"tablist";       break;
        // ARIA's word for two panes with a draggable handle between them.
        case CTD_W_SPLIT_VIEW:   role = @"separator";     break;
        // ARIA's word for a region holding a whole document of its own.
        case CTD_W_WEB_VIEW:     role = @"document";      break;
        default:               role = @"window";   break;
    }
    return ctd_copy_out(role, out, cap);
}

ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[NSSplitView class]]) {
        // A drag, as far as anything above can tell: the divider moves and the
        // delegate AppKit calls is what raises the event, which is the same
        // path a real drag takes.
        NSSplitView *split = (NSSplitView *)object;
        if ([[split subviews] count] < 2) return CTD_ERR_RANGE;
        NSRect own = [split bounds];
        double along = [split isVertical] ? own.size.width : own.size.height;
        if (value < 0.0 || value > along) return CTD_ERR_RANGE;
        [split setPosition:value ofDividerAtIndex:0];
        return CTD_OK;
    }
    {
        // A table, selected the way a click selects: *without* the g_writing
        // guard ctd_table_select uses, so AppKit's own notification fires and
        // the event travels the path a real click travels. That difference is
        // the whole point of this call — the setter is silent, this is not.
        NSTableView *rows = ctd_table_view(object);
        if (rows) {
            if (index < 0 || index >= (int64_t)[rows numberOfRows]) return CTD_ERR_RANGE;
            [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index]
              byExtendingSelection:NO];
            return CTD_OK;
        }
    }
    if ([object isKindOfClass:[NSTabView class]]) {
        NSTabView *tabs = (NSTabView *)object;
        if (index < 0 || index >= (int64_t)[tabs numberOfTabViewItems]) return CTD_ERR_RANGE;
        // The ordinary selection, and the delegate AppKit calls is what raises
        // the event — the same path a user's click takes.
        [tabs selectTabViewItemAtIndex:(NSInteger)index];
        return CTD_OK;
    }
    if ([object isKindOfClass:[CortadoDisclosure class]]) {
        // Through the triangle, so the control ends up in the state its own
        // click would have left it in — and the event is raised here rather
        // than by ctd_emit_control below, which decides the kind from the
        // class and would call a disclosure a plain view being activated.
        if (index < 0 || index > 1) return CTD_ERR_RANGE;
        CortadoDisclosure *twisty = (CortadoDisclosure *)object;
        [[twisty triangle] setState:index ? NSControlStateValueOn
                                          : NSControlStateValueOff];
        [[twisty content] setHidden:index ? NO : YES];
        ctd_emit(CTD_EV_VALUE_CHANGED, widget, index, 0);
        return CTD_OK;
    }
    if ([object isKindOfClass:[NSDatePicker class]]) {
        // Through the rule, the same as the setter: a user picks a day from a
        // calendar and cannot pick a quarter past one.
        [(NSDatePicker *)object
            setDateValue:[NSDate dateWithTimeIntervalSince1970:ctd_date_floor(value)]];
    } else if ([object isKindOfClass:[NSColorWell class]]) {
        if (!ctd_color_in_range(index)) return CTD_ERR_RANGE;
        [(NSColorWell *)object setColor:
            [NSColor colorWithSRGBRed:ctd_color_red(index)   / 255.0
                                green:ctd_color_green(index) / 255.0
                                 blue:ctd_color_blue(index)  / 255.0
                                alpha:ctd_color_alpha(index) / 255.0]];
    } else if ([object isKindOfClass:[NSStepper class]]) {
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
    // Typing into a field changes its text and so how big it wants to be,
    // exactly as a program writing the text does.
    ctd_forget_size(widget);
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
