// The two things that hang off a window rather than sit inside it.
//
// A toolbar here is a real strip: ToolbarWindow32, a child window pinned to
// the top of the frame, which takes room off the client area. That room is
// subtracted in ctd_surface_content_size rather than made visible to the
// layout, so a program that asks how much room it has never has to know a
// toolbar is there.
//
// A popover is nothing: Windows has no such control. Every application that
// has one makes a layered top-level window, gives it a shadow, and captures
// the mouse to dismiss it — which is cortado drawing a control, and is what
// the capability flags exist to refuse instead.

#include "internal.h"

// One strip per surface, by slot. There are never many surfaces and a table
// keyed by slot is what every other per-surface fact here uses.
static HWND    g_toolbar[CTD_SLOTS];
static int32_t g_toolbar_items[CTD_SLOTS];

void ctd_toolbar_remember(ctd_handle surface, HWND bar, int32_t items) {
    uint32_t slot = ctd_slot(surface);
    if (!slot) return;
    g_toolbar[slot] = bar;
    g_toolbar_items[slot] = items;
}

void ctd_toolbar_drop(ctd_handle surface) {
    uint32_t slot = ctd_slot(surface);
    if (!slot) return;
    if (g_toolbar[slot]) DestroyWindow(g_toolbar[slot]);
    g_toolbar[slot] = NULL;
    g_toolbar_items[slot] = 0;
}

HWND ctd_toolbar_bar(ctd_handle surface) {
    uint32_t slot = ctd_slot(surface);
    return slot ? g_toolbar[slot] : NULL;
}

int32_t ctd_toolbar_items(ctd_handle surface) {
    uint32_t slot = ctd_slot(surface);
    return slot ? g_toolbar_items[slot] : 0;
}

ctd_status ctd_toolbar_set(ctd_handle surface, ctd_handle menu_handle) {
    HWND frame = ctd_window(surface);
    if (!frame || !ctd_slot(menu_handle)) return CTD_ERR_STALE;
    int32_t count = 0;
    if (ctd_menu_item_count(menu_handle, &count) != CTD_OK) return CTD_ERR_KIND;


    ctd_toolbar_drop(surface);
    HWND bar = CreateWindowExW(0, TOOLBARCLASSNAMEW, L"",
                               WS_CHILD | WS_VISIBLE | TBSTYLE_FLAT | TBSTYLE_LIST |
                               CCS_TOP | CCS_NODIVIDER,
                               0, 0, 0, 0, frame, NULL,
                               GetModuleHandleW(NULL), NULL);
    if (!bar) return CTD_ERR_PLATFORM;
    SendMessageW(bar, TB_BUTTONSTRUCTSIZE, sizeof(TBBUTTON), 0);
    SendMessageW(bar, WM_SETFONT, (WPARAM)g_ui_font, TRUE);

    int shown = 0;
    for (int32_t at = 0; at < count; at++) {
        const CtdCommand *command = ctd_menu_command_at(menu_handle, at);
        if (!command) continue;
        WCHAR *words = ctd_wide(command->title ? command->title : "", -1);
        TBBUTTON button;
        memset(&button, 0, sizeof button);
        if (command->separator) {
            button.fsStyle = BTNS_SEP;
            button.iBitmap = 8;
        } else {
            // The token is the command id, so a click arrives as a WM_COMMAND
            // carrying the number the application chose — the same number the
            // menu item carries, because it is the same item.
            // The menu's own command id, so a click arrives as the same
            // WM_COMMAND the menu item sends and reaches the same handler.
            button.idCommand = (int)command->id;
            button.fsStyle = BTNS_AUTOSIZE | BTNS_SHOWTEXT;
            button.fsState = command->enabled ? TBSTATE_ENABLED : 0;
            button.iString = (INT_PTR)words;
            button.iBitmap = I_IMAGENONE;
        }
        SendMessageW(bar, TB_ADDBUTTONSW, 1, (LPARAM)&button);
        free(words);
        shown++;
    }
    SendMessageW(bar, TB_AUTOSIZE, 0, 0);
    ctd_toolbar_remember(surface, bar, shown);
    return CTD_OK;
}

ctd_status ctd_toolbar_clear(ctd_handle surface) {
    if (!ctd_window(surface)) return CTD_ERR_STALE;
    ctd_toolbar_drop(surface);
    return CTD_OK;
}

ctd_status ctd_toolbar_count(ctd_handle surface, int32_t *out) {
    if (!ctd_window(surface)) return CTD_ERR_STALE;
    if (out) *out = ctd_toolbar_items(surface);
    return CTD_OK;
}

// ----------------------------------------------------------------- popovers

ctd_handle ctd_popover_new(ctd_handle content, double width, double height) {
    (void)content; (void)width; (void)height;
    return 0;
}

ctd_status ctd_popover_show(ctd_handle popover, ctd_handle anchor, int32_t edge) {
    (void)popover; (void)anchor; (void)edge;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_popover_close(ctd_handle popover) {
    (void)popover;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_popover_shown(ctd_handle popover, int32_t *out) {
    (void)popover;
    if (out) *out = 0;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_popover_release(ctd_handle popover) {
    (void)popover;
    return CTD_ERR_UNSUPPORTED;
}
