// A window onto something bigger.
package widgets

/// A control that shows part of a larger subtree and scrolls the rest into
/// view.
///
/// It holds children the way a `Container` does, and the platform puts them
/// somewhere a caller never names: AppKit inside a document view, GTK inside a
/// viewport. Asking a caller to know which would be asking them to write
/// platform code in Beans, so the child calls reach through whatever the
/// platform wrapped and the tree above sees one control with children.
///
/// The scrolled content is laid out at whatever size the layout gives it,
/// which will usually be larger than the scroll view itself — that is the
/// point. A stack inside a scroll view with no height of its own will size to
/// its children and scroll; one told to stretch will fit and not scroll.
///
/// **It extends `ChildHolder` like every other box.** It used to carry its own
/// copy of the list, the ordering, the platform calls and the lifetime — sixty
/// lines that said the same thing — and the copy is how it ended up outside
/// the one downcast the component applier does: `<ScrollView>` with children
/// in markup was refused as a control that holds none. Two implementations of
/// one idea is how one of them gets left behind.
pub class ScrollView extends ChildHolder {
    pub fn init() {
        super.init(WidgetKind.scroll_view)
    }
}
