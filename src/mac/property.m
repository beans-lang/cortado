// Text, and the scalar property bag.
//
// Which widgets carry CTD_P_ENABLED is a rule of cortado's rather than of
// AppKit's — see `ctd_kind_has_enabled` in ../cortado_rules.h.

#import "internal.h"
#import <objc/runtime.h>

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

// Whether a spinner is turning.
//
// Kept here because NSProgressIndicator has no way to be asked. It answers
// -isIndeterminate and nothing about whether the animation is running, and a
// property a caller can set and not read back is half a property. Nothing but
// the program starts or stops one, so there is no second answer for this to
// disagree with — the same argument the progress bar's value makes on the
// three hosts that keep it.
static int g_spinning[CTD_SLOTS];

// Where each link goes, by handle.
//
// Kept here because an attributed string is not a place to read a URL back
// from: -attribute:atIndex:effectiveRange: answers an NSURL that AppKit
// normalised, so a program that set "example.com/a b" would read back
// "example.com/a%20b" and a round-trip test would fail for a reason that is
// nobody's bug. The control still holds the real link; this holds the words.
static NSMutableDictionary *g_link_urls;

// The link's text and its target, as one attributed string.
//
// Called from both setters, because an NSTextField's attributed value carries
// the words *and* the link together — writing either one alone would drop the
// other.
// The dictionary, made on first use. A message to nil is a no-op in
// Objective-C, so a -setObject: before it exists loses the URL silently — and
// that is exactly what happened: the link drew correctly and read back "".
static NSMutableDictionary *ctd_link_book(void) {
    if (!g_link_urls) g_link_urls = [[NSMutableDictionary alloc] init];
    return g_link_urls;
}

void ctd_link_retitle(NSTextField *link, NSString *words, NSURL *target) {
    NSString *text = words ? words : @"";
    NSMutableDictionary *style = [NSMutableDictionary dictionary];
    if (target) {
        [style setObject:target forKey:NSLinkAttributeName];
        [style setObject:[NSNumber numberWithInt:NSUnderlineStyleSingle]
                  forKey:NSUnderlineStyleAttributeName];
        [style setObject:[NSColor linkColor] forKey:NSForegroundColorAttributeName];
    }
    NSAttributedString *rich =
        [[NSAttributedString alloc] initWithString:text attributes:style];
    [link setAttributedStringValue:rich];
    [rich release];
}

CALayer *ctd_layer_of(NSView *view) {
    if (![view wantsLayer]) [view setWantsLayer:YES];
    return [view layer];
}

/* The layer a view already has, or nil. Not ctd_layer_of: a getter must not
 * make a layer on every control it is asked about. */
static CALayer *ctd_layer_if_any(NSView *view) {
    return [view wantsLayer] ? [view layer] : nil;
}

/* A CGColor back to 0xRRGGBBAA. Matched into sRGB first: four floats out of a
 * grey or pattern space read as RGBA are plausible and wrong. */
static int64_t ctd_color_of_cg(CGColorRef color) {
    if (!color) return 0;
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef matched = CGColorCreateCopyByMatchingToColorSpace(
        srgb, kCGRenderingIntentDefault, color, NULL);
    CGColorSpaceRelease(srgb);
    if (!matched) return 0;
    const CGFloat *parts = CGColorGetComponents(matched);
    size_t count = CGColorGetNumberOfComponents(matched);
    int64_t packed = 0;
    if (count >= 4) {
        packed = ctd_color_pack(ctd_color_byte(parts[0]), ctd_color_byte(parts[1]),
                                ctd_color_byte(parts[2]), ctd_color_byte(parts[3]));
    }
    CGColorRelease(matched);
    return packed;
}

/* An NSColor back to 0xRRGGBBAA, through sRGB for the reason ctd_color_of_cg
 * matches: a colour left in the display profile is a different byte. */
static int64_t ctd_color_of_ns(NSColor *color) {
    if (!color) return 0;
    NSColor *shown = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!shown) return 0;
    return ctd_color_pack(ctd_color_byte([shown redComponent]),
                          ctd_color_byte([shown greenComponent]),
                          ctd_color_byte([shown blueComponent]),
                          ctd_color_byte([shown alphaComponent]));
}

static CGColorRef ctd_cg_color(int64_t value) {
    return [[NSColor colorWithSRGBRed:ctd_color_red(value)   / 255.0
                                green:ctd_color_green(value) / 255.0
                                 blue:ctd_color_blue(value)  / 255.0
                                alpha:ctd_color_alpha(value) / 255.0] CGColor];
}

ctd_status ctd_set_string(ctd_handle widget, int32_t key,
                          const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    // Anything written to a control can change how big it wants to be — a
    // longer title, a bigger font, a different image. Forgotten here rather
    // than at each of the dozens of cases below, because this is the door
    // every write comes through and a case that forgot would be a control
    // that laid out at its old size for ever.
    ctd_forget_size(widget);

    switch (key) {
        case CTD_S_A11Y_LABEL: {
            // Carried by every kind: a label on a button is a legitimate
            // override, and it is how a toolbar of icons is usable at all.
            NSString *label = len == 0 ? nil : ctd_string(utf8, len);
            [(NSView *)object setAccessibilityLabel:label];
            [(NSView *)object setToolTip:label];
            NSTableView *table = ctd_table_view(object);
            if (table) [table setAccessibilityLabel:label];
            NSTextView *text = ctd_text_view(object);
            if (text) [text setAccessibilityLabel:label];
            return CTD_OK;
        }
        case CTD_S_HINT:
            if (!ctd_kind_has_hint(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            [(NSTextField *)object setPlaceholderString:ctd_string(utf8, len)];
            return CTD_OK;
        case CTD_S_URL: {
            if (!ctd_kind_has_url(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSTextField *link = (NSTextField *)object;
            NSString *where = ctd_string(utf8, len);
            NSURL *target = [NSURL URLWithString:where];
            // A string AppKit cannot read as a URL is refused here rather than
            // becoming a link that does nothing when clicked.
            if (len > 0 && !target) return CTD_ERR_RANGE;
            [ctd_link_book() setObject:where forKey:[NSNumber numberWithUnsignedLongLong:widget]];
            ctd_link_retitle(link, [link stringValue], target);
            return CTD_OK;
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

int32_t ctd_get_string(ctd_handle widget, int32_t key, char *out, int32_t cap) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    switch (key) {
        case CTD_S_A11Y_LABEL: {
            // What was set, never the control's own text: "" means no label
            // was given, not "this control has no words".
            NSString *said = [(NSView *)object accessibilityLabel];
            return ctd_copy_out(said ? said : @"", out, cap);
        }
        case CTD_S_HINT: {
            if (!ctd_kind_has_hint(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSString *hint = [(NSTextField *)object placeholderString];
            return ctd_copy_out(hint ? hint : @"", out, cap);
        }
        case CTD_S_URL: {
            if (!ctd_kind_has_url(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSString *where = [ctd_link_book() objectForKey:
                [NSNumber numberWithUnsignedLongLong:widget]];
            return ctd_copy_out(where ? where : @"", out, cap);
        }
        default: return CTD_ERR_UNSUPPORTED;
    }
}

ctd_status ctd_set_text(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    // The door most writes come through, and the one that matters most for a
    // remembered size: a label given more words is wider.
    ctd_forget_size(widget);
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    NSString *text = ctd_string(utf8, len);
    NSTextView *inner = ctd_text_view(object);
    if (ctd_slot_kind(widget) == CTD_W_LINK) {
        // A link's words and its target are one attributed string, so writing
        // the words alone would drop the link. Both go through one place.
        NSString *where = [ctd_link_book() objectForKey:
            [NSNumber numberWithUnsignedLongLong:widget]];
        ctd_link_retitle((NSTextField *)object, text,
                         where ? [NSURL URLWithString:where] : nil);
        return CTD_OK;
    }
    if (inner)                                           [inner setString:text];
    // A group box's text is the title on its frame. A separator is also an
    // NSBox and has none, which the kind decides rather than the class.
    else if (ctd_slot_kind(widget) == CTD_W_GROUP_BOX)   [(NSBox *)object setTitle:text];
    // A disclosure's text is the title beside the triangle. The header sizes
    // itself to the words, so the body moves when a title wraps to two lines —
    // which is why the caller is told about it through ctd_view_content_inset
    // rather than being asked to guess.
    else if ([object isKindOfClass:[CortadoDisclosure class]]) {
        [[(CortadoDisclosure *)object caption] setStringValue:text];
        [(CortadoDisclosure *)object relayout];
    }
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
    if (ctd_slot_kind(widget) == CTD_W_GROUP_BOX)
        return ctd_copy_out([(NSBox *)object title], out, cap);
    if ([object isKindOfClass:[CortadoDisclosure class]])
        return ctd_copy_out([[(CortadoDisclosure *)object caption] stringValue], out, cap);
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
    ctd_forget_size(widget);
    switch (key) {
        case CTD_P_ENABLED:
            if (!ctd_kind_has_enabled(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            [(NSControl *)object setEnabled:value ? YES : NO];
            return CTD_OK;
        case CTD_P_BORDERLESS:
            if (ctd_slot_kind(widget) != CTD_W_TAB_VIEW) return CTD_ERR_KIND;
            if (value != 0 && value != 1) return CTD_ERR_RANGE;
            [(NSTabView *)object setTabViewType:value ? NSNoTabsNoBorder : NSTopTabsBezelBorder];
            [(NSTabView *)object setDrawsBackground:!value];
            return CTD_OK;
        case CTD_P_COMPACT: {
            int kind = ctd_slot_kind(widget);
            if (kind != CTD_W_TABLE && kind != CTD_W_OUTLINE_VIEW) return CTD_ERR_KIND;
            if (value != 0 && value != 1) return CTD_ERR_RANGE;
            NSTableView *table = ctd_table_view(object);
            [(NSScrollView *)object setBorderType:value ? NSNoBorder : NSBezelBorder];
            [(NSScrollView *)object setAutohidesScrollers:YES];
            if (@available(macOS 11.0, *)) [table setStyle:value ? NSTableViewStylePlain : NSTableViewStyleAutomatic];
            [table setFocusRingType:value ? NSFocusRingTypeNone : NSFocusRingTypeDefault];
            [table setRowHeight:value ? 23.0 : 17.0];
            [table setIntercellSpacing:NSMakeSize(3.0, 1.0)];
            [table setGridStyleMask:value && kind == CTD_W_TABLE ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
            if (kind == CTD_W_OUTLINE_VIEW) {
                if (value) [table setHeaderView:nil];
                else if (![table headerView]) [table setHeaderView:[[[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 100, 23)] autorelease]];
                [table setUsesAlternatingRowBackgroundColors:!value];
                [table setBackgroundColor:value ? [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
                    BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
                    return [NSColor colorWithCalibratedWhite:dark ? 0.145 : 0.96 alpha:1];
                }] : [NSColor controlBackgroundColor]];
            }
            objc_setAssociatedObject(table, @selector(ctdCompact), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (NSTableColumn *column in [table tableColumns]) {
                [[column dataCell] setFont:value ? [NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular] : [NSFont systemFontOfSize:13.0]];
            }
            [table reloadData];
            return CTD_OK;
        }
        case CTD_P_HIDDEN:
            [(NSView *)object setHidden:value ? YES : NO];
            return CTD_OK;
        case CTD_P_LINES: {
            if (!ctd_kind_has_lines(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0) return CTD_ERR_RANGE;
            NSTextField *label = (NSTextField *)object;
            [label setMaximumNumberOfLines:(NSInteger)value];
            // One line is cut short rather than wrapped into a box one line tall.
            [[label cell] setLineBreakMode:value == 1 ? NSLineBreakByTruncatingTail
                                                      : NSLineBreakByWordWrapping];
            return CTD_OK;
        }
        case CTD_P_CODE_MODE: {
            if (ctd_slot_kind(widget) != CTD_W_TEXT_AREA) return CTD_ERR_KIND;
            if (value != 0 && value != 1) return CTD_ERR_RANGE;
            [(CortadoTextView *)ctd_text_view(object) ctdSetCodeMode:value == 1];
            return CTD_OK;
        }
        case CTD_P_AXIS: {
            if (!ctd_kind_has_divider(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value > 1) return CTD_ERR_RANGE;
            // cortado names the axis the panes run along; AppKit names the
            // divider. Side by side is `vertical` here and 0 there.
            [(NSSplitView *)object setVertical:value == 0 ? YES : NO];
            return CTD_OK;
        }
        case CTD_P_ICON: {
            if (!ctd_kind_has_icon(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value >= CTD_ICON_COUNT) return CTD_ERR_RANGE;
            NSImage *picture = value == CTD_ICON_NONE
                             ? nil : ctd_icon_image((int32_t)value);
            // Refused rather than cleared, so a role this system has no
            // symbol for is an answer at the call and not a blank control
            // three screens later.
            if (value != CTD_ICON_NONE && !picture) return CTD_ERR_RANGE;
            if ([object isKindOfClass:[NSButton class]]) {
                [(NSButton *)object setImage:picture];
                // Beside the words where there are words, and on its own
                // where there are not — which is what a toolbar-shaped button
                // and a labelled one each want, without the caller saying.
                [(NSButton *)object setImagePosition:
                    [[(NSButton *)object title] length] ? NSImageLeading
                                                        : NSImageOnly];
            } else if ([object isKindOfClass:[NSImageView class]]) {
                [(NSImageView *)object setImage:picture];
            } else {
                return CTD_ERR_KIND;
            }
            g_icon[(uint32_t)(widget & 0xffffffffu)] = (int32_t)value;
            return CTD_OK;
        }
        case CTD_P_EXPANDED: {
            if (!ctd_kind_has_expanded(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value > 1) return CTD_ERR_RANGE;
            CortadoDisclosure *twisty = (CortadoDisclosure *)object;
            [[twisty triangle] setState:value ? NSControlStateValueOn
                                              : NSControlStateValueOff];
            [[twisty content] setHidden:value ? NO : YES];
            return CTD_OK;
        }
        case CTD_P_COLOR: {
            if (!ctd_kind_has_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (!ctd_color_in_range(value)) return CTD_ERR_RANGE;
            // sRGB by name. NSColor has a dozen colour spaces and the one a
            // well is left in is the user's display profile, which is not the
            // space 0xRRGGBBAA names — a byte written on a wide-gamut screen
            // would come back as a different byte.
            [(NSColorWell *)object setColor:
                [NSColor colorWithSRGBRed:ctd_color_red(value)   / 255.0
                                    green:ctd_color_green(value) / 255.0
                                     blue:ctd_color_blue(value)  / 255.0
                                    alpha:ctd_color_alpha(value) / 255.0]];
            return CTD_OK;
        }
        case CTD_P_BG_COLOR: {
            if (!ctd_kind_has_background(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (!ctd_color_in_range(value)) return CTD_ERR_RANGE;
            [ctd_layer_of((NSView *)object) setBackgroundColor:ctd_cg_color(value)];
            return CTD_OK;
        }
        case CTD_P_BORDER_COLOR: {
            if (!ctd_color_in_range(value)) return CTD_ERR_RANGE;
            [ctd_layer_of((NSView *)object) setBorderColor:ctd_cg_color(value)];
            return CTD_OK;
        }
        case CTD_P_FG_COLOR: {
            if (!ctd_kind_has_fg_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (!ctd_color_in_range(value)) return CTD_ERR_RANGE;
            NSColor *ink = [NSColor colorWithSRGBRed:ctd_color_red(value)   / 255.0
                                               green:ctd_color_green(value) / 255.0
                                                blue:ctd_color_blue(value)  / 255.0
                                               alpha:ctd_color_alpha(value) / 255.0];
            /* A text area is an NSScrollView around the view that holds the
             * text, the same indirection CTD_P_FONT_SIZE steps through. */
            NSTextView *inner = ctd_text_view(object);
            if (inner) { [inner setTextColor:ink]; return CTD_OK; }
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            [(NSTextField *)object setTextColor:ink];
            return CTD_OK;
        }
        case CTD_P_FOCUSABLE: {
            if (!ctd_kind_is_drawn(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < 0 || value > 1) return CTD_ERR_RANGE;
            [(CortadoView *)object setCtdFocusable:value ? YES : NO];
            return CTD_OK;
        }
        case CTD_P_A11Y_ROLE: {
            if (!ctd_kind_is_drawn(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            if (value < CTD_A11Y_AUTO || value > CTD_A11Y_GROUP) return CTD_ERR_RANGE;
            [(CortadoView *)object setCtdRole:(int32_t)value];
            // Told to the accessibility system too, and not only reported back
            // through ctd_a11y_role: a role cortado prints in a golden and a
            // role VoiceOver hears are two different things, and a program that
            // set one and got the other would be worse off than one that could
            // set neither.
            NSString *ax = nil;
            if (value == CTD_A11Y_BUTTON) ax = NSAccessibilityButtonRole;
            else if (value == CTD_A11Y_IMAGE) ax = NSAccessibilityImageRole;
            else if (value == CTD_A11Y_GROUP) ax = NSAccessibilityGroupRole;
            [(NSView *)object setAccessibilityRole:ax];
            return CTD_OK;
        }
        case CTD_P_CHECKED: {
            // By kind, not by class. AppKit makes a push button, a check box
            // and a radio out of one class, so asking the object said yes to
            // all three — see the rule beside CTD_P_CHECKED in the header.
            int32_t kind = ctd_slot_kind(widget);
            if (!ctd_kind_has_checked(kind)) return CTD_ERR_KIND;
            if (!ctd_checked_in_range(kind, value)) return CTD_ERR_RANGE;
            if ([object isKindOfClass:[NSSwitch class]]) {
                [(NSSwitch *)object setState:value == 1 ? NSControlStateValueOn
                                                        : NSControlStateValueOff];
                return CTD_OK;
            }
            NSControlStateValue state = value == 2 ? NSControlStateValueMixed
                                      : value == 1 ? NSControlStateValueOn
                                                   : NSControlStateValueOff;
            [(NSButton *)object setState:state];
            return CTD_OK;
        }
        case CTD_P_EDITABLE: {
            if (!ctd_kind_has_editable(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            /* The old class check refused a text area (an NSScrollView) and
             * accepted a label (an NSTextField). Both wrong. */
            NSTextView *inner = ctd_text_view(object);
            if (inner) { [inner setEditable:value ? YES : NO]; return CTD_OK; }
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            [(NSTextField *)object setEditable:value ? YES : NO];
            return CTD_OK;
        }
        case CTD_P_ALIGNMENT: {
            if (!ctd_kind_has_alignment(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSTextAlignment alignment = value == 1 ? NSTextAlignmentCenter
                                      : value == 2 ? NSTextAlignmentRight
                                                   : NSTextAlignmentLeft;
            NSTextView *inner = ctd_text_view(object);
            if (inner) { [inner setAlignment:alignment]; return CTD_OK; }
            [(NSTextField *)object setAlignment:alignment];
            return CTD_OK;
        }
        case CTD_P_SELECTED: {
            // A tab view first, because its selection is a page rather than a
            // row of a menu, and -1 means nothing to it: a tab view always
            // shows one of its pages.
            NSTabView *tabs = ctd_tab_view(object);
            if (tabs) {
                if (value < 0 || value >= (int64_t)[tabs numberOfTabViewItems])
                    return CTD_ERR_RANGE;
                [tabs selectTabViewItemAtIndex:(NSInteger)value];
                return CTD_OK;
            }
            if ([object isKindOfClass:[NSSegmentedControl class]]) {
                NSSegmentedControl *bar = (NSSegmentedControl *)object;
                if (value < 0) { [bar setSelectedSegment:-1]; return CTD_OK; }
                if (value >= (int64_t)[bar segmentCount]) return CTD_ERR_RANGE;
                [bar setSelectedSegment:(NSInteger)value];
                return CTD_OK;
            }
            if (![object isKindOfClass:[NSPopUpButton class]]) return CTD_ERR_KIND;
            NSPopUpButton *menu = (NSPopUpButton *)object;
            if (value < 0) { [menu selectItem:nil]; return CTD_OK; }
            if (value >= (int64_t)[menu numberOfItems]) return CTD_ERR_RANGE;
            [menu selectItemAtIndex:(NSInteger)value];
            return CTD_OK;
        }
        case CTD_P_ANIMATING: {
            if (!ctd_kind_has_animating(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSProgressIndicator *wheel = (NSProgressIndicator *)object;
            if (value) [wheel startAnimation:nil]; else [wheel stopAnimation:nil];
            g_spinning[(uint32_t)(widget & 0xffffffffu)] = value ? 1 : 0;
            return CTD_OK;
        }
        case CTD_P_INDETERMINATE: {
            // A spinner has no total to be unknown about; that is what
            // CTD_P_ANIMATING is for, and the two mean different things.
            if (ctd_slot_kind(widget) == CTD_W_SPINNER) return CTD_ERR_KIND;
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
        case CTD_P_BORDERLESS:
            if (ctd_slot_kind(widget) != CTD_W_TAB_VIEW) return CTD_ERR_KIND;
            value = [(NSTabView *)object tabViewType] == NSNoTabsNoBorder;
            break;
        case CTD_P_COMPACT:
            if (ctd_slot_kind(widget) != CTD_W_TABLE && ctd_slot_kind(widget) != CTD_W_OUTLINE_VIEW) return CTD_ERR_KIND;
            value = [objc_getAssociatedObject(ctd_table_view(object), @selector(ctdCompact)) boolValue];
            break;
        case CTD_P_HIDDEN:
            value = [(NSView *)object isHidden] ? 1 : 0;
            break;
        case CTD_P_LINES:
            if (!ctd_kind_has_lines(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = (int64_t)[(NSTextField *)object maximumNumberOfLines];
            break;
        case CTD_P_CODE_MODE:
            if (ctd_slot_kind(widget) != CTD_W_TEXT_AREA) return CTD_ERR_KIND;
            value = [(CortadoTextView *)ctd_text_view(object) ctdCodeMode] ? 1 : 0;
            break;
        case CTD_P_AXIS:
            if (!ctd_kind_has_divider(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = [(NSSplitView *)object isVertical] ? 0 : 1;
            break;
        case CTD_P_ICON:
            if (!ctd_kind_has_icon(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            // Kept beside the handle rather than read back off the control:
            // AppKit hands out an NSImage and there is no way from one to the
            // role that asked for it.
            value = g_icon[(uint32_t)(widget & 0xffffffffu)];
            break;
        case CTD_P_EXPANDED:
            if (!ctd_kind_has_expanded(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            // The triangle, not a copy kept beside it: the user can turn it
            // and a second record of the same fact is a second answer.
            value = [[(CortadoDisclosure *)object triangle] state] ==
                        NSControlStateValueOn ? 1 : 0;
            break;
        case CTD_P_BG_COLOR: {
            /* These shipped write-only. No layer means no background, which
             * is 0 — a true answer rather than a refusal. */
            if (!ctd_kind_has_background(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            CALayer *layer = ctd_layer_if_any((NSView *)object);
            value = layer ? ctd_color_of_cg([layer backgroundColor]) : 0;
            break;
        }
        case CTD_P_BORDER_COLOR: {
            CALayer *layer = ctd_layer_if_any((NSView *)object);
            value = layer ? ctd_color_of_cg([layer borderColor]) : 0;
            break;
        }
        case CTD_P_FG_COLOR: {
            if (!ctd_kind_has_fg_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSTextView *inner = ctd_text_view(object);
            if (inner) { value = (double)ctd_color_of_ns([inner textColor]); break; }
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            value = (double)ctd_color_of_ns([(NSTextField *)object textColor]);
            break;
        }
        case CTD_P_FOCUSABLE: {
            if (!ctd_kind_is_drawn(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = [(CortadoView *)object ctdFocusable] ? 1 : 0;
            break;
        }
        case CTD_P_A11Y_ROLE: {
            if (!ctd_kind_is_drawn(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = [(CortadoView *)object ctdRole];
            break;
        }
        case CTD_P_COLOR: {
            if (!ctd_kind_has_color(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSColor *shown = [[(NSColorWell *)object color]
                colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            if (!shown) return CTD_ERR_UNSUPPORTED;
            value = ctd_color_pack(ctd_color_byte([shown redComponent]),
                                   ctd_color_byte([shown greenComponent]),
                                   ctd_color_byte([shown blueComponent]),
                                   ctd_color_byte([shown alphaComponent]));
            break;
        }
        case CTD_P_CHECKED: {
            if (!ctd_kind_has_checked(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            // NSSwitch and NSButton both answer -state, and neither inherits
            // it: NSControl's own -state has been deprecated since 10.10.
            NSControlStateValue state = [object isKindOfClass:[NSSwitch class]]
                                      ? [(NSSwitch *)object state]
                                      : [(NSButton *)object state];
            value = state == NSControlStateValueMixed ? 2
                  : state == NSControlStateValueOn    ? 1 : 0;
            break;
        }
        case CTD_P_EDITABLE: {
            if (!ctd_kind_has_editable(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSTextView *inner = ctd_text_view(object);
            if (inner) { value = [inner isEditable] ? 1 : 0; break; }
            if (![object isKindOfClass:[NSTextField class]]) return CTD_ERR_KIND;
            value = [(NSTextField *)object isEditable] ? 1 : 0;
            break;
        }
        case CTD_P_SELECTED:
            if ([object isKindOfClass:[NSTabView class]]) {
                NSTabView *tabs = (NSTabView *)object;
                NSTabViewItem *shown = [tabs selectedTabViewItem];
                value = shown ? (int64_t)[tabs indexOfTabViewItem:shown] : -1;
                break;
            }
            if ([object isKindOfClass:[NSSegmentedControl class]]) {
                value = (int64_t)[(NSSegmentedControl *)object selectedSegment];
                break;
            }
            if (![object isKindOfClass:[NSPopUpButton class]]) return CTD_ERR_KIND;
            value = (int64_t)[(NSPopUpButton *)object indexOfSelectedItem];
            break;
        case CTD_P_ANIMATING:
            if (!ctd_kind_has_animating(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = g_spinning[(uint32_t)(widget & 0xffffffffu)] ? 1 : 0;
            break;
        case CTD_P_INDETERMINATE:
            if (ctd_slot_kind(widget) == CTD_W_SPINNER) return CTD_ERR_KIND;
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
// The AppKit controls that carry a number in a range.
//
// Four classes, no common ancestor below NSControl, and the same three
// accessors on each — so a protocol is how Objective-C says "any of these
// four" without casting one class to another and hoping. The membership test
// stays an explicit class check rather than -respondsToSelector:, because
// every NSControl answers -doubleValue, an NSImageView included, and "it
// compiles" is not "it means anything".
@protocol CortadoRanged
- (void)setMinValue:(double)value;
- (double)minValue;
- (void)setMaxValue:(double)value;
- (double)maxValue;
- (void)setDoubleValue:(double)value;
- (double)doubleValue;
@end

// The kind decides, and the class only picks which object to send it to. A
// spinner is an NSProgressIndicator — the same class as a progress bar — so
// asking the object would let a spinner take a range on this platform and
// nowhere else. See ctd_kind_has_range in ../cortado_rules.h.
static id<CortadoRanged> ctd_ranged(ctd_handle widget, id object) {
    if (!ctd_kind_has_range(ctd_slot_kind(widget))) return nil;
    if ([object isKindOfClass:[NSSlider class]] ||
        [object isKindOfClass:[NSProgressIndicator class]] ||
        [object isKindOfClass:[NSStepper class]] ||
        [object isKindOfClass:[NSLevelIndicator class]]) {
        return (id<CortadoRanged>)object;
    }
    return nil;
}

ctd_status ctd_set_real(ctd_handle widget, int32_t key, double value) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    ctd_forget_size(widget);
    switch (key) {
        case CTD_P_OPACITY:
            if (value < 0.0 || value > 1.0) return CTD_ERR_RANGE;
            [(NSView *)object setAlphaValue:value];
            return CTD_OK;
        case CTD_P_FONT_SIZE: {
            /* NSControl said yes to a slider and no to a text area. */
            if (!ctd_kind_has_font_size(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSTextView *inner = ctd_text_view(object);
            if (inner) {
                [(CortadoTextView *)inner ctdSetFontSize:value];
                return CTD_OK;
            }
            if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
            [(NSControl *)object setFont:[NSFont systemFontOfSize:value]];
            return CTD_OK;
        }
        case CTD_P_CORNER_RADIUS:
            if (value < 0.0) return CTD_ERR_RANGE;
            [ctd_layer_of((NSView *)object) setCornerRadius:value];
            return CTD_OK;
        case CTD_P_BORDER_WIDTH:
            if (value < 0.0) return CTD_ERR_RANGE;
            [ctd_layer_of((NSView *)object) setBorderWidth:value];
            return CTD_OK;
        case CTD_P_MIN: {
            id<CortadoRanged> ranged = ctd_ranged(widget, object);
            if (!ranged) return CTD_ERR_KIND;
            [ranged setMinValue:value];
            return CTD_OK;
        }
        case CTD_P_MAX: {
            id<CortadoRanged> ranged = ctd_ranged(widget, object);
            if (!ranged) return CTD_ERR_KIND;
            [ranged setMaxValue:value];
            return CTD_OK;
        }
        case CTD_P_VALUE: {
            id<CortadoRanged> ranged = ctd_ranged(widget, object);
            if (!ranged) return CTD_ERR_KIND;
            [ranged setDoubleValue:value];
            return CTD_OK;
        }
        case CTD_P_DIVIDER: {
            if (!ctd_kind_has_divider(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSSplitView *split = (NSSplitView *)object;
            if ([[split subviews] count] < 2) return CTD_ERR_RANGE;
            NSRect own = [split bounds];
            double along = [split isVertical] ? own.size.width : own.size.height;
            if (value < 0.0 || value > along) return CTD_ERR_RANGE;
            // Marked, because AppKit tells the delegate a divider moved
            // whether a person dragged it or the program wrote it — and this
            // is the only control on this host that does. Writing a
            // checkbox, a slider or a tab raises nothing; without this line,
            // writing a divider raises a value change, and a program that
            // keeps what it hears would store the number it just set and
            // call that news. See CortadoSplit in pane.m.
            g_writing = g_writing + 1;
            [split setPosition:value ofDividerAtIndex:0];
            g_writing = g_writing - 1;
            return CTD_OK;
        }
        case CTD_P_DATE: {
            if (!ctd_kind_has_date(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            [(NSDatePicker *)object
                setDateValue:[NSDate dateWithTimeIntervalSince1970:ctd_date_floor(value)]];
            return CTD_OK;
        }
        case CTD_P_STEP: {
            if ([object isKindOfClass:[NSStepper class]]) {
                // A stepper with no increment is two arrows that do nothing,
                // which is a bug in the caller rather than a thing to honour.
                if (value <= 0.0) return CTD_ERR_RANGE;
                [(NSStepper *)object setIncrement:value];
                return CTD_OK;
            }
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
        case CTD_P_FONT_SIZE: {
            if (!ctd_kind_has_font_size(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            NSTextView *inner = ctd_text_view(object);
            if (inner) { value = (double)[[inner font] pointSize]; break; }
            if (![object isKindOfClass:[NSControl class]]) return CTD_ERR_KIND;
            value = (double)[[(NSControl *)object font] pointSize];
            break;
        }
        case CTD_P_CORNER_RADIUS: {
            /* These two arrived as a copy of their own setters, so asking for
             * the corner radius set it to zero. */
            CALayer *layer = ctd_layer_if_any((NSView *)object);
            value = layer ? (double)[layer cornerRadius] : 0.0;
            break;
        }
        case CTD_P_BORDER_WIDTH: {
            CALayer *layer = ctd_layer_if_any((NSView *)object);
            value = layer ? (double)[layer borderWidth] : 0.0;
            break;
        }
        case CTD_P_MIN: {
            id<CortadoRanged> ranged = ctd_ranged(widget, object);
            if (!ranged) return CTD_ERR_KIND;
            value = [ranged minValue];
            break;
        }
        case CTD_P_MAX: {
            id<CortadoRanged> ranged = ctd_ranged(widget, object);
            if (!ranged) return CTD_ERR_KIND;
            value = [ranged maxValue];
            break;
        }
        case CTD_P_VALUE: {
            id<CortadoRanged> ranged = ctd_ranged(widget, object);
            if (!ranged) return CTD_ERR_KIND;
            value = [ranged doubleValue];
            break;
        }
        case CTD_P_DIVIDER:
            if (!ctd_kind_has_divider(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            value = ctd_split_position((NSSplitView *)object);
            break;
        case CTD_P_DATE:
            if (!ctd_kind_has_date(ctd_slot_kind(widget))) return CTD_ERR_KIND;
            // Floored again on the way out, not trusted from the way in: a
            // user who picks a day through the control writes it themselves,
            // and this is the only place that answer is made to agree with the
            // one a program wrote.
            value = ctd_date_floor([[(NSDatePicker *)object dateValue] timeIntervalSince1970]);
            break;
        case CTD_P_STEP:
            // Only a stepper reads one back. A slider's step is tick marks,
            // and a count of ticks is not the increment that was asked for —
            // answering the wrong number is worse than refusing.
            if (![object isKindOfClass:[NSStepper class]]) return CTD_ERR_KIND;
            value = [(NSStepper *)object increment];
            break;
        default: return CTD_ERR_UNSUPPORTED;
    }
    if (out) *out = value;
    return CTD_OK;
}
