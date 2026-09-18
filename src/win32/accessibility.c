#define INITGUID
#include "internal.h"
#include <uiautomation.h>
#include <oleauto.h>
#include <math.h>
#include <stddef.h>

/* A canvas is one HWND, while Beans supplies the children. UIA may retain a
 * COM child after Beans replaces its snapshot, so every child has its own ref
 * count and an invalid bit. No provider writes a control value. */
#define CTD_AX_PROP L"cortado-shared-ax"
typedef struct CtdAxTree CtdAxTree;
typedef struct CtdAxNode CtdAxNode;
struct CtdAxNode {
    IRawElementProviderSimple simple;
    IRawElementProviderFragment fragment;
    IInvokeProvider invoke;
    IToggleProvider toggle;
    ISelectionItemProvider selection;
    LONG refs;
    volatile LONG active;
    CtdAxTree *tree;
    uint64_t id;
    int role;
    int secure, selected;
    WCHAR *label, *value;
    double x, y, width, height;
    int enabled, focused;
};
struct CtdAxTree {
    IRawElementProviderSimple simple;
    IRawElementProviderFragment fragment;
    IRawElementProviderFragmentRoot root;
    LONG refs;
    SRWLOCK lock; /* UIA may call providers away from the Beans UI thread. */
    HWND hwnd;
    ctd_handle canvas;
    CtdAxNode **nodes;
    size_t count, capacity;
};
static CtdAxTree *ctd_ax_tree(HWND hwnd) { return (CtdAxTree *)GetPropW(hwnd, CTD_AX_PROP); }
static CtdAxTree *tree_simple(IRawElementProviderSimple *p) { return CONTAINING_RECORD(p, CtdAxTree, simple); }
static CtdAxTree *tree_fragment(IRawElementProviderFragment *p) { return CONTAINING_RECORD(p, CtdAxTree, fragment); }
static CtdAxTree *tree_root(IRawElementProviderFragmentRoot *p) { return CONTAINING_RECORD(p, CtdAxTree, root); }
static CtdAxNode *node_simple(IRawElementProviderSimple *p) { return CONTAINING_RECORD(p, CtdAxNode, simple); }
static CtdAxNode *node_fragment(IRawElementProviderFragment *p) { return CONTAINING_RECORD(p, CtdAxNode, fragment); }
static CtdAxNode *node_invoke(IInvokeProvider *p) { return CONTAINING_RECORD(p, CtdAxNode, invoke); }
static CtdAxNode *node_toggle(IToggleProvider *p) { return CONTAINING_RECORD(p, CtdAxNode, toggle); }
static CtdAxNode *node_selection(ISelectionItemProvider *p) { return CONTAINING_RECORD(p, CtdAxNode, selection); }
static ULONG tree_addref(CtdAxTree *tree) { return (ULONG)InterlockedIncrement(&tree->refs); }
static ULONG tree_release(CtdAxTree *tree) {
    ULONG left = (ULONG)InterlockedDecrement(&tree->refs);
    if (!left) { free(tree->nodes); free(tree); }
    return left;
}
static ULONG node_addref(CtdAxNode *node) { return (ULONG)InterlockedIncrement(&node->refs); }
static ULONG node_release(CtdAxNode *node) {
    ULONG left = (ULONG)InterlockedDecrement(&node->refs);
    if (!left) {
        CtdAxTree *tree = node->tree;
        free(node->label); free(node->value); free(node);
        tree_release(tree);
    }
    return left;
}
static int node_alive(CtdAxNode *node) {
    CtdAxTree *tree = node->tree;
    AcquireSRWLockShared(&tree->lock);
    int alive = InterlockedCompareExchange(&node->active, 1, 1) && tree->hwnd &&
                ctd_handle_for_window(tree->hwnd) == tree->canvas;
    ReleaseSRWLockShared(&tree->lock);
    return alive;
}
static int node_actionable(CtdAxNode *node) {
    return node->role == UIA_ButtonControlTypeId || node->role == UIA_CheckBoxControlTypeId ||
           node->role == UIA_RadioButtonControlTypeId || node->role == UIA_ListItemControlTypeId ||
           node->role == UIA_ComboBoxControlTypeId;
}
static int node_focusable(CtdAxNode *node) {
    return node_actionable(node) || node->role == UIA_EditControlTypeId ||
           node->role == UIA_SliderControlTypeId || node->role == UIA_SpinnerControlTypeId;
}
static int node_toggleable(CtdAxNode *node) { return node->role == UIA_CheckBoxControlTypeId; }
static int node_selectable(CtdAxNode *node) {
    return node->role == UIA_ListItemControlTypeId || node->role == UIA_RadioButtonControlTypeId;
}
static int node_is_selected(CtdAxNode *node) {
    return node->selected || (node->role == UIA_RadioButtonControlTypeId &&
                              !wcscmp(node->value, L"on"));
}
static HRESULT tree_qi(CtdAxTree *tree, REFIID iid, void **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IRawElementProviderSimple))
        *out = &tree->simple;
    else if (IsEqualIID(iid, &IID_IRawElementProviderFragment)) *out = &tree->fragment;
    else if (IsEqualIID(iid, &IID_IRawElementProviderFragmentRoot)) *out = &tree->root;
    if (!*out) return E_NOINTERFACE;
    tree_addref(tree); return S_OK;
}
static HRESULT node_qi(CtdAxNode *node, REFIID iid, void **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IRawElementProviderSimple))
        *out = &node->simple;
    else if (IsEqualIID(iid, &IID_IRawElementProviderFragment)) *out = &node->fragment;
    else if (IsEqualIID(iid, &IID_IInvokeProvider) && node_actionable(node)) *out = &node->invoke;
    else if (IsEqualIID(iid, &IID_IToggleProvider) && node_toggleable(node)) *out = &node->toggle;
    else if (IsEqualIID(iid, &IID_ISelectionItemProvider) && node_selectable(node)) *out = &node->selection;
    if (!*out) return E_NOINTERFACE;
    node_addref(node); return S_OK;
}
#define TREE_QI(name,type,conv) \
static HRESULT STDMETHODCALLTYPE name(type *p, REFIID iid, void **out) { return tree_qi(conv(p), iid, out); }
#define TREE_REF(name,type,conv) \
static ULONG STDMETHODCALLTYPE name(type *p) { return tree_addref(conv(p)); }
#define TREE_UNREF(name,type,conv) \
static ULONG STDMETHODCALLTYPE name(type *p) { return tree_release(conv(p)); }
#define NODE_QI(name,type,conv) \
static HRESULT STDMETHODCALLTYPE name(type *p, REFIID iid, void **out) { return node_qi(conv(p), iid, out); }
#define NODE_REF(name,type,conv) \
static ULONG STDMETHODCALLTYPE name(type *p) { return node_addref(conv(p)); }
#define NODE_UNREF(name,type,conv) \
static ULONG STDMETHODCALLTYPE name(type *p) { return node_release(conv(p)); }
TREE_QI(ts_qi, IRawElementProviderSimple, tree_simple)
TREE_REF(ts_ref, IRawElementProviderSimple, tree_simple)
TREE_UNREF(ts_unref, IRawElementProviderSimple, tree_simple)
TREE_QI(tf_qi, IRawElementProviderFragment, tree_fragment)
TREE_REF(tf_ref, IRawElementProviderFragment, tree_fragment)
TREE_UNREF(tf_unref, IRawElementProviderFragment, tree_fragment)
TREE_QI(tr_qi, IRawElementProviderFragmentRoot, tree_root)
TREE_REF(tr_ref, IRawElementProviderFragmentRoot, tree_root)
TREE_UNREF(tr_unref, IRawElementProviderFragmentRoot, tree_root)
NODE_QI(ns_qi, IRawElementProviderSimple, node_simple)
NODE_REF(ns_ref, IRawElementProviderSimple, node_simple)
NODE_UNREF(ns_unref, IRawElementProviderSimple, node_simple)
NODE_QI(nf_qi, IRawElementProviderFragment, node_fragment)
NODE_REF(nf_ref, IRawElementProviderFragment, node_fragment)
NODE_UNREF(nf_unref, IRawElementProviderFragment, node_fragment)
NODE_QI(ni_qi, IInvokeProvider, node_invoke)
NODE_REF(ni_ref, IInvokeProvider, node_invoke)
NODE_UNREF(ni_unref, IInvokeProvider, node_invoke)
NODE_QI(nt_qi, IToggleProvider, node_toggle)
NODE_REF(nt_ref, IToggleProvider, node_toggle)
NODE_UNREF(nt_unref, IToggleProvider, node_toggle)
NODE_QI(nsi_qi, ISelectionItemProvider, node_selection)
NODE_REF(nsi_ref, ISelectionItemProvider, node_selection)
NODE_UNREF(nsi_unref, ISelectionItemProvider, node_selection)

static HRESULT STDMETHODCALLTYPE ts_options(IRawElementProviderSimple *p, enum ProviderOptions *out) {
    (void)p; if (!out) return E_POINTER; *out = ProviderOptions_ServerSideProvider; return S_OK;
}
static HRESULT STDMETHODCALLTYPE ts_pattern(IRawElementProviderSimple *p, PATTERNID id, IUnknown **out) {
    (void)p; (void)id; if (!out) return E_POINTER; *out = NULL; return S_OK;
}
static HRESULT STDMETHODCALLTYPE ts_property(IRawElementProviderSimple *p, PROPERTYID id, VARIANT *out) {
    CtdAxTree *tree = tree_simple(p);
    if (!out) return E_POINTER;
    VariantInit(out);
    AcquireSRWLockShared(&tree->lock);
    int alive = tree->hwnd != NULL;
    ReleaseSRWLockShared(&tree->lock);
    if (!alive) return UIA_E_ELEMENTNOTAVAILABLE;
    if (id == UIA_ControlTypePropertyId) { out->vt = VT_I4; out->lVal = UIA_PaneControlTypeId; }
    else if (id == UIA_NamePropertyId) { out->vt = VT_BSTR; out->bstrVal = SysAllocString(L"Cortado canvas"); }
    else if (id == UIA_FrameworkIdPropertyId) { out->vt = VT_BSTR; out->bstrVal = SysAllocString(L"Cortado"); }
    else if (id == UIA_IsControlElementPropertyId || id == UIA_IsContentElementPropertyId) {
        out->vt = VT_BOOL; out->boolVal = VARIANT_TRUE;
    }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE ts_host(IRawElementProviderSimple *p, IRawElementProviderSimple **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxTree *tree = tree_simple(p);
    AcquireSRWLockShared(&tree->lock);
    HWND hwnd = tree->hwnd;
    ReleaseSRWLockShared(&tree->lock);
    if (!hwnd) return UIA_E_ELEMENTNOTAVAILABLE;
    return UiaHostProviderFromHwnd(hwnd, out);
}
static HRESULT STDMETHODCALLTYPE ns_options(IRawElementProviderSimple *p, enum ProviderOptions *out) {
    (void)p; if (!out) return E_POINTER; *out = ProviderOptions_ServerSideProvider; return S_OK;
}
static HRESULT STDMETHODCALLTYPE ns_pattern(IRawElementProviderSimple *p, PATTERNID id, IUnknown **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxNode *node = node_simple(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    if (id == UIA_InvokePatternId && node_actionable(node)) {
        node_addref(node); *out = (IUnknown *)&node->invoke;
    } else if (id == UIA_TogglePatternId && node_toggleable(node)) {
        node_addref(node); *out = (IUnknown *)&node->toggle;
    } else if (id == UIA_SelectionItemPatternId && node_selectable(node)) {
        node_addref(node); *out = (IUnknown *)&node->selection;
    }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE ns_property(IRawElementProviderSimple *p, PROPERTYID id, VARIANT *out) {
    if (!out) return E_POINTER;
    VariantInit(out);
    CtdAxNode *node = node_simple(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    if (id == UIA_ControlTypePropertyId) { out->vt = VT_I4; out->lVal = node->role; }
    else if (id == UIA_NamePropertyId || id == UIA_ValueValuePropertyId) {
        out->vt = VT_BSTR;
        out->bstrVal = SysAllocString(id == UIA_NamePropertyId ? node->label : node->value);
    } else if (id == UIA_IsEnabledPropertyId || id == UIA_HasKeyboardFocusPropertyId ||
               id == UIA_IsKeyboardFocusablePropertyId || id == UIA_IsPasswordPropertyId ||
               id == UIA_IsControlElementPropertyId || id == UIA_IsContentElementPropertyId) {
        int value = id == UIA_IsEnabledPropertyId ? node->enabled :
                    id == UIA_HasKeyboardFocusPropertyId ? node->focused :
                    id == UIA_IsKeyboardFocusablePropertyId ? node_focusable(node) :
                    id == UIA_IsPasswordPropertyId ? node->secure : 1;
        out->vt = VT_BOOL; out->boolVal = value ? VARIANT_TRUE : VARIANT_FALSE;
    } else if (id == UIA_SelectionItemIsSelectedPropertyId) {
        out->vt = VT_BOOL; out->boolVal = node_is_selected(node) ? VARIANT_TRUE : VARIANT_FALSE;
    } else if (id == UIA_IsInvokePatternAvailablePropertyId) {
        out->vt = VT_BOOL; out->boolVal = node_actionable(node) ? VARIANT_TRUE : VARIANT_FALSE;
    } else if (id == UIA_IsTogglePatternAvailablePropertyId ||
               id == UIA_IsSelectionItemPatternAvailablePropertyId) {
        out->vt = VT_BOOL;
        out->boolVal = (id == UIA_IsTogglePatternAvailablePropertyId ?
                        node_toggleable(node) : node_selectable(node)) ? VARIANT_TRUE : VARIANT_FALSE;
    } else if (id == UIA_FrameworkIdPropertyId) {
        out->vt = VT_BSTR; out->bstrVal = SysAllocString(L"Cortado");
    }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE ns_host(IRawElementProviderSimple *p, IRawElementProviderSimple **out) {
    (void)p; if (!out) return E_POINTER; *out = NULL; return S_OK;
}
static HRESULT STDMETHODCALLTYPE tf_navigate(IRawElementProviderFragment *p, enum NavigateDirection direction,
                                             IRawElementProviderFragment **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxTree *tree = tree_fragment(p);
    AcquireSRWLockShared(&tree->lock);
    if (!tree->hwnd) { ReleaseSRWLockShared(&tree->lock); return UIA_E_ELEMENTNOTAVAILABLE; }
    if (!tree->count) { ReleaseSRWLockShared(&tree->lock); return S_OK; }
    CtdAxNode *node = direction == NavigateDirection_FirstChild ? tree->nodes[0] :
                      direction == NavigateDirection_LastChild ? tree->nodes[tree->count - 1] : NULL;
    if (node) { node_addref(node); *out = &node->fragment; }
    ReleaseSRWLockShared(&tree->lock);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE tf_runtime(IRawElementProviderFragment *p, SAFEARRAY **out) {
    (void)p; if (!out) return E_POINTER; *out = NULL; return S_OK;
}
static HRESULT STDMETHODCALLTYPE tf_bounds(IRawElementProviderFragment *p, struct UiaRect *out) {
    if (!out) return E_POINTER;
    CtdAxTree *tree = tree_fragment(p);
    AcquireSRWLockShared(&tree->lock);
    HWND hwnd = tree->hwnd;
    ReleaseSRWLockShared(&tree->lock);
    if (!hwnd) return UIA_E_ELEMENTNOTAVAILABLE;
    RECT box; if (!GetWindowRect(hwnd, &box)) return UIA_E_ELEMENTNOTAVAILABLE;
    out->left = box.left; out->top = box.top;
    out->width = box.right - box.left; out->height = box.bottom - box.top;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE tf_embedded(IRawElementProviderFragment *p, SAFEARRAY **out) {
    (void)p; if (!out) return E_POINTER; *out = NULL; return S_OK;
}
static HRESULT STDMETHODCALLTYPE tf_focus(IRawElementProviderFragment *p) {
    (void)p; return UIA_E_NOTSUPPORTED;
}
static HRESULT STDMETHODCALLTYPE tf_root(IRawElementProviderFragment *p, IRawElementProviderFragmentRoot **out) {
    if (!out) return E_POINTER;
    CtdAxTree *tree = tree_fragment(p);
    AcquireSRWLockShared(&tree->lock);
    int alive = tree->hwnd != NULL;
    ReleaseSRWLockShared(&tree->lock);
    if (!alive) { *out = NULL; return UIA_E_ELEMENTNOTAVAILABLE; }
    tree_addref(tree); *out = &tree->root; return S_OK;
}
static HRESULT STDMETHODCALLTYPE nf_navigate(IRawElementProviderFragment *p, enum NavigateDirection direction,
                                             IRawElementProviderFragment **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxNode *node = node_fragment(p);
    CtdAxTree *tree = node->tree;
    AcquireSRWLockShared(&tree->lock);
    if (!node->active || !tree->hwnd) {
        ReleaseSRWLockShared(&tree->lock); return UIA_E_ELEMENTNOTAVAILABLE;
    }
    if (direction == NavigateDirection_Parent) {
        tree_addref(tree); *out = &tree->fragment;
        ReleaseSRWLockShared(&tree->lock); return S_OK;
    }
    for (size_t i = 0; i < tree->count; ++i) if (tree->nodes[i] == node) {
        CtdAxNode *next = direction == NavigateDirection_NextSibling && i + 1 < tree->count ? tree->nodes[i + 1] :
                          direction == NavigateDirection_PreviousSibling && i > 0 ? tree->nodes[i - 1] : NULL;
        if (next) { node_addref(next); *out = &next->fragment; }
        break;
    }
    ReleaseSRWLockShared(&tree->lock);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE nf_runtime(IRawElementProviderFragment *p, SAFEARRAY **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxNode *node = node_fragment(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    SAFEARRAY *ids = SafeArrayCreateVector(VT_I4, 0, 3);
    if (!ids) return E_OUTOFMEMORY;
    LONG at;
    at = 0; LONG value = UiaAppendRuntimeId; SafeArrayPutElement(ids, &at, &value);
    at = 1; value = (LONG)(node->id & 0xffffffffu); SafeArrayPutElement(ids, &at, &value);
    at = 2; value = (LONG)(node->id >> 32); SafeArrayPutElement(ids, &at, &value);
    *out = ids; return S_OK;
}
static HRESULT STDMETHODCALLTYPE nf_bounds(IRawElementProviderFragment *p, struct UiaRect *out) {
    if (!out) return E_POINTER;
    CtdAxNode *node = node_fragment(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    AcquireSRWLockShared(&node->tree->lock);
    HWND hwnd = node->tree->hwnd;
    ReleaseSRWLockShared(&node->tree->lock);
    if (!hwnd) return UIA_E_ELEMENTNOTAVAILABLE;
    POINT origin = {0, 0};
    if (!ClientToScreen(hwnd, &origin)) return UIA_E_ELEMENTNOTAVAILABLE;
    /* Scene coordinates are HWND client pixels on this host: surface_content_size
     * reads GetClientRect and view_set_frame passes them to SetWindowPos. The
     * renderer's DPI scale affects bitmap resolution, not these bounds. */
    out->left = origin.x + node->x; out->top = origin.y + node->y;
    out->width = node->width; out->height = node->height;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE nf_embedded(IRawElementProviderFragment *p, SAFEARRAY **out) {
    (void)p; if (!out) return E_POINTER; *out = NULL; return S_OK;
}
static HRESULT STDMETHODCALLTYPE nf_focus(IRawElementProviderFragment *p) {
    CtdAxNode *node = node_fragment(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    if (!node->enabled) return UIA_E_ELEMENTNOTENABLED;
    if (!node_focusable(node)) return UIA_E_NOTSUPPORTED;
    AcquireSRWLockShared(&node->tree->lock);
    HWND hwnd = node->tree->hwnd;
    ReleaseSRWLockShared(&node->tree->lock);
    return hwnd && SendMessageW(hwnd, CTD_WM_AX_ACTION, 2, (LPARAM)node->id) ? S_OK : UIA_E_ELEMENTNOTAVAILABLE;
}
static HRESULT STDMETHODCALLTYPE nf_root(IRawElementProviderFragment *p, IRawElementProviderFragmentRoot **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxNode *node = node_fragment(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    AcquireSRWLockShared(&node->tree->lock);
    int alive = node->tree->hwnd != NULL;
    ReleaseSRWLockShared(&node->tree->lock);
    if (!alive) return UIA_E_ELEMENTNOTAVAILABLE;
    tree_addref(node->tree); *out = &node->tree->root; return S_OK;
}
static HRESULT STDMETHODCALLTYPE tr_point(IRawElementProviderFragmentRoot *p, double x, double y,
                                          IRawElementProviderFragment **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxTree *tree = tree_root(p);
    AcquireSRWLockShared(&tree->lock);
    HWND hwnd = tree->hwnd;
    if (!hwnd) { ReleaseSRWLockShared(&tree->lock); return UIA_E_ELEMENTNOTAVAILABLE; }
    POINT origin = {0, 0};
    if (!ClientToScreen(hwnd, &origin)) {
        ReleaseSRWLockShared(&tree->lock); return UIA_E_ELEMENTNOTAVAILABLE;
    }
    for (size_t i = tree->count; i > 0; --i) {
        CtdAxNode *node = tree->nodes[i - 1];
        if (x >= origin.x + node->x && y >= origin.y + node->y &&
            x < origin.x + node->x + node->width && y < origin.y + node->y + node->height) {
            node_addref(node); *out = &node->fragment;
            ReleaseSRWLockShared(&tree->lock); return S_OK;
        }
    }
    tree_addref(tree); *out = &tree->fragment;
    ReleaseSRWLockShared(&tree->lock); return S_OK;
}
static HRESULT STDMETHODCALLTYPE tr_focus(IRawElementProviderFragmentRoot *p, IRawElementProviderFragment **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxTree *tree = tree_root(p);
    AcquireSRWLockShared(&tree->lock);
    if (!tree->hwnd) { ReleaseSRWLockShared(&tree->lock); return UIA_E_ELEMENTNOTAVAILABLE; }
    for (size_t i = 0; i < tree->count; ++i) if (tree->nodes[i]->focused) {
        node_addref(tree->nodes[i]); *out = &tree->nodes[i]->fragment; break;
    }
    ReleaseSRWLockShared(&tree->lock);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE ni_activate(IInvokeProvider *p) {
    CtdAxNode *node = node_invoke(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    if (!node->enabled) return UIA_E_ELEMENTNOTENABLED;
    AcquireSRWLockShared(&node->tree->lock);
    HWND hwnd = node->tree->hwnd;
    ReleaseSRWLockShared(&node->tree->lock);
    return hwnd && SendMessageW(hwnd, CTD_WM_AX_ACTION, 1, (LPARAM)node->id) ? S_OK : UIA_E_ELEMENTNOTAVAILABLE;
}
static HRESULT ctd_ax_send_action(CtdAxNode *node) {
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    if (!node->enabled) return UIA_E_ELEMENTNOTENABLED;
    AcquireSRWLockShared(&node->tree->lock);
    HWND hwnd = node->tree->hwnd;
    ReleaseSRWLockShared(&node->tree->lock);
    return hwnd && SendMessageW(hwnd, CTD_WM_AX_ACTION, 1, (LPARAM)node->id) ? S_OK : UIA_E_ELEMENTNOTAVAILABLE;
}
static HRESULT STDMETHODCALLTYPE nt_toggle(IToggleProvider *p) {
    return ctd_ax_send_action(node_toggle(p));
}
static HRESULT STDMETHODCALLTYPE nt_state(IToggleProvider *p, enum ToggleState *out) {
    if (!out) return E_POINTER;
    CtdAxNode *node = node_toggle(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    *out = !wcscmp(node->value, L"mixed") ? ToggleState_Indeterminate :
           !wcscmp(node->value, L"on") ? ToggleState_On : ToggleState_Off;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE nsi_select(ISelectionItemProvider *p) {
    return ctd_ax_send_action(node_selection(p));
}
static HRESULT STDMETHODCALLTYPE nsi_add(ISelectionItemProvider *p) {
    return ctd_ax_send_action(node_selection(p));
}
static HRESULT STDMETHODCALLTYPE nsi_remove(ISelectionItemProvider *p) {
    CtdAxNode *node = node_selection(p);
    return node_alive(node) ? UIA_E_INVALIDOPERATION : UIA_E_ELEMENTNOTAVAILABLE;
}
static HRESULT STDMETHODCALLTYPE nsi_selected(ISelectionItemProvider *p, WINBOOL *out) {
    if (!out) return E_POINTER;
    CtdAxNode *node = node_selection(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    *out = node_is_selected(node);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE nsi_container(ISelectionItemProvider *p, IRawElementProviderSimple **out) {
    if (!out) return E_POINTER;
    *out = NULL;
    CtdAxNode *node = node_selection(p);
    if (!node_alive(node)) return UIA_E_ELEMENTNOTAVAILABLE;
    tree_addref(node->tree);
    *out = &node->tree->simple;
    return S_OK;
}
static IRawElementProviderSimpleVtbl tree_simple_vt = {
    ts_qi, ts_ref, ts_unref, ts_options, ts_pattern, ts_property, ts_host
};
static IRawElementProviderFragmentVtbl tree_fragment_vt = {
    tf_qi, tf_ref, tf_unref, tf_navigate, tf_runtime, tf_bounds, tf_embedded, tf_focus, tf_root
};
static IRawElementProviderFragmentRootVtbl tree_root_vt = {
    tr_qi, tr_ref, tr_unref, tr_point, tr_focus
};
static IRawElementProviderSimpleVtbl node_simple_vt = {
    ns_qi, ns_ref, ns_unref, ns_options, ns_pattern, ns_property, ns_host
};
static IRawElementProviderFragmentVtbl node_fragment_vt = {
    nf_qi, nf_ref, nf_unref, nf_navigate, nf_runtime, nf_bounds, nf_embedded, nf_focus, nf_root
};
static IInvokeProviderVtbl node_invoke_vt = { ni_qi, ni_ref, ni_unref, ni_activate };
static IToggleProviderVtbl node_toggle_vt = { nt_qi, nt_ref, nt_unref, nt_toggle, nt_state };
static ISelectionItemProviderVtbl node_selection_vt = {
    nsi_qi, nsi_ref, nsi_unref, nsi_select, nsi_add, nsi_remove, nsi_selected, nsi_container
};

static void ctd_ax_clear(CtdAxTree *tree) {
    AcquireSRWLockExclusive(&tree->lock);
    for (size_t i = 0; i < tree->count; ++i) {
        CtdAxNode *node = tree->nodes[i];
        InterlockedExchange(&node->active, 0);
        node_release(node);
    }
    tree->count = 0;
    ReleaseSRWLockExclusive(&tree->lock);
}
void ctd_canvas_ax_release(HWND hwnd) {
    CtdAxTree *tree = (CtdAxTree *)RemovePropW(hwnd, CTD_AX_PROP);
    if (!tree) return;
    /* UIAutomationCore asks providers to disconnect when their HWND dies. */
    UiaReturnRawElementProvider(hwnd, 0, 0, NULL);
    ctd_ax_clear(tree);
    AcquireSRWLockExclusive(&tree->lock);
    tree->hwnd = NULL;
    ReleaseSRWLockExclusive(&tree->lock);
    tree_release(tree);
}
LRESULT ctd_canvas_ax_getobject(HWND hwnd, WPARAM wparam, LPARAM lparam) {
    if (lparam != UiaRootObjectId) return 0;
    CtdAxTree *tree = ctd_ax_tree(hwnd);
    return tree ? UiaReturnRawElementProvider(hwnd, wparam, lparam, &tree->simple) : 0;
}
void *ctd_canvas_ax_provider(HWND hwnd) {
    CtdAxTree *tree = ctd_ax_tree(hwnd);
    if (!tree) return NULL;
    tree_addref(tree);
    return &tree->simple;
}
LRESULT ctd_canvas_ax_action(HWND hwnd, WPARAM action, LPARAM id) {
    CtdAxTree *tree = ctd_ax_tree(hwnd);
    if (!tree || !g_sink || !ctd_listening(CTD_EV_SEMANTICS_ACTION)) return 0;
    int found = 0;
    ctd_handle canvas = tree->canvas;
    ctd_event_fn sink = g_sink;
    void *context = g_sink_context;
    AcquireSRWLockShared(&tree->lock);
    for (size_t i = 0; i < tree->count; ++i) {
        CtdAxNode *node = tree->nodes[i];
        if (node->id != (uint64_t)id || !node->enabled ||
            (action == 1 && !node_actionable(node)) ||
            (action == 2 && !node_focusable(node))) continue;
        found = 1; break;
    }
    ReleaseSRWLockShared(&tree->lock);
    if (!found) return 0;
    if (action == 2) SetFocus(hwnd);
    ctd_event event = {0};
    event.kind = CTD_EV_SEMANTICS_ACTION;
    event.target = canvas;
    event.index = (int64_t)action;
    event.token = id;
    sink(context, &event);
    return 1;
}
static CtdAxTree *ctd_ax_get(HWND hwnd, ctd_handle canvas) {
    CtdAxTree *tree = ctd_ax_tree(hwnd);
    if (tree) return tree;
    tree = calloc(1, sizeof(*tree));
    if (!tree) return NULL;
    tree->simple.lpVtbl = &tree_simple_vt;
    tree->fragment.lpVtbl = &tree_fragment_vt;
    tree->root.lpVtbl = &tree_root_vt;
    tree->refs = 1; tree->hwnd = hwnd; tree->canvas = canvas;
    InitializeSRWLock(&tree->lock);
    if (!SetPropW(hwnd, CTD_AX_PROP, tree)) { free(tree); return NULL; }
    return tree;
}
static WCHAR *ctd_ax_wide(const char *utf8, int32_t length) {
    if (length < 0 || (length && !utf8)) return NULL;
    if (!length) return calloc(1, sizeof(WCHAR));
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, length, NULL, 0);
    if (!count) return NULL;
    WCHAR *out = calloc((size_t)count + 1, sizeof(WCHAR));
    if (!out || !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, length, out, count)) {
        free(out); return NULL;
    }
    return out;
}
static int ctd_ax_role(const char *role, int32_t length) {
#define ROLE(word, kind) if (length == (int32_t)sizeof(word) - 1 && !memcmp(role, word, sizeof(word) - 1)) return kind
    ROLE("button", UIA_ButtonControlTypeId);
    ROLE("checkbox", UIA_CheckBoxControlTypeId);
    ROLE("radio", UIA_RadioButtonControlTypeId);
    ROLE("switch", UIA_CheckBoxControlTypeId);
    ROLE("textbox", UIA_EditControlTypeId);
    ROLE("securetext", UIA_EditControlTypeId);
    ROLE("text", UIA_TextControlTypeId);
    ROLE("option", UIA_ListItemControlTypeId);
    ROLE("image", UIA_ImageControlTypeId);
    ROLE("slider", UIA_SliderControlTypeId);
    ROLE("spinbutton", UIA_SpinnerControlTypeId);
    ROLE("progressbar", UIA_ProgressBarControlTypeId);
    ROLE("meter", UIA_ProgressBarControlTypeId);
    ROLE("separator", UIA_SeparatorControlTypeId);
    ROLE("combobox", UIA_ComboBoxControlTypeId);
    ROLE("tablist", UIA_TabControlTypeId);
    ROLE("table", UIA_TableControlTypeId);
    ROLE("scrollarea", UIA_PaneControlTypeId);
#undef ROLE
    return UIA_GroupControlTypeId;
}
ctd_status ctd_canvas_semantics_clear(ctd_handle canvas) {
    uint32_t slot = ctd_slot(canvas);
    if (!slot) return CTD_ERR_STALE;
    if (ctd_slot_kind(canvas) != CTD_W_CANVAS) return CTD_ERR_KIND;
    CtdAxTree *tree = ctd_ax_get((HWND)g_object[slot], canvas);
    if (!tree) return CTD_ERR_PLATFORM;
    ctd_ax_clear(tree); return CTD_OK;
}
ctd_status ctd_canvas_semantics_add(ctd_handle canvas, uint64_t node_id,
    const char *role, int32_t role_len, const char *label, int32_t label_len,
    const char *value, int32_t value_len, double x, double y,
    double width, double height, int32_t enabled, int32_t focused) {
    uint32_t slot = ctd_slot(canvas);
    if (!slot) return CTD_ERR_STALE;
    if (ctd_slot_kind(canvas) != CTD_W_CANVAS) return CTD_ERR_KIND;
    if (!node_id || role_len < 0 || label_len < 0 || value_len < 0 ||
        (role_len && !role) || (label_len && !label) || (value_len && !value) ||
        !isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) ||
        width < 0 || height < 0) return CTD_ERR_RANGE;
    CtdAxTree *tree = ctd_ax_get((HWND)g_object[slot], canvas);
    if (!tree) return CTD_ERR_PLATFORM;
    AcquireSRWLockShared(&tree->lock);
    for (size_t i = 0; i < tree->count; ++i) if (tree->nodes[i]->id == node_id) {
        ReleaseSRWLockShared(&tree->lock); return CTD_ERR_RANGE;
    }
    ReleaseSRWLockShared(&tree->lock);
    WCHAR *l = ctd_ax_wide(label, label_len), *v = ctd_ax_wide(value, value_len);
    if (!l || !v) { free(l); free(v); return CTD_ERR_RANGE; }
    AcquireSRWLockExclusive(&tree->lock);
    if (tree->count == tree->capacity) {
        size_t next = tree->capacity ? tree->capacity * 2 : 16;
        CtdAxNode **nodes = realloc(tree->nodes, next * sizeof(*nodes));
        if (!nodes) { ReleaseSRWLockExclusive(&tree->lock); free(l); free(v); return CTD_ERR_PLATFORM; }
        tree->nodes = nodes; tree->capacity = next;
    }
    CtdAxNode *node = calloc(1, sizeof(*node));
    if (!node) { ReleaseSRWLockExclusive(&tree->lock); free(l); free(v); return CTD_ERR_PLATFORM; }
    node->simple.lpVtbl = &node_simple_vt;
    node->fragment.lpVtbl = &node_fragment_vt;
    node->invoke.lpVtbl = &node_invoke_vt;
    node->toggle.lpVtbl = &node_toggle_vt;
    node->selection.lpVtbl = &node_selection_vt;
    node->refs = 1; node->active = 1;
    node->tree = tree; tree_addref(tree);
    node->id = node_id; node->role = ctd_ax_role(role, role_len);
    node->secure = role_len == 10 && !memcmp(role, "securetext", 10);
    node->selected = value_len == 8 && !memcmp(value, "selected", 8);
    node->label = l; node->value = v;
    node->x = x; node->y = y; node->width = width; node->height = height;
    node->enabled = enabled != 0; node->focused = focused != 0;
    tree->nodes[tree->count++] = node;
    ReleaseSRWLockExclusive(&tree->lock);
    return CTD_OK;
}
ctd_status ctd_canvas_semantics_end(ctd_handle canvas) {
    uint32_t slot = ctd_slot(canvas);
    if (!slot) return CTD_ERR_STALE;
    if (ctd_slot_kind(canvas) != CTD_W_CANVAS) return CTD_ERR_KIND;
    CtdAxTree *tree = ctd_ax_tree((HWND)g_object[slot]);
    if (!tree) return CTD_ERR_PLATFORM;
    if (UiaClientsAreListening()) {
        UiaRaiseStructureChangedEvent(&tree->simple, StructureChangeType_ChildrenInvalidated, NULL, 0);
        CtdAxNode *focused = NULL;
        AcquireSRWLockShared(&tree->lock);
        for (size_t i = 0; i < tree->count; ++i) if (tree->nodes[i]->focused) {
            focused = tree->nodes[i]; node_addref(focused); break;
        }
        ReleaseSRWLockShared(&tree->lock);
        if (focused) {
            UiaRaiseAutomationEvent(&focused->simple, UIA_AutomationFocusChangedEventId);
            node_release(focused);
        }
    }
    return CTD_OK;
}
