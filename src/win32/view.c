// The view tree: parenting, ordering, frames and measurement.
//
// There is no view tree to walk on Win32 — a child's parent is an HWND
// property and order is Z-order — so the tree is kept here and the platform
// is told about it.

#include "internal.h"

// Where a widget's children go. A scroll view's live in its content window; a
// text area holds text and can hold nothing else.
static HWND ctd_container_of(ctd_handle handle) {
    uint32_t slot = ctd_slot(handle);
    if (!slot) return NULL;
    if (g_type[slot] == CTD_T_SURFACE) return (HWND)g_object[slot];
    if (g_type[slot] != CTD_T_WIDGET) return NULL;
    HWND window = (HWND)g_object[slot];
    if (g_kind[slot] == CTD_W_CONTAINER) return window;
    if (g_kind[slot] == CTD_W_SCROLL_VIEW) {
        for (HWND child = GetWindow(window, GW_CHILD); child;
             child = GetWindow(child, GW_HWNDNEXT)) {
            if (GetPropW(child, CTD_INNER)) return child;
        }
        return NULL;
    }
    return NULL;
}

// cortado's children of a container, in insertion order.
//
// Win32 keeps no list of children — the order is the stacking order, and
// `GetWindow` walks it from the top down. Appending puts a window at the
// bottom, so the walk comes back reversed and is flipped here. Index 0 is the
// bottom of the stack, the child drawn first, which is what `addSubview:` and
// `gtk_fixed_put` also mean by "first".
// Shared rather than static: pane.c needs the same walk to keep a tab
// control's strip in step with its pages, and two walks that could disagree
// about which windows are cortado's would be two answers to one question.
int32_t ctd_own_children(HWND container, HWND *out, int32_t cap) {
    HWND stack[256];
    int32_t found = 0;
    for (HWND child = GetWindow(container, GW_CHILD); child;
         child = GetWindow(child, GW_HWNDNEXT)) {
        if (!ctd_is_ours(child)) continue;
        if (GetPropW(child, CTD_INNER)) continue;
        if (found < (int32_t)(sizeof stack / sizeof stack[0])) stack[found] = child;
        found++;
    }
    int32_t kept = found < (int32_t)(sizeof stack / sizeof stack[0])
                 ? found : (int32_t)(sizeof stack / sizeof stack[0]);
    if (out) {
        for (int32_t i = 0; i < kept && i < cap; i++) out[i] = stack[kept - 1 - i];
    }
    return kept;
}

ctd_status ctd_view_add_child(ctd_handle parent, ctd_handle child, int32_t index) {
    HWND container = ctd_container_of(parent);
    HWND view = ctd_window(child);
    if (!ctd_slot(parent) || !view) return CTD_ERR_STALE;
    if (!container) return CTD_ERR_KIND;

    SetParent(view, container);
    // Appending is sending the new child to the bottom of the stack, because
    // Win32 puts a freshly parented window on top.
    SetWindowPos(view, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

    ctd_tab_sync(parent);
    if (index >= 0) {
        HWND ours[256];
        int32_t count = ctd_own_children(container, ours, 256);
        if (index < count - 1) {
            // In front of the one it should precede: "after" in z-order terms
            // is the window just below it, and index 0 is the bottom.
            HWND below = index == 0 ? HWND_BOTTOM : ours[index - 1];
            SetWindowPos(view, below, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }

    // A radio button joins the group of the radios already under this parent.
    // Windows groups auto-radio buttons by the WS_GROUP style and the tab
    // order: the first radio in a group carries WS_GROUP and the rest do not,
    // and clicking one clears its neighbours. "The same parent is one group"
    // is the rule every host here follows, and this is how Windows spells it.
    if (ctd_slot_kind(child) == CTD_W_RADIO_BUTTON) {
        HWND ours[256];
        int32_t count = ctd_own_children(container, ours, 256);
        int first = 1;
        for (int32_t i = 0; i < count; i++) {
            if (ctd_slot_kind(ctd_handle_of(ours[i])) != CTD_W_RADIO_BUTTON) continue;
            LONG_PTR style = GetWindowLongPtrW(ours[i], GWL_STYLE);
            if (first) style |= WS_GROUP; else style &= ~(LONG_PTR)WS_GROUP;
            SetWindowLongPtrW(ours[i], GWL_STYLE, style);
            first = 0;
        }
    }
    return CTD_OK;
}

ctd_status ctd_view_remove_child(ctd_handle parent, ctd_handle child) {
    HWND container = ctd_container_of(parent);
    HWND view = ctd_window(child);
    if (!ctd_slot(parent) || !view) return CTD_ERR_STALE;
    if (!container) return CTD_ERR_KIND;
    if (GetParent(view) != container) return CTD_ERR_RANGE;
    // Back to the holder, not destroyed: the handle still names it, and a
    // widget that was removed so it could be added somewhere else must survive
    // the trip.
    SetParent(view, g_limbo);
    ctd_tab_sync(parent);
    return CTD_OK;
}

ctd_status ctd_view_move_child(ctd_handle parent, int32_t from, int32_t to) {
    HWND container = ctd_container_of(parent);
    if (!ctd_slot(parent)) return CTD_ERR_STALE;
    if (!container) return CTD_ERR_KIND;
    HWND ours[256];
    int32_t count = ctd_own_children(container, ours, 256);
    if (from < 0 || from >= count || to < 0 || to >= count) return CTD_ERR_RANGE;
    if (from == to) return CTD_OK;

    // Restacking, not remove-and-add. On Windows the hazard the header names
    // is focus rather than lifetime: `SetParent` on the focused control takes
    // focus away mid-edit, and a reorder that did it would silently cancel the
    // user's typing. A z-order change touches neither parent nor focus.
    HWND moving = ours[from];
    HWND below = to == 0 ? HWND_BOTTOM : ours[to > from ? to : to - 1];
    SetWindowPos(moving, below, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    ctd_tab_sync(parent);
    return CTD_OK;
}

ctd_status ctd_view_child_count(ctd_handle parent, int32_t *out) {
    if (!ctd_slot(parent)) return CTD_ERR_STALE;
    HWND container = ctd_container_of(parent);
    // A control that cannot hold children has none, which is an answer and not
    // a refusal: a tree walk asks this of every node.
    if (out) *out = container ? ctd_own_children(container, NULL, 0) : 0;
    return CTD_OK;
}

ctd_handle ctd_view_child_at(ctd_handle parent, int32_t index) {
    HWND container = ctd_container_of(parent);
    if (!container) return 0;
    HWND ours[256];
    int32_t count = ctd_own_children(container, ours, 256);
    if (index < 0 || index >= count) return 0;
    return ctd_handle_of(ours[index]);
}

ctd_handle ctd_view_parent(ctd_handle child) {
    HWND view = ctd_window(child);
    if (!view) return 0;
    HWND parent = GetParent(view);
    while (parent && parent != g_limbo && GetPropW(parent, CTD_INNER)) {
        parent = GetParent(parent);
    }
    if (!parent || parent == g_limbo) return 0;
    return ctd_handle_of(parent);
}


ctd_status ctd_view_set_frame(ctd_handle widget, double x, double y,
                              double width, double height) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int tall = (int)height;
    if (ctd_slot_kind(widget) == CTD_W_COMBO_BOX) tall += CTD_COMBO_DROP;
    SetWindowPos(view, NULL, (int)x, (int)y, (int)width, tall,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    // A scroll view's range used to be worked out right here, from the
    // children's frames. See ctd_view_set_content_size: it is cortado's number.
    return CTD_OK;
}

// The content window is the thing behind the viewport, and the scroll range is
// what is left over once the viewport has taken its page.
ctd_status ctd_view_set_content_size(ctd_handle widget, double width, double height) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    if (!ctd_kind_scrolls(ctd_slot_kind(widget))) return CTD_ERR_KIND;
    HWND content = ctd_container_of(widget);
    if (!content) return CTD_ERR_KIND;
    RECT seen;
    GetClientRect(view, &seen);
    SetWindowPos(content, NULL, 0, 0, (int)width, (int)height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    SCROLLINFO info;
    memset(&info, 0, sizeof info);
    info.cbSize = sizeof info;
    info.fMask = SIF_RANGE | SIF_PAGE;
    info.nMin = 0;
    info.nMax = (int)height;
    info.nPage = (UINT)(seen.bottom - seen.top);
    SetScrollInfo(view, SB_VERT, &info, TRUE);
    info.nMax = (int)width;
    info.nPage = (UINT)(seen.right - seen.left);
    SetScrollInfo(view, SB_HORZ, &info, TRUE);
    return CTD_OK;
}

ctd_status ctd_view_content_size(ctd_handle widget, double *out_size) {
    if (!ctd_window(widget)) return CTD_ERR_STALE;
    if (!ctd_kind_scrolls(ctd_slot_kind(widget))) return CTD_ERR_KIND;
    HWND content = ctd_container_of(widget);
    if (!content) return CTD_ERR_KIND;
    RECT held;
    GetClientRect(content, &held);
    if (out_size) {
        out_size[0] = (double)(held.right - held.left);
        out_size[1] = (double)(held.bottom - held.top);
    }
    return CTD_OK;
}

ctd_status ctd_view_frame(ctd_handle widget, double *out_frame) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    RECT frame;
    GetWindowRect(view, &frame);
    HWND parent = GetParent(view);
    MapWindowPoints(HWND_DESKTOP, parent ? parent : HWND_DESKTOP,
                    (POINT *)&frame, 2);
    double height = (double)(frame.bottom - frame.top);
    if (ctd_slot_kind(widget) == CTD_W_COMBO_BOX) height -= CTD_COMBO_DROP;
    if (out_frame) {
        out_frame[0] = (double)frame.left;
        out_frame[1] = (double)frame.top;
        out_frame[2] = (double)(frame.right - frame.left);
        out_frame[3] = height;
    }
    return CTD_OK;
}

// How wide and tall a string is in a control's own font. Win32 has no
// "measure yourself" message for most classes, so the text is measured and the
// control's own chrome added on top — which is what the classes that *do* have
// one (a button's BCM_GETIDEALSIZE) also do internally.
static void ctd_text_extent(HWND view, int wrap_width, SIZE *out) {
    out->cx = 0;
    out->cy = 0;
    int length = GetWindowTextLengthW(view);
    HDC device = GetDC(view);
    if (!device) return;
    HFONT font = (HFONT)SendMessageW(view, WM_GETFONT, 0, 0);
    if (!font) font = g_ui_font;
    HGDIOBJ previous = SelectObject(device, font);

    TEXTMETRICW metrics;
    GetTextMetricsW(device, &metrics);
    out->cy = metrics.tmHeight;

    if (length > 0) {
        WCHAR *text = (WCHAR *)malloc(((size_t)length + 1) * sizeof(WCHAR));
        if (text) {
            GetWindowTextW(view, text, length + 1);
            RECT box = { 0, 0, wrap_width > 0 ? wrap_width : 0, 0 };
            UINT format = DT_CALCRECT | DT_NOPREFIX |
                          (wrap_width > 0 ? DT_WORDBREAK : DT_SINGLELINE);
            DrawTextW(device, text, length, &box, format);
            out->cx = box.right - box.left;
            out->cy = box.bottom - box.top;
            free(text);
        }
    }
    SelectObject(device, previous);
    ReleaseDC(view, device);
}

ctd_status ctd_view_measure(ctd_handle widget, double avail_width, double avail_height,
                            double *out_size) {
    HWND view = ctd_window(widget);
    if (!view) return CTD_ERR_STALE;
    int wrap = avail_width >= 0.0 ? (int)avail_width : 0;
    SIZE text;
    ctd_text_extent(view, 0, &text);
    double width = (double)text.cx;
    double height = (double)text.cy;

    switch (ctd_slot_kind(widget)) {
        case CTD_W_BUTTON: {
            // The one class that answers for itself, and only with common
            // controls v6 behind it; a v5 button answers zero, so the measured
            // text is the fallback rather than a wrong small number.
            SIZE ideal = { 0, 0 };
            if (SendMessageW(view, BCM_GETIDEALSIZE, 0, (LPARAM)&ideal) &&
                ideal.cx > 0 && ideal.cy > 0) {
                width = (double)ideal.cx;
                height = (double)ideal.cy;
            } else {
                width += 24.0;
                height += 10.0;
            }
            break;
        }
        case CTD_W_LABEL: {
            // One line keeps the unwrapped extent; a larger cap holds the
            // wrapped height to that many of the single line.
            int64_t lines = g_lines[(uint32_t)(widget & 0xffffffffu)];
            if (wrap > 0 && lines != 1) {
                double line = height;
                ctd_text_extent(view, wrap, &text);
                width = (double)text.cx;
                height = (double)text.cy;
                if (lines > 1 && height > line * (double)lines) height = line * (double)lines;
            }
            break;
        }
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON:
            // The box or the dot, plus the gap Windows leaves before the label.
            width += (double)GetSystemMetrics(SM_CXMENUCHECK) + 8.0;
            if (height < 17.0) height = 17.0;
            break;
        case CTD_W_TEXT_FIELD:
        case CTD_W_SECURE_FIELD:
        case CTD_W_SEARCH_FIELD:
            width += 8.0;
            height += 8.0;
            break;
        case CTD_W_TEXT_AREA:
            width = avail_width >= 0.0 ? avail_width : width + 8.0;
            height = height * 3.0 + 8.0;
            break;
        case CTD_W_COMBO_BOX:
            width += (double)GetSystemMetrics(SM_CXVSCROLL) + 16.0;
            height += 9.0;
            break;
        case CTD_W_SLIDER:
            width = avail_width >= 0.0 ? avail_width : 100.0;
            height = 25.0;
            break;
        case CTD_W_PROGRESS_BAR:
            width = avail_width >= 0.0 ? avail_width : 100.0;
            height = 20.0;
            break;
        case CTD_W_SEPARATOR:
            width = avail_width >= 0.0 ? avail_width : 100.0;
            height = 2.0;
            break;
        case CTD_W_CONTAINER:
        case CTD_W_SCROLL_VIEW:
            // A box is as big as it is told to be. Its children were measured
            // by the solver, which is the layer that knows how they are
            // arranged.
            width = 0.0;
            height = 0.0;
            break;
        default: break;
    }

    if (avail_width >= 0.0 && width > avail_width) width = avail_width;
    if (avail_height >= 0.0 && height > avail_height) height = avail_height;
    if (out_size) {
        out_size[0] = width;
        out_size[1] = height;
    }
    return CTD_OK;
}

// The surface a widget is in.
//
// GA_ROOT walks up to the top-level window, which for cortado is the HWND a
// surface was made as. `ctd_handle_of` turns it back into a handle — this host
// already had the reverse lookup, because a Win32 control reports what
// happened by sending a message to its parent and the parent has to be found
// by HWND every time.
ctd_handle ctd_view_surface(ctd_handle widget) {
    HWND window = ctd_window(widget);
    if (!window) return 0;
    return ctd_handle_of(GetAncestor(window, GA_ROOT));
}
