// One page at a time, with a strip of labels to choose it.
package widgets

import cortado.host
import cortado.render

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
    labels_value: List<string> = []
    labels_explicit: bool = false
    pending_page: int = 0
    /// Hide the native strip and border when an external control selects pages.
    pub fn set_borderless(on: bool) -> Result<bool> {
        return self.set_property(host.P_BORDERLESS, if on { 1 } else { 0 })
    }

    pub fn init(context: Option<render.UiContext> = none) {
        super.init(WidgetKind.tab_view, context)
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

    /// Typed labels can be written before markup creates the page widgets.
    pub fn set_labels(labels: List<string>) -> Result<bool> {
        if !self.is_alive() { return err("tab view has been released", "stale_handle") }
        var copy: List<string> = []
        for label: string in labels { copy.push(label) }
        self.labels_value = move copy
        self.labels_explicit = true
        if self.is_rendered() {
            let tabs: render.TabViewRender = (self.render_object()? as? render.TabViewRender).expect("shared tab view")
            return tabs.set_labels(labels)
        }
        return self.refresh_labels()
    }

    fn refresh_labels() -> Result<bool> {
        if self.is_rendered() { return ok(true) }
        let limit: int = if self.count() < self.labels_value.len() { self.count() } else { self.labels_value.len() }
        for index: int in 0..limit { self.set_label(index, self.labels_value[index])? }
        return ok(true)
    }

    pub override fn insert(child: Widget, index: int) -> Result<bool> {
        super.insert(child, index)?
        self.refresh_labels()?
        if !self.is_rendered() && self.pending_page >= 0 && self.pending_page < self.count() {
            self.set_property(host.P_SELECTED, self.pending_page)?
        }
        return ok(true)
    }

    pub override fn remove(index: int) -> Result<bool> {
        super.remove(index)?
        return self.refresh_labels()
    }

    pub override fn move_child(from: int, to: int) -> Result<bool> {
        super.move_child(from, to)?
        return self.refresh_labels()
    }

    pub fn validate_pages() -> Result<bool> {
        if self.count() > 0 && self.pending_page >= self.count() {
            return err("selected tab is outside the pages", "out_of_range")
        }
        if self.labels_explicit && self.labels_value.len() != self.count() {
            return err("tab labels must match page count", "out_of_range")
        }
        return ok(true)
    }

    pub fn set_label(index: int, label: string) -> Result<bool> {
        if self.is_rendered() {
            let tabs: render.TabViewRender = (self.render_object()? as? render.TabViewRender).expect("shared tab view")
            return tabs.set_label(index, label)
        }
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
        if self.is_rendered() {
            let tabs: render.TabViewRender = (self.render_object()? as? render.TabViewRender).expect("shared tab view")
            return tabs.label(index)
        }
        unsafe {
            return host.HostText.read("read the label of tab {index}",
                fn(out: RawPtr<i8>, cap: i32) -> i32 {
                    return host.ctd_tab_label(self.handle().raw, index as i32, out, cap)
                })
        }
    }

    /// Which page is showing.
    pub fn set_page(index: int) -> Result<bool> {
        if !self.is_alive() { return err("tab view has been released", "stale_handle") }
        if index < 0 { return err("selected tab is outside the pages", "out_of_range") }
        if self.count() > 0 && index >= self.count() { return err("selected tab is outside the pages", "out_of_range") }
        return self.set_page_from_markup(index)
    }

    /// Markup writes selected before it adds or removes pages. The finished
    /// tree is checked by WidgetMaker and Applier after those edits.
    pub fn set_page_from_markup(index: int) -> Result<bool> {
        if !self.is_alive() { return err("tab view has been released", "stale_handle") }
        if index < 0 { return err("selected tab is outside the pages", "out_of_range") }
        self.pending_page = index
        if !self.is_rendered() && index >= self.count() { return ok(true) }
        return self.set_property(host.P_SELECTED, index)
    }

    pub fn page() -> Result<int> {
        if !self.is_rendered() && self.pending_page >= self.count() { return ok(self.pending_page) }
        return self.read_property(host.P_SELECTED)
    }
}
