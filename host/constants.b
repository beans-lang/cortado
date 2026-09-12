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

pub const ABI_VERSION: int = 11

// ---- statuses ----

pub const OK: int = 0
pub const ERR_STALE: int = -1
pub const ERR_KIND: int = -2
pub const ERR_PLATFORM: int = -3
pub const ERR_THREAD: int = -4
pub const ERR_UNSUPPORTED: int = -5
pub const ERR_RANGE: int = -6
pub const ERR_ABI: int = -7
pub const ERR_STATE: int = -8

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
pub const EV_COMMAND: int = 22
pub const EV_FRAME: int = 23
pub const EV_ANIM_DONE: int = 24

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
pub const CAP_GPU: int = 7

// ---- widget kinds ----

pub const W_CONTAINER: int = 0
pub const W_LABEL: int = 1
pub const W_BUTTON: int = 2
pub const W_TEXT_FIELD: int = 3
pub const W_CHECK_BOX: int = 4
pub const W_IMAGE_VIEW: int = 5
pub const W_SLIDER: int = 6
pub const W_PROGRESS_BAR: int = 7
pub const W_SEPARATOR: int = 8
pub const W_TEXT_AREA: int = 9
pub const W_COMBO_BOX: int = 10
pub const W_SCROLL_VIEW: int = 11
pub const W_RADIO_BUTTON: int = 12
pub const W_CANVAS: int = 13
pub const W_SWITCH: int = 14
pub const W_SECURE_FIELD: int = 15
pub const W_STEPPER: int = 16
pub const W_LEVEL_INDICATOR: int = 17
pub const W_TABLE: int = 18
pub const W_SEARCH_FIELD: int = 19
pub const W_SPINNER: int = 20

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
pub const P_STEP: int = 10
pub const P_SELECTED: int = 11
pub const P_INDETERMINATE: int = 12
pub const P_OPACITY: int = 13
pub const P_ANIMATING: int = 14
pub const S_HINT: int = 1

// ---- animation curves ----

pub const CURVE_LINEAR: int = 0
pub const CURVE_EASE_IN: int = 1
pub const CURVE_EASE_OUT: int = 2
pub const CURVE_EASE_IN_OUT: int = 3

// Menu command roles. The platform places, names and keys a command that has
// one; a command with no role goes where the application puts it.
pub const CMD_NONE: int = 0
pub const CMD_ABOUT: int = 1
pub const CMD_PREFERENCES: int = 2
pub const CMD_QUIT: int = 3
pub const CMD_HIDE: int = 4
pub const CMD_UNDO: int = 5
pub const CMD_REDO: int = 6
pub const CMD_CUT: int = 7
pub const CMD_COPY: int = 8
pub const CMD_PASTE: int = 9
pub const CMD_SELECT_ALL: int = 10
pub const CMD_CLOSE: int = 11
pub const CMD_MINIMIZE: int = 12
pub const CMD_FULLSCREEN: int = 13

// Dialog kinds. Every one is asynchronous: the answer arrives as an event
// carrying the token the request was made with.
pub const DLG_MESSAGE: int = 0
pub const DLG_CONFIRM: int = 1
pub const DLG_OPEN: int = 2
pub const DLG_SAVE: int = 3

// The system's own fonts, by role, so a program never hard-codes a family that
// is wrong on three platforms out of four.
pub const FONT_BODY: int = 0
pub const FONT_HEADING: int = 1
pub const FONT_CAPTION: int = 2
pub const FONT_MONO: int = 3

// ---- the GPU ----
//
// Which shading languages this host accepts, as bits. Three languages and no
// translation between them: see "the GPU" in the header for why that is the
// honest answer rather than a portability failure.
pub const SHADER_MSL: int = 1
pub const SHADER_HLSL: int = 2
pub const SHADER_SPIRV: int = 4
pub const SHADER_GLSL: int = 8

// What a device can be asked about itself.
pub const GPU_UNIFIED_MEMORY: int = 1
pub const GPU_MAX_BUFFER_BYTES: int = 2
pub const GPU_MEMORY_BYTES: int = 3

// How a drawn pixel is mixed with the one already there. Three named modes
// rather than a pair of blend factors: every backend has these three and means
// the same by them, and a factor pair is eight enums to get right in a
// combination nothing checks.
pub const BLEND_REPLACE: int = 0
pub const BLEND_ALPHA: int = 1
pub const BLEND_ADD: int = 2

// What a draw call makes out of its vertices.
pub const SHAPE_TRIANGLES: int = 0
pub const SHAPE_TRIANGLE_STRIP: int = 1
pub const SHAPE_LINES: int = 2
pub const SHAPE_LINE_STRIP: int = 3
pub const SHAPE_POINTS: int = 4

// Which pixels a pipeline writes: an off-screen target's 8-bit RGBA, or
// whatever this platform's compositor shows a canvas in.
pub const PIXELS_RGBA8: int = 0
pub const PIXELS_SCREEN: int = 1
