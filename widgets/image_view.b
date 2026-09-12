// A picture.
package widgets

import cortado.host

/// A view that shows an image.
///
/// What it can show today is a **system icon** — one of the platform's own,
/// named by role rather than by the platform's name for it. That is the half
/// of "a picture" that is portable: every platform here ships an icon set,
/// and a person already knows what their system's "warning" looks like.
///
/// A picture of your own is a different problem — file formats, scale
/// factors, colour spaces — and `cortado.image` is where it will go.
pub class ImageView extends Widget {
    pub fn init() {
        super.init(WidgetKind.image_view)
    }

    pub static fn of(icon: SystemIcon) -> Result<ImageView> {
        var view: ImageView = new ImageView()
        view.set_icon(icon)?
        return ok(view)
    }

    /// The system icon this view shows, or `SystemIcon.none` for none.
    ///
    /// Refused with `out_of_range` where this platform has no icon for the
    /// role, rather than quietly leaving the view blank — ask
    /// `SystemIcon.available()` first and show a word when the answer is no.
    pub fn set_icon(icon: SystemIcon) -> Result<bool> {
        return self.set_property(host.P_ICON, icon.code())
    }

    pub fn icon() -> Result<SystemIcon> {
        return ok(SystemIcon.of(self.read_property(host.P_ICON)?))
    }
}
