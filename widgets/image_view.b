// A picture.
package widgets

/// A view that shows an image.
///
/// It carries no image yet — `cortado.image` arrives with the rest of the
/// widget shelf. What exists today is the view itself, so layout, the tree and
/// the accessibility role can be exercised against a real native image view
/// rather than against a placeholder that behaves differently.
pub class ImageView extends Widget {
    pub fn init() {
        super.init(WidgetKind.image_view)
    }
}
