// The containers a platform draws chrome for.
//
// The same shape as the macOS host's file of this name, and for the same
// reason: UIKit has no disclosure *container* either. What it has is the
// chevron — `chevron.right` and `chevron.down`, the symbols the Settings app
// and the Files app use for a section that opens — and putting one beside a
// title with a body under it is what an application does. The glyph is drawn
// by UIKit from the system symbol set; there is no cortado-drawn pixel here.
//
// Children go into a content view this one keeps positioned under the header,
// so a child's coordinates start at the content view's corner and a caller
// never has to know the header is there. `ctd_view_content_inset` is how the
// layout learns how much room the header took.

#import "internal.h"

// The space a platform leaves between one thing and the next.
//
// UIKit's own, and asked rather than written: every UIView carries layout
// margins the system sets and the system adjusts, and their top is what UIKit
// means by "a small space". Asked once, because it is the same on every plain
// view and a fresh UIView inside a layout pass would be a needless allocation
// on every frame change.
static CGFloat ctd_pane_gap(void) {
    static CGFloat known = 0.0;
    static int asked = 0;
    if (!asked) {
        UIView *ruler = [[UIView alloc] initWithFrame:CGRectZero];
        known = [ruler directionalLayoutMargins].top;
        [ruler release];
        asked = 1;
    }
    return known;
}

@implementation CortadoDisclosure

// The header is the title's height, and the chevron is sized to match it.
//
// Not the taller of the two, which is what this did first and what iOS
// disagreed with the other hosts about: `chevron.right` and `chevron.down` are
// different shapes with different intrinsic heights, so a header measured from
// whichever was showing grew and shrank as the user twisted it — and a
// disclosure whose header changes height when it opens moves everything below
// it on the page. Measuring the words instead makes the answer the same in
// both states, and `ctd_disclosure_glyph` makes the symbol follow the words
// rather than the other way round.
- (CGFloat)headerHeight {
    return [_caption intrinsicContentSize].height + ctd_pane_gap();
}

- (void)relayout {
    CGRect own = [self bounds];
    CGFloat header = [self headerHeight];
    CGFloat gap = ctd_pane_gap();
    // A square the height of the header, so the glyph sits on the same line as
    // the words whichever way it is pointing.
    [_triangle setFrame:CGRectMake(0.0, 0.0, header, header)];
    CGFloat left = header + gap;
    CGFloat words = own.size.width - left;
    [_caption setFrame:CGRectMake(left, 0.0, words > 0.0 ? words : 0.0, header)];
    CGFloat body = own.size.height - header;
    [_content setFrame:CGRectMake(0.0, header, own.size.width,
                                  body > 0.0 ? body : 0.0)];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self relayout];
}

// Which way the chevron points. UIKit's own symbols, swapped rather than
// rotated, because a rotation is an animation cortado would be choosing and
// the symbol set already has both.
- (void)showState:(BOOL)open {
    // Sized to the title's font by UIKit, so the two chevrons are the same
    // height as each other and as the words beside them.
    UIImageSymbolConfiguration *scale =
        [UIImageSymbolConfiguration configurationWithFont:[_caption font]];
    [_triangle setImage:[UIImage systemImageNamed:open ? @"chevron.down"
                                                       : @"chevron.right"
                                withConfiguration:scale]
               forState:UIControlStateNormal];
    [_content setHidden:!open];
}

- (BOOL)isOpen { return _open; }
- (void)setOpen:(BOOL)open {
    _open = open;
    [self showState:open];
}

@end

// ------------------------------------------------------------------ building

@interface CortadoTwist : NSObject
@property (assign) ctd_handle handle;
- (void)twisted:(id)sender;
@end

@implementation CortadoTwist
- (void)twisted:(id)sender {
    (void)sender;
    id object = ctd_resolve(_handle);
    if (![object isKindOfClass:[CortadoDisclosure class]]) return;
    CortadoDisclosure *twisty = (CortadoDisclosure *)object;
    [twisty setOpen:![twisty isOpen]];
    ctd_emit(CTD_EV_VALUE_CHANGED, _handle, [twisty isOpen] ? 1 : 0, 0);
}
@end

UIView *ctd_disclosure_new(void) {
    CortadoDisclosure *twisty =
        [[CortadoDisclosure alloc] initWithFrame:CGRectZero];

    UIButton *triangle = [UIButton buttonWithType:UIButtonTypeSystem];
    [triangle setFrame:CGRectZero];
    [twisty addSubview:triangle];
    [twisty setTriangle:triangle];

    UILabel *caption = [[UILabel alloc] initWithFrame:CGRectZero];
    [caption setText:@""];
    [twisty addSubview:caption];
    [twisty setCaption:caption];
    [caption release];

    UIView *content = [[UIView alloc] initWithFrame:CGRectZero];
    ctd_tag(content);
    [twisty addSubview:content];
    [twisty setContent:content];
    [content release];

    [twisty setOpen:YES];
    return twisty;
}

void ctd_disclosure_attach(ctd_handle handle, UIView *view) {
    if (![view isKindOfClass:[CortadoDisclosure class]]) return;
    CortadoDisclosure *twisty = (CortadoDisclosure *)view;
    CortadoTwist *forwarder = [[CortadoTwist alloc] init];
    [forwarder setHandle:handle];
    [[twisty triangle] addTarget:forwarder
                          action:@selector(twisted:)
                forControlEvents:UIControlEventTouchUpInside];
    [g_targets addObject:forwarder];
    [forwarder release];
}

void ctd_chrome_of(id object, double *out) {
    out[0] = 0.0; out[1] = 0.0; out[2] = 0.0; out[3] = 0.0;
    // UIKit has no group box, so a disclosure's header is the only chrome on
    // this platform. See ctd_widget_supports for why there is no group box
    // here rather than a drawn imitation of one.
    if ([object isKindOfClass:[CortadoDisclosure class]]) {
        out[1] = (double)[(CortadoDisclosure *)object headerHeight];
    }
}

ctd_status ctd_view_content_inset(ctd_handle widget, double *out_inset) {
    id object = ctd_resolve(widget);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[UIView class]]) return CTD_ERR_KIND;
    double chrome[4];
    ctd_chrome_of(object, chrome);
    if (out_inset) {
        out_inset[0] = chrome[0];
        out_inset[1] = chrome[1];
        out_inset[2] = chrome[2];
        out_inset[3] = chrome[3];
    }
    return CTD_OK;
}

// ------------------------------------------------------------------ tab views
//
// There are none on this platform — see ctd_widget_supports in widget.m — so
// both entry points refuse by kind. Written out rather than left to a default,
// because "this platform has no such control" is an answer a caller can act on
// and a missing symbol is not.
ctd_status ctd_tab_set_label(ctd_handle widget, int32_t index,
                             const char *utf8, int32_t len) {
    (void)index; (void)utf8; (void)len;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

int32_t ctd_tab_label(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    (void)index; (void)out; (void)cap;
    return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
}
