#import "internal.h"
#import <Carbon/Carbon.h>

static NSPasteboard *g_clipboard_override = nil;
void ctd_clipboard_use_pasteboard(NSPasteboard *board) {
    [g_clipboard_override release];
    g_clipboard_override = [board retain];
}
static NSPasteboard *ctd_clipboard(void) {
    return g_clipboard_override ?: [NSPasteboard generalPasteboard];
}

// The canvas is an NSTextInputClient only while Beans focuses an editable
// field. AppKit can ask for its text, selection and candidate location; every
// edit comes back to Beans as an event. This class never changes the value.
static int32_t ctd_byte_offset(NSString *value, NSUInteger utf16) {
    if (utf16 > [value length]) utf16 = [value length];
    NSString *prefix = [value substringToIndex:utf16];
    return (int32_t)[[prefix dataUsingEncoding:NSUTF8StringEncoding] length];
}

static NSUInteger ctd_utf16_offset(NSString *value, int32_t bytes) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes < 0) bytes = 0;
    if ((NSUInteger)bytes > [data length]) bytes = (int32_t)[data length];
    NSString *prefix = [[[NSString alloc] initWithBytes:[data bytes] length:(NSUInteger)bytes
                                                encoding:NSUTF8StringEncoding] autorelease];
    return prefix ? [prefix length] : 0;
}

static void ctd_emit_text(NSView *view, uint32_t kind, NSString *value,
                          int64_t index, int64_t token) {
    if (!g_sink || !ctd_listening(kind)) return;
    ctd_handle handle = ctd_handle_for_view(view);
    if (!handle) return;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = kind;
    event.target = handle;
    event.index = index;
    event.token = token;
    event.text = [data bytes];
    event.text_len = (int32_t)[data length];
    g_sink(g_sink_context, &event);
}

@interface CortadoSemanticsElement : NSAccessibilityElement
@property (nonatomic, assign) CortadoSharedCanvas *canvas;
@property (nonatomic) uint64_t renderID;
@property (nonatomic, retain) NSString *nodeRole;
@property (nonatomic, retain) NSString *nodeLabel;
@property (nonatomic, retain) NSString *nodeValue;
@property (nonatomic) NSRect nodeBounds;
@property (nonatomic) BOOL nodeEnabled;
@property (nonatomic) BOOL nodeFocused;
@end

@implementation CortadoSemanticsElement
@synthesize canvas = _canvas, renderID = _renderID, nodeRole = _nodeRole,
            nodeLabel = _nodeLabel, nodeValue = _nodeValue,
            nodeBounds = _nodeBounds, nodeEnabled = _nodeEnabled, nodeFocused = _nodeFocused;
- (void)dealloc {
    [_nodeRole release]; [_nodeLabel release]; [_nodeValue release];
    [super dealloc];
}
- (NSString *)accessibilityRole {
    if ([_nodeRole isEqualToString:@"button"]) return NSAccessibilityButtonRole;
    if ([_nodeRole isEqualToString:@"textbox"] || [_nodeRole isEqualToString:@"securetext"]) return NSAccessibilityTextFieldRole;
    if ([_nodeRole isEqualToString:@"text"]) return NSAccessibilityStaticTextRole;
    if ([_nodeRole isEqualToString:@"option"]) return NSAccessibilityRowRole;
    if ([_nodeRole isEqualToString:@"combobox"]) return NSAccessibilityComboBoxRole;
    if ([_nodeRole isEqualToString:@"scrollarea"]) return NSAccessibilityScrollAreaRole;
    if ([_nodeRole isEqualToString:@"table"]) return NSAccessibilityTableRole;
    if ([_nodeRole isEqualToString:@"checkbox"]) return NSAccessibilityCheckBoxRole;
    if ([_nodeRole isEqualToString:@"radio"]) return NSAccessibilityRadioButtonRole;
    if ([_nodeRole isEqualToString:@"switch"]) return NSAccessibilityCheckBoxRole;
    if ([_nodeRole isEqualToString:@"slider"]) return NSAccessibilitySliderRole;
    if ([_nodeRole isEqualToString:@"spinbutton"]) return NSAccessibilityIncrementorRole;
    if ([_nodeRole isEqualToString:@"progressbar"] || [_nodeRole isEqualToString:@"meter"]) return NSAccessibilityProgressIndicatorRole;
    if ([_nodeRole isEqualToString:@"separator"]) return NSAccessibilitySplitterRole;
    return NSAccessibilityGroupRole;
}
- (NSString *)accessibilityLabel { return _nodeLabel; }
- (id)accessibilityValue { return [_nodeRole isEqualToString:@"option"] ? @"" : _nodeValue; }
- (BOOL)isAccessibilitySelected { return [_nodeRole isEqualToString:@"option"] && [_nodeValue isEqualToString:@"selected"]; }
- (BOOL)accessibilityEnabled { return _nodeEnabled; }
- (NSRect)accessibilityFrame {
    if (!_canvas || !ctd_handle_for_view(_canvas)) return NSZeroRect;
    NSRect window = [_canvas convertRect:_nodeBounds toView:nil];
    return [[_canvas window] convertRectToScreen:window];
}
- (id)accessibilityParent { return _canvas; }
- (BOOL)ctdCanPress {
    return [_nodeRole isEqualToString:@"button"] ||
           [_nodeRole isEqualToString:@"checkbox"] ||
           [_nodeRole isEqualToString:@"radio"] ||
           [_nodeRole isEqualToString:@"switch"] ||
           [_nodeRole isEqualToString:@"option"] ||
           [_nodeRole isEqualToString:@"combobox"];
}
- (BOOL)ctdCanFocus {
    return [self ctdCanPress] || [_nodeRole isEqualToString:@"textbox"] ||
           [_nodeRole isEqualToString:@"securetext"] ||
           [_nodeRole isEqualToString:@"slider"] ||
           [_nodeRole isEqualToString:@"spinbutton"];
}
- (BOOL)accessibilityPerformPress {
    if (!_canvas || !_nodeEnabled || ![self ctdCanPress] || !g_sink || !ctd_handle_for_view(_canvas)) return NO;
    ctd_event event; memset(&event, 0, sizeof event);
    event.kind = CTD_EV_SEMANTICS_ACTION;
    event.target = ctd_handle_for_view(_canvas);
    event.token = (int64_t)_renderID;
    event.index = 1;
    g_sink(g_sink_context, &event);
    return YES;
}
- (BOOL)accessibilityFocused { return _nodeFocused; }
- (void)setAccessibilityFocused:(BOOL)focused {
    if (!_canvas || !focused || ![self ctdCanFocus] || !g_sink || !ctd_handle_for_view(_canvas)) return;
    ctd_event event; memset(&event, 0, sizeof event);
    event.kind = CTD_EV_SEMANTICS_ACTION;
    event.target = ctd_handle_for_view(_canvas);
    event.token = (int64_t)_renderID;
    event.index = 2;
    g_sink(g_sink_context, &event);
}
@end

@implementation CortadoSharedCanvas {
    NSString *_marked;
    NSRange _markedRange;
    NSTrackingArea *_ctdLeaveTracking;
}
@synthesize ctdTextActive = _ctdTextActive;
@synthesize ctdSecureInput = _ctdSecureInput;
@synthesize ctdEditorText = _ctdEditorText;
@synthesize ctdEditorSelection = _ctdEditorSelection;
@synthesize ctdCaretRect = _ctdCaretRect;
@synthesize ctdSemantics = _ctdSemantics;

- (void)dealloc {
    if (_ctdSecureInput) DisableSecureEventInput();
    if (_ctdLeaveTracking) {
        [self removeTrackingArea:_ctdLeaveTracking];
        [_ctdLeaveTracking release];
    }
    [_marked release];
    [_ctdEditorText release];
    for (CortadoSemanticsElement *node in _ctdSemantics) node.canvas = nil;
    [_ctdSemantics release];
    [super dealloc];
}
- (void)updateTrackingAreas {
    if (_ctdLeaveTracking) {
        [self removeTrackingArea:_ctdLeaveTracking];
        [_ctdLeaveTracking release];
    }
    _ctdLeaveTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow |
                NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_ctdLeaveTracking];
    [super updateTrackingAreas];
}
- (void)mouseExited:(NSEvent *)event {
    (void)event;
    if (!g_sink || !ctd_listening(CTD_EV_POINTER_MOVE)) return;
    ctd_handle handle = ctd_handle_for_view(self);
    if (!handle) return;
    ctd_event out = {0};
    out.kind = CTD_EV_POINTER_MOVE;
    out.target = handle;
    out.index = CTD_BTN_LEFT;
    out.x = -1.0; out.y = -1.0;
    g_sink(g_sink_context, &out);
}
- (void)keyDown:(NSEvent *)event {
    if (_ctdTextActive && !([event modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagControl)))
        [self interpretKeyEvents:@[event]];
    else [super keyDown:event];
}
- (void)ctdDiscardMarked { [_marked release]; _marked = nil; _markedRange = NSMakeRange(NSNotFound, 0); }
- (void)insertText:(id)value replacementRange:(NSRange)range {
    NSString *string = [value isKindOfClass:[NSAttributedString class]] ? [value string] : value;
    if (!string) string = @"";
    int64_t first = -1, last = -1;
    if (range.location != NSNotFound && NSMaxRange(range) <= [_ctdEditorText length]) {
        first = ctd_byte_offset(_ctdEditorText, range.location);
        last = ctd_byte_offset(_ctdEditorText, NSMaxRange(range));
    }
    [self ctdDiscardMarked];
    ctd_emit_text(self, CTD_EV_TEXT_INPUT, string, first, last);
}
- (void)insertText:(id)value { [self insertText:value replacementRange:NSMakeRange(NSNotFound, 0)]; }
- (void)setMarkedText:(id)value selectedRange:(NSRange)selection replacementRange:(NSRange)range {
    NSString *string = [value isKindOfClass:[NSAttributedString class]] ? [value string] : value;
    NSUInteger start = range.location != NSNotFound ? range.location :
                       (_marked ? _markedRange.location : _ctdEditorSelection.location);
    [_marked release]; _marked = [string copy];
    _markedRange = NSMakeRange(start, [string length]);
    NSUInteger local_start = MIN(selection.location, [string length]);
    NSUInteger end = MIN(NSMaxRange(selection), [string length]);
    ctd_emit_text(self, CTD_EV_COMPOSITION_UPDATE, string,
                  ctd_byte_offset(string, local_start), ctd_byte_offset(string, end));
}
- (void)setMarkedText:(id)value selectedRange:(NSRange)selection {
    [self setMarkedText:value selectedRange:selection replacementRange:NSMakeRange(NSNotFound, 0)];
}
- (void)unmarkText {
    if (!_marked) return;
    NSString *text = [[_marked retain] autorelease];
    [self ctdDiscardMarked];
    ctd_emit_text(self, CTD_EV_TEXT_INPUT, text, -1, -1);
}
- (BOOL)hasMarkedText { return _marked != nil; }
- (NSRange)markedRange { return _marked ? _markedRange : NSMakeRange(NSNotFound, 0); }
- (NSRange)selectedRange { return _ctdEditorSelection; }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual {
    NSString *text = _ctdEditorText ?: @"";
    if (range.location == NSNotFound || range.location > [text length]) return nil;
    range.length = MIN(range.length, [text length] - range.location);
    if (actual) *actual = range;
    return [[[NSAttributedString alloc] initWithString:[text substringWithRange:range]] autorelease];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    (void)point;
    return _ctdEditorSelection.location;
}
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual {
    if (actual) *actual = range;
    NSRect inWindow = [self convertRect:_ctdCaretRect toView:nil];
    return [[self window] convertRectToScreen:inWindow];
}
// AppKit names an extending command separately: shift+left arrives as
// moveLeftAndModifySelection:, never as moveLeft: with a shift flag.
static int32_t ctd_key_of_command(SEL selector, uint32_t *extend) {
    *extend = 0;
    if (selector == @selector(deleteBackward:)) return CTD_KEY_BACKSPACE;
    if (selector == @selector(deleteForward:))  return CTD_KEY_DELETE;
    if (selector == @selector(insertNewline:))  return CTD_KEY_RETURN;
    if (selector == @selector(insertTab:))      return CTD_KEY_TAB;
    if (selector == @selector(moveLeft:))       return CTD_KEY_LEFT;
    if (selector == @selector(moveRight:))      return CTD_KEY_RIGHT;
    if (selector == @selector(moveUp:))         return CTD_KEY_UP;
    if (selector == @selector(moveDown:))       return CTD_KEY_DOWN;
    if (selector == @selector(moveToBeginningOfLine:) ||
        selector == @selector(moveToLeftEndOfLine:) ||
        selector == @selector(moveToBeginningOfParagraph:) ||
        selector == @selector(moveToBeginningOfDocument:)) return CTD_KEY_HOME;
    if (selector == @selector(moveToEndOfLine:) ||
        selector == @selector(moveToRightEndOfLine:) ||
        selector == @selector(moveToEndOfParagraph:) ||
        selector == @selector(moveToEndOfDocument:)) return CTD_KEY_END;
    // A word step is option+arrow, and AppKit drops the option on the way, so
    // it is put back: the toolkit reads the chord, not the command's name.
    *extend = CTD_MOD_ALT;
    if (selector == @selector(moveWordLeft:) ||
        selector == @selector(moveWordBackward:)) return CTD_KEY_LEFT;
    if (selector == @selector(moveWordRight:) ||
        selector == @selector(moveWordForward:)) return CTD_KEY_RIGHT;
    if (selector == @selector(deleteWordBackward:)) return CTD_KEY_BACKSPACE;
    if (selector == @selector(deleteWordForward:)) return CTD_KEY_DELETE;
    *extend = CTD_MOD_ALT | CTD_MOD_SHIFT;
    if (selector == @selector(moveWordLeftAndModifySelection:) ||
        selector == @selector(moveWordBackwardAndModifySelection:)) return CTD_KEY_LEFT;
    if (selector == @selector(moveWordRightAndModifySelection:) ||
        selector == @selector(moveWordForwardAndModifySelection:)) return CTD_KEY_RIGHT;
    *extend = CTD_MOD_SHIFT;
    if (selector == @selector(moveLeftAndModifySelection:))  return CTD_KEY_LEFT;
    if (selector == @selector(moveRightAndModifySelection:)) return CTD_KEY_RIGHT;
    if (selector == @selector(moveUpAndModifySelection:))    return CTD_KEY_UP;
    if (selector == @selector(moveDownAndModifySelection:))  return CTD_KEY_DOWN;
    if (selector == @selector(moveToBeginningOfLineAndModifySelection:) ||
        selector == @selector(moveToLeftEndOfLineAndModifySelection:) ||
        selector == @selector(moveToBeginningOfParagraphAndModifySelection:) ||
        selector == @selector(moveToBeginningOfDocumentAndModifySelection:)) return CTD_KEY_HOME;
    if (selector == @selector(moveToEndOfLineAndModifySelection:) ||
        selector == @selector(moveToRightEndOfLineAndModifySelection:) ||
        selector == @selector(moveToEndOfParagraphAndModifySelection:) ||
        selector == @selector(moveToEndOfDocumentAndModifySelection:)) return CTD_KEY_END;
    *extend = 0;
    return CTD_KEY_UNKNOWN;
}

- (void)doCommandBySelector:(SEL)selector {
    if (selector == @selector(cancelOperation:)) {
        [self ctdDiscardMarked];
        ctd_emit_text(self, CTD_EV_COMPOSITION_CANCEL, @"", 0, 0);
        return;
    }
    uint32_t extend = 0;
    int32_t key = ctd_key_of_command(selector, &extend);
    if (key == CTD_KEY_UNKNOWN || !g_sink || !ctd_listening(CTD_EV_KEY_DOWN)) return;
    ctd_event event; memset(&event, 0, sizeof event);
    event.kind = CTD_EV_KEY_DOWN;
    event.target = ctd_handle_for_view(self);
    event.index = key;
    NSEvent *native = [NSApp currentEvent];
    if (native) event.modifiers = ctd_modifiers_of([native modifierFlags]);
    event.modifiers |= extend;
    g_sink(g_sink_context, &event);
}
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren { return _ctdSemantics ?: @[]; }
@end

ctd_status ctd_canvas_text_state(ctd_handle handle, int32_t active,
    const char *utf8, int32_t length, int32_t anchor, int32_t caret,
    double x, double y, double width, double height) {
    id object = ctd_resolve(handle);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[CortadoSharedCanvas class]]) return CTD_ERR_KIND;
    if (length < 0 || (length && !utf8) || anchor < 0 || caret < 0 ||
        anchor > length || caret > length) return CTD_ERR_RANGE;
    NSString *text = [[NSString alloc] initWithBytes:utf8 length:(NSUInteger)length
                                           encoding:NSUTF8StringEncoding];
    if (!text) return CTD_ERR_RANGE;
    CortadoSharedCanvas *canvas = object;
    if (active == 2 && !canvas.ctdSecureInput) {
        if (EnableSecureEventInput() != noErr) { [text release]; return CTD_ERR_PLATFORM; }
        canvas.ctdSecureInput = YES;
    } else if (active != 2 && canvas.ctdSecureInput) {
        DisableSecureEventInput();
        canvas.ctdSecureInput = NO;
    }
    canvas.ctdTextActive = active != 0;
    canvas.ctdEditorText = text;
    NSUInteger a = ctd_utf16_offset(text, anchor);
    NSUInteger b = ctd_utf16_offset(text, caret);
    canvas.ctdEditorSelection = NSMakeRange(MIN(a, b), MAX(a, b) - MIN(a, b));
    canvas.ctdCaretRect = NSMakeRect(x, y, width, height);
    [[canvas inputContext] invalidateCharacterCoordinates];
    if (!active) [canvas ctdDiscardMarked];
    [text release];
    return CTD_OK;
}

ctd_status ctd_clipboard_write(const char *utf8, int32_t length) {
    if (length < 0 || (length && !utf8)) return CTD_ERR_RANGE;
    NSString *text = [[NSString alloc] initWithBytes:utf8 length:(NSUInteger)length
                                           encoding:NSUTF8StringEncoding];
    if (!text) return CTD_ERR_RANGE;
    NSPasteboard *board = ctd_clipboard();
    [board clearContents];
    BOOL accepted = [board setString:text forType:NSPasteboardTypeString];
    [text release];
    return accepted ? CTD_OK : CTD_ERR_PLATFORM;
}

int32_t ctd_reduce_motion(void) {
    return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion] ? 1 : 0;
}

int32_t ctd_clipboard_read(char *out, int32_t cap) {
    if (cap < 0) return CTD_ERR_RANGE;
    NSString *text = [ctd_clipboard() stringForType:NSPasteboardTypeString];
    NSData *data = [(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    int32_t count = (int32_t)[data length];
    if (out && cap < count) return CTD_ERR_RANGE;
    if (out && count) memcpy(out, [data bytes], (size_t)count);
    return count;
}

ctd_status ctd_canvas_semantics_clear(ctd_handle handle) {
    id object = ctd_resolve(handle);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[CortadoSharedCanvas class]]) return CTD_ERR_KIND;
    CortadoSharedCanvas *canvas = object;
    for (CortadoSemanticsElement *node in canvas.ctdSemantics) node.canvas = nil;
    canvas.ctdSemantics = [NSMutableArray array];
    return CTD_OK;
}

ctd_status ctd_canvas_semantics_add(ctd_handle handle, uint64_t node_id,
    const char *role, int32_t role_len, const char *label, int32_t label_len,
    const char *value, int32_t value_len, double x, double y,
    double width, double height, int32_t enabled, int32_t focused) {
    id object = ctd_resolve(handle);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[CortadoSharedCanvas class]]) return CTD_ERR_KIND;
    if (!node_id || role_len < 0 || label_len < 0 || value_len < 0 ||
        (role_len && !role) || (label_len && !label) || (value_len && !value) ||
        width < 0 || height < 0) return CTD_ERR_RANGE;
    CortadoSharedCanvas *canvas = object;
    if (!canvas.ctdSemantics) canvas.ctdSemantics = [NSMutableArray array];
    CortadoSemanticsElement *node = [[CortadoSemanticsElement alloc] init];
    node.canvas = canvas; node.renderID = node_id;
    node.nodeRole = [[[NSString alloc] initWithBytes:role length:role_len encoding:NSUTF8StringEncoding] autorelease];
    node.nodeLabel = [[[NSString alloc] initWithBytes:label length:label_len encoding:NSUTF8StringEncoding] autorelease];
    node.nodeValue = [[[NSString alloc] initWithBytes:value length:value_len encoding:NSUTF8StringEncoding] autorelease];
    node.nodeBounds = NSMakeRect(x, y, width, height);
    node.nodeEnabled = enabled != 0;
    node.nodeFocused = focused != 0;
    [canvas.ctdSemantics addObject:node];
    [node release];
    return CTD_OK;
}

ctd_status ctd_canvas_semantics_end(ctd_handle handle) {
    id object = ctd_resolve(handle);
    if (!object) return CTD_ERR_STALE;
    if (![object isKindOfClass:[CortadoSharedCanvas class]]) return CTD_ERR_KIND;
    NSAccessibilityPostNotification(object, NSAccessibilityLayoutChangedNotification);
    return CTD_OK;
}
