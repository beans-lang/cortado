// Making a control of each kind, and letting one go.

#import "internal.h"

// iOS has no radio button and no pop-up list control. Both are built from a
// UIButton — a radio out of a selected state, a combo box out of a UIMenu —
// which is what Apple's own applications do. Neither is a stand-in drawn by
// cortado: a UIButton with a menu *is* the platform's control for choosing one
// of several on this system.

ctd_handle ctd_widget_new(int32_t kind) {
    UIView *view = nil;
    switch (kind) {
        case CTD_W_CONTAINER:
            view = [[UIView alloc] initWithFrame:CGRectZero];
            break;
        case CTD_W_LABEL: {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            [label setText:@""];
            view = label;
            break;
        }
        case CTD_W_BUTTON: {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setFrame:CGRectZero];
            view = [button retain];
            break;
        }
        case CTD_W_TEXT_FIELD: {
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
            [field setBorderStyle:UITextBorderStyleRoundedRect];
            view = field;
            break;
        }
        case CTD_W_CHECK_BOX: {
            // A switch is what iOS uses where a desktop uses a check box. It
            // has no mixed state, which `ctd_set_int` reports rather than
            // rounding to on or off.
            UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
            view = toggle;
            break;
        }
        case CTD_W_IMAGE_VIEW:
            view = [[UIImageView alloc] initWithFrame:CGRectZero];
            break;
        case CTD_W_SLIDER: {
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
            [slider setMinimumValue:0.0f];
            [slider setMaximumValue:1.0f];
            view = slider;
            break;
        }
        case CTD_W_PROGRESS_BAR: {
            UIProgressView *bar =
                [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
            view = bar;
            break;
        }
        case CTD_W_SEPARATOR: {
            // iOS has no separator control; a hairline view is what a table's
            // own separators are, and `separatorColor` is the system's.
            UIView *rule = [[UIView alloc] initWithFrame:CGRectZero];
            [rule setBackgroundColor:[UIColor separatorColor]];
            view = rule;
            break;
        }
        case CTD_W_TEXT_AREA: {
            UITextView *text = [[UITextView alloc] initWithFrame:CGRectZero];
            [text setScrollEnabled:YES];
            view = text;
            break;
        }
        case CTD_W_COMBO_BOX: {
            UIButton *menu = [UIButton buttonWithType:UIButtonTypeSystem];
            [menu setFrame:CGRectZero];
            [menu setShowsMenuAsPrimaryAction:YES];
            [menu setTag:-1];
            view = [menu retain];
            break;
        }
        case CTD_W_SCROLL_VIEW: {
            UIScrollView *scroller = [[UIScrollView alloc] initWithFrame:CGRectZero];
            view = scroller;
            break;
        }
        case CTD_W_RADIO_BUTTON: {
            UIButton *radio = [UIButton buttonWithType:UIButtonTypeSystem];
            [radio setFrame:CGRectZero];
            view = [radio retain];
            break;
        }
        default:
            return 0;
    }
    ctd_tag(view);
    ctd_handle handle = ctd_track(view, kind);
    if ([view isKindOfClass:[UIControl class]]) {
        CortadoTarget *forwarder = [[CortadoTarget alloc] init];
        [forwarder setHandle:handle];
        // Both events, because a UIControl reports a press and a value change
        // on different ones and cortado decides the kind from the widget.
        [(UIControl *)view addTarget:forwarder
                              action:@selector(fire:)
                    forControlEvents:UIControlEventTouchUpInside |
                                     UIControlEventValueChanged |
                                     UIControlEventEditingDidEndOnExit];
        [g_targets addObject:forwarder];
        [forwarder release];
    }
    [view release];
    return handle;
}

int32_t ctd_widget_kind(ctd_handle widget) { return ctd_slot_kind(widget); }

int32_t ctd_widget_alive(ctd_handle widget) { return ctd_resolve(widget) ? 1 : 0; }

ctd_status ctd_widget_release(ctd_handle widget) {
    uint32_t slot = (uint32_t)(widget & 0xffffffffu);
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[UIView class]]) {
        [(UIView *)object removeFromSuperview];
    }
    [object release];
    g_object[slot] = nil;
    // Bumping the generation is what turns a stale handle into a checked
    // error rather than a jump into a slot somebody else now owns — and what
    // makes handing the slot back safe.
    g_generation[slot] = g_generation[slot] + 1;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    ctd_give_back(slot);
    return CTD_OK;
}
