// A tree, filled by asking about one node at a time.
//
// Win32's half of the contract in ../cortado_host.h beside `ctd_outline_fn`,
// and the host where it is least like the others — for one reason worth
// stating plainly at the top:
//
// **A SysTreeView32 has no columns.** The common controls have a tree and a
// list and nothing that is both. Windows applications that show a tree with
// columns either own-draw a list view or buy a control, and cortado will do
// neither, so `ctd_outline_columns` takes 1 here and refuses more by name.
//
// What it does have is everything else: TVS_HASBUTTONS draws the twisty,
// TVN_ITEMEXPANDING is where children are filled in the first time a node is
// opened, and LPSTR_TEXTCALLBACK means no text is ever stored — the control
// asks while it draws, which is the same pull the other three hosts make.

#include "internal.h"

static ctd_outline_fn      g_outline_shape;
static void               *g_outline_shape_context;
static ctd_outline_text_fn g_outline_text;
static void               *g_outline_text_context;

static int64_t ctd_outline_ask(ctd_handle outline, int32_t what, int64_t node,
                               int32_t index) {
    if (!g_outline_shape) return 0;
    return g_outline_shape(g_outline_shape_context, outline, what, node, index);
}

// One cell as a freshly allocated wide string, or NULL. The caller frees it.
static WCHAR *ctd_outline_words(ctd_handle outline, int64_t node, int32_t column) {
    if (!g_outline_text) return NULL;
    char small[256];
    int32_t needed = g_outline_text(g_outline_text_context, outline, node, column,
                                    small, (int32_t)sizeof small);
    if (needed <= 0) return NULL;
    if (needed <= (int32_t)sizeof small) return ctd_wide(small, needed);
    char *big = (char *)malloc((size_t)needed);
    if (!big) return NULL;
    int32_t wrote = g_outline_text(g_outline_text_context, outline, node, column,
                                   big, needed);
    WCHAR *wide = wrote > 0 ? ctd_wide(big, wrote < needed ? wrote : needed) : NULL;
    free(big);
    return wide;
}

// The tree a handle stands for. Unlike a table, this host tracks the control
// itself: a tree view scrolls on its own and there is no wrapper.
static HWND ctd_outline_window(ctd_handle outline, ctd_status *problem) {
    HWND view = ctd_window(outline);
    if (!view) { *problem = CTD_ERR_STALE; return NULL; }
    if (ctd_slot_kind(outline) != CTD_W_OUTLINE_VIEW) {
        *problem = CTD_ERR_KIND;
        return NULL;
    }
    *problem = CTD_OK;
    return view;
}

// The HTREEITEM whose lParam is `node`, or NULL. Walked rather than kept in a
// table, for the reason the other hosts keep one: the control already knows,
// and a second record of the same fact is a second answer that can be wrong.
// Only the items the control is *showing* are walked, which is also exactly
// the set the header says may be expanded or selected.
static HTREEITEM ctd_outline_find(HWND view, HTREEITEM from, int64_t node) {
    HTREEITEM item = from ? (HTREEITEM)SendMessageW(view, TVM_GETNEXTITEM,
                                                    TVGN_CHILD, (LPARAM)from)
                          : (HTREEITEM)SendMessageW(view, TVM_GETNEXTITEM,
                                                    TVGN_ROOT, 0);
    while (item) {
        TVITEMW ask;
        memset(&ask, 0, sizeof ask);
        ask.mask = TVIF_PARAM | TVIF_HANDLE;
        ask.hItem = item;
        if (SendMessageW(view, TVM_GETITEMW, 0, (LPARAM)&ask) &&
            (int64_t)(intptr_t)ask.lParam == node) {
            return item;
        }
        HTREEITEM found = ctd_outline_find(view, item, node);
        if (found) return found;
        item = (HTREEITEM)SendMessageW(view, TVM_GETNEXTITEM, TVGN_NEXT,
                                       (LPARAM)item);
    }
    return NULL;
}

static int64_t ctd_outline_node_of(HWND view, HTREEITEM item) {
    if (!item) return CTD_OUTLINE_ROOT;
    TVITEMW ask;
    memset(&ask, 0, sizeof ask);
    ask.mask = TVIF_PARAM | TVIF_HANDLE;
    ask.hItem = item;
    if (!SendMessageW(view, TVM_GETITEMW, 0, (LPARAM)&ask)) return CTD_OUTLINE_ROOT;
    return (int64_t)(intptr_t)ask.lParam;
}

// Inserts the children of `node` under `parent`. The text is a callback and
// the child count is a callback, so nothing is stored and nothing is read
// that the control is not about to draw.
static void ctd_outline_fill(HWND view, ctd_handle outline, HTREEITEM parent,
                             int64_t node) {
    int64_t count = ctd_outline_ask(outline, CTD_OUTLINE_CHILDREN, node, 0);
    for (int32_t at = 0; at < (int32_t)count; at++) {
        int64_t child = ctd_outline_ask(outline, CTD_OUTLINE_CHILD, node, at);
        TVINSERTSTRUCTW insert;
        memset(&insert, 0, sizeof insert);
        insert.hParent = parent ? parent : TVI_ROOT;
        insert.hInsertAfter = TVI_LAST;
        insert.item.mask = TVIF_TEXT | TVIF_PARAM | TVIF_CHILDREN;
        insert.item.pszText = LPSTR_TEXTCALLBACKW;
        insert.item.lParam = (LPARAM)(intptr_t)child;
        // Asked, not inferred from the child count: a folder nobody has read
        // yet has no children to report and must still draw a twisty.
        insert.item.cChildren =
            ctd_outline_ask(outline, CTD_OUTLINE_EXPANDS, child, 0) ? 1 : 0;
        SendMessageW(view, TVM_INSERTITEMW, 0, (LPARAM)&insert);
    }
}

// TVN_ITEMEXPANDING: the first time a node opens, its children go in. Called
// from the window procedure, which is where every Win32 notification lands.
void ctd_outline_expanding(NMTREEVIEWW *info) {
    if (!info || info->action != TVE_EXPAND) return;
    HWND view = info->hdr.hwndFrom;
    ctd_handle outline = ctd_handle_of(view);
    if (!outline) return;
    // Already filled: a node with a child item has been here before.
    if (SendMessageW(view, TVM_GETNEXTITEM, TVGN_CHILD,
                     (LPARAM)info->itemNew.hItem)) {
        return;
    }
    ctd_outline_fill(view, outline, info->itemNew.hItem,
                     (int64_t)(intptr_t)info->itemNew.lParam);
}

// TVN_GETDISPINFO: the control is drawing and wants the words.
void ctd_outline_disp_info(NMTVDISPINFOW *info) {
    if (!info || !(info->item.mask & TVIF_TEXT)) return;
    HWND view = info->hdr.hwndFrom;
    ctd_handle outline = ctd_handle_of(view);
    if (!outline || !info->item.pszText || info->item.cchTextMax <= 0) return;
    WCHAR *words = ctd_outline_words(outline, (int64_t)(intptr_t)info->item.lParam, 0);
    if (!words) {
        info->item.pszText[0] = L'\0';
        return;
    }
    lstrcpynW(info->item.pszText, words, info->item.cchTextMax);
    free(words);
}

// TVN_SELCHANGED: a selection moved.
void ctd_outline_sel_changed(NMTREEVIEWW *info) {
    if (!info) return;
    // Not when the program did it — see g_writing in internal.h.
    if (g_writing) return;
    ctd_handle outline = ctd_handle_of(info->hdr.hwndFrom);
    if (!outline) return;
    ctd_emit(CTD_EV_SELECTION, outline,
             (int64_t)(intptr_t)info->itemNew.lParam, 0);
}

// ---------------------------------------------------------------- entry points

ctd_status ctd_set_outline_source(ctd_outline_fn shape, void *shape_context,
                                  ctd_outline_text_fn text, void *text_context) {
    g_outline_shape = shape;
    g_outline_shape_context = shape_context;
    g_outline_text = text;
    g_outline_text_context = text_context;
    return CTD_OK;
}

ctd_status ctd_outline_columns(ctd_handle outline, int32_t count) {
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    if (count < 1) return CTD_ERR_RANGE;
    // See the note at the top of this file: the common controls have a tree
    // and a list and nothing that is both.
    if (count > 1) return CTD_ERR_UNSUPPORTED;
    return CTD_OK;
}

ctd_status ctd_outline_column_title(ctd_handle outline, int32_t column,
                                    const char *utf8, int32_t len) {
    (void)utf8; (void)len;
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    if (column != 0) return CTD_ERR_RANGE;
    // A tree view draws no header, so the title is accepted and not shown —
    // rather than refused, because a portable program titles its one column
    // and should not have to know which platform draws the title.
    return CTD_OK;
}

ctd_status ctd_outline_column_width(ctd_handle outline, int32_t column,
                                    double points) {
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    if (column != 0) return CTD_ERR_RANGE;
    if (points <= 0.0) return CTD_ERR_RANGE;
    // The one column is the control, so its width is the control's width,
    // which the layout above already set.
    return CTD_OK;
}

ctd_status ctd_outline_reload(ctd_handle outline) {
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    // What was open is remembered before the tree is thrown away, and put
    // back after — because TVM_DELETEITEM on TVI_ROOT is the only way to
    // re-read the top level, and a refresh that closed the tree would be
    // useless in the one place a refresh is used.
    int64_t open[256];
    int32_t opened = 0;
    HTREEITEM walk = (HTREEITEM)SendMessageW(view, TVM_GETNEXTITEM, TVGN_ROOT, 0);
    while (walk && opened < 256) {
        TVITEMW ask;
        memset(&ask, 0, sizeof ask);
        ask.mask = TVIF_PARAM | TVIF_STATE | TVIF_HANDLE;
        ask.stateMask = TVIS_EXPANDED;
        ask.hItem = walk;
        if (SendMessageW(view, TVM_GETITEMW, 0, (LPARAM)&ask) &&
            (ask.state & TVIS_EXPANDED)) {
            open[opened++] = (int64_t)(intptr_t)ask.lParam;
        }
        walk = (HTREEITEM)SendMessageW(view, TVM_GETNEXTITEM, TVGN_NEXTVISIBLE,
                                       (LPARAM)walk);
    }

    g_writing++;
    SendMessageW(view, TVM_DELETEITEM, 0, (LPARAM)TVI_ROOT);
    ctd_outline_fill(view, outline, NULL, CTD_OUTLINE_ROOT);
    for (int32_t at = 0; at < opened; at++) {
        HTREEITEM item = ctd_outline_find(view, NULL, open[at]);
        if (item) SendMessageW(view, TVM_EXPAND, TVE_EXPAND, (LPARAM)item);
    }
    g_writing--;
    return CTD_OK;
}

ctd_status ctd_outline_expand(ctd_handle outline, int64_t node, int32_t on) {
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    if (node == CTD_OUTLINE_ROOT) return on ? CTD_OK : CTD_ERR_RANGE;
    HTREEITEM item = ctd_outline_find(view, NULL, node);
    if (!item) return CTD_ERR_RANGE;
    g_writing++;
    SendMessageW(view, TVM_EXPAND, on ? TVE_EXPAND : TVE_COLLAPSE, (LPARAM)item);
    g_writing--;
    return CTD_OK;
}

ctd_status ctd_outline_expanded(ctd_handle outline, int64_t node, int32_t *out) {
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    if (node == CTD_OUTLINE_ROOT) {
        if (out) *out = 1;
        return CTD_OK;
    }
    HTREEITEM item = ctd_outline_find(view, NULL, node);
    if (!item) return CTD_ERR_RANGE;
    if (out) {
        *out = (SendMessageW(view, TVM_GETITEMSTATE, (WPARAM)item,
                             (LPARAM)TVIS_EXPANDED) & TVIS_EXPANDED) ? 1 : 0;
    }
    return CTD_OK;
}

ctd_status ctd_outline_selected(ctd_handle outline, int64_t *out) {
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    HTREEITEM item = (HTREEITEM)SendMessageW(view, TVM_GETNEXTITEM,
                                             TVGN_CARET, 0);
    if (out) *out = ctd_outline_node_of(view, item);
    return CTD_OK;
}

ctd_status ctd_outline_select(ctd_handle outline, int64_t node) {
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    if (node == CTD_OUTLINE_ROOT) {
        g_writing++;
        SendMessageW(view, TVM_SELECTITEM, TVGN_CARET, (LPARAM)NULL);
        g_writing--;
        return CTD_OK;
    }
    HTREEITEM item = ctd_outline_find(view, NULL, node);
    if (!item) return CTD_ERR_RANGE;
    g_writing++;
    SendMessageW(view, TVM_SELECTITEM, TVGN_CARET, (LPARAM)item);
    g_writing--;
    return CTD_OK;
}

int32_t ctd_outline_cell(ctd_handle outline, int64_t node, int32_t column,
                         char *out, int32_t cap) {
    ctd_status problem;
    HWND view = ctd_outline_window(outline, &problem);
    if (!view) return problem;
    if (column != 0) return CTD_ERR_RANGE;
    // The control's own text, asked for the way it asks: TVM_GETITEM with a
    // buffer runs the same TVN_GETDISPINFO path a draw runs, which is what
    // makes this a round trip and not a second reading of the source.
    HTREEITEM item = ctd_outline_find(view, NULL, node);
    if (!item) return CTD_ERR_RANGE;
    WCHAR words[512];
    words[0] = L'\0';
    TVITEMW ask;
    memset(&ask, 0, sizeof ask);
    ask.mask = TVIF_TEXT | TVIF_HANDLE;
    ask.hItem = item;
    ask.pszText = words;
    ask.cchTextMax = 512;
    SendMessageW(view, TVM_GETITEMW, 0, (LPARAM)&ask);
    return ctd_copy_wide_out(words, out, cap);
}
