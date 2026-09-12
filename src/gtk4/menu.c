// Menus, and the roles that make them portable.

#include "internal.h"

//
// GTK4 removed the menu-bar widget from the application: a menu is a
// GMenuModel shown by a GtkPopoverMenuBar that lives *inside a window*. So
// `CTD_CAP_MENU_BAR` answers no and `CTD_CAP_WINDOW_MENU` answers yes, and the
// menu calls build a real GMenu that a window can show.
//
// Roles are placed by the platform here as everywhere else, but GTK's idea of
// "placed" is thinner than macOS's: there is no responder chain to hand Cut
// and Copy to, so a role that the platform would handle becomes an ordinary
// command reported to the application. That is a real difference and it is why
// `CommandRole.is_platform_handled` exists rather than being assumed.

static const char *ctd_role_title(int32_t role, const char *fallback) {
    switch (role) {
        case CTD_CMD_ABOUT:       return "About";
        case CTD_CMD_PREFERENCES: return "Preferences";
        case CTD_CMD_QUIT:        return "Quit";
        case CTD_CMD_HIDE:        return "Hide";
        case CTD_CMD_UNDO:        return "Undo";
        case CTD_CMD_REDO:        return "Redo";
        case CTD_CMD_CUT:         return "Cut";
        case CTD_CMD_COPY:        return "Copy";
        case CTD_CMD_PASTE:       return "Paste";
        case CTD_CMD_SELECT_ALL:  return "Select All";
        case CTD_CMD_CLOSE:       return "Close";
        case CTD_CMD_MINIMIZE:    return "Minimize";
        case CTD_CMD_FULLSCREEN:  return "Fullscreen";
        default:                  return fallback;
    }
}

// `mod` is Control here, not Command: that is the whole reason a shortcut is
// written portably rather than as a literal key.
static const char *ctd_role_key(int32_t role, const char *fallback) {
    switch (role) {
        case CTD_CMD_PREFERENCES: return "mod+,";
        case CTD_CMD_QUIT:        return "mod+q";
        case CTD_CMD_UNDO:        return "mod+z";
        case CTD_CMD_REDO:        return "mod+shift+z";
        case CTD_CMD_CUT:         return "mod+x";
        case CTD_CMD_COPY:        return "mod+c";
        case CTD_CMD_PASTE:       return "mod+v";
        case CTD_CMD_SELECT_ALL:  return "mod+a";
        case CTD_CMD_CLOSE:       return "mod+w";
        case CTD_CMD_MINIMIZE:    return "mod+m";
        case CTD_CMD_FULLSCREEN:  return "F11";
        default:                  return fallback;
    }
}

// CtdCommand is in internal.h: the toolbar builds its buttons from the same
// list, because a toolbar here is a menu.

typedef struct {
    GMenu  *model;
    GArray *commands;   // CtdCommand
} CtdMenu;

static GHashTable *g_menus;   // ctd_handle -> CtdMenu*


static CtdMenu *ctd_menu_of(ctd_handle handle) {
    if (!g_menus) return NULL;
    return g_hash_table_lookup(g_menus, GINT_TO_POINTER((int)(handle & 0xffffffffu)));
}

// The items a menu holds, for the toolbar to build buttons from. Shared rather
// than copied, because a toolbar *is* a menu here — the same handle, the same
// tokens — and two lists of the same commands is the duplication that design
// exists to avoid.
GArray *ctd_menu_commands(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    return menu ? menu->commands : NULL;
}

ctd_handle ctd_menu_new(const char *title, int32_t len) {
    GMenu *model = g_menu_new();
    ctd_handle handle = ctd_track(model, -1);
    if (!handle) { g_object_unref(model); return 0; }
    if (!g_menus) g_menus = g_hash_table_new(g_direct_hash, g_direct_equal);
    CtdMenu *menu = g_new0(CtdMenu, 1);
    menu->model = model;
    menu->commands = g_array_new(FALSE, TRUE, sizeof(CtdCommand));
    g_hash_table_insert(g_menus, GINT_TO_POINTER((int)(handle & 0xffffffffu)), menu);
    char *name = ctd_dup(title, len);
    g_object_set_data_full(G_OBJECT(model), "cortado-title", name, g_free);
    return handle;
}

ctd_status ctd_menu_add_item(ctd_handle handle, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token) {
    if (ctd_has_nul(title, title_len) || ctd_has_nul(key, key_len))
        return CTD_ERR_RANGE;
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (role < 0 || role > CTD_CMD_FULLSCREEN) return CTD_ERR_RANGE;

    char *asked_title = ctd_dup(title, title_len);
    char *asked_key = ctd_dup(key, key_len);
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.token = token;
    command.title = g_strdup(ctd_role_title(role, asked_title));
    command.key = g_strdup(ctd_role_key(role, asked_key));
    command.enabled = 1;
    g_free(asked_title);
    g_free(asked_key);

    char action[64];
    snprintf(action, sizeof action, "app.cortado%lld", (long long)command.token);
    GMenuItem *item = g_menu_item_new(command.title, action);
    g_menu_append_item(menu->model, item);
    g_object_unref(item);
    g_array_append_val(menu->commands, command);
    return CTD_OK;
}

ctd_status ctd_menu_add_separator(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // GTK spells a separator as a section boundary rather than an item, and
    // the item list here mirrors that with a marker so indices line up with
    // what a caller added.
    GMenu *section = g_menu_new();
    g_menu_append_section(menu->model, NULL, G_MENU_MODEL(section));
    g_object_unref(section);
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.separator = 1;
    command.title = g_strdup("-");
    command.key = g_strdup("");
    g_array_append_val(menu->commands, command);
    return CTD_OK;
}

ctd_status ctd_menu_add_submenu(ctd_handle handle, ctd_handle child) {
    CtdMenu *menu = ctd_menu_of(handle);
    CtdMenu *inner = ctd_menu_of(child);
    if (!menu || !inner) return CTD_ERR_STALE;
    const char *title = g_object_get_data(G_OBJECT(inner->model), "cortado-title");
    g_menu_append_submenu(menu->model, title ? title : "",
                          G_MENU_MODEL(inner->model));
    CtdCommand command;
    memset(&command, 0, sizeof command);
    command.title = g_strdup(title ? title : "");
    command.key = g_strdup("");
    command.enabled = 1;
    g_array_append_val(menu->commands, command);
    return CTD_OK;
}

ctd_status ctd_menu_item_count(ctd_handle handle, int32_t *out) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = (int32_t)menu->commands->len;
    return CTD_OK;
}

int32_t ctd_menu_item_title(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || (guint)index >= menu->commands->len) return CTD_ERR_RANGE;
    return ctd_copy_out(g_array_index(menu->commands, CtdCommand, index).title, out, cap);
}

int32_t ctd_menu_item_key(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || (guint)index >= menu->commands->len) return CTD_ERR_RANGE;
    return ctd_copy_out(g_array_index(menu->commands, CtdCommand, index).key, out, cap);
}

ctd_status ctd_menu_set_bar(ctd_handle handle) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // There is no application-wide menu bar in GTK4 to install one into, which
    // `ctd_capability(CTD_CAP_MENU_BAR)` already says. A window menu is the
    // GTK shape and is reached by putting a GtkPopoverMenuBar in the window.
    return CTD_ERR_UNSUPPORTED;
}

// Finds a command by token, this menu's own only — a submenu is a separate
// handle here, unlike AppKit where one NSMenu owns the tree.
static CtdCommand *ctd_find_command(CtdMenu *menu, int64_t token) {
    for (guint i = 0; i < menu->commands->len; i++) {
        CtdCommand *command = &g_array_index(menu->commands, CtdCommand, i);
        if (!command->separator && command->token == token) return command;
    }
    return NULL;
}

ctd_status ctd_menu_set_enabled(ctd_handle handle, int64_t token, int32_t on) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    command->enabled = on ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_menu_set_icon(ctd_handle handle, int64_t token, int32_t icon) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    if (icon == CTD_ICON_NONE) {
        command->icon = CTD_ICON_NONE;
        return CTD_OK;
    }
    // Refused rather than remembered, so a theme without the icon is an
    // answer at the call and not a blank button later.
    if (!ctd_icon_theme_name(icon)) return CTD_ERR_RANGE;
    command->icon = icon;
    return CTD_OK;
}

ctd_status ctd_menu_invoke(ctd_handle handle, int64_t token) {
    CtdMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CtdCommand *command = ctd_find_command(menu, token);
    if (!command) return CTD_ERR_RANGE;
    if (!command->enabled) return CTD_ERR_PLATFORM;
    ctd_emit(CTD_EV_COMMAND, 0, 0, token);
    return CTD_OK;
}
