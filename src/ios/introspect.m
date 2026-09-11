// What the platform says it built, and driving it from a test.
//
// `ctd_widget_activate` is the one that needed real work here:
// `sendActionsForControlEvents:` routes through `[UIApplication
// sharedApplication]`, and a headless run has none.

#import "internal.h"

int32_t ctd_native_class(ctd_handle widget, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    return ctd_copy_out(NSStringFromClass([object class]), out, cap);
}

// The same vocabulary the macOS host answers, which is what lets
// `tests/roles.out` be one file for both.
int32_t ctd_a11y_role(ctd_handle widget, char *out, int32_t cap) {
    if (!ctd_resolve(widget)) return CTD_ERR_STALE;
    NSString *role = @"group";
    switch (ctd_slot_kind(widget)) {
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
        default:                 role = @"group";       break;
    }
    return ctd_copy_out(role, out, cap);
}

// No snapshot here, and `ctd_capability(CTD_CAP_SNAPSHOT)` says so rather than
// this being discovered at the call. Reading a widget back as pixels is real
// work on this platform and it has not been done; a stub that answered a blank
// image would be worse than a refusal, because a test asserting "something was
// drawn" would then fail for a reason that has nothing to do with drawing.
int32_t ctd_snapshot(ctd_handle widget, double *out_size, char *out, int32_t cap) {
    (void)widget; (void)out_size; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_widget_activate(ctd_handle widget) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIControl class]]) return CTD_ERR_KIND;
    UIControl *control = (UIControl *)object;
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];

    // `sendActionsForControlEvents:` does not call the target itself: it hands
    // the action to `[UIApplication sharedApplication]`, which delivers it. A
    // program that has not called `UIApplicationMain` has no shared
    // application — and that is every headless run, which on iOS means every
    // test, because `ctd_app_run` is `UIApplicationMain` and never returns.
    //
    // So the call above silently did nothing, and a button driven from a test
    // raised no event at all while a switch driven through
    // `ctd_widget_synth_value` raised one, because that path emits directly.
    // `tests/events.out` says `clicks=2` on macOS and on GTK4, and iOS printed
    // `clicks=0` from the day this host landed — invisible until the portable
    // goldens were more than `roles.out`, which has no events in it.
    //
    // The actions are read back out of UIKit's own target table rather than
    // from any bookkeeping of cortado's, so a handler that was never
    // registered is still not called, and a control whose registration was
    // removed stops responding. That is the same guarantee the AppKit host
    // gets from `-performClick:`.
    if (![UIApplication sharedApplication]) {
        for (id target in [control allTargets]) {
            NSArray<NSString *> *actions =
                [control actionsForTarget:target
                           forControlEvent:UIControlEventTouchUpInside];
            for (NSString *name in actions) {
                SEL action = NSSelectorFromString(name);
                if ([target respondsToSelector:action]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(target, action, control);
                }
            }
        }
    }
    return CTD_OK;
}

ctd_status ctd_widget_synth_value(ctd_handle widget, int64_t index, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[UISlider class]]) {
        [(UISlider *)object setValue:(float)value];
    } else if ([object isKindOfClass:[UISwitch class]]) {
        [(UISwitch *)object setOn:index == 1];
    } else if (ctd_slot_kind(widget) == CTD_W_COMBO_BOX ||
               ctd_slot_kind(widget) == CTD_W_RADIO_BUTTON) {
        ctd_status wrote = ctd_set_int(widget,
            ctd_slot_kind(widget) == CTD_W_COMBO_BOX ? CTD_P_SELECTED : CTD_P_CHECKED,
            index);
        if (wrote != CTD_OK) return wrote;
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
    if ([object isKindOfClass:[UITextField class]])      [(UITextField *)object setText:text];
    else if ([object isKindOfClass:[UITextView class]])  [(UITextView *)object setText:text];
    else return CTD_ERR_KIND;
    ctd_emit_control(widget, object);
    return CTD_OK;
}
