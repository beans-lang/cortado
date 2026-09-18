// Rows and columns, filled by asking rather than by building.
//
// Win32's half of the contract in ../cortado_host.h, and the platform whose
// own name for this is the clearest: a list view with LVS_OWNERDATA holds no
// items at all. It knows how many rows there are and sends the parent an
// LVN_GETDISPINFO for the text of a cell it is about to paint. A million rows
// costs a million nothing.

#include "internal.h"

static ctd_table_fn g_table_source;
static void        *g_table_context;

// One cell, as UTF-16 for the control. The caller owns the returned buffer and
// frees it; ctd_wide is the same arrangement everywhere else in this host.
static WCHAR *ctd_table_wide(ctd_handle table, int32_t row, int32_t column) {
    if (!g_table_source) return NULL;
    char small[256];
    int32_t needed = g_table_source(g_table_context, table, row, column,
                                    small, (int32_t)sizeof small);
    if (needed <= 0) return NULL;
    if (needed <= (int32_t)sizeof small) return ctd_wide(small, needed);
    char *big = (char *)malloc((size_t)needed);
    if (!big) return NULL;
    int32_t wrote = g_table_source(g_table_context, table, row, column, big, needed);
    WCHAR *wide = wrote > 0 ? ctd_wide(big, wrote < needed ? wrote : needed) : NULL;
    free(big);
    return wide;
}

// What the control asks for when it is about to paint a cell. Called from the
// parent's WM_NOTIFY, which is where every Win32 control reports.
void ctd_table_disp_info(NMLVDISPINFOW *info) {
    if (!info || !(info->item.mask & LVIF_TEXT)) return;
    if (!info->item.pszText || info->item.cchTextMax <= 0) return;
    ctd_handle table = ctd_handle_of(info->hdr.hwndFrom);
    if (!table) return;
    info->item.pszText[0] = L'\0';
    WCHAR *text = ctd_table_wide(table, (int32_t)info->item.iItem,
                                 (int32_t)info->item.iSubItem);
    if (!text) return;
    // The control owns the buffer and says how big it is; anything longer is
    // cut here rather than written past the end.
    lstrcpynW(info->item.pszText, text, info->item.cchTextMax);
    free(text);
}

// A selection moved. LVN_ITEMCHANGED fires for every state change, so the
// ones that are not a selection arriving are dropped.
void ctd_table_item_changed(NMLISTVIEW *info) {
    if (!info) return;
    // Not when the program did it — see g_writing in internal.h.
    if (g_writing) return;
    if (!(info->uChanged & LVIF_STATE)) return;
    if (!(info->uNewState & LVIS_SELECTED)) return;
    if (info->uOldState & LVIS_SELECTED) return;
    ctd_handle table = ctd_handle_of(info->hdr.hwndFrom);
    if (!table) return;
    ctd_emit(CTD_EV_SELECTION, table, (int64_t)info->iItem, 0);
}

static HWND ctd_table_window(ctd_handle table, ctd_status *problem) {
    HWND view = ctd_window(table);
    if (!view) { *problem = CTD_ERR_STALE; return NULL; }
    if (ctd_slot_kind(table) != CTD_W_TABLE) { *problem = CTD_ERR_KIND; return NULL; }
    *problem = CTD_OK;
    return view;
}

// -------------------------------------------------------------- entry points

ctd_status ctd_set_table_source(ctd_table_fn source, void *context) {
    g_table_source = source;
    g_table_context = context;
    return CTD_OK;
}

ctd_status ctd_set_table_edit_policy(ctd_table_editable_fn policy, void *context) {
    (void)policy; (void)context;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_table_editing(ctd_handle table, int32_t on) {
    (void)table; (void)on;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_table_edit_as_user(ctd_handle table, int32_t row, int32_t column,
                                  const char *utf8, int32_t len) {
    (void)table; (void)row; (void)column; (void)utf8; (void)len;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_table_columns(ctd_handle table, int32_t count) {
    ctd_status problem;
    HWND view = ctd_table_window(table, &problem);
    if (!view) return problem;
    if (count < 0) return CTD_ERR_RANGE;
    HWND header = (HWND)SendMessageW(view, LVM_GETHEADER, 0, 0);
    int held = header ? (int)SendMessageW(header, HDM_GETITEMCOUNT, 0, 0) : 0;
    for (int i = held - 1; i >= 0; i--) {
        SendMessageW(view, LVM_DELETECOLUMN, (WPARAM)i, 0);
    }
    for (int32_t i = 0; i < count; i++) {
        LVCOLUMNW column;
        memset(&column, 0, sizeof column);
        column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
        column.pszText = L"";
        column.cx = 120;
        column.iSubItem = i;
        if (SendMessageW(view, LVM_INSERTCOLUMN, (WPARAM)i, (LPARAM)&column) < 0) {
            return CTD_ERR_PLATFORM;
        }
    }
    return CTD_OK;
}

ctd_status ctd_table_column_title(ctd_handle table, int32_t column,
                                  const char *utf8, int32_t len) {
    if (ctd_has_nul(utf8, len)) return CTD_ERR_RANGE;
    ctd_status problem;
    HWND view = ctd_table_window(table, &problem);
    if (!view) return problem;
    HWND header = (HWND)SendMessageW(view, LVM_GETHEADER, 0, 0);
    int held = header ? (int)SendMessageW(header, HDM_GETITEMCOUNT, 0, 0) : 0;
    if (column < 0 || column >= held) return CTD_ERR_RANGE;
    WCHAR *text = ctd_wide(utf8, len);
    if (!text) return CTD_ERR_PLATFORM;
    LVCOLUMNW item;
    memset(&item, 0, sizeof item);
    item.mask = LVCF_TEXT;
    item.pszText = text;
    LRESULT done = SendMessageW(view, LVM_SETCOLUMN, (WPARAM)column, (LPARAM)&item);
    free(text);
    return done ? CTD_OK : CTD_ERR_PLATFORM;
}

ctd_status ctd_table_column_width(ctd_handle table, int32_t column, double points) {
    ctd_status problem;
    HWND view = ctd_table_window(table, &problem);
    if (!view) return problem;
    HWND header = (HWND)SendMessageW(view, LVM_GETHEADER, 0, 0);
    int held = header ? (int)SendMessageW(header, HDM_GETITEMCOUNT, 0, 0) : 0;
    if (column < 0 || column >= held) return CTD_ERR_RANGE;
    if (points <= 0.0) return CTD_ERR_RANGE;
    SendMessageW(view, LVM_SETCOLUMNWIDTH, (WPARAM)column, (LPARAM)(int)(points + 0.5));
    return CTD_OK;
}

ctd_status ctd_table_rows(ctd_handle table, int32_t count) {
    ctd_status problem;
    HWND view = ctd_table_window(table, &problem);
    if (!view) return problem;
    if (count < 0) return CTD_ERR_RANGE;
    SendMessageW(view, LVM_SETITEMCOUNT, (WPARAM)count, LVSICF_NOSCROLL);
    return CTD_OK;
}

ctd_status ctd_table_reload(ctd_handle table) {
    ctd_status problem;
    HWND view = ctd_table_window(table, &problem);
    if (!view) return problem;
    // Everything an owner-data list holds is asked for again when it is
    // invalidated; there is nothing else to throw away.
    InvalidateRect(view, NULL, TRUE);
    return CTD_OK;
}

int32_t ctd_table_cell(ctd_handle table, int32_t row, int32_t column,
                       char *out, int32_t cap) {
    ctd_status problem;
    HWND view = ctd_table_window(table, &problem);
    if (!view) return problem;
    int rows = (int)SendMessageW(view, LVM_GETITEMCOUNT, 0, 0);
    if (row < 0 || row >= rows) return CTD_ERR_RANGE;
    HWND header = (HWND)SendMessageW(view, LVM_GETHEADER, 0, 0);
    int held = header ? (int)SendMessageW(header, HDM_GETITEMCOUNT, 0, 0) : 0;
    if (column < 0 || column >= held) return CTD_ERR_RANGE;
    // LVM_GETITEMTEXT on an owner-data list sends LVN_GETDISPINFO, so this
    // goes out through the source and back exactly the way a paint does.
    WCHAR room[512];
    room[0] = L'\0';
    LVITEMW item;
    memset(&item, 0, sizeof item);
    item.mask = LVIF_TEXT;
    item.iItem = row;
    item.iSubItem = column;
    item.pszText = room;
    item.cchTextMax = (int)(sizeof room / sizeof room[0]);
    SendMessageW(view, LVM_GETITEMTEXT, (WPARAM)row, (LPARAM)&item);
    return ctd_copy_wide_out(room, out, cap);
}

ctd_status ctd_table_selected(ctd_handle table, int32_t *out) {
    ctd_status problem;
    HWND view = ctd_table_window(table, &problem);
    if (!view) return problem;
    if (out) {
        *out = (int32_t)SendMessageW(view, LVM_GETNEXTITEM, (WPARAM)-1,
                                     (LPARAM)LVNI_SELECTED);
    }
    return CTD_OK;
}

ctd_status ctd_table_select(ctd_handle table, int32_t row) {
    ctd_status problem;
    HWND view = ctd_table_window(table, &problem);
    if (!view) return problem;
    LVITEMW item;
    memset(&item, 0, sizeof item);
    item.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
    if (row < 0) {
        item.state = 0;
        g_writing++;
        SendMessageW(view, LVM_SETITEMSTATE, (WPARAM)-1, (LPARAM)&item);
        g_writing--;
        return CTD_OK;
    }
    int rows = (int)SendMessageW(view, LVM_GETITEMCOUNT, 0, 0);
    if (row >= rows) return CTD_ERR_RANGE;
    item.state = LVIS_SELECTED | LVIS_FOCUSED;
    g_writing++;
    SendMessageW(view, LVM_SETITEMSTATE, (WPARAM)row, (LPARAM)&item);
    g_writing--;
    return CTD_OK;
}
