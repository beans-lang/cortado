// Text, and the scalar property bag.
//
// Which widgets carry CTD_P_ENABLED is a rule of cortado's rather than of
// UIKit's — see `ctd_kind_has_enabled` in ../cortado_rules.h. A UILabel is
// not a UIControl, which is the disagreement that rule exists to settle.

#import "internal.h"

ctd_status ctd_set_int(ctd_handle widget, int32_t key, int64_t value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_P_ENABLED:
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            [(UIControl *)object setEnabled:value ? YES : NO];
            return CTD_OK;
        case CTD_P_HIDDEN:
            if (![object isKindOfClass:[UIView class]]) return CTD_ERR_KIND;
            [(UIView *)object setHidden:value ? YES : NO];
            return CTD_OK;
        case CTD_P_CHECKED: {
            // Which kinds have this property, and which of them have a third
            // state, is cortado's rule rather than UIKit's — the paragraph
            // beside CTD_P_CHECKED in the header says why. The order matters:
            // "that control has no such state anywhere" is answered before
            // "this platform cannot show it", because the first is true of
            // every platform and the second of one.
            int32_t made_as = ctd_slot_kind(widget);
            if (!ctd_kind_has_checked(made_as)) return CTD_ERR_KIND;
            if (!ctd_checked_in_range(made_as, value)) return CTD_ERR_RANGE;
            if ([object isKindOfClass:[UISwitch class]]) {
                // A UISwitch has two positions. A check box has three, and
                // this is the platform that cannot show the third — quietly
                // rounding it to on or off would make a tri-state check box
                // lie about itself here and nowhere else.
                if (value == 2) return CTD_ERR_UNSUPPORTED;
                [(UISwitch *)object setOn:value ? YES : NO];
                return CTD_OK;
            }
            if (made_as == CTD_W_RADIO_BUTTON) {
                UIButton *radio = (UIButton *)object;
                [radio setSelected:value == 1];
                // iOS has no radio control, so the state has to be visible
                // some other way. A filled circle beside the title is what
                // Apple's own settings screens use.
                [radio setImage:[UIImage systemImageNamed:
                    value == 1 ? @"largecircle.fill.circle" : @"circle"]
               forState:UIControlStateNormal];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        }
        case CTD_P_EDITABLE:
            if ([object isKindOfClass:[UITextField class]]) {
                [(UITextField *)object setEnabled:value ? YES : NO];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setEditable:value ? YES : NO];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_ALIGNMENT: {
            NSTextAlignment alignment = value == 1 ? NSTextAlignmentCenter
                                      : value == 2 ? NSTextAlignmentRight
                                                   : NSTextAlignmentLeft;
            if ([object isKindOfClass:[UILabel class]]) {
                [(UILabel *)object setTextAlignment:alignment];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UITextField class]]) {
                [(UITextField *)object setTextAlignment:alignment];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setTextAlignment:alignment];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        }
        case CTD_P_SELECTED: {
            if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
            UIButton *menu = (UIButton *)object;
            UIMenu *items = [menu menu];
            NSArray *children = items ? [items children] : @[];
            if (value < 0) {
                [menu setTag:-1];
                [menu setTitle:@"" forState:UIControlStateNormal];
                return CTD_OK;
            }
            if (value >= (int64_t)[children count]) return CTD_ERR_RANGE;
            UIAction *chosen = (UIAction *)[children objectAtIndex:(NSUInteger)value];
            [menu setTag:(NSInteger)value];
            [menu setTitle:[chosen title] forState:UIControlStateNormal];
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE:
            // A UIProgressView is always determinate; an indeterminate one is
            // a UIActivityIndicatorView, a different control. Saying so beats
            // showing a bar stuck at zero.
            if (![object isKindOfClass:[UIProgressView class]]) return CTD_ERR_KIND;
            return value ? CTD_ERR_UNSUPPORTED : CTD_OK;
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_int(ctd_handle widget, int32_t key, int64_t *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    int64_t value = 0;
    switch (key) {
        case CTD_P_ENABLED:
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = [(UIControl *)object isEnabled] ? 1 : 0;
            break;
        case CTD_P_HIDDEN:
            if (![object isKindOfClass:[UIView class]]) return CTD_ERR_KIND;
            value = [(UIView *)object isHidden] ? 1 : 0;
            break;
        case CTD_P_CHECKED:
            if (!ctd_kind_has_checked(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if ([object isKindOfClass:[UISwitch class]]) {
                value = [(UISwitch *)object isOn] ? 1 : 0;
            } else {
                value = [(UIButton *)object isSelected] ? 1 : 0;
            }
            break;
        case CTD_P_EDITABLE:
            if ([object isKindOfClass:[UITextField class]]) {
                value = [(UITextField *)object isEnabled] ? 1 : 0;
            } else if ([object isKindOfClass:[UITextView class]]) {
                value = [(UITextView *)object isEditable] ? 1 : 0;
            } else {
                return CTD_ERR_KIND;
            }
            break;
        case CTD_P_SELECTED:
            if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
            value = (int64_t)[(UIButton *)object tag];
            break;
        case CTD_P_INDETERMINATE:
            if (![object isKindOfClass:[UIProgressView class]]) return CTD_ERR_KIND;
            value = 0;
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}

// A slider and a progress view both carry a range and a position, and UIKit
// puts them on unrelated classes with different spellings — a progress view
// has no range at all, only a 0..1 fraction. The property bag hides that: a
// caller sets CTD_P_MIN on either and the host does the arithmetic.
static double g_progress_min[CTD_SLOTS];
static double g_progress_max[CTD_SLOTS];

static uint32_t ctd_slot_of(ctd_handle handle) {
    return (uint32_t)(handle & 0xffffffffu);
}

ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = ctd_slot_of(widget);
    switch (key) {
        case CTD_P_OPACITY:
            if (value < 0.0 || value > 1.0) return CTD_ERR_RANGE;
            if (![object isKindOfClass:[UIView class]]) return CTD_ERR_KIND;
            [(UIView *)object setAlpha:value];
            return CTD_OK;
        case CTD_P_FONT_SIZE: {
            UIFont *font = [UIFont systemFontOfSize:value];
            if ([object isKindOfClass:[UILabel class]]) {
                [(UILabel *)object setFont:font];
            } else if ([object isKindOfClass:[UITextField class]]) {
                [(UITextField *)object setFont:font];
            } else if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setFont:font];
            } else if ([object isKindOfClass:[UIButton class]]) {
                [[(UIButton *)object titleLabel] setFont:font];
            } else {
                return CTD_ERR_KIND;
            }
            return CTD_OK;
        }
        case CTD_P_MIN:
            if ([object isKindOfClass:[UISlider class]]) {
                [(UISlider *)object setMinimumValue:(float)value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UIProgressView class]]) {
                g_progress_min[slot] = value;
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_MAX:
            if ([object isKindOfClass:[UISlider class]]) {
                [(UISlider *)object setMaximumValue:(float)value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UIProgressView class]]) {
                g_progress_max[slot] = value;
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[UISlider class]]) {
                [(UISlider *)object setValue:(float)value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[UIProgressView class]]) {
                double low = g_progress_min[slot];
                double high = g_progress_max[slot];
                double span = high - low;
                double fraction = span > 0.0 ? (value - low) / span : 0.0;
                if (fraction < 0.0) fraction = 0.0;
                if (fraction > 1.0) fraction = 1.0;
                [(UIProgressView *)object setProgress:(float)fraction];
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_STEP: {
            // A UISlider is always continuous. Refusing beats snapping in the
            // host: a caller that asked for detents and got none should be
            // told, not left wondering why the thumb slides freely.
            if (![object isKindOfClass:[UISlider class]]) return CTD_ERR_KIND;
            if (value <= 0.0) return CTD_OK;
            return CTD_ERR_UNSUPPORTED;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_get_real(ctd_handle widget, int32_t key, double *out) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    uint32_t slot = ctd_slot_of(widget);
    double value = 0.0;
    switch (key) {
        case CTD_P_OPACITY:
            if (![object isKindOfClass:[UIView class]]) return CTD_ERR_KIND;
            value = [(UIView *)object alpha];
            break;
        case CTD_P_FONT_SIZE:
            if ([object isKindOfClass:[UILabel class]]) {
                value = [[(UILabel *)object font] pointSize];
            } else if ([object isKindOfClass:[UITextField class]]) {
                value = [[(UITextField *)object font] pointSize];
            } else if ([object isKindOfClass:[UITextView class]]) {
                value = [[(UITextView *)object font] pointSize];
            } else if ([object isKindOfClass:[UIButton class]]) {
                value = [[[(UIButton *)object titleLabel] font] pointSize];
            } else {
                return CTD_ERR_KIND;
            }
            break;
        case CTD_P_MIN:
            if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object minimumValue];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                value = g_progress_min[slot];
            } else { return CTD_ERR_KIND; }
            break;
        case CTD_P_MAX:
            if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object maximumValue];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                value = g_progress_max[slot];
            } else { return CTD_ERR_KIND; }
            break;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object value];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                double low = g_progress_min[slot];
                double high = g_progress_max[slot];
                value = low + (high - low) * [(UIProgressView *)object progress];
            } else { return CTD_ERR_KIND; }
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}


ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = ctd_string(utf8, len);
    if ([object isKindOfClass:[UILabel class]])          [(UILabel *)object setText:text];
    else if ([object isKindOfClass:[UITextField class]]) [(UITextField *)object setText:text];
    else if ([object isKindOfClass:[UITextView class]])  [(UITextView *)object setText:text];
    else if ([object isKindOfClass:[UIButton class]])
        [(UIButton *)object setTitle:text forState:UIControlStateNormal];
    else if ([object isKindOfClass:[UISwitch class]]) {
        // A UISwitch shows no text — on iOS the label sits beside it as its
        // own view. But the text a program gives a check box is exactly what
        // VoiceOver should read, so it becomes the accessibility label. That
        // is not a place to park it: it is where that string belongs on this
        // platform, and it is the only thing that makes the switch legible to
        // somebody who cannot see it.
        [(UISwitch *)object setAccessibilityLabel:text];
    }
    else return CTD_ERR_KIND;
    return CTD_OK;
}

int32_t ctd_get_text(ctd_handle widget, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[UILabel class]])
        return ctd_copy_out([(UILabel *)object text], out, cap);
    if ([object isKindOfClass:[UITextField class]])
        return ctd_copy_out([(UITextField *)object text], out, cap);
    if ([object isKindOfClass:[UITextView class]])
        return ctd_copy_out([(UITextView *)object text], out, cap);
    if ([object isKindOfClass:[UIButton class]])
        return ctd_copy_out([(UIButton *)object currentTitle], out, cap);
    if ([object isKindOfClass:[UISwitch class]])
        return ctd_copy_out([(UISwitch *)object accessibilityLabel], out, cap);
    return ctd_copy_out(@"", out, cap);
}
