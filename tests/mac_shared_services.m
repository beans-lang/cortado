#import "../src/mac/internal.h"
#include <assert.h>
#include <stdio.h>

static ctd_event last;
static char text_copy[128];
static void receive(void *context, const ctd_event *event) {
    (void)context;
    last = *event;
    int count = event->text_len < 127 ? event->text_len : 127;
    if (event->text && count) memcpy(text_copy, event->text, (size_t)count);
    text_copy[count] = 0;
}

int main(void) {
    @autoreleasepool {
        assert(ctd_init(CTD_ABI_VERSION) == CTD_OK);
        assert(ctd_set_event_sink(receive, NULL) == CTD_OK);
        ctd_listen(CTD_EV_TEXT_INPUT, 1);
        ctd_listen(CTD_EV_COMPOSITION_UPDATE, 1);
        ctd_listen(CTD_EV_SEMANTICS_ACTION, 1);
        ctd_listen(CTD_EV_POINTER_MOVE, 1);
        ctd_listen(CTD_EV_POINTER_DOWN, 1);
        ctd_listen(CTD_EV_POINTER_UP, 1);
        ctd_listen(CTD_EV_KEY_DOWN, 1);
        ctd_handle canvas_id = ctd_widget_new(CTD_W_CANVAS);
        assert(canvas_id);
        ctd_handle surface_id = ctd_surface_new(300, 120);
        assert(surface_id && ctd_surface_set_root(surface_id, canvas_id) == CTD_OK);
        CortadoSharedCanvas *canvas = (CortadoSharedCanvas *)ctd_resolve(canvas_id);
        assert([canvas isKindOfClass:[CortadoSharedCanvas class]]);
        [canvas updateTrackingAreas];
        assert([[canvas trackingAreas] count] > 0);
        NSEvent *exit_event = [NSEvent enterExitEventWithType:NSEventTypeMouseExited
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
            context:nil eventNumber:1 trackingNumber:1 userData:NULL];
        assert(exit_event);
        [canvas mouseExited:exit_event];
        assert(last.kind == CTD_EV_POINTER_MOVE && last.target == canvas_id &&
               last.x == -1.0 && last.y == -1.0);
        NSWindow *window = (NSWindow *)ctd_resolve(surface_id);
        NSEvent *double_down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
            location:NSMakePoint(10, 10) modifierFlags:0 timestamp:1
            windowNumber:[window windowNumber] context:nil eventNumber:2 clickCount:2 pressure:1.0];
        [NSApp sendEvent:double_down];
        assert(last.kind == CTD_EV_POINTER_DOWN && last.target == canvas_id && last.token == 2);
        NSEvent *double_up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
            location:NSMakePoint(10, 10) modifierFlags:0 timestamp:1
            windowNumber:[window windowNumber] context:nil eventNumber:3 clickCount:2 pressure:0.0];
        [NSApp sendEvent:double_up];
        assert(last.kind == CTD_EV_POINTER_UP && last.target == canvas_id && last.token == 2);
        assert(ctd_canvas_text_state(canvas_id, 1, "aé", 3, 1, 3, 10, 20, 1, 16) == CTD_OK);
        assert(NSEqualRanges([canvas selectedRange], NSMakeRange(1, 1)));
        [canvas insertText:@"Ω" replacementRange:NSMakeRange(1, 1)];
        assert(last.kind == CTD_EV_TEXT_INPUT && last.index == 1 && last.token == 3);
        assert(strcmp(text_copy, "Ω") == 0);
        [canvas insertText:@"x" replacementRange:NSMakeRange(NSNotFound, 0)];
        assert(last.kind == CTD_EV_TEXT_INPUT && last.index == -1 && last.token == -1);
        [canvas setMarkedText:@"かな" selectedRange:NSMakeRange(2, 0)
             replacementRange:NSMakeRange(NSNotFound, 0)];
        assert(last.kind == CTD_EV_COMPOSITION_UPDATE && last.index == 6 && last.token == 6);
        assert([canvas hasMarkedText]);
        [canvas unmarkText];
        assert(last.kind == CTD_EV_TEXT_INPUT && ![canvas hasMarkedText]);

        // A keyboard selection reaches the toolkit only as its own command:
        // AppKit sends moveLeftAndModifySelection:, never moveLeft: plus shift.
        [canvas doCommandBySelector:@selector(moveLeft:)];
        assert(last.kind == CTD_EV_KEY_DOWN && last.index == CTD_KEY_LEFT &&
               !(last.modifiers & CTD_MOD_SHIFT));
        [canvas doCommandBySelector:@selector(moveLeftAndModifySelection:)];
        assert(last.kind == CTD_EV_KEY_DOWN && last.index == CTD_KEY_LEFT &&
               (last.modifiers & CTD_MOD_SHIFT));
        [canvas doCommandBySelector:@selector(moveRightAndModifySelection:)];
        assert(last.index == CTD_KEY_RIGHT && (last.modifiers & CTD_MOD_SHIFT));
        [canvas doCommandBySelector:@selector(moveUp:)];
        assert(last.index == CTD_KEY_UP && !(last.modifiers & CTD_MOD_SHIFT));
        [canvas doCommandBySelector:@selector(moveDownAndModifySelection:)];
        assert(last.index == CTD_KEY_DOWN && (last.modifiers & CTD_MOD_SHIFT));
        [canvas doCommandBySelector:@selector(moveToBeginningOfLineAndModifySelection:)];
        assert(last.index == CTD_KEY_HOME && (last.modifiers & CTD_MOD_SHIFT));
        [canvas doCommandBySelector:@selector(moveToEndOfLineAndModifySelection:)];
        assert(last.index == CTD_KEY_END && (last.modifiers & CTD_MOD_SHIFT));
        // AppKit spends the option on naming the command, so the chord the
        // toolkit reads has to be put back on the way out.
        [canvas doCommandBySelector:@selector(moveWordLeft:)];
        assert(last.index == CTD_KEY_LEFT && (last.modifiers & CTD_MOD_ALT) &&
               !(last.modifiers & CTD_MOD_SHIFT));
        [canvas doCommandBySelector:@selector(moveWordRightAndModifySelection:)];
        assert(last.index == CTD_KEY_RIGHT && (last.modifiers & CTD_MOD_ALT) &&
               (last.modifiers & CTD_MOD_SHIFT));
        [canvas doCommandBySelector:@selector(deleteWordBackward:)];
        assert(last.index == CTD_KEY_BACKSPACE && (last.modifiers & CTD_MOD_ALT));
        [canvas doCommandBySelector:@selector(deleteWordForward:)];
        assert(last.index == CTD_KEY_DELETE && (last.modifiers & CTD_MOD_ALT));
        [canvas doCommandBySelector:@selector(deleteBackward:)];
        assert(last.index == CTD_KEY_BACKSPACE && !(last.modifiers & CTD_MOD_ALT));

        NSPasteboard *isolated = [NSPasteboard pasteboardWithUniqueName];
        ctd_clipboard_use_pasteboard(isolated);
        assert(ctd_clipboard_write("café", 5) == CTD_OK);
        char buffer[32] = {0};
        assert(ctd_clipboard_read(NULL, 0) == 5);
        assert(ctd_clipboard_read(buffer, sizeof buffer) == 5);
        assert(memcmp(buffer, "café", 5) == 0);
        ctd_clipboard_use_pasteboard(nil);
        [isolated releaseGlobally];

        assert(ctd_canvas_semantics_clear(canvas_id) == CTD_OK);
        assert(ctd_canvas_semantics_add(canvas_id, 17, "button", 6, "Order", 5,
                                        "", 0, 4, 5, 80, 24, 1, 0) == CTD_OK);
        assert(ctd_canvas_semantics_end(canvas_id) == CTD_OK);
        assert([[canvas accessibilityChildren] count] == 1);
        id node = [[[canvas accessibilityChildren] objectAtIndex:0] retain];
        assert([[node accessibilityRole] isEqualToString:NSAccessibilityButtonRole]);
        assert([[node accessibilityLabel] isEqualToString:@"Order"]);
        assert([node accessibilityPerformPress]);
        assert(last.kind == CTD_EV_SEMANTICS_ACTION && last.index == 1 && last.token == 17);
        assert(ctd_canvas_semantics_add(canvas_id, 18, "option", 6, "Tea", 3,
                                        "selected", 8, 4, 35, 80, 24, 1, 0) == CTD_OK);
        assert(ctd_canvas_semantics_end(canvas_id) == CTD_OK);
        id option = [[canvas accessibilityChildren] objectAtIndex:1];
        assert([[option accessibilityRole] isEqualToString:NSAccessibilityRowRole]);
        assert([(NSAccessibilityElement *)option isAccessibilitySelected]);
        assert([option accessibilityPerformPress]);
        assert(last.kind == CTD_EV_SEMANTICS_ACTION && last.token == 18);
        assert(ctd_canvas_semantics_clear(canvas_id) == CTD_OK);
        assert(![node accessibilityPerformPress]);
        [node release];
        ctd_handle label = ctd_widget_new(CTD_W_LABEL);
        assert(ctd_canvas_text_state(label, 1, "", 0, 0, 0, 0, 0, 1, 1) == CTD_ERR_KIND);
        assert(ctd_canvas_semantics_clear(label) == CTD_ERR_KIND);
        assert(ctd_canvas_text_state(canvas_id, 1, "x", 1, 2, 2, 0, 0, 1, 1) == CTD_ERR_RANGE);
        CortadoSharedCanvas *retained = [canvas retain];
        assert(ctd_canvas_text_state(canvas_id, 2, "", 0, 0, 0, 0, 0, 1, 1) == CTD_OK);
        assert(retained.ctdSecureInput);
        assert(ctd_canvas_text_state(canvas_id, 0, "", 0, 0, 0, 0, 0, 1, 1) == CTD_OK);
        assert(!retained.ctdSecureInput);
        assert(ctd_widget_release(label) == CTD_OK);
        assert(ctd_widget_release(canvas_id) == CTD_OK);
        assert(ctd_surface_close(surface_id) == CTD_OK);
        assert(!retained.ctdSecureInput);
        [retained release];
        assert(ctd_canvas_text_state(canvas_id, 1, "", 0, 0, 0, 0, 0, 1, 1) == CTD_ERR_STALE);
        ctd_shutdown();
        puts("native shared IME, keyboard selection, clipboard, and accessibility: true");
    }
    return 0;
}
