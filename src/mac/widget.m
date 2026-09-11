// Making a control of each kind, and letting one go.

#import "internal.h"

// -------------------------------------------------------------------- widgets

ctd_handle ctd_widget_new(int32_t kind) {
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
        default:
            return 0;
    }
    ctd_tag(view);
    ctd_handle handle = ctd_track(view, kind);
    // Controls report their own actions from birth; a widget with no handler
    // registered simply reaches a sink that does nothing with it.
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
