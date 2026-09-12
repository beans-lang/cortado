// Making a control of each kind, and letting one go.

#import "internal.h"

// -------------------------------------------------------------------- widgets

// Everything in the header, because AppKit has a control for all of it. The
// switch is written out one case per kind rather than as a range, so a kind
// added to the header and forgotten here is a build-time refusal — see the
// note beside ctd_widget_supports in ../cortado_host.h.
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
        case CTD_W_LEVEL_INDICATOR:
        case CTD_W_TABLE:
        case CTD_W_SEARCH_FIELD:
        case CTD_W_SPINNER:
        case CTD_W_LINK:
        case CTD_W_SEGMENTED:
        case CTD_W_GROUP_BOX:
        case CTD_W_DATE_PICKER:
        case CTD_W_COLOR_WELL:
        case CTD_W_DISCLOSURE:
        case CTD_W_TAB_VIEW:
        case CTD_W_SPLIT_VIEW:
        case CTD_W_WEB_VIEW:
            return 1;
        default:
            return CTD_ERR_RANGE;
    }
}

ctd_handle ctd_widget_new(int32_t kind) {
    // Asked rather than re-decided, so the factory and the question cannot
    // answer differently about the same kind.
    if (ctd_widget_supports(kind) != 1) return 0;
    NSView *view = nil;
    switch (kind) {
        case CTD_W_CONTAINER:
            view = [[CortadoView alloc] initWithFrame:NSZeroRect];
            break;
        // A canvas is a plain view, and that is the whole of it here: the
        // platform lays it out and shows it, and everything inside is the
        // program's. `ctd_gpu_canvas_attach` is what gives it a layer to draw
        // into, and until then it is an empty area rather than a broken one.
        case CTD_W_CANVAS:
            view = [[CortadoView alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_LABEL: {
            NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
            [label setBezeled:NO];
            [label setDrawsBackground:NO];
            [label setEditable:NO];
            [label setSelectable:NO];
            view = label;
            break;
        }
        case CTD_W_BUTTON: {
            NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
            [button setBezelStyle:NSBezelStyleRounded];
            [button setButtonType:NSButtonTypeMomentaryPushIn];
            [button setTitle:@""];
            view = button;
            break;
        }
        case CTD_W_TEXT_FIELD:
            view = [[NSTextField alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_CHECK_BOX: {
            NSButton *box = [[NSButton alloc] initWithFrame:NSZeroRect];
            [box setButtonType:NSButtonTypeSwitch];
            [box setAllowsMixedState:YES];
            [box setTitle:@""];
            view = box;
            break;
        }
        case CTD_W_IMAGE_VIEW:
            view = [[NSImageView alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_SLIDER: {
            NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
            [slider setMinValue:0.0];
            [slider setMaxValue:1.0];
            [slider setDoubleValue:0.0];
            // Continuous by default: a slider that only reports on mouse-up
            // cannot drive a live preview, which is most of what sliders are
            // for. A program that wants the other behaviour ignores the events
            // until it stops getting them.
            [slider setContinuous:YES];
            view = slider;
            break;
        }
        case CTD_W_PROGRESS_BAR: {
            NSProgressIndicator *bar =
                [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
            [bar setStyle:NSProgressIndicatorStyleBar];
            [bar setIndeterminate:NO];
            [bar setMinValue:0.0];
            [bar setMaxValue:1.0];
            [bar setDoubleValue:0.0];
            view = bar;
            break;
        }
        case CTD_W_SEPARATOR: {
            NSBox *rule = [[NSBox alloc] initWithFrame:NSZeroRect];
            [rule setBoxType:NSBoxSeparator];
            view = rule;
            break;
        }
        case CTD_W_TEXT_AREA: {
            // A text view has to live inside a scroll view to scroll, and a
            // multi-line field that cannot scroll is a field with a hidden
            // bottom. The scroll view is what cortado tracks: it is the thing
            // with a frame, and the text view inside it is an implementation
            // detail the tree never shows.
            NSScrollView *scroller =
                [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
            NSTextView *text =
                [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
            [text setMinSize:NSMakeSize(0, 0)];
            [text setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
            [text setVerticallyResizable:YES];
            [text setHorizontallyResizable:NO];
            [text setAutoresizingMask:NSViewWidthSizable];
            [[text textContainer] setWidthTracksTextView:YES];
            [scroller setDocumentView:text];
            [scroller setHasVerticalScroller:YES];
            [scroller setBorderType:NSBezelBorder];
            [text release];
            view = scroller;
            break;
        }
        case CTD_W_COMBO_BOX: {
            NSPopUpButton *menu =
                [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
            view = menu;
            break;
        }
        case CTD_W_SCROLL_VIEW: {
            NSScrollView *scroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
            CortadoView *content = [[CortadoView alloc] initWithFrame:NSZeroRect];
            [scroller setDocumentView:content];
            [scroller setHasVerticalScroller:YES];
            [scroller setDrawsBackground:NO];
            ctd_tag(content);
            [content release];
            view = scroller;
            break;
        }
        case CTD_W_RADIO_BUTTON: {
            NSButton *radio = [[NSButton alloc] initWithFrame:NSZeroRect];
            [radio setButtonType:NSButtonTypeRadio];
            [radio setTitle:@""];
            view = radio;
            break;
        }
        case CTD_W_TABLE: {
            // Tracked as the scroll view, like a text area: that is the thing
            // with a frame, and a table that cannot scroll is a table with a
            // hidden bottom. Everything in table.m reaches through it.
            NSScrollView *scroller =
                [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
            NSTableView *rows =
                [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
            [rows setUsesAlternatingRowBackgroundColors:YES];
            [rows setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
            [scroller setDocumentView:rows];
            [scroller setHasVerticalScroller:YES];
            [scroller setBorderType:NSBezelBorder];
            [rows release];
            view = scroller;
            break;
        }
        case CTD_W_SWITCH:
            // NSSwitch, not an NSButton with a switch button type. The two are
            // different controls: the button type draws a check box, and what
            // a Mac user calls a switch has been its own class since 10.15.
            view = [[NSSwitch alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_SEARCH_FIELD:
            // Also an NSTextField underneath, so every text and property path
            // in this host reaches it — and a real one, so it brings the
            // magnifier, the clear button and the shape a Mac user expects to
            // find a search box in.
            view = [[NSSearchField alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_SEGMENTED: {
            NSSegmentedControl *bar =
                [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
            [bar setSegmentCount:0];
            [bar setTrackingMode:NSSegmentSwitchTrackingSelectOne];
            view = bar;
            break;
        }
        case CTD_W_DISCLOSURE:
            view = ctd_disclosure_new();
            break;
        case CTD_W_TAB_VIEW:
            view = [[NSTabView alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_SPLIT_VIEW:
            view = ctd_split_new();
            break;
        case CTD_W_WEB_VIEW:
            view = ctd_web_new();
            break;
        case CTD_W_GROUP_BOX: {
            NSBox *group = [[NSBox alloc] initWithFrame:NSZeroRect];
            [group setBoxType:NSBoxPrimary];
            [group setTitle:@""];
            // A flipped content view, so children inside a group box are
            // placed the same way children anywhere else are. AppKit's own is
            // not flipped, and a box whose children ran the other way up would
            // be the one place in cortado where y grows downward.
            CortadoView *content = [[CortadoView alloc] initWithFrame:NSZeroRect];
            [group setContentView:content];
            ctd_tag(content);
            [content release];
            view = group;
            break;
        }
        case CTD_W_DATE_PICKER: {
            NSDatePicker *picker = [[NSDatePicker alloc] initWithFrame:NSZeroRect];
            // A day, not an instant — the rule stated beside CTD_W_DATE_PICKER
            // in the header. AppKit would happily show hours and minutes;
            // GtkCalendar has nowhere to put them, so cortado does not ask for
            // them anywhere.
            [picker setDatePickerElements:NSDatePickerElementFlagYearMonthDay];
            [picker setDatePickerStyle:NSDatePickerStyleTextFieldAndStepper];
            // UTC, so the number that crosses the ABI means the same day on a
            // machine in Auckland and one in Los Angeles. A picker left in the
            // local zone would read back a different day either side of
            // midnight, on one host only.
            [picker setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
            [picker setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];
            [picker setDateValue:[NSDate dateWithTimeIntervalSince1970:0.0]];
            view = picker;
            break;
        }
        case CTD_W_COLOR_WELL: {
            NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSZeroRect];
            [well setColor:[NSColor colorWithSRGBRed:0.0 green:0.0 blue:0.0 alpha:1.0]];
            view = well;
            break;
        }
        case CTD_W_LINK: {
            // AppKit has no link control, and the native affordance is not a
            // button: it is an NSTextField holding an attributed string with
            // NSLinkAttributeName on it. That is what gives the blue
            // underline, the pointing-hand cursor and the click that opens the
            // URL in the user's own browser with the user's own handler
            // registrations — none of which a styled button would have.
            NSTextField *link = [[NSTextField alloc] initWithFrame:NSZeroRect];
            [link setBezeled:NO];
            [link setDrawsBackground:NO];
            [link setEditable:NO];
            // Selectable, because an NSTextField only follows a link when its
            // text can be selected. It is the one thing that makes the control
            // clickable at all.
            [link setSelectable:YES];
            [link setAllowsEditingTextAttributes:YES];
            view = link;
            break;
        }
        case CTD_W_SPINNER: {
            NSProgressIndicator *wheel =
                [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
            [wheel setStyle:NSProgressIndicatorStyleSpinning];
            [wheel setIndeterminate:YES];
            // Kept on screen when it stops. The default is to vanish, which
            // leaves a hole in a laid-out column and makes "stopped" look like
            // "broken" — and cortado has already decided where it goes.
            [wheel setDisplayedWhenStopped:YES];
            view = wheel;
            break;
        }
        case CTD_W_SECURE_FIELD:
            // A subclass of NSTextField, so every text and property path in
            // this host already reaches it — and a real one, so the window
            // server keeps what is typed out of screen recordings.
            view = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
            break;
        case CTD_W_STEPPER: {
            NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
            [stepper setMinValue:0.0];
            [stepper setMaxValue:1.0];
            [stepper setIncrement:1.0];
            [stepper setDoubleValue:0.0];
            // Off, because a stepper that wraps turns "one past the end" into
            // "the beginning" silently, and a caller that wanted that can ask
            // for it by clamping their own number.
            [stepper setValueWraps:NO];
            view = stepper;
            break;
        }
        case CTD_W_LEVEL_INDICATOR: {
            NSLevelIndicator *level =
                [[NSLevelIndicator alloc] initWithFrame:NSZeroRect];
            // Continuous capacity: a bar that fills. The other styles are a
            // row of stars and a row of segments, which are the same number
            // told a different way — and a caller who wants one of those wants
            // it on purpose, which is a property this does not have yet.
            [level setLevelIndicatorStyle:NSLevelIndicatorStyleContinuousCapacity];
            [level setMinValue:0.0];
            [level setMaxValue:1.0];
            [level setDoubleValue:0.0];
            // An output, not an input. NSLevelIndicator is editable by default
            // in some styles, and a user dragging a battery gauge to full is
            // not something any caller asked for.
            [level setEditable:NO];
            view = level;
            break;
        }
        default:
            return 0;
    }
    ctd_tag(view);
    ctd_handle handle = ctd_track(view, kind);
    // A table's data source needs the handle, so it is made after tracking.
    // AppKit holds a data source weakly; g_targets is what keeps it alive, the
    // same arrangement the target/action forwarder below uses.
    if (kind == CTD_W_TABLE) {
        NSTableView *rows = ctd_table_view(view);
        CortadoTableSource *source = [[CortadoTableSource alloc] init];
        [source setHandle:handle];
        [source setRows:0];
        [rows setDataSource:source];
        [rows setDelegate:source];
        [g_targets addObject:source];
        [source release];
    }
    // Controls report their own actions from birth; a widget with no handler
    // registered simply reaches a sink that does nothing with it.
    if (kind == CTD_W_DISCLOSURE) ctd_disclosure_attach(handle, view);
    if (kind == CTD_W_TAB_VIEW) ctd_tabs_attach(handle, view);
    if (kind == CTD_W_SPLIT_VIEW) ctd_split_attach(handle, view);
    if (kind == CTD_W_WEB_VIEW) ctd_web_attach(handle, view);
    if ([view isKindOfClass:[NSControl class]]) {
        CortadoTarget *forwarder = [[CortadoTarget alloc] init];
        [forwarder setHandle:handle];
        [(NSControl *)view setTarget:forwarder];
        [(NSControl *)view setAction:@selector(fire:)];
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
    if ([object isKindOfClass:[NSView class]]) [(NSView *)object removeFromSuperview];
    ctd_untrack(widget);
    return CTD_OK;
}
