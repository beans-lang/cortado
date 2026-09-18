#define COBJMACROS
#include "../src/win32/internal.h"
#include <uiautomation.h>
#include <assert.h>
#include <stdio.h>

static ctd_event last;
static int received;
static char text_copy[8];
static void receive(void *context, const ctd_event *event) {
    (void)context;
    last = *event;
    if (event->text && event->text_len > 0 && event->text_len < (int)sizeof text_copy)
        memcpy(text_copy, event->text, event->text_len);
    received++;
}

int main(void) {
    assert(ctd_init(CTD_ABI_VERSION) == CTD_OK);
    assert(ctd_app_set_role(CTD_ROLE_HEADLESS) == CTD_OK);
    assert(ctd_set_event_sink(receive, NULL) == CTD_OK);
    assert(ctd_listen(CTD_EV_SEMANTICS_ACTION, 1) == CTD_OK);
    assert(ctd_listen(CTD_EV_TEXT_INPUT, 1) == CTD_OK);
    ctd_handle canvas = ctd_widget_new(CTD_W_CANVAS);
    assert(canvas);
    HWND hwnd = ctd_window(canvas);
    assert(ctd_listen(CTD_EV_POINTER_MOVE, 1) == CTD_OK);
    SendMessageW(hwnd, WM_MOUSEMOVE, 0, MAKELPARAM(10, 11));
    SendMessageW(hwnd, WM_MOUSELEAVE, 0, 0);
    assert(last.kind == CTD_EV_POINTER_MOVE && last.target == canvas &&
           last.x == -1.0 && last.y == -1.0);
    assert(ctd_canvas_text_state(canvas, 1, "ab", 2, 1, 1, 2, 3, 1, 12) == CTD_OK);
    SendMessageW(hwnd, WM_CHAR, L'x', 0);
    assert(last.kind == CTD_EV_TEXT_INPUT && last.index == -1 && last.token == -1);
    assert(last.text_len == 1 && text_copy[0] == 'x');
    SendMessageW(hwnd, WM_UNICHAR, 0x1f600, 0);
    assert(last.kind == CTD_EV_TEXT_INPUT && last.index == -1 && last.token == -1);
    assert(last.text_len == 4);
    assert(ctd_canvas_semantics_clear(canvas) == CTD_OK);
    assert(ctd_canvas_semantics_add(canvas, 17, "button", 6, "Order", 5, "", 0,
                                    4, 5, 80, 24, 1, 0) == CTD_OK);
    assert(ctd_canvas_semantics_add(canvas, 18, "securetext", 10, "PIN", 3, "", 0,
                                    4, 35, 80, 24, 1, 1) == CTD_OK);
    assert(ctd_canvas_semantics_add(canvas, 20, "checkbox", 8, "Alerts", 6, "on", 2,
                                    4, 65, 80, 24, 1, 0) == CTD_OK);
    assert(ctd_canvas_semantics_add(canvas, 21, "option", 6, "Tea", 3, "selected", 8,
                                    4, 95, 80, 24, 1, 0) == CTD_OK);
    assert(ctd_canvas_semantics_add(canvas, 22, "radio", 5, "Large", 5, "on", 2,
                                    4, 125, 80, 24, 1, 0) == CTD_OK);
    assert(ctd_canvas_semantics_end(canvas) == CTD_OK);
    IRawElementProviderSimple *provider = ctd_canvas_ax_provider(hwnd);
    assert(provider);
    IRawElementProviderFragment *root = NULL;
    assert(IRawElementProviderSimple_QueryInterface(provider, &IID_IRawElementProviderFragment,
                                                    (void **)&root) == S_OK);
    IRawElementProviderFragment *button = NULL;
    assert(IRawElementProviderFragment_Navigate(root, NavigateDirection_FirstChild, &button) == S_OK);
    assert(button);
    IRawElementProviderSimple *button_simple = NULL;
    assert(IRawElementProviderFragment_QueryInterface(button, &IID_IRawElementProviderSimple,
                                                      (void **)&button_simple) == S_OK);
    VARIANT property;
    assert(IRawElementProviderSimple_GetPropertyValue(button_simple, UIA_NamePropertyId, &property) == S_OK);
    assert(property.vt == VT_BSTR && !wcscmp(property.bstrVal, L"Order"));
    VariantClear(&property);
    IUnknown *pattern = NULL;
    assert(IRawElementProviderSimple_GetPatternProvider(button_simple, UIA_InvokePatternId, &pattern) == S_OK);
    assert(pattern);
    IInvokeProvider *invoke = (IInvokeProvider *)pattern;
    received = 0;
    assert(IInvokeProvider_Invoke(invoke) == S_OK);
    assert(received == 1 && last.kind == CTD_EV_SEMANTICS_ACTION &&
           last.token == 17 && last.index == 1);
    IInvokeProvider_Release(invoke);
    IRawElementProviderSimple_Release(button_simple);
    IRawElementProviderFragment *secure = NULL, *checkbox = NULL, *option = NULL, *radio = NULL;
    assert(IRawElementProviderFragment_Navigate(button, NavigateDirection_NextSibling, &secure) == S_OK && secure);
    assert(IRawElementProviderFragment_Navigate(secure, NavigateDirection_NextSibling, &checkbox) == S_OK && checkbox);
    assert(IRawElementProviderFragment_Navigate(checkbox, NavigateDirection_NextSibling, &option) == S_OK && option);
    assert(IRawElementProviderFragment_Navigate(option, NavigateDirection_NextSibling, &radio) == S_OK && radio);
    IRawElementProviderSimple *item = NULL;
    assert(IRawElementProviderFragment_QueryInterface(checkbox, &IID_IRawElementProviderSimple, (void **)&item) == S_OK);
    assert(IRawElementProviderSimple_GetPatternProvider(item, UIA_TogglePatternId, &pattern) == S_OK && pattern);
    IToggleProvider *toggle = (IToggleProvider *)pattern;
    enum ToggleState state;
    assert(IToggleProvider_get_ToggleState(toggle, &state) == S_OK && state == ToggleState_On);
    assert(IToggleProvider_Toggle(toggle) == S_OK && last.token == 20);
    IToggleProvider_Release(toggle);
    IRawElementProviderSimple_Release(item);
    assert(IRawElementProviderFragment_QueryInterface(option, &IID_IRawElementProviderSimple, (void **)&item) == S_OK);
    assert(IRawElementProviderSimple_GetPatternProvider(item, UIA_SelectionItemPatternId, &pattern) == S_OK && pattern);
    ISelectionItemProvider *selection = (ISelectionItemProvider *)pattern;
    WINBOOL selected = FALSE;
    assert(ISelectionItemProvider_get_IsSelected(selection, &selected) == S_OK && selected);
    assert(ISelectionItemProvider_Select(selection) == S_OK && last.token == 21);
    ISelectionItemProvider_Release(selection);
    IRawElementProviderSimple_Release(item);
    assert(IRawElementProviderFragment_QueryInterface(radio, &IID_IRawElementProviderSimple, (void **)&item) == S_OK);
    assert(IRawElementProviderSimple_GetPropertyValue(item, UIA_SelectionItemIsSelectedPropertyId, &property) == S_OK);
    assert(property.vt == VT_BOOL && property.boolVal == VARIANT_TRUE);
    VariantClear(&property);
    assert(IRawElementProviderSimple_GetPatternProvider(item, UIA_SelectionItemPatternId, &pattern) == S_OK && pattern);
    selected = FALSE;
    assert(ISelectionItemProvider_get_IsSelected((ISelectionItemProvider *)pattern, &selected) == S_OK && selected);
    ISelectionItemProvider_Release((ISelectionItemProvider *)pattern);
    IRawElementProviderSimple_Release(item);
    assert(ctd_canvas_semantics_clear(canvas) == CTD_OK);
    assert(IRawElementProviderFragment_SetFocus(button) == (HRESULT)UIA_E_ELEMENTNOTAVAILABLE);
    assert(IRawElementProviderFragment_SetFocus(option) == (HRESULT)UIA_E_ELEMENTNOTAVAILABLE);
    IRawElementProviderFragment_Release(option);
    IRawElementProviderFragment_Release(radio);
    IRawElementProviderFragment_Release(checkbox);
    IRawElementProviderFragment_Release(secure);
    IRawElementProviderFragment_Release(button);
    assert(ctd_canvas_semantics_add(canvas, 19, "button", 6, "Blocked", 7, "", 0,
                                    0, 0, 60, 20, 0, 0) == CTD_OK);
    assert(ctd_canvas_semantics_end(canvas) == CTD_OK);
    IRawElementProviderFragment *disabled = NULL;
    assert(IRawElementProviderFragment_Navigate(root, NavigateDirection_FirstChild, &disabled) == S_OK);
    IRawElementProviderSimple *disabled_simple = NULL;
    assert(IRawElementProviderFragment_QueryInterface(disabled, &IID_IRawElementProviderSimple,
                                                      (void **)&disabled_simple) == S_OK);
    assert(IRawElementProviderSimple_GetPatternProvider(disabled_simple, UIA_InvokePatternId, &pattern) == S_OK);
    assert(IInvokeProvider_Invoke((IInvokeProvider *)pattern) == (HRESULT)UIA_E_ELEMENTNOTENABLED);
    IInvokeProvider_Release((IInvokeProvider *)pattern);
    IRawElementProviderSimple_Release(disabled_simple);
    IRawElementProviderFragment_Release(disabled);
    ctd_handle label = ctd_widget_new(CTD_W_LABEL);
    assert(ctd_canvas_semantics_clear(label) == CTD_ERR_KIND);
    assert(ctd_widget_release(label) == CTD_OK);
    assert(ctd_widget_release(canvas) == CTD_OK);
    assert(IRawElementProviderFragment_Navigate(root, NavigateDirection_FirstChild, &button) == (HRESULT)UIA_E_ELEMENTNOTAVAILABLE);
    IRawElementProviderFragment_Release(root);
    IRawElementProviderSimple_Release(provider);
    assert(ctd_canvas_semantics_clear(canvas) == CTD_ERR_STALE);
    ctd_shutdown();
    puts("win32 UIA tree, actions, and stale providers: true");
    return 0;
}
