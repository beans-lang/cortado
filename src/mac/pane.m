// The containers a platform draws chrome for.
//
// A disclosure is the first of them, and the reason this file exists rather
// than another case in widget.m: AppKit has no disclosure *container*. It has
// the triangle — an NSButton with NSBezelStyleDisclosure, which AppKit draws,
// AppKit rotates, and AppKit reports to assistive technology as
// AXDisclosureTriangle — and putting one beside a title with a body under it
// is what an application does. This class does that and nothing else; there is
// no cortado-drawn pixel in it.
//
// The arrangement is the group box's: children go into a content view this one
// keeps positioned under the header, so a child's coordinates start at the
// content view's corner and a caller never has to know the header is there.
// `ctd_view_content_inset` is how the layout learns how much room it took.

#import "internal.h"

// The space a platform leaves between one thing and the next.
//
// AppKit's own number rather than one written here: it is the vertical content
// margin of a box, which is the system's idea of "a small space". Asked once,
// because it is the same on every box on this machine and building an NSBox
// inside a layout pass would be a needless allocation on every frame change.
static CGFloat ctd_pane_gap(void) {
    static CGFloat known = 0.0;
    static int asked = 0;
    if (!asked) {
        NSBox *ruler = [[NSBox alloc] initWithFrame:NSZeroRect];
        known = [ruler contentViewMargins].height;
        [ruler release];
        asked = 1;
    }
    return known;
}

@implementation CortadoDisclosure

- (BOOL)isFlipped { return YES; }

// The header's height, from AppKit's own numbers: whichever of the triangle
// and the title wants to be taller, plus the space under it.
//
// Not a constant, because the title's height follows the user's text size and
// the triangle's follows the system's control metrics. A number written here
// would be right on the machine it was written on.
- (CGFloat)headerHeight {
    NSSize glyph = [_triangle fittingSize];
    NSSize words = [_caption fittingSize];
    CGFloat tall = glyph.height > words.height ? glyph.height : words.height;
    return tall + ctd_pane_gap();
}

- (void)relayout {
    NSRect own = [self bounds];
    CGFloat header = [self headerHeight];
    CGFloat gap = ctd_pane_gap();
    NSSize glyph = [_triangle fittingSize];
    [_triangle setFrame:NSMakeRect(0.0, 0.0, glyph.width, header)];
    CGFloat left = glyph.width + gap;
    CGFloat words = own.size.width - left;
    [_caption setFrame:NSMakeRect(left, 0.0, words > 0.0 ? words : 0.0, header)];
    CGFloat body = own.size.height - header;
    [_content setFrame:NSMakeRect(0.0, header, own.size.width, body > 0.0 ? body : 0.0)];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self relayout];
}

@end

// ------------------------------------------------------------------ building

// The triangle's action. It is the control's own click, so the state AppKit
// put it in is the truth; the body follows, and the event goes out as a value
// change because that is what happened.
@interface CortadoTwist : NSObject
@property (assign) ctd_handle handle;
- (void)twisted:(id)sender;
@end

@implementation CortadoTwist
- (void)twisted:(id)sender {
    id object = ctd_resolve(_handle);
    if (![object isKindOfClass:[CortadoDisclosure class]]) return;
    CortadoDisclosure *twisty = (CortadoDisclosure *)object;
    BOOL open = [[twisty triangle] state] == NSControlStateValueOn;
    [[twisty content] setHidden:!open];
    ctd_emit(CTD_EV_VALUE_CHANGED, _handle, open ? 1 : 0, 0);
}
@end

NSView *ctd_disclosure_new(void) {
    CortadoDisclosure *twisty =
        [[CortadoDisclosure alloc] initWithFrame:NSZeroRect];

    NSButton *triangle = [[NSButton alloc] initWithFrame:NSZeroRect];
    [triangle setBezelStyle:NSBezelStyleDisclosure];
    [triangle setButtonType:NSButtonTypePushOnPushOff];
    [triangle setTitle:@""];
    [triangle setState:NSControlStateValueOn];
    [twisty addSubview:triangle];
    [twisty setTriangle:triangle];
    [triangle release];

    NSTextField *caption = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [caption setBezeled:NO];
    [caption setDrawsBackground:NO];
    [caption setEditable:NO];
    [caption setSelectable:NO];
    [caption setStringValue:@""];
    [twisty addSubview:caption];
    [twisty setCaption:caption];
    [caption release];

    CortadoView *content = [[CortadoView alloc] initWithFrame:NSZeroRect];
    ctd_tag(content);
    [twisty addSubview:content];
    [twisty setContent:content];
    [content release];

    return twisty;
}

// Wires the triangle to the handle, once the handle exists. Split from the
// builder above for the reason the table's data source is: a handle is only
// made after the view is, and the forwarder has to carry it.
void ctd_disclosure_attach(ctd_handle handle, NSView *view) {
    if (![view isKindOfClass:[CortadoDisclosure class]]) return;
    CortadoDisclosure *twisty = (CortadoDisclosure *)view;
    CortadoTwist *forwarder = [[CortadoTwist alloc] init];
    [forwarder setHandle:handle];
    [[twisty triangle] setTarget:forwarder];
    [[twisty triangle] setAction:@selector(twisted:)];
    [g_targets addObject:forwarder];
    [forwarder release];
}
