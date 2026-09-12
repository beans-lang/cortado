// The window procedure, the window classes, and starting the message pump.
//
// Every event in this host is born in the window procedure below: a control
// tells its *parent* what happened, and the parent looks the sender up in the
// handle table. The one callback edge into Beans is `g_sink`, a function
// pointer registered at run time.

#include "internal.h"

void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token) {
    if (!g_sink) return;
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = kind;
    event.target = target;
    event.index = index;
    event.token = token;
    g_sink(g_sink_context, &event);
}

// The same rule the other three hosts follow: a control that carries a value
// says the value changed; a control that is a command says it was activated.
// Win32 makes this the host's job in a way the others do not — every one of
// these arrives on the parent as WM_COMMAND, so only the kind the control was
// created as can tell them apart.
void ctd_emit_control(ctd_handle target) {
    if (!g_sink) return;
    HWND window = ctd_window(target);
    if (!window) return;

    uint32_t kind = CTD_EV_ACTIVATE;
    int64_t index = 0;
    char *text = NULL;
    int32_t text_len = 0;

    switch (ctd_slot_kind(target)) {
        case CTD_W_SLIDER:
            kind = CTD_EV_VALUE_CHANGED;
            index = (int64_t)SendMessageW(window, TBM_GETPOS, 0, 0);
            break;
        case CTD_W_STEPPER: {
            kind = CTD_EV_VALUE_CHANGED;
            uint32_t slot = (uint32_t)(target & 0xffffffffu);
            index = (int64_t)ctd_stepper_value(window, slot);
            break;
        }
        case CTD_W_CHECK_BOX:
        case CTD_W_RADIO_BUTTON: {
            kind = CTD_EV_VALUE_CHANGED;
            LRESULT state = SendMessageW(window, BM_GETCHECK, 0, 0);
            index = state == BST_CHECKED ? 1 : state == BST_INDETERMINATE ? 2 : 0;
            break;
        }
        case CTD_W_COMBO_BOX:
            kind = CTD_EV_VALUE_CHANGED;
            index = (int64_t)SendMessageW(window, CB_GETCURSEL, 0, 0);
            if (index == CB_ERR) index = -1;
            break;
        case CTD_W_TAB_VIEW:
            kind = CTD_EV_VALUE_CHANGED;
            index = (int64_t)SendMessageW(window, TCM_GETCURSEL, 0, 0);
            break;
        case CTD_W_DATE_PICKER: {
            kind = CTD_EV_VALUE_CHANGED;
            SYSTEMTIME shown;
            if (SendMessageW(window, DTM_GETSYSTEMTIME, 0, (LPARAM)&shown) == GDT_VALID)
                index = (int64_t)ctd_date_from_system(&shown);
            break;
        }
        case CTD_W_TEXT_FIELD:
        case CTD_W_SECURE_FIELD:
        case CTD_W_SEARCH_FIELD:
            kind = CTD_EV_TEXT_COMMIT;
            break;
        default: break;
    }

    // The control's text at the moment the event was raised, for the kinds
    // where that is the news. The bytes belong to the host and live only for
    // the duration of the call, which is what the header promises.
    if (kind == CTD_EV_VALUE_CHANGED || kind == CTD_EV_TEXT_COMMIT) {
        int32_t needed = ctd_get_text(target, NULL, 0);
        if (needed > 0) {
            text = (char *)malloc((size_t)needed);
            if (text) {
                ctd_get_text(target, text, needed);
                text_len = needed;
            }
        }
    }

    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = kind;
    event.target = target;
    event.index = index;
    event.text = text;
    event.text_len = text_len;
    g_sink(g_sink_context, &event);
    free(text);
}


#define CTD_WM_POST   (WM_APP + 1)

const WCHAR *CTD_CLASS_VIEW    = L"cortado_view";
const WCHAR *CTD_CLASS_SURFACE = L"cortado_surface";


// Every notification a cortado container or surface can receive from a child.
// One function because a container and a top-level window see exactly the same
// messages from the controls inside them.
static LRESULT ctd_common_message(HWND window, UINT message,
                                  WPARAM wparam, LPARAM lparam, int *handled) {
    (void)window;   // every case here is about the sender, not the receiver
    *handled = 1;
    switch (message) {
        case WM_COMMAND:
            // A control notification carries the control's HWND; a menu
            // command carries zero. That is how Win32 tells them apart, and
            // there is no other way: the id space overlaps.
            if (lparam != 0) {
                HWND control = (HWND)lparam;
                WORD notification = HIWORD(wparam);
                ctd_handle target = ctd_handle_of(control);
                if (!target) break;
                switch (ctd_slot_kind(target)) {
                    case CTD_W_BUTTON:
                    case CTD_W_CHECK_BOX:
                    case CTD_W_RADIO_BUTTON:
                        if (notification == BN_CLICKED) ctd_emit_control(target);
                        break;
                    case CTD_W_COMBO_BOX:
                        if (notification == CBN_SELCHANGE) ctd_emit_control(target);
                        break;
                    case CTD_W_TEXT_FIELD:
                    case CTD_W_SECURE_FIELD:
                    case CTD_W_SEARCH_FIELD:
                        // "Return pressed, or focus left the field" is what the
                        // header calls a commit. An edit box reports the second
                        // and not the first, so Return is caught in the
                        // subclass below and turned into the same event.
                        if (notification == EN_KILLFOCUS) ctd_emit_control(target);
                        break;
                    default: break;
                }
                return 0;
            } else {
                UINT id = LOWORD(wparam);
                CtdCommand *command = ctd_command_by_id(id);
                const CtdMenuId *entry = ctd_menu_id(id);
                if (command && entry) {
                    if (!command->enabled) return 0;
                    if (ctd_dispatch_editing(command->role)) return 0;
                    ctd_emit(CTD_EV_COMMAND, 0, 0, entry->token);
                    return 0;
                }
            }
            break;

        case WM_NOTIFY: {
            // A list view reports through WM_NOTIFY rather than WM_COMMAND,
            // and an owner-data one asks for its text the same way.
            NMHDR *note = (NMHDR *)lparam;
            if (!note) break;
            if (note->code == LVN_GETDISPINFOW) {
                ctd_table_disp_info((NMLVDISPINFOW *)lparam);
                return 0;
            }
            if (note->code == NM_CLICK || note->code == NM_RETURN) {
                // A SysLink reports the click and does not follow it, so this
                // host is what opens the URL — with the user's own browser and
                // the user's own handler registrations, which is what the note
                // beside CTD_S_URL says a link does.
                ctd_handle link = ctd_handle_of(note->hwndFrom);
                if (link && ctd_slot_kind(link) == CTD_W_LINK) {
                    const WCHAR *where = ctd_link_target(link);
                    if (where && where[0] != L'\0') {
                        ShellExecuteW(NULL, L"open", where, NULL, NULL, SW_SHOWNORMAL);
                    }
                    return 0;
                }
                break;
            }
            if (note->code == TCN_SELCHANGE) {
                ctd_handle tabs = ctd_handle_of(note->hwndFrom);
                if (tabs && ctd_slot_kind(tabs) == CTD_W_TAB_VIEW) {
                    // Showing the right page is the application's job on this
                    // platform — a tab control is the strip and nothing else.
                    ctd_tab_sync(tabs);
                    ctd_emit_control(tabs);
                    return 0;
                }
                break;
            }
            if (note->code == DTN_DATETIMECHANGE) {
                ctd_handle picker = ctd_handle_of(note->hwndFrom);
                if (picker && ctd_slot_kind(picker) == CTD_W_DATE_PICKER) {
                    ctd_emit_control(picker);
                    return 0;
                }
                break;
            }
            if (note->code == LVN_ITEMCHANGED) {
                ctd_table_item_changed((NMLISTVIEW *)lparam);
                return 0;
            }
            break;
        }

        case WM_HSCROLL:
        case WM_VSCROLL:
            // A trackbar reports through the scroll messages rather than
            // WM_COMMAND, which is the one place Win32's "notify the parent"
            // rule uses a different message for the same idea.
            if (lparam != 0) {
                ctd_handle target = ctd_handle_of((HWND)lparam);
                int32_t scrolled = target ? ctd_slot_kind(target) : -1;
                if (scrolled == CTD_W_SLIDER || scrolled == CTD_W_STEPPER) {
                    ctd_emit_control(target);
                    return 0;
                }
            }
            break;

        case CTD_WM_POST:
            ctd_emit(CTD_EV_POST, 0, 0, (int64_t)lparam);
            return 0;

        case CTD_WM_DIALOG:
            ctd_run_dialog((void *)lparam);
            return 0;

        default: break;
    }
    *handled = 0;
    return 0;
}

// A scroll view's content window, offset by however far it is scrolled.
static void ctd_scroll_to(HWND scroller, int which, int position) {
    HWND content = NULL;
    for (HWND child = GetWindow(scroller, GW_CHILD); child;
         child = GetWindow(child, GW_HWNDNEXT)) {
        if (GetPropW(child, CTD_INNER)) { content = child; break; }
    }
    if (!content) return;
    RECT frame;
    GetWindowRect(content, &frame);
    MapWindowPoints(HWND_DESKTOP, scroller, (POINT *)&frame, 2);
    int x = which == SB_HORZ ? -position : frame.left;
    int y = which == SB_HORZ ? frame.top : -position;
    SetWindowPos(content, NULL, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    SetScrollPos(scroller, which, position, TRUE);
}

static LRESULT CALLBACK ctd_view_proc(HWND window, UINT message,
                                      WPARAM wparam, LPARAM lparam) {
    // A scroll view is a view with bars, and the bar messages arrive with a
    // zero lParam — a trackbar's carry its HWND — so they are separated here
    // before the shared handler sees them.
    if ((message == WM_VSCROLL || message == WM_HSCROLL) && lparam == 0) {
        int which = message == WM_VSCROLL ? SB_VERT : SB_HORZ;
        SCROLLINFO info;
        memset(&info, 0, sizeof info);
        info.cbSize = sizeof info;
        info.fMask = SIF_ALL;
        GetScrollInfo(window, which, &info);
        int position = info.nPos;
        switch (LOWORD(wparam)) {
            case SB_LINEUP:   position -= 16; break;
            case SB_LINEDOWN: position += 16; break;
            case SB_PAGEUP:   position -= (int)info.nPage; break;
            case SB_PAGEDOWN: position += (int)info.nPage; break;
            case SB_THUMBTRACK:
            case SB_THUMBPOSITION: position = info.nTrackPos; break;
            default: break;
        }
        if (position < info.nMin) position = info.nMin;
        if (position > info.nMax) position = info.nMax;
        ctd_scroll_to(window, which, position);
        return 0;
    }
    int handled = 0;
    LRESULT answer = ctd_common_message(window, message, wparam, lparam, &handled);
    if (handled) return answer;
    // A child window draws nothing of its own; without this it shows whatever
    // was behind it.
    if (message == WM_ERASEBKGND) {
        HDC device = (HDC)wparam;
        RECT client;
        GetClientRect(window, &client);
        FillRect(device, &client, (HBRUSH)(COLOR_BTNFACE + 1));
        return 1;
    }
    if (message == WM_CTLCOLORSTATIC) {
        SetBkMode((HDC)wparam, TRANSPARENT);
        return (LRESULT)GetSysColorBrush(COLOR_BTNFACE);
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

static LRESULT CALLBACK ctd_surface_proc(HWND window, UINT message,
                                         WPARAM wparam, LPARAM lparam) {
    int handled = 0;
    LRESULT answer = ctd_common_message(window, message, wparam, lparam, &handled);
    if (handled) return answer;
    switch (message) {
        case WM_SIZE: {
            ctd_handle surface = ctd_handle_of(window);
            if (surface && g_sink) {
                ctd_event event;
                memset(&event, 0, sizeof event);
                event.kind = CTD_EV_SURFACE_RESIZED;
                event.target = surface;
                event.width = (double)LOWORD(lparam);
                event.height = (double)HIWORD(lparam);
                g_sink(g_sink_context, &event);
            }
            return 0;
        }
        case WM_TIMER:
            // The frame clock's own timer, and nothing else uses one on a
            // surface. Any other id is somebody else's and goes to DefWindowProc.
            if (wparam == CTD_CLOCK_TIMER) {
                ctd_clock_ticked(window);
                return 0;
            }
            break;
        case WM_CLOSE:
            ctd_emit(CTD_EV_SURFACE_CLOSE, ctd_handle_of(window), 0, 0);
            // The application decides whether a close request closes anything.
            // Destroying the window here would take the decision away, and the
            // handle would go stale under a program that meant to refuse.
            return 0;
        case WM_DPICHANGED: {
            ctd_handle surface = ctd_handle_of(window);
            const RECT *suggested = (const RECT *)lparam;
            SetWindowPos(window, NULL, suggested->left, suggested->top,
                         suggested->right - suggested->left,
                         suggested->bottom - suggested->top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
            if (g_sink) {
                ctd_event event;
                memset(&event, 0, sizeof event);
                event.kind = CTD_EV_SCALE_CHANGED;
                event.target = surface;
                event.x = (double)LOWORD(wparam) / 96.0;
                g_sink(g_sink_context, &event);
            }
            return 0;
        }
        case WM_SETTINGCHANGE:
            // Light and dark live in a user setting, and this is the broadcast
            // that says one changed. Windows names the key rather than the
            // thing, so the value is read back rather than taken from here.
            if (lparam && wcscmp((const WCHAR *)lparam, L"ImmersiveColorSet") == 0)
                ctd_emit(CTD_EV_APPEARANCE, 0, ctd_appearance(), 0);
            return 0;
        default: break;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

// An edit box does not report Return; it reports losing focus. The header
// promises both, so Return is caught here and turned into the same commit.
LRESULT CALLBACK ctd_edit_proc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
    (void)id; (void)data;
    if (message == WM_CHAR && wparam == VK_RETURN) {
        ctd_handle target = ctd_handle_of(window);
        if (target) ctd_emit_control(target);
        return 0;                 // and no beep, which is what the default does
    }
    if (message == WM_NCDESTROY) {
        RemoveWindowSubclass(window, ctd_edit_proc, 1);
    }
    return DefSubclassProc(window, message, wparam, lparam);
}


uint32_t ctd_abi_version(void) { return CTD_ABI_VERSION; }

static HFONT ctd_make_ui_font(void) {
    NONCLIENTMETRICSW metrics;
    memset(&metrics, 0, sizeof metrics);
    metrics.cbSize = sizeof metrics;
    if (SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof metrics, &metrics, 0))
        return CreateFontIndirectW(&metrics.lfMessageFont);
    return (HFONT)GetStockObject(DEFAULT_GUI_FONT);
}

ctd_status ctd_init(uint32_t want_abi) {
    if (want_abi != CTD_ABI_VERSION) return CTD_ERR_ABI;
    if (g_started) return CTD_OK;

    // Per-monitor v2 so `ctd_surface_scale` answers the display the window is
    // actually on. Without it Windows lies to the process and scales its
    // output, and every frame cortado computed would be stretched by the
    // system instead of laid out at the real size.
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    INITCOMMONCONTROLSEX controls;
    controls.dwSize = sizeof controls;
    controls.dwICC = ICC_STANDARD_CLASSES | ICC_BAR_CLASSES | ICC_PROGRESS_CLASS;
    if (!InitCommonControlsEx(&controls)) return CTD_ERR_PLATFORM;

    g_ui_font = ctd_make_ui_font();

    WNDCLASSEXW view;
    memset(&view, 0, sizeof view);
    view.cbSize = sizeof view;
    view.lpfnWndProc = ctd_view_proc;
    view.hInstance = GetModuleHandleW(NULL);
    view.hCursor = LoadCursorW(NULL, IDC_ARROW);
    view.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    view.lpszClassName = CTD_CLASS_VIEW;
    if (!RegisterClassExW(&view)) return CTD_ERR_PLATFORM;

    WNDCLASSEXW surface = view;
    surface.lpfnWndProc = ctd_surface_proc;
    surface.lpszClassName = CTD_CLASS_SURFACE;
    if (!RegisterClassExW(&surface)) return CTD_ERR_PLATFORM;

    // Where a widget lives before it is added to anything. `CreateWindowEx`
    // refuses to make a WS_CHILD window with no parent, and cortado creates a
    // control before it knows where the control goes.
    g_limbo = CreateWindowExW(0, CTD_CLASS_VIEW, L"", WS_POPUP,
                              0, 0, 0, 0, NULL, NULL,
                              GetModuleHandleW(NULL), NULL);
    if (!g_limbo) return CTD_ERR_PLATFORM;

    g_started = 1;
    return CTD_OK;
}

ctd_status ctd_app_set_role(int32_t role) {
    if (role != CTD_ROLE_GUI && role != CTD_ROLE_ACCESSORY &&
        role != CTD_ROLE_HEADLESS) {
        return CTD_ERR_RANGE;
    }
    g_role = role;
    return CTD_OK;
}

ctd_status ctd_set_event_sink(ctd_event_fn sink, void *context) {
    g_sink = sink;
    g_sink_context = context;
    return CTD_OK;
}

void ctd_shutdown(void) {
    g_sink = NULL;
    g_sink_context = NULL;
}

// Whether the unbounded loop is the one that is running.
//
// PostQuitMessage does not stop a loop, it leaves a WM_QUIT on the queue — and
// a WM_QUIT nobody consumed would end the *next* GetMessage loop the instant it
// started. So it is posted only when there is a GetMessage loop to end, and a
// bounded run ends on its own flag instead.
static int g_in_run;

void ctd_app_run(void) {
    if (g_role == CTD_ROLE_HEADLESS) return;
    g_in_run = 1;
    g_running = 1;
    ctd_emit(CTD_EV_APP_LAUNCHED, 0, 0, 0);
    MSG message;
    while (g_running && GetMessageW(&message, NULL, 0, 0) > 0) {
        // Accelerators first, then dialog navigation: without the second, Tab
        // and the arrow keys do nothing between controls, because a plain
        // message loop never offers them to the control group.
        if (g_accelerators && g_accel_window &&
            TranslateAcceleratorW(g_accel_window, g_accelerators, &message)) {
            continue;
        }
        HWND root = GetAncestor(message.hwnd, GA_ROOT);
        if (root && IsDialogMessageW(root, &message)) continue;
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    g_in_run = 0;
}

// The same loop, with a deadline.
//
// PeekMessage rather than GetMessage, because GetMessage does not return until
// there is a message and this call has to give up when the time is out.
// MsgWaitForMultipleObjects is what keeps that from being a spin: it sleeps
// until either a message arrives or the slice ends.
ctd_status ctd_app_run_for(double seconds) {
    if (!g_started) return CTD_ERR_STATE;
    if (!(seconds >= 0.0)) return CTD_ERR_RANGE;
    g_running = 1;
    ULONGLONG deadline = GetTickCount64() + (ULONGLONG)(seconds * 1000.0);
    MSG message;
    while (g_running) {
        ULONGLONG now = GetTickCount64();
        if (now >= deadline) break;
        DWORD remaining = (DWORD)(deadline - now);
        MsgWaitForMultipleObjects(0, NULL, FALSE, remaining < 10 ? remaining : 10,
                                  QS_ALLINPUT);
        while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) { g_running = 0; break; }
            // The same two steps the unbounded loop does before dispatching.
            // A bounded run is a real run: a program that waits for a frame
            // must not have its accelerators and its Tab key stop working for
            // as long as it waits.
            if (g_accelerators && g_accel_window &&
                TranslateAcceleratorW(g_accel_window, g_accelerators, &message)) {
                continue;
            }
            HWND root = GetAncestor(message.hwnd, GA_ROOT);
            if (root && IsDialogMessageW(root, &message)) continue;
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    g_running = 0;
    return CTD_OK;
}

void ctd_app_stop(void) {
    g_running = 0;
    if (g_in_run) PostQuitMessage(0);
}

void ctd_post(int64_t token) {
    // The one entry point that is safe off the UI thread, and PostMessage is
    // what makes that true: it puts a message on the target thread's queue and
    // returns, touching none of this file's state from the caller's thread.
    if (g_limbo) PostMessageW(g_limbo, CTD_WM_POST, 0, (LPARAM)token);
}

int32_t ctd_capability(int32_t capability) {
    switch (capability) {
        // Windows has no application-wide menu bar: a menu belongs to a
        // window, and `SetMenu` is a per-window call. That is the same answer
        // GTK4 gives, for a different reason, and it is exactly the
        // distinction the two capabilities were written for.
        case CTD_CAP_MENU_BAR:      return 0;
        case CTD_CAP_WINDOW_MENU:   return 1;
        case CTD_CAP_MULTI_SURFACE: return 1;
        case CTD_CAP_RESIZABLE:     return 1;
        case CTD_CAP_FILE_DIALOG:   return 1;
        case CTD_CAP_SNAPSHOT:      return 0;
        // Written out rather than left to the default, because "no GPU
        // host" is a decision this host is making and not a key nobody
        // has heard of. src/win32/gpu.c says what would have to land.
        case CTD_CAP_GPU:           return 0;
        case CTD_CAP_TOOLBAR:       return 1;
        // No popover. Every Windows application that has one makes a layered
        // top-level window, gives it a shadow and captures the mouse to
        // dismiss it — which is cortado drawing a control.
        case CTD_CAP_POPOVER:       return 0;
        default:                    return 0;
    }
}
