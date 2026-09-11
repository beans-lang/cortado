// Somewhere a program draws for itself.
package widgets

/// A control whose contents a program paints on the GPU.
///
/// Every other widget in cortado is the platform's: a `Button` is an
/// `NSButton`, and what it looks like is the operating system's business. A
/// canvas is the opposite — an area the platform lays out and shows, and
/// nothing else. A chart with fifty thousand points, a waveform, a map, a
/// game: none of those is a tree of controls, and a canvas is where they go.
///
/// It is a control on every host, laid out by the same solver and named in
/// `tests/roles.out` like any other. On a host with no GPU it is an empty
/// area rather than a missing one, which is the right shape for a control
/// whose contents were never the platform's to draw.
///
/// `gpu.Canvas` is what fills it. This class is deliberately only the control:
/// `cortado.widgets` does not import `cortado.gpu`, so a program that draws
/// nothing on the GPU still gets the widget, and the layering stays one way.
pub class Canvas extends Widget {
    pub fn init() {
        super.init(WidgetKind.canvas)
    }
}
