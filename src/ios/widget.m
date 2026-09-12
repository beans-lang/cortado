// Making a control of each kind, and letting one go.

#import "internal.h"

// iOS has no radio button and no pop-up list control. Both are built from a
// UIButton — a radio out of a selected state, a combo box out of a UIMenu —
// which is what Apple's own applications do. Neither is a stand-in drawn by
// cortado: a UIButton with a menu *is* the platform's control for choosing one
// of several on this system.

// Everything in the header. Two of them are the same UIKit control: a phone
// has no check box, so CTD_W_CHECK_BOX is a UISwitch here, and CTD_W_SWITCH is
// the same control asked for by its own name. That is not a substitution of
// the kind ctd_widget_supports exists to refuse — a UISwitch *is* what iOS
// offers for a boolean, and both kinds get the real one.
int32_t ctd_widget_supports(int32_t kind) {
    switch (kind) {
        case CTD_W_CONTAINER:
        case CTD_W_LABEL:
        case CTD_W_BUTTON:
        case CTD_W_TEXT_FIELD:
        case CTD_W_CHECK_BOX:
        case CTD_W_IMAGE_VIEW:
        case CTD_W_SLIDER:
        case CTD_W_PROGRESS_BAR:
        case CTD_W_SEPARATOR:
        case CTD_W_TEXT_AREA:
        case CTD_W_COMBO_BOX:
        case CTD_W_SCROLL_VIEW:
        case CTD_W_RADIO_BUTTON:
        case CTD_W_CANVAS:
        case CTD_W_SWITCH:
        case CTD_W_SECURE_FIELD:
        case CTD_W_STEPPER:
        case CTD_W_TABLE:
        case CTD_W_SEARCH_FIELD:
        case CTD_W_SPINNER:
        case CTD_W_LINK:
        case CTD_W_SEGMENTED:
        case CTD_W_DATE_PICKER:
        case CTD_W_COLOR_WELL:
        case CTD_W_DISCLOSURE:
        case CTD_W_WEB_VIEW:
            return 1;
        case CTD_W_SPLIT_VIEW:
            // UIKit's split view is a view *controller* as well, and one that
            // owns the screen and changes shape with the device. There is no
            // draggable divider on a phone at all.
            return 0;
        case CTD_W_TAB_VIEW:
            // UIKit has no tab *view*. UITabBarController is a view controller
            // that owns the whole screen — not a control that goes into a
            // layout — and a UISegmentedControl with a container under it
            // would be cortado assembling a substitute out of two kinds the
            // caller already has, which is what ctd_widget_supports exists to
            // refuse.
            return 0;
        case CTD_W_GROUP_BOX:
            // UIKit has nothing that means "a titled frame around a group".
            // A UIView with a border and a label on top would be cortado
            // drawing a control, which is the substitution ctd_widget_supports
            // exists to refuse.
            return 0;
        case CTD_W_LEVEL_INDICATOR:
            // UIKit has no level indicator. A UIProgressView is a progress
            // bar — work being done, with a beginning and an end — and a level
            // is a reading that goes up and down and never finishes. Drawing a
            // bar and calling it one would be the substitution
            // ctd_widget_supports exists to refuse.
            return 0;
        default:
            return CTD_ERR_RANGE;
    }
}

ctd_handle ctd_widget_new(int32_t kind) {
    // Asked rather than re-decided, so the factory and the question cannot
    // answer differently about the same kind.
    if (ctd_widget_supports(kind) != 1) return 0;
    UIView *view = nil;
    switch (kind) {
        case CTD_W_CONTAINER:
            view = [[UIView alloc] initWithFrame:CGRectZero];
            break;
        // A canvas is a plain view, and that is the whole of it here: the
        // platform lays it out and shows it, and everything inside is the
        // program's. On a host with no GPU nothing ever draws into it, and
        // an empty area is the honest shape for that.
        case CTD_W_CANVAS:
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
        case CTD_W_CHECK_BOX:
        case CTD_W_SWITCH: {
            // A switch is what iOS uses where a desktop uses a check box, and
            // it is also, on its own account, a switch. Both kinds build one.
            // The difference the two kinds keep is the mixed state: a check
            // box has one everywhere and this platform cannot show it, which
            // `ctd_set_int` reports rather than rounding to on or off.
            UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
            view = toggle;
            break;
        }
        case CTD_W_STEPPER: {
            UIStepper *stepper = [[UIStepper alloc] initWithFrame:CGRectZero];
            [stepper setMinimumValue:0.0];
            [stepper setMaximumValue:1.0];
            [stepper setStepValue:1.0];
            [stepper setValue:0.0];
            [stepper setWraps:NO];
            view = stepper;
            break;
        }
        case CTD_W_SEARCH_FIELD: {
            // A UITextField underneath, so every text path in this host
            // reaches it — and the real one, so it brings the magnifier and
            // the clear button a phone user expects.
            UISearchTextField *field =
                [[UISearchTextField alloc] initWithFrame:CGRectZero];
            view = field;
            break;
        }
        case CTD_W_SEGMENTED: {
            UISegmentedControl *bar =
                [[UISegmentedControl alloc] initWithItems:@[]];
            [bar setFrame:CGRectZero];
            view = bar;
            break;
        }
        case CTD_W_DISCLOSURE:
            view = ctd_disclosure_new();
            break;
        case CTD_W_WEB_VIEW:
            view = ctd_web_new();
            break;
        case CTD_W_DATE_PICKER: {
            UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:CGRectZero];
            // A day, the rule beside CTD_W_DATE_PICKER in the header — and
            // UTC, so the number that crosses means the same day wherever the
            // phone is. A picker left in the device's zone reads back a
            // different day either side of midnight.
            [picker setDatePickerMode:UIDatePickerModeDate];
            [picker setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
            [picker setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];
            // Compact rather than the wheel: an inline calendar is 320 points
            // tall and would be the one control in cortado whose measured size
            // ignores the space the solver gave it.
            [picker setPreferredDatePickerStyle:UIDatePickerStyleCompact];
            [picker setDate:[NSDate dateWithTimeIntervalSince1970:0.0]];
            view = picker;
            break;
        }
        case CTD_W_COLOR_WELL: {
            UIColorWell *well = [[UIColorWell alloc] initWithFrame:CGRectZero];
            [well setSelectedColor:[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0]];
            view = well;
            break;
        }
        case CTD_W_LINK: {
            // UIKit has no link control either. A UIButton is the control a
            // phone user taps, and the host opens the URL itself — see the
            // note beside CTD_S_URL in the header for why a link opens and
            // raises nothing.
            UIButton *link = [UIButton buttonWithType:UIButtonTypeSystem];
            [link setFrame:CGRectZero];
            view = [link retain];
            break;
        }
        case CTD_W_SPINNER: {
            UIActivityIndicatorView *wheel = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            // Kept on screen when it stops, for the reason the Mac keeps it:
            // cortado has already decided where it goes, and a control that
            // vanishes leaves a hole in a laid-out column.
            [wheel setHidesWhenStopped:NO];
            view = wheel;
            break;
        }
        case CTD_W_SECURE_FIELD: {
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
            [field setBorderStyle:UITextBorderStyleRoundedRect];
            // The real thing, not a font trick: UIKit keeps a secure field out
            // of the pasteboard, out of autocorrect's dictionary and off a
            // screen recording, and none of that follows from drawing dots.
            [field setSecureTextEntry:YES];
            view = field;
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
        case CTD_W_TABLE: {
            UITableView *rows = [[UITableView alloc]
                initWithFrame:CGRectZero style:UITableViewStylePlain];
            view = rows;
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
    if (kind == CTD_W_LINK) {
        // Its own target, so a tap opens the URL rather than reaching the
        // sink. A link is the one control in cortado that acts on its own.
        CortadoLink *opener = [[CortadoLink alloc] init];
        [opener setHandle:handle];
        [(UIButton *)view addTarget:opener
                             action:@selector(follow:)
                   forControlEvents:UIControlEventTouchUpInside];
        [g_targets addObject:opener];
        [opener release];
    }
    if (kind == CTD_W_TABLE) {
        UITableView *rows = ctd_table_view(view);
        CortadoTableSource *source = [[CortadoTableSource alloc] init];
        [source setHandle:handle];
        [source setRows:0];
        [rows setDataSource:source];
        [rows setDelegate:source];
        [g_targets addObject:source];
        [source release];
    }
    if (kind == CTD_W_DISCLOSURE) ctd_disclosure_attach(handle, view);
    if (kind == CTD_W_WEB_VIEW) ctd_web_attach(handle, view);
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
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if ([object isKindOfClass:[UIView class]]) {
        [(UIView *)object removeFromSuperview];
    }
    // Bumping the generation, which ctd_untrack does, is what turns a stale
    // handle into a checked error rather than a jump into a slot somebody
    // else now owns — and what makes handing the slot back safe.
    ctd_untrack(widget);
    return CTD_OK;
}
