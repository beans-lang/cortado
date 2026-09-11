// Text, and the scalar property bag.
//
// Which widgets carry CTD_P_ENABLED is a rule of cortado's rather than of
// AppKit's — see `ctd_kind_has_enabled` in ../cortado_rules.h.

#import "internal.h"

// ----------------------------------------------------------------- properties

// UTF-8 bytes with an explicit length, as an NSString. Never NUL-terminated:
// a string with an embedded NUL crosses this boundary whole.
NSString *ctd_string(const char *utf8, int32_t len) {
    NSString *text = [[[NSString alloc] initWithBytes:utf8
                                               length:(NSUInteger)(len < 0 ? 0 : len)
                                             encoding:NSUTF8StringEncoding] autorelease];
    return text ? text : @"";
}

// The object a widget's text actually lives on. A text area is tracked as its
// scroll view, because that is the thing with a frame — the text view inside
// is an implementation detail, and every text call has to reach through it.
NSTextView *ctd_text_view(id object) {
    if (![object isKindOfClass:[NSScrollView class]]) return nil;
    id inner = [(NSScrollView *)object documentView];
    if ([inner isKindOfClass:[NSTextView class]]) return (NSTextView *)inner;
    return nil;
}

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = ctd_string(utf8, len);
    NSTextView *inner = ctd_text_view(object);
    if (inner)                                           [inner setString:text];
    else if ([object isKindOfClass:[NSButton class]])    [(NSButton *)object setTitle:text];
    else if ([object isKindOfClass:[NSTextField class]]) [(NSTextField *)object setStringValue:text];
    else return CTD_ERR_KIND;
    return CTD_OK;
}

int32_t ctd_get_text(ctd_handle widget, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    // Class checks are explicit rather than -respondsToSelector:, because
    // NSImageView inherits -stringValue from NSControl and answers its
    // objectValue's description, which carries a heap address in it.
    NSTextView *inner = ctd_text_view(object);
    if (inner)
        return ctd_copy_out([inner string], out, cap);
    if ([object isKindOfClass:[NSButton class]])
        return ctd_copy_out([(NSButton *)object title], out, cap);
    if ([object isKindOfClass:[NSTextField class]])
        return ctd_copy_out([(NSTextField *)object stringValue], out, cap);
    if ([object isKindOfClass:[NSPopUpButton class]])
        return ctd_copy_out([(NSPopUpButton *)object titleOfSelectedItem], out, cap);
    return ctd_copy_out(@"", out, cap);
}

ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_ENABLED:
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            [(NSControl *)object setEnabled:value ? YES : NO];
            return CTD_OK;
        case CTD_P_HIDDEN:
            [(NSView *)object setHidden:value ? YES : NO];
            return CTD_OK;
        case CTD_P_CHECKED: {
            if (![object isKindOfClass:[NSButton class]]) return CTD_ERR_KIND;
            NSControlStateValue state = value == 2 ? NSControlStateValueMixed
                                      : value == 1 ? NSControlStateValueOn
                                                   : NSControlStateValueOff;
            [(NSButton *)object setState:state];
            return CTD_OK;
        }
        case CTD_P_EDITABLE:
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            [(NSTextField *)object setEditable:value ? YES : NO];
            return CTD_OK;
        case CTD_P_ALIGNMENT: {
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            NSTextAlignment alignment = value == 1 ? NSTextAlignmentCenter
                                      : value == 2 ? NSTextAlignmentRight
                                                   : NSTextAlignmentLeft;
            [(NSTextField *)object setAlignment:alignment];
            return CTD_OK;
        }
        case CTD_P_SELECTED: {
            if (![object isKindOfClass:[NSPopUpButton class]]) return CTD_ERR_KIND;
            NSPopUpButton *menu = (NSPopUpButton *)object;
            if (value < 0) { [menu selectItem:nil]; return CTD_OK; }
            if (value >= (int64_t)[menu numberOfItems]) return CTD_ERR_RANGE;
            [menu selectItemAtIndex:(NSInteger)value];
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE: {
            if (![object isKindOfClass:[NSProgressIndicator class]]) return CTD_ERR_KIND;
            NSProgressIndicator *bar = (NSProgressIndicator *)object;
            [bar setIndeterminate:value ? YES : NO];
            // An indeterminate bar that is not animating is a bar that looks
            // broken, so the two are one property rather than two.
            if (value) [bar startAnimation:nil]; else [bar stopAnimation:nil];
            return CTD_OK;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    int64_t value = 0;
    switch (key) {
        case CTD_P_ENABLED:
            // A kind with no enabled state answers "wrong widget" rather than
            // 0, because 0 reads as "disabled" — a wrong answer rather than a
            // missing one. The caller gets to tell the difference.
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = [(NSControl *)object isEnabled] ? 1 : 0;
            break;
        case CTD_P_HIDDEN:
            value = [(NSView *)object isHidden] ? 1 : 0;
            break;
        case CTD_P_CHECKED: {
            if (![object isKindOfClass:[NSButton class]]) return CTD_ERR_KIND;
            NSControlStateValue state = [(NSButton *)object state];
            value = state == NSControlStateValueMixed ? 2
                  : state == NSControlStateValueOn    ? 1 : 0;
            break;
        }
        case CTD_P_EDITABLE:
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            value = [(NSTextField *)object isEditable] ? 1 : 0;
            break;
        case CTD_P_SELECTED:
            if (![object isKindOfClass:[NSPopUpButton class]]) return CTD_ERR_KIND;
            value = (int64_t)[(NSPopUpButton *)object indexOfSelectedItem];
            break;
        case CTD_P_INDETERMINATE:
            if (![object isKindOfClass:[NSProgressIndicator class]]) return CTD_ERR_KIND;
            value = [(NSProgressIndicator *)object isIndeterminate] ? 1 : 0;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

/* A slider and a progress bar both carry a range and a position, and AppKit
 * puts them on unrelated classes — NSSlider is an NSControl, NSProgressIndicator
 * is not. The property bag hides that: a caller sets CTD_P_MIN on either and
 * the host knows which message to send. */
ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_OPACITY:
            if (value < 0.0 || value > 1.0) return CTD_ERR_RANGE;
            [(NSView *)object setAlphaValue:value];
            return CTD_OK;
        case CTD_P_FONT_SIZE:
            if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
            [(NSControl *)object setFont:[NSFont systemFontOfSize:value]];
            return CTD_OK;
        case CTD_P_MIN:
            if ([object isKindOfClass:[NSSlider class]]) {
                [(NSSlider *)object setMinValue:value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[NSProgressIndicator class]]) {
                [(NSProgressIndicator *)object setMinValue:value];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if ([object isKindOfClass:[NSSlider class]]) {
                [(NSSlider *)object setMaxValue:value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[NSProgressIndicator class]]) {
                [(NSProgressIndicator *)object setMaxValue:value];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[NSSlider class]]) {
                [(NSSlider *)object setDoubleValue:value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[NSProgressIndicator class]]) {
                [(NSProgressIndicator *)object setDoubleValue:value];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_STEP: {
            if (![object isKindOfClass:[NSSlider class]]) return CTD_ERR_KIND;
            NSSlider *slider = (NSSlider *)object;
            if (value <= 0.0) {
                [slider setAllowsTickMarkValuesOnly:NO];
                [slider setNumberOfTickMarks:0];
                return CTD_OK;
            }
            double span = [slider maxValue] - [slider minValue];
            if (span <= 0.0) return CTD_ERR_RANGE;
            // AppKit has no increment: a stepped slider is one with tick marks
            // it must land on. The count is the number of positions, which is
            // one more than the number of steps.
            [slider setNumberOfTickMarks:(NSInteger)(span / value) + 1];
            [slider setAllowsTickMarkValuesOnly:YES];
            return CTD_OK;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    double value = 0.0;
    switch (key) {
        case CTD_P_OPACITY:
            value = [(NSView *)object alphaValue];
            break;
        case CTD_P_FONT_SIZE:
            if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
            value = (double)[[(NSControl *)object font] pointSize];
            break;
        case CTD_P_MIN:
            if ([object isKindOfClass:[NSSlider class]])
                value = [(NSSlider *)object minValue];
            else if ([object isKindOfClass:[NSProgressIndicator class]])
                value = [(NSProgressIndicator *)object minValue];
            else return CTD_ERR_KIND;
            break;
        case CTD_P_MAX:
            if ([object isKindOfClass:[NSSlider class]])
                value = [(NSSlider *)object maxValue];
            else if ([object isKindOfClass:[NSProgressIndicator class]])
                value = [(NSProgressIndicator *)object maxValue];
            else return CTD_ERR_KIND;
            break;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[NSSlider class]])
                value = [(NSSlider *)object doubleValue];
            else if ([object isKindOfClass:[NSProgressIndicator class]])
                value = [(NSProgressIndicator *)object doubleValue];
            else return CTD_ERR_KIND;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}
