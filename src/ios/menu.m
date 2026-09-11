// Menus, which a phone does not have.
//
// Every entry point here answers CTD_ERR_UNSUPPORTED and
// `ctd_capability(CTD_CAP_MENU_BAR)` answers no, so a program asks before it
// tries rather than discovering a silent no-op.

#import "internal.h"

//
// **A phone has no menu bar, and this is what that looks like.** Every menu
// call answers CTD_ERR_UNSUPPORTED and `ctd_capability(CTD_CAP_MENU_BAR)`
// answers no, so a program asks before it builds one and gets a typed refusal
// if it does not. That is the capability API doing the job it exists for, and
// this host is the first to exercise it.
//
// It is not a stub in the sense of unfinished work. iOS commands live in a
// navigation bar, a toolbar or a context menu, which are different controls
// with different placement rules — modelling them as a menu bar would produce
// something that is neither.

ctd_handle ctd_menu_new(const char *title, int32_t len) {
    (void)title; (void)len;
    return 0;
}

ctd_status ctd_menu_add_item(ctd_handle menu, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token) {
    if (ctd_has_nul(title, title_len) || ctd_has_nul(key, key_len))
        return CTD_ERR_RANGE;
    (void)menu; (void)title; (void)title_len; (void)key; (void)key_len;
    (void)role; (void)token;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_add_separator(ctd_handle menu) {
    (void)menu;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_add_submenu(ctd_handle menu, ctd_handle child) {
    (void)menu; (void)child;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_item_count(ctd_handle menu, int32_t *out) {
    (void)menu; (void)out;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_menu_item_title(ctd_handle menu, int32_t index, char *out, int32_t cap) {
    (void)menu; (void)index; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

int32_t ctd_menu_item_key(ctd_handle menu, int32_t index, char *out, int32_t cap) {
    (void)menu; (void)index; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_set_bar(ctd_handle menu) {
    (void)menu;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_set_enabled(ctd_handle menu, int64_t token, int32_t on) {
    (void)menu; (void)token; (void)on;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_menu_invoke(ctd_handle menu, int64_t token) {
    (void)menu; (void)token;
    return CTD_ERR_UNSUPPORTED;
}
