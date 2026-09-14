// Text, and the scalar property bag.
//
// Which widgets carry CTD_P_ENABLED is a rule of cortado's rather than of
// UIKit's — see `ctd_kind_has_enabled` in ../cortado_rules.h. A UILabel is
// not a UIControl, which is the disagreement that rule exists to settle.

#import "internal.h"

// A UIColor as CTD_P_COLOR carries it. Declared in internal.h; see the note
// there for why it is shared rather than written out three times.
int64_t ctd_ui_color_packed(UIColor *color) {
    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 0.0;
    if (!color) return 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return 0;
    return ctd_color_pack(ctd_color_byte((double)r), ctd_color_byte((double)g),
                          ctd_color_byte((double)b), ctd_color_byte((double)a));
}

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
        case CTD_P_AXIS:
            // No kind this platform builds has one; the kind refusal is what
            // every other host answers for a control that is not a split view.
            return CTD_ERR_KIND;
        case CTD_P_ICON: {
            if (!ctd_kind_has_icon(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value >= CTD_ICON_COUNT) return CTD_ERR_RANGE;
            UIImage *picture = value == CTD_ICON_NONE
                             ? nil : ctd_icon_image((int32_t)value);
            if (value != CTD_ICON_NONE && !picture) return CTD_ERR_RANGE;
            if ([object isKindOfClass:[UIButton class]]) {
                [(UIButton *)object setImage:picture forState:UIControlStateNormal];
            } else if ([object isKindOfClass:[UIImageView class]]) {
                [(UIImageView *)object setImage:picture];
            } else {
                return CTD_ERR_KIND;
            }
            ctd_set_slot_icon(widget, (int32_t)value);
            return CTD_OK;
        }
        case CTD_P_EXPANDED:
            if (!ctd_kind_has_expanded(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value > 1) return CTD_ERR_RANGE;
            [(CortadoDisclosure *)object setOpen:value ? YES : NO];
            return CTD_OK;
        case CTD_P_COLOR:
            if (!ctd_kind_has_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (!ctd_color_in_range(value)) return CTD_ERR_RANGE;
            [(UIColorWell *)object setSelectedColor:
                [UIColor colorWithRed:ctd_color_red(value)   / 255.0
                                green:ctd_color_green(value) / 255.0
                                 blue:ctd_color_blue(value)  / 255.0
                                alpha:ctd_color_alpha(value) / 255.0]];
            return CTD_OK;
        case CTD_P_FG_COLOR: {
            if (!ctd_kind_has_fg_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (!ctd_color_in_range(value)) return CTD_ERR_RANGE;
            UIColor *ink = [UIColor colorWithRed:ctd_color_red(value)   / 255.0
                                           green:ctd_color_green(value) / 255.0
                                            blue:ctd_color_blue(value)  / 255.0
                                           alpha:ctd_color_alpha(value) / 255.0];
            if ([object isKindOfClass:[UILabel class]]) {
                [(UILabel *)object setTextColor:ink];
            } else if ([object isKindOfClass:[UITextField class]]) {
                [(UITextField *)object setTextColor:ink];
            } else if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setTextColor:ink];
            } else if ([object isKindOfClass:[UISearchBar class]]) {
                [[(UISearchBar *)object searchTextField] setTextColor:ink];
            } else {
                return CTD_ERR_KIND;
            }
            return CTD_OK;
        }
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
            if (!ctd_kind_has_editable(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setEditable:value ? YES : NO];
                return CTD_OK;
            }
            /* A UITextField has no read-only state. What stood here was
             * setEnabled:, which is CTD_P_ENABLED — two keys writing one piece
             * of state. UNSUPPORTED rather than KIND: the kind carries it,
             * this platform cannot. Removing it needs a UITextFieldDelegate
             * per field returning a flag from -textFieldShouldBeginEditing. */
            return CTD_ERR_UNSUPPORTED;
        case CTD_P_ALIGNMENT: {
            if (!ctd_kind_has_alignment(ctd_slot_kind(widget))) return CTD_ERR_KIND;
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
            if (ctd_slot_kind(widget) == CTD_W_SEGMENTED) {
                UISegmentedControl *bar = (UISegmentedControl *)object;
                if (value < 0) {
                    [bar setSelectedSegmentIndex:UISegmentedControlNoSegment];
                    return CTD_OK;
                }
                if (value >= (int64_t)[bar numberOfSegments]) return CTD_ERR_RANGE;
                [bar setSelectedSegmentIndex:(NSInteger)value];
                return CTD_OK;
            }
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
        case CTD_P_ANIMATING: {
            if (!ctd_kind_has_animating(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            UIActivityIndicatorView *wheel = (UIActivityIndicatorView *)object;
            if (value) [wheel startAnimating]; else [wheel stopAnimating];
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE:
            // A UIProgressView is always determinate; an indeterminate one is
            // a UIActivityIndicatorView, a different control — which is
            // CTD_W_SPINNER and CTD_P_ANIMATING, not this. Saying so beats
            // showing a bar stuck at zero.
            if (ctd_slot_kind(widget) == CTD_W_SPINNER) return CTD_ERR_KIND;
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
        case CTD_P_AXIS:
            return CTD_ERR_KIND;
        case CTD_P_ICON:
            if (!ctd_kind_has_icon(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            // Kept beside the handle: UIKit hands out a UIImage and there is
            // no way from one back to the role that asked for it.
            value = ctd_slot_icon(widget);
            break;
        case CTD_P_EXPANDED:
            if (!ctd_kind_has_expanded(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = [(CortadoDisclosure *)object isOpen] ? 1 : 0;
            break;
        case CTD_P_COLOR:
            if (!ctd_kind_has_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = ctd_ui_color_packed([(UIColorWell *)object selectedColor]);
            break;
        case CTD_P_FG_COLOR:
            if (!ctd_kind_has_fg_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if ([object isKindOfClass:[UILabel class]]) {
                value = ctd_ui_color_packed([(UILabel *)object textColor]);
            } else if ([object isKindOfClass:[UITextField class]]) {
                value = ctd_ui_color_packed([(UITextField *)object textColor]);
            } else if ([object isKindOfClass:[UITextView class]]) {
                value = ctd_ui_color_packed([(UITextView *)object textColor]);
            } else if ([object isKindOfClass:[UISearchBar class]]) {
                value = ctd_ui_color_packed(
                    [[(UISearchBar *)object searchTextField] textColor]);
            } else {
                return CTD_ERR_KIND;
            }
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
            if (!ctd_kind_has_editable(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if ([object isKindOfClass:[UITextView class]]) {
                value = [(UITextView *)object isEditable] ? 1 : 0;
                break;
            }
            /* It used to answer isEnabled here, which is a different property
             * with its own key — see the setter. */
            return CTD_ERR_UNSUPPORTED;
        case CTD_P_SELECTED:
            if (ctd_slot_kind(widget) == CTD_W_SEGMENTED) {
                NSInteger at = [(UISegmentedControl *)object selectedSegmentIndex];
                value = at == UISegmentedControlNoSegment ? -1 : (int64_t)at;
                break;
            }
            if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
            value = (int64_t)[(UIButton *)object tag];
            break;
        case CTD_P_ANIMATING:
            if (!ctd_kind_has_animating(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = [(UIActivityIndicatorView *)object isAnimating] ? 1 : 0;
            break;
        case CTD_P_INDETERMINATE:
            if (ctd_slot_kind(widget) == CTD_W_SPINNER) return CTD_ERR_KIND;
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
// And the value itself. A UIProgressView holds a 0..1 **float**, so the range
// is not the only thing cortado has to keep: 3 in 0..10 becomes 0.3f, and
// 0.3f read back and scaled is 3.0000001. The whole triple is cortado's data
// on this platform, because UIKit has no range here at all — min and max were
// already kept for exactly that reason, and the value belongs beside them.
// Nothing but the program writes a progress bar, so there is no second writer
// for this copy to disagree with.
static double g_progress_value[CTD_SLOTS];
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
            if (!ctd_kind_has_font_size(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            UIFont *font = [UIFont systemFontOfSize:value];
            if ([object isKindOfClass:[UILabel class]]) {
                [(UILabel *)object setFont:font];
            } else if ([object isKindOfClass:[UITextField class]]) {
                [(UITextField *)object setFont:font];
            } else if ([object isKindOfClass:[UITextView class]]) {
                [(UITextView *)object setFont:font];
            } else if ([object isKindOfClass:[UIButton class]]) {
                [[(UIButton *)object titleLabel] setFont:font];
            } else if ([object isKindOfClass:[UISegmentedControl class]]) {
                [(UISegmentedControl *)object
                    setTitleTextAttributes:@{NSFontAttributeName: font}
                                  forState:UIControlStateNormal];
            } else {
                /* A check box is a UISwitch here and has no text; a
                 * UIDatePicker offers no font. The kind carries it, this
                 * platform cannot — so UNSUPPORTED, not KIND. */
                return CTD_ERR_UNSUPPORTED;
            }
            return CTD_OK;
        }
        case CTD_P_MIN:
            // By kind first: the classes do not line up with the rule, and the
            // rule is cortado's. See ctd_kind_has_range in ../cortado_rules.h.
            if (!ctd_kind_has_range(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if ([object isKindOfClass:[UIStepper class]]) {
                [(UIStepper *)object setMinimumValue:value];
                return CTD_OK;
            }
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
            if (!ctd_kind_has_range(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if ([object isKindOfClass:[UIStepper class]]) {
                [(UIStepper *)object setMaximumValue:value];
                return CTD_OK;
            }
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
            if (!ctd_kind_has_range(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if ([object isKindOfClass:[UIStepper class]]) {
                [(UIStepper *)object setValue:value];
                return CTD_OK;
            }
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
                g_progress_value[slot] = value;
                return CTD_OK;
            }
            return CTD_ERR_KIND;
        case CTD_P_DIVIDER:
            // Nor a divider. See ctd_widget_supports in widget.m.
            return CTD_ERR_KIND;
        case CTD_P_DATE:
            if (!ctd_kind_has_date(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            [(UIDatePicker *)object
                setDate:[NSDate dateWithTimeIntervalSince1970:ctd_date_floor(value)]];
            return CTD_OK;
        case CTD_P_STEP: {
            if ([object isKindOfClass:[UIStepper class]]) {
                if (value <= 0.0) return CTD_ERR_RANGE;
                [(UIStepper *)object setStepValue:value];
                return CTD_OK;
            }
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
            if (!ctd_kind_has_font_size(ctd_slot_kind(widget))) return CTD_ERR_KIND;
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
            if ([object isKindOfClass:[UIStepper class]]) {
                value = [(UIStepper *)object minimumValue];
            } else if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object minimumValue];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                value = g_progress_min[slot];
            } else { return CTD_ERR_KIND; }
            break;
        case CTD_P_MAX:
            if ([object isKindOfClass:[UIStepper class]]) {
                value = [(UIStepper *)object maximumValue];
            } else if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object maximumValue];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                value = g_progress_max[slot];
            } else { return CTD_ERR_KIND; }
            break;
        case CTD_P_VALUE:
            if ([object isKindOfClass:[UIStepper class]]) {
                value = [(UIStepper *)object value];
            } else if ([object isKindOfClass:[UISlider class]]) {
                value = [(UISlider *)object value];
            } else if ([object isKindOfClass:[UIProgressView class]]) {
                value = g_progress_value[slot];
            } else { return CTD_ERR_KIND; }
            break;
        case CTD_P_DIVIDER:
            return CTD_ERR_KIND;
        case CTD_P_DATE:
            if (!ctd_kind_has_date(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = ctd_date_floor([[(UIDatePicker *)object date] timeIntervalSince1970]);
            break;
        case CTD_P_STEP:
            // Only a stepper has one. A UISlider is continuous and always was,
            // so answering it a number would be inventing one.
            if (![object isKindOfClass:[UIStepper class]]) return CTD_ERR_KIND;
            value = [(UIStepper *)object stepValue];
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}


// Where each link goes, by handle. A UIButton has nowhere to keep it, and the
// host is what opens it.
static NSMutableDictionary *g_link_urls;

@implementation CortadoLink
- (void)follow:(id)sender {
    (void)sender;
    NSString *where = [g_link_urls objectForKey:
        [NSNumber numberWithUnsignedLongLong:_handle]];
    if (!where || [where length] == 0) return;
    NSURL *target = [NSURL URLWithString:where];
    if (!target) return;
    [[UIApplication sharedApplication] openURL:target options:@{} completionHandler:nil];
}
@end

ctd_status ctd_set_string(ctd_handle widget, int32_t key,
                          const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_S_HINT:
            if (!ctd_kind_has_hint(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            [(UITextField *)object setPlaceholder:ctd_string(utf8, len)];
            return CTD_OK;
        case CTD_S_URL: {
            if (!ctd_kind_has_url(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSString *where = ctd_string(utf8, len);
            if (len > 0 && ![NSURL URLWithString:where]) return CTD_ERR_RANGE;
            if (!g_link_urls) g_link_urls = [[NSMutableDictionary alloc] init];
            [g_link_urls setObject:where
                            forKey:[NSNumber numberWithUnsignedLongLong:widget]];
            return CTD_OK;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

int32_t ctd_get_string(ctd_handle widget, int32_t key, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_S_HINT: {
            if (!ctd_kind_has_hint(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSString *hint = [(UITextField *)object placeholder];
            return ctd_copy_out(hint ? hint : @"", out, cap);
        }
        case CTD_S_URL: {
            if (!ctd_kind_has_url(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSString *where = [g_link_urls objectForKey:
                [NSNumber numberWithUnsignedLongLong:widget]];
            return ctd_copy_out(where ? where : @"", out, cap);
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = ctd_string(utf8, len);
    // A disclosure's text is the title beside the chevron. Asked before
    // UILabel and the rest, because none of those is what it is.
    if ([object isKindOfClass:[CortadoDisclosure class]]) {
        [[(CortadoDisclosure *)object caption] setText:text];
        [(CortadoDisclosure *)object relayout];
    }
    else if ([object isKindOfClass:[UILabel class]])     [(UILabel *)object setText:text];
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
    if ([object isKindOfClass:[CortadoDisclosure class]])
        return ctd_copy_out([[(CortadoDisclosure *)object caption] text], out, cap);
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
