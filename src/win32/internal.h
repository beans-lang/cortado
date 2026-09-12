// What the Windows host's translation units share, and nothing else does.
//
// `cortado_host.h` is the contract every platform implements. This is the
// opposite: private to this one platform, naming Win32 types freely, included
// by no other host and seen by no Beans file.
//
// ## There is no object system here
//
// A control is an `HWND`. Its state is set by sending it a message and it
// reports what happened by sending a message back to its **parent** — a button
// click is a `WM_COMMAND` to the parent with the child's `HWND` in `lParam`, a
// trackbar move is a `WM_HSCROLL`. So the window procedure in app.c is where
// every event is born, and it looks the sender up in the handle table to find
// out what it was.
//
// ## Text
//
// Windows is UTF-16 and this ABI is UTF-8, so every string crosses a
// conversion. The `W` entry points are used everywhere — the `A` ones would
// silently mangle anything outside the active code page, which is exactly the
// class of bug the ABI's "UTF-8 with an explicit length" rule exists to
// prevent.
#ifndef CORTADO_WIN32_INTERNAL_H
#define CORTADO_WIN32_INTERNAL_H

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef WINVER
#define WINVER 0x0A00
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <commdlg.h>
// ShellExecuteW, which is how a link is followed: see ctd_link_target.
#include <shellapi.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "../cortado_host.h"
#include "../cortado_rules.h"

enum { CTD_SLOTS = 8192 };

#define CTD_INNER L"cortado-inner"
#define CTD_TAG   L"cortado"
#define CTD_WM_DIALOG (WM_APP + 2)
// What a slot holds. A handle names a widget, a surface or a menu, and the
// three are not interchangeable: asking a menu for its frame has to be
// CTD_ERR_KIND and not a cast.
enum { CTD_T_FREE = 0, CTD_T_WIDGET, CTD_T_SURFACE, CTD_T_MENU, CTD_T_ANIM };
// Win32 overloads a combo box's window height: the number passed to
// `CreateWindow` or `MoveWindow` is how tall the control is *with its list
// dropped down*, not how tall it looks closed. Every other platform means the
// closed height, and so does cortado, so the room for the list is added on the
// way in and taken off on the way out.
enum { CTD_COMBO_DROP = 160 };
// Font sizes already made, so a second control asking for the same size gets
// the same HFONT rather than another GDI object. Fonts are a limited resource
// on Windows in a way they are not elsewhere.
enum { CTD_FONT_CACHE = 32 };

// The frame clock's timer on a surface window, and how often it fires. Named
// here because the clock sets it and the window procedure receives it.
enum { CTD_CLOCK_TIMER = 0x0C10, CTD_CLOCK_PERIOD = 16 };
// How often an animation is stepped, in milliseconds — about sixty times a
// second, the same beat as the frame clock and for the same reason.
enum { CTD_ANIM_PERIOD = 16 };

typedef struct CtdMenu CtdMenu;

// A menu item's token and its portable shortcut, kept beside the HMENU. Win32
// can be asked for an item's display string but not for the spelling the
// caller used, and the display string carries the accelerator baked into it
// after a tab, so reading one back would answer something nobody wrote.
typedef struct {
    int64_t token;
    char   *title;      // UTF-8, as the platform ended up showing it
    char   *key;        // the portable spelling: "mod+z"
    int32_t role;
    int     separator;
    int     enabled;
    UINT    id;         // the 16-bit WM_COMMAND id, 0 for a separator
} CtdCommand;

struct CtdMenu {
    HMENU       handle;
    CtdCommand *commands;
    int32_t     count;
    int32_t     capacity;
    char       *title;
};

// Win32 identifies a menu item by a 16-bit number in WM_COMMAND, and cortado's
// token is 64 bits and the application's own, so the two are kept in a table.
typedef struct {
    UINT       id;
    ctd_handle menu;
    int64_t    token;
} CtdMenuId;

extern HACCEL g_accelerators;
extern HFONT g_ui_font;
extern HWND g_accel_window;
extern HWND g_limbo;
extern const WCHAR *CTD_CLASS_SURFACE;
extern const WCHAR *CTD_CLASS_VIEW;
extern ctd_event_fn g_sink;
extern double g_progress_max[CTD_SLOTS];
// And the value. A progress bar's position is an int in a fixed 0..10000 span,
// so a value put in and taken out comes back rounded. The whole triple is
// cortado's data here, as min and max already were.
extern double g_progress_value[CTD_SLOTS];
// A stepper's range, kept here because an up-down control counts in whole
// numbers and cortado's range is real. The control holds a tick index and
// these three turn it back into the number the caller asked about.
extern double g_step_min[CTD_SLOTS];
extern double g_step_max[CTD_SLOTS];
extern double g_step_size[CTD_SLOTS];
// The number a stepper is showing, and the tick range that produces it.
double ctd_stepper_value(HWND view, uint32_t slot);
void   ctd_stepper_range(HWND view, uint32_t slot);
ctd_status ctd_stepper_set(HWND view, uint32_t slot, double value);
extern double g_progress_min[CTD_SLOTS];
extern int g_running;
extern int g_started;
extern int32_t g_kind[CTD_SLOTS];
extern int32_t g_role;
extern int32_t g_type[CTD_SLOTS];
extern uint32_t g_generation[CTD_SLOTS];
extern uint32_t g_used;
extern void *g_object[CTD_SLOTS];
extern void *g_sink_context;

BOOL ctd_is_ours(HWND window);
CtdCommand *ctd_command_by_id(UINT id);
HWND ctd_surface_window(ctd_handle handle, ctd_status *problem);
HWND ctd_window(ctd_handle handle);
LRESULT CALLBACK ctd_edit_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR id, DWORD_PTR data);
WCHAR *ctd_wide(const char *utf8, int32_t len);
const CtdMenuId *ctd_menu_id(UINT id);
ctd_handle ctd_handle_of(HWND window);
ctd_handle ctd_track(void *object, int32_t type, int32_t kind);
int ctd_dispatch_editing(int32_t role);
int ctd_has_nul(const char *utf8, int32_t len);
int32_t ctd_copy_out(const char *text, char *out, int32_t cap);
int32_t ctd_copy_wide_out(const WCHAR *text, char *out, int32_t cap);
int32_t ctd_slot_kind(ctd_handle handle);
int32_t ctd_window_text_out(HWND window, char *out, int32_t cap);
uint32_t ctd_slot(ctd_handle handle);
void ctd_emit(uint32_t kind, ctd_handle target, int64_t index, int64_t token);
// A list view asking for a cell it is about to paint, and a selection that
// moved. Both arrive as WM_NOTIFY on the *parent*, which is where every Win32
// control reports, so app.c routes them here.
// A SysLink's two halves: the words it shows and where it goes. The control
// holds them as one markup string, so they are kept apart in property.c and
// composed on every write.
ctd_status ctd_link_set_words(ctd_handle widget, HWND view, const char *utf8, int32_t len);
int32_t ctd_link_words_out(ctd_handle widget, char *out, int32_t cap);
const WCHAR *ctd_link_target(ctd_handle widget);
void ctd_table_disp_info(NMLVDISPINFOW *info);
void ctd_table_item_changed(NMLISTVIEW *info);
void ctd_emit_control(ctd_handle target);
void ctd_give_back(uint32_t slot);
// WM_TIMER on a surface, handed to the frame clock. Declared here because the
// window procedure is what receives it and the clock is what knows what it is.
void ctd_clock_ticked(HWND window);
// Forgets the clock a slot may have had, before the slot is handed out again.
void ctd_clock_forget(uint32_t slot);
// Ends whatever a slot had to do with an animation, before it is handed out
// again: the animation it *was*, and any animation of the control it held.
void ctd_anim_forget(uint32_t slot);
// Where a property is going while an animation moves it. A control keeps one
// value per property and Core Animation keeps two, so this is the second one —
// see the model and presentation paragraph beside ctd_anim_start in the header.
int ctd_anim_destination(ctd_handle widget, int32_t property, double *out);
void ctd_untrack(ctd_handle handle);
void ctd_run_dialog(void *data);

#endif
