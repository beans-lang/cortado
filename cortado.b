// cortado — native desktop UI for Beans.
//
// A cortado program builds a tree of real operating-system controls. A
// `Button` is an `NSButton` on macOS, a `BUTTON` window class on Windows, a
// `GtkButton` on Linux — so the app inherits the platform's own text input,
// input methods, accessibility, keyboard conventions and dark mode rather than
// imitating them.
//
// The layers, bottom up:
//
//   cortado.host       the flat C ABI, and the only package that names it
//   cortado.geometry   points, sizes and rectangles; no platform, no state
//   cortado.platform   what this platform can and cannot do
//   cortado.events     what the user did
//   cortado.layout     where everything goes; pure arithmetic, no controls
//   cortado.widgets    the controls themselves
//   cortado.motion     the frame clock, and animation
//   cortado.surface    windows, menus and dialogs
//   cortado.component  the retained tree that .bx markup renders into
//
// This file stays thin on purpose. A package under a module may not import its
// own module root, so anything shared has to live in a leaf package that the
// root imports rather than in the root itself.
package cortado

/// The version of cortado this build is. Reported by `beansc`-built binaries
/// and by the test suite, so a bug report names something checkable.
pub fn version() -> string {
    return "0.1.0"
}
