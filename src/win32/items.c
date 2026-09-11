// A control that offers a list of choices.

#include "internal.h"

ctd_status ctd_items_clear(ctd_handle widget) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    SendMessageW(view, CB_RESETCONTENT, 0, 0);
    return CTD_OK;
}

ctd_status ctd_items_add(ctd_handle widget, const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    if (len < 0) return CTD_ERR_RANGE;
    WCHAR *text = ctd_wide(utf8, len);
    if (!text) return CTD_ERR_PLATFORM;
    LRESULT added = SendMessageW(view, CB_ADDSTRING, 0, (LPARAM)text);
    free(text);
    return added == CB_ERR || added == CB_ERRSPACE ? CTD_ERR_PLATFORM : CTD_OK;
}

ctd_status ctd_items_count(ctd_handle widget, int32_t *out) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    LRESULT count = SendMessageW(view, CB_GETCOUNT, 0, 0);
    if (out) *out = count == CB_ERR ? 0 : (int32_t)count;
    return CTD_OK;
}

int32_t ctd_items_at(ctd_handle widget, int32_t index, char *out, int32_t cap) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_COMBO_BOX) return CTD_ERR_KIND;
    LRESULT count = SendMessageW(view, CB_GETCOUNT, 0, 0);
    if (index < 0 || count == CB_ERR || index >= (int32_t)count) return CTD_ERR_RANGE;
    LRESULT length = SendMessageW(view, CB_GETLBTEXTLEN, (WPARAM)index, 0);
    if (length <= 0) return ctd_copy_out("", out, cap);
    WCHAR *item = (WCHAR *)malloc(((size_t)length + 1) * sizeof(WCHAR));
    if (!item) return CTD_ERR_PLATFORM;
    SendMessageW(view, CB_GETLBTEXT, (WPARAM)index, (LPARAM)item);
    int32_t needed = ctd_copy_wide_out(item, out, cap);
    free(item);
    return needed;
}
