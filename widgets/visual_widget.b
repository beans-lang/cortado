package widgets

import cortado.render
import cortado.visual

/// A declarative drawing node inside a shared Canvas scene.
pub class VisualWidget extends Widget {
    pub fn init(kind: visual.Kind, context: render.UiContext) {
        super.init(WidgetKind.canvas, some(context), some(kind))
    }
}
