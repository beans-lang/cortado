// Alerts and file choosers, every one of them asynchronous.

#include "internal.h"

typedef struct {
    int64_t token;
    int32_t kind;
    HWND    parent;
    WCHAR  *title;
    WCHAR  *body;
} CtdDialogRequest;

void ctd_run_dialog(void *data) {
    CtdDialogRequest *request = (CtdDialogRequest *)data;
    int64_t index = 0;
    WCHAR path[MAX_PATH];
    path[0] = 0;

    int visible = request->parent && IsWindowVisible(request->parent);
    if (g_role == CTD_ROLE_HEADLESS || !visible) {
        // With nothing on screen to attach to, a dialog answers its default
        // rather than putting a window somewhere nobody asked for. The contract
        // that matters is that **a dialog always answers**: a caller waiting on
        // a token that never arrives is worse than an answer it can see.
        index = (request->kind == CTD_DLG_MESSAGE ||
                 request->kind == CTD_DLG_CONFIRM) ? 0 : 1;
    } else if (request->kind == CTD_DLG_MESSAGE || request->kind == CTD_DLG_CONFIRM) {
        UINT buttons = request->kind == CTD_DLG_CONFIRM ? MB_OKCANCEL : MB_OK;
        int answer = MessageBoxW(request->parent, request->body, request->title,
                                 buttons | MB_ICONINFORMATION);
        index = answer == IDCANCEL ? 1 : 0;
    } else {
        OPENFILENAMEW chooser;
        memset(&chooser, 0, sizeof chooser);
        chooser.lStructSize = sizeof chooser;
        chooser.hwndOwner = request->parent;
        chooser.lpstrFile = path;
        chooser.nMaxFile = MAX_PATH;
        chooser.lpstrTitle = request->title;
        chooser.Flags = OFN_EXPLORER | OFN_NOCHANGEDIR |
                        (request->kind == CTD_DLG_OPEN ? OFN_FILEMUSTEXIST
                                                       : OFN_OVERWRITEPROMPT);
        BOOL chose = request->kind == CTD_DLG_OPEN ? GetOpenFileNameW(&chooser)
                                                   : GetSaveFileNameW(&chooser);
        index = chose ? 0 : 1;
        if (!chose) path[0] = 0;
    }

    if (g_sink) {
        char *text = NULL;
        int32_t text_len = 0;
        if (path[0]) {
            int needed = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
            if (needed > 1) {
                text = (char *)malloc((size_t)needed);
                if (text) {
                    WideCharToMultiByte(CP_UTF8, 0, path, -1, text, needed, NULL, NULL);
                    text_len = needed - 1;
                }
            }
        }
        ctd_event event;
        memset(&event, 0, sizeof event);
        event.kind = CTD_EV_POST;
        event.token = request->token;
        event.index = index;
        event.text = text;
        event.text_len = text_len;
        g_sink(g_sink_context, &event);
        free(text);
    }
    free(request->title);
    free(request->body);
    free(request);
}

ctd_status ctd_dialog_open(ctd_handle parent, int32_t kind,
                           const char *title, int32_t title_len,
                           const char *body, int32_t body_len,
                           int64_t token) {
    if (kind < CTD_DLG_MESSAGE || kind > CTD_DLG_SAVE) return CTD_ERR_RANGE;
    HWND owner = NULL;
    if (parent) {
        ctd_status problem;
        owner = ctd_surface_window(parent, &problem);
        if (!owner) return problem;
    }
    CtdDialogRequest *request =
        (CtdDialogRequest *)calloc(1, sizeof(CtdDialogRequest));
    if (!request) return CTD_ERR_PLATFORM;
    request->token = token;
    request->kind = kind;
    request->parent = owner;
    request->title = ctd_wide(title, title_len);
    request->body = ctd_wide(body, body_len);
    if (!request->title || !request->body) {
        free(request->title); free(request->body); free(request);
        return CTD_ERR_PLATFORM;
    }
    // Posted, not run here. `MessageBox` and the file choosers each run a loop
    // of their own, and running one inside this call would re-enter everything
    // above it — including the render the call came out of.
    if (g_role == CTD_ROLE_HEADLESS || !g_limbo) {
        ctd_run_dialog(request);
        return CTD_OK;
    }
    PostMessageW(g_limbo, CTD_WM_DIALOG, 0, (LPARAM)request);
    return CTD_OK;
}
