// One page at a time, with a strip of labels to choose it.
package widgets

import cortado.host

/// A tab view.
///
/// `NSTabView`, `GtkNotebook`, `SysTabControl32` — and **not on every
/// platform**: UIKit has no tab *view*. `UITabBarController` is a view
/// controller that owns the whole screen rather than a control that goes into
/// a layout, and a segmented control with a container under it would be
/// cortado assembling a substitute out of two kinds the caller already has.
/// On a phone that arrangement is the right one to build by hand, and this
/// class refuses with `no_such_control` rather than pretending to be it.
///
/// **Its children are its pages**, one each, in order. That is what makes the
/// tree a program builds and the tree a screen reader walks the same tree, and
/// it means a page is an ordinary container laid out by the same solver.
///
/// The labels are not children: a page is a container, and containers have no
/// text on any platform cortado targets. `set_label` names one by index, the
/// same shape a table's column titles use.
pub class TabView extends ChildHolder {
    /// Hide the native strip and border when an external control selects pages.
    pub fn set_borderless(on: bool) -> Result<bool> {
        return self.set_property(host.P_BORDERLESS, if on { 1 } else { 0 })
    }

    pub fn init() {
        super.init(WidgetKind.tab_view)
    }

    pub static fn of() -> Result<TabView> {
        WidgetKind.tab_view.demand()?
        return ok(new TabView())
    }

    /// Adds a page with a label on its tab.
    ///
    /// The label is written after the page is added, because a tab view has
    /// exactly as many tabs as it has children and it is adding the child that
    /// makes the tab.
    pub fn add_page(page: Widget, label: string) -> Result<bool> {
        let at: int = self.count()
        self.add(page)?
        return self.set_label(at, label)
    }

    pub fn set_label(index: int, label: string) -> Result<bool> {
        let bytes: Bytes = host.HostText.encode(label, "name a tab")?
        unsafe {
            return host.check(
                host.ctd_tab_set_label(self.handle().raw, index as i32,
                                       host.HostText.pointer(bytes),
                                       bytes.len() as i32) as int,
                "name tab {index}")
        }
    }

    pub fn label(index: int) -> Result<string> {
        unsafe {
            return host.HostText.read("read the label of tab {index}",
                fn(out: RawPtr<i8>, cap: i32) -> i32 {
                    return host.ctd_tab_label(self.handle().raw, index as i32, out, cap)
                })
        }
    }

    /// Which page is showing.
    pub fn set_page(index: int) -> Result<bool> {
        return self.set_property(host.P_SELECTED, index)
    }

    pub fn page() -> Result<int> {
        return self.read_property(host.P_SELECTED)
    }
}
