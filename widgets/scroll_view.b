// A window onto something bigger.
package widgets

/// A control that shows part of a larger subtree and scrolls the rest into
/// view.
///
/// It holds children the way a `Container` does, and the platform puts them
/// somewhere a caller never names: AppKit inside a document view, GTK inside a
/// viewport. Asking a caller to know which would be asking them to write
/// platform code in Beans, so `add` reaches through whatever the platform
/// wrapped and the tree above sees one control with children.
///
/// The scrolled content is laid out at whatever size the layout gives it,
/// which will usually be larger than the scroll view itself — that is the
/// point. A stack inside a scroll view with no height of its own will size to
/// its children and scroll; one told to stretch will fit and not scroll.
pub class ScrollView extends Widget implements Holder {
    contents: List<Widget> = []

    pub fn init() {
        super.init(WidgetKind.scroll_view)
    }

    pub override fn children() -> List<Widget> {
        var copy: List<Widget> = []
        for child: Widget in self.contents {
            copy.push(child)
        }
        return move copy
    }

    pub fn count() -> int {
        return self.contents.len()
    }

    pub fn child_at(index: int) -> Option<Widget> {
        if index < 0 || index >= self.contents.len() {
            return none
        }
        return some(self.contents[index])
    }

    pub fn add(child: Widget) -> Result<bool> {
        return self.insert(child, self.contents.len())
    }

    pub fn insert(child: Widget, index: int) -> Result<bool> {
        if index < 0 || index > self.contents.len() {
            return err("cannot put a child at {index} of a scroll view holding {self.contents.len()}",
                       "range")
        }
        self.attach_child(child, index)?
        self.contents.insert(index, child)
        return ok(true)
    }

    /// Moves the child at `from` to `to`, in one host call — the same
    /// contract a `Container` holds, and for the same reason: remove and
    /// re-insert is not equivalent on any platform cortado targets.
    pub fn move_child(from: int, to: int) -> Result<bool> {
        let count: int = self.contents.len()
        if from < 0 || from >= count || to < 0 || to >= count {
            return err("cannot move child {from} to {to}: this scroll view has {count} children",
                       "range")
        }
        if from == to {
            return ok(true)
        }
        self.reorder_child(from, to)?
        let moving: Widget = self.contents[from]
        self.contents.remove(from)
        self.contents.insert(to, moving)
        return ok(true)
    }

    pub fn remove(index: int) -> Result<bool> {
        if index < 0 || index >= self.contents.len() {
            return err("cannot remove child {index} of a scroll view holding {self.contents.len()}",
                       "range")
        }
        let going: Widget = self.contents[index]
        self.detach_child(going)?
        self.contents.remove(index)
        return ok(true)
    }
}
