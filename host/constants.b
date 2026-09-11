// The header's `#define`s, restated.
//
// `beansc bindgen` reads declarations, not the preprocessor, so every constant
// in cortado_host.h is invisible to the generated binding and has to live
// here. Hand-copied values go stale silently, so `tools/check_constants.sh`
// reads both files and fails the build when a number here stops matching the
// header.
//
// These are the raw ABI numbers. Nothing outside this package should name
// them: the widget kinds surface as `widgets.WidgetKind`, the statuses as
// `host.HostStatus`, and the capabilities as `platform.Capability`.
package host

pub const ABI_VERSION: int = 1

// ---- statuses ----

pub const OK: int = 0
pub const ERR_STALE: int = -1
pub const ERR_KIND: int = -2
pub const ERR_PLATFORM: int = -3
pub const ERR_THREAD: int = -4
pub const ERR_UNSUPPORTED: int = -5
pub const ERR_RANGE: int = -6
pub const ERR_ABI: int = -7

// ---- event kinds ----

pub const EV_ACTIVATE: int = 1
pub const EV_VALUE_CHANGED: int = 2
pub const EV_TEXT_COMMIT: int = 3
pub const EV_SELECTION: int = 4
pub const EV_POINTER_DOWN: int = 5
pub const EV_POINTER_UP: int = 6
pub const EV_POINTER_MOVE: int = 7
pub const EV_KEY_DOWN: int = 8
pub const EV_KEY_UP: int = 9
pub const EV_FOCUS: int = 10
pub const EV_BLUR: int = 11
pub const EV_SURFACE_RESIZED: int = 12
pub const EV_SURFACE_CLOSE: int = 13
pub const EV_APPEARANCE: int = 14
pub const EV_SCALE_CHANGED: int = 15
pub const EV_POST: int = 16
pub const EV_APP_LAUNCHED: int = 17
pub const EV_APP_FOREGROUND: int = 18
pub const EV_APP_BACKGROUND: int = 19
pub const EV_APP_WILL_QUIT: int = 20
pub const EV_LOW_MEMORY: int = 21

// ---- modifier bits ----

pub const MOD_SHIFT: int = 1
pub const MOD_CONTROL: int = 2
pub const MOD_ALT: int = 4
pub const MOD_COMMAND: int = 8

// ---- application roles ----

pub const ROLE_GUI: int = 0
pub const ROLE_ACCESSORY: int = 1
pub const ROLE_HEADLESS: int = 2

// ---- capabilities ----

pub const CAP_MENU_BAR: int = 1
pub const CAP_WINDOW_MENU: int = 2
pub const CAP_MULTI_SURFACE: int = 3
pub const CAP_RESIZABLE: int = 4
pub const CAP_FILE_DIALOG: int = 5
pub const CAP_SNAPSHOT: int = 6

// ---- widget kinds ----

pub const W_CONTAINER: int = 0
pub const W_LABEL: int = 1
pub const W_BUTTON: int = 2
pub const W_TEXT_FIELD: int = 3
pub const W_CHECK_BOX: int = 4
pub const W_IMAGE_VIEW: int = 5

// ---- property keys ----

pub const P_CHECKED: int = 1
pub const P_ENABLED: int = 2
pub const P_HIDDEN: int = 3
pub const P_MIN: int = 4
pub const P_MAX: int = 5
pub const P_VALUE: int = 6
pub const P_EDITABLE: int = 7
pub const P_ALIGNMENT: int = 8
pub const P_FONT_SIZE: int = 9
