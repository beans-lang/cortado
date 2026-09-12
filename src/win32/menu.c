// Menus: the command table beside each HMENU, and the roles that place them.
//
// Win32 can be asked for an item's display string but not for the spelling the
// caller used, and the display string carries the accelerator baked into it
// after a tab — so reading one back would answer something nobody wrote. The
// token, title, key and role are kept here instead.

#include "internal.h"

static CtdMenuId *g_menu_ids;
static int32_t    g_menu_id_count;
static int32_t    g_menu_id_capacity;
static UINT       g_next_menu_id = 0x1000;   // above the standard control ids

static CtdMenu *ctd_menu_of(ctd_handle handle) {
    uint32_t slot = ctd_slot(handle);
    if (!slot || g_type[slot] != CTD_T_MENU) return NULL;
    return (CtdMenu *)g_object[slot];
}

static UINT ctd_register_menu_id(ctd_handle menu, int64_t token) {
    if (g_menu_id_count == g_menu_id_capacity) {
        int32_t grown = g_menu_id_capacity ? g_menu_id_capacity * 2 : 32;
        CtdMenuId *bigger = (CtdMenuId *)realloc(g_menu_ids,
                                                 (size_t)grown * sizeof(CtdMenuId));
        if (!bigger) return 0;
        g_menu_ids = bigger;
        g_menu_id_capacity = grown;
    }
    UINT id = g_next_menu_id++;
    g_menu_ids[g_menu_id_count].id = id;
    g_menu_ids[g_menu_id_count].menu = menu;
    g_menu_ids[g_menu_id_count].token = token;
    g_menu_id_count++;
    return id;
}

const CtdMenuId *ctd_menu_id(UINT id) {
    for (int32_t i = 0; i < g_menu_id_count; i++) {
        if (g_menu_ids[i].id == id) return &g_menu_ids[i];
    }
    return NULL;
}

CtdCommand *ctd_command_by_id(UINT id) {
    const CtdMenuId *entry = ctd_menu_id(id);
    if (!entry) return NULL;
    CtdMenu *menu = ctd_menu_of(entry->menu);
    if (!menu) return NULL;
    for (int32_t i = 0; i < menu->count; i++) {
        if (menu->commands[i].id == id) return &menu->commands[i];
    }
    return NULL;
}

// Cut, Copy, Paste, Undo and Select All must reach the control that has focus,
// or the system's own text boxes stop working inside the application. On macOS
// that means a nil target so the responder chain finds the field; Windows has
// no responder chain, and the equivalent is sending the editing message to the
// focused window. Either way the application never hears about it, which is
// the point: it is the platform's command, not the program's.
int ctd_dispatch_editing(int32_t role) {
    HWND focus = GetFocus();
    if (!focus) return 0;
    switch (role) {
        case CTD_CMD_CUT:   SendMessageW(focus, WM_CUT, 0, 0); return 1;
        case CTD_CMD_COPY:  SendMessageW(focus, WM_COPY, 0, 0); return 1;
        case CTD_CMD_PASTE: SendMessageW(focus, WM_PASTE, 0, 0); return 1;
        case CTD_CMD_UNDO:  SendMessageW(focus, WM_UNDO, 0, 0); return 1;
        case CTD_CMD_SELECT_ALL:
            SendMessageW(focus, EM_SETSEL, 0, (LPARAM)-1);
            return 1;
        default: return 0;
    }
}

//
// Windows has no application menu bar — a menu belongs to a window, which is
// what `ctd_capability(CTD_CAP_MENU_BAR)` answering no already says. The rest
// of the menu API builds a real HMENU that a window can carry.
//
// The roles are where the platforms visibly part company, and that is the
// point of having them. Preferences is "Options" here and lives under Tools,
// not under an application menu that does not exist. Quit is "Exit" and has no
// menu accelerator, because Alt+F4 is a window command rather than a menu one.
// Redo is Ctrl+Y, not Ctrl+Shift+Z. A menu described as a tree of titles would
// have got every one of those wrong.

static const char *ctd_role_title(int32_t role, const char *fallback) {
    switch (role) {
        case CTD_CMD_ABOUT:       return "About";
        case CTD_CMD_PREFERENCES: return "Options";
        case CTD_CMD_QUIT:        return "Exit";
        case CTD_CMD_HIDE:        return "Minimize to Taskbar";
        case CTD_CMD_UNDO:        return "Undo";
        case CTD_CMD_REDO:        return "Redo";
        case CTD_CMD_CUT:         return "Cut";
        case CTD_CMD_COPY:        return "Copy";
        case CTD_CMD_PASTE:       return "Paste";
        case CTD_CMD_SELECT_ALL:  return "Select All";
        case CTD_CMD_CLOSE:       return "Close";
        case CTD_CMD_MINIMIZE:    return "Minimize";
        case CTD_CMD_FULLSCREEN:  return "Full Screen";
        default:                  return fallback;
    }
}

// `mod` is Control here, not Command — which is the whole reason a shortcut is
// written portably rather than as a literal key.
static const char *ctd_role_key(int32_t role, const char *fallback) {
    switch (role) {
        case CTD_CMD_UNDO:       return "mod+z";
        case CTD_CMD_REDO:       return "mod+y";
        case CTD_CMD_CUT:        return "mod+x";
        case CTD_CMD_COPY:       return "mod+c";
        case CTD_CMD_PASTE:      return "mod+v";
        case CTD_CMD_SELECT_ALL: return "mod+a";
        case CTD_CMD_CLOSE:      return "mod+w";
        case CTD_CMD_FULLSCREEN: return "F11";
        // About, Options, Exit, Hide and Minimize carry no accelerator on
        // Windows. Inventing one would put a key in the golden that no Windows
        // program has.
        default:                 return fallback;
    }
}

// "mod+shift+z" as Windows shows it in a menu: "Ctrl+Shift+Z", after a tab.
static void ctd_display_key(const char *portable, WCHAR *out, size_t cap) {
    out[0] = 0;
    if (!portable || !*portable) return;
    char shown[64];
    size_t at = 0;
    const char *scan = portable;
    while (*scan && at + 8 < sizeof shown) {
        if (strncmp(scan, "mod+", 4) == 0) {
            memcpy(shown + at, "Ctrl+", 5); at += 5; scan += 4; continue;
        }
        if (strncmp(scan, "shift+", 6) == 0) {
            memcpy(shown + at, "Shift+", 6); at += 6; scan += 6; continue;
        }
        if (strncmp(scan, "alt+", 4) == 0) {
            memcpy(shown + at, "Alt+", 4); at += 4; scan += 4; continue;
        }
        // The key itself, capitalised the way a menu shows it.
        shown[at++] = (char)(scan[0] >= 'a' && scan[0] <= 'z'
                             ? scan[0] - 'a' + 'A' : scan[0]);
        scan++;
    }
    shown[at] = 0;
    MultiByteToWideChar(CP_UTF8, 0, shown, -1, out, (int)cap);
}

// The accelerator table, rebuilt whenever a menu becomes a window's menu bar.
static void ctd_rebuild_accelerators(CtdMenu *menu, HWND window) {
    ACCEL entries[128];
    int count = 0;
    for (int32_t i = 0; i < menu->count && count < 128; i++) {
        CtdCommand *command = &menu->commands[i];
        if (command->separator || !command->key || !*command->key) continue;
        BYTE flags = FVIRTKEY;
        const char *scan = command->key;
        WORD key = 0;
        while (*scan) {
            if (strncmp(scan, "mod+", 4) == 0)   { flags |= FCONTROL; scan += 4; continue; }
            if (strncmp(scan, "shift+", 6) == 0) { flags |= FSHIFT;   scan += 6; continue; }
            if (strncmp(scan, "alt+", 4) == 0)   { flags |= FALT;     scan += 4; continue; }
            if (scan[0] == 'F' && scan[1] >= '1' && scan[1] <= '9') {
                key = (WORD)(VK_F1 + atoi(scan + 1) - 1);
            } else {
                key = (WORD)(scan[0] >= 'a' && scan[0] <= 'z'
                             ? scan[0] - 'a' + 'A' : scan[0]);
            }
            break;
        }
        if (!key) continue;
        entries[count].fVirt = flags;
        entries[count].key = key;
        entries[count].cmd = (WORD)command->id;
        count++;
    }
    if (g_accelerators) DestroyAcceleratorTable(g_accelerators);
    g_accelerators = count > 0 ? CreateAcceleratorTable(entries, count) : NULL;
    g_accel_window = window;
}

static int ctd_menu_grow(CtdMenu *menu) {
    if (menu->count < menu->capacity) return 1;
    int32_t grown = menu->capacity ? menu->capacity * 2 : 8;
    CtdCommand *bigger = (CtdCommand *)realloc(menu->commands,
                                               (size_t)grown * sizeof(CtdCommand));
    if (!bigger) return 0;
    menu->commands = bigger;
    menu->capacity = grown;
    return 1;
}

static char *ctd_dup_utf8(const char *utf8, int32_t len) {
    if (len < 0) len = 0;
    char *copy = (char *)malloc((size_t)len + 1);
    if (!copy) return NULL;
    if (len > 0) memcpy(copy, utf8, (size_t)len);
    copy[len] = 0;
    return copy;
}

ctd_handle ctd_menu_new(const char *title, int32_t len) {
    CtdMenu *menu = (CtdMenu *)calloc(1, sizeof(CtdMenu));
    if (!menu) return 0;
    // A popup, not a bar: a bar can only be a window's, and this becomes one
    // when `ctd_menu_set_bar` is called on it or it is added as a submenu.
    menu->handle = CreatePopupMenu();
    menu->title = ctd_dup_utf8(title, len);
    if (!menu->handle || !menu->title) {
        if (menu->handle) DestroyMenu(menu->handle);
        free(menu->title);
        free(menu);
        return 0;
    }
    ctd_handle handle = ctd_track(menu, CTD_T_MENU, -1);
    if (!handle) {
        DestroyMenu(menu->handle);
        free(menu->title);
        free(menu);
        return 0;
    }
    return handle;
}

ctd_status ctd_menu_add_item(ctd_handle handle, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token) {
    if (ctd_has_nul(title, title_len) || ctd_has_nul(key, key_len))
        return CTD_ERR_RANGE;
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (role < 0 || role > CTD_CMD_FULLSCREEN) return CTD_ERR_RANGE;
    if (!ctd_menu_grow(menu)) return CTD_ERR_PLATFORM;

    char *asked_title = ctd_dup_utf8(title, title_len);
    char *asked_key = ctd_dup_utf8(key, key_len);
    if (!asked_title || !asked_key) {
        free(asked_title); free(asked_key);
        return CTD_ERR_PLATFORM;
    }
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.token = token;
    command.role = role;
    command.enabled = 1;
    command.title = ctd_dup_utf8(ctd_role_title(role, asked_title), -1);
    command.key = ctd_dup_utf8(ctd_role_key(role, asked_key), -1);
    {
        const char *chosen_title = ctd_role_title(role, asked_title);
        const char *chosen_key = ctd_role_key(role, asked_key);
        free(command.title);
        free(command.key);
        command.title = ctd_dup_utf8(chosen_title, (int32_t)strlen(chosen_title));
        command.key = ctd_dup_utf8(chosen_key, (int32_t)strlen(chosen_key));
    }
    free(asked_title);
    free(asked_key);
    if (!command.title || !command.key) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }

    command.id = ctd_register_menu_id(handle, token);
    if (!command.id) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }

    // Windows shows the accelerator inside the item's own string, after a tab.
    // It is display only — the key itself comes from the accelerator table.
    WCHAR shown[128];
    WCHAR accelerator[64];
    ctd_display_key(command.key, accelerator, 64);
    WCHAR *wide_title = ctd_wide(command.title, (int32_t)strlen(command.title));
    if (!wide_title) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }
    if (accelerator[0]) {
        _snwprintf(shown, 128, L"%s\t%s", wide_title, accelerator);
    } else {
        _snwprintf(shown, 128, L"%s", wide_title);
    }
    shown[127] = 0;
    free(wide_title);

    AppendMenuW(menu->handle, MF_STRING, command.id, shown);
    menu->commands[menu->count++] = command;
    return CTD_OK;
}

ctd_status ctd_menu_add_separator(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (!ctd_menu_grow(menu)) return CTD_ERR_PLATFORM;
    AppendMenuW(menu->handle, MF_SEPARATOR, 0, NULL);
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.separator = 1;
    command.role = CTD_CMD_NONE;
    command.title = ctd_dup_utf8("-", 1);
    command.key = ctd_dup_utf8("", 0);
    if (!command.title || !command.key) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }
    menu->commands[menu->count++] = command;
    return CTD_OK;
}

ctd_status ctd_menu_add_submenu(ctd_handle handle, ctd_handle child) {
    CtdMenu *menu = ctd_menu_of(handle);
    CtdMenu *inner = ctd_menu_of(child);
    if (!menu || !inner) return CTD_ERR_STALE;
    if (!ctd_menu_grow(menu)) return CTD_ERR_PLATFORM;
    WCHAR *title = ctd_wide(inner->title, (int32_t)strlen(inner->title));
    if (!title) return CTD_ERR_PLATFORM;
    AppendMenuW(menu->handle, MF_POPUP, (UINT_PTR)inner->handle, title);
    free(title);
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.enabled = 1;
    command.role = CTD_CMD_NONE;
    command.title = ctd_dup_utf8(inner->title, (int32_t)strlen(inner->title));
    command.key = ctd_dup_utf8("", 0);
    if (!command.title || !command.key) {
        free(command.title); free(command.key);
        return CTD_ERR_PLATFORM;
    }
    menu->commands[menu->count++] = command;
    return CTD_OK;
}

ctd_status ctd_menu_item_count(ctd_handle handle, int32_t *out) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = menu->count;
    return CTD_OK;
}

int32_t ctd_menu_item_title(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= menu->count) return CTD_ERR_RANGE;
    return ctd_copy_out(menu->commands[index].title, out, cap);
}

// The two things a toolbar needs off a menu item, and the reason they are
// shared rather than copied: a toolbar here *is* a menu — the same handle, the
// same tokens — so two lists of the same commands would be the duplication
// that design exists to avoid.
const CtdCommand *ctd_menu_command_at(ctd_handle handle, int32_t index) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu || index < 0 || index >= menu->count) return NULL;
    return &menu->commands[index];
}

int32_t ctd_menu_item_key(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= menu->count) return CTD_ERR_RANGE;
    return ctd_copy_out(menu->commands[index].key, out, cap);
}

ctd_status ctd_menu_set_bar(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // There is no application-wide menu bar on Windows to install one into,
    // which `ctd_capability(CTD_CAP_MENU_BAR)` already says. A window menu is
    // the Windows shape, and the accelerators are rebuilt for whichever window
    // gets one so the keys work without a menu ever being opened.
    HWND window = NULL;
    for (uint32_t slot = 1; slot <= g_used; slot++) {
        if (g_type[slot] == CTD_T_SURFACE) { window = (HWND)g_object[slot]; break; }
    }
    if (window) ctd_rebuild_accelerators(menu, window);
    return CTD_ERR_UNSUPPORTED;
}

static CtdCommand *ctd_find_command(CtdMenu *menu, int64_t token) {
    for (int32_t i = 0; i < menu->count; i++) {
        if (!menu->commands[i].separator && menu->commands[i].token == token)
            return &menu->commands[i];
    }
    return NULL;
}

ctd_status ctd_menu_set_enabled(ctd_handle handle, int64_t token, int32_t on) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    command->enabled = on ? 1 : 0;
    EnableMenuItem(menu->handle, command->id,
                   MF_BYCOMMAND | (on ? MF_ENABLED : MF_GRAYED));
    return CTD_OK;
}

ctd_status ctd_menu_invoke(ctd_handle handle, int64_t token) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_slot(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    if (!command->enabled) return CTD_ERR_PLATFORM;
    if (ctd_dispatch_editing(command->role)) return CTD_OK;
    ctd_emit(CTD_EV_COMMAND, 0, 0, token);
    return CTD_OK;
}
