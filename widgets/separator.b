// A line between things.
package widgets
import cortado.render

/// A rule that divides one group of controls from another.
///
/// It carries no state and answers nothing, and it is a control rather than a
/// drawing for one reason: the platform decides what a divider looks like, and
/// it is not the same on any two of them. A line cortado drew would be right
/// on the machine it was tuned on and subtly wrong everywhere else, and would
/// not follow the system appearance when it changed.
pub class Separator extends Widget {
    pub fn init(context: Option<render.UiContext> = none) {
        super.init(WidgetKind.separator, context)
    }
}
