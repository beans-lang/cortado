// A plain box with children and no appearance of its own.
package widgets

import cortado.render

/// A box with no appearance of its own.
///
/// The layout container almost every screen is made of. Everything about
/// holding children is in `ChildHolder`; this is that, built as `CTD_W_CONTAINER`.
pub class Container extends ChildHolder {
    pub fn init(context: Option<render.UiContext> = none) {
        super.init(WidgetKind.container, context)
    }
}
