// A few choices, all of them on screen.
package widgets

import cortado.host
import cortado.render

/// A segmented control.
///
/// `NSSegmentedControl` and `UISegmentedControl` are real controls; **GTK and
/// the Win32 common controls have none**, and cortado refuses rather than
/// building a row of toggle buttons that looks like one. A row of toggles is
/// not a segmented control: nothing keeps exactly one of them down, so it can
/// be all-off or all-on, and a program that relied on "one is always chosen"
/// would be wrong in a way the user can see.
///
/// The choices are the item list — the same one a `ComboBox` uses, because "a
/// list of choices" is one idea and a caller should not have to know which
/// control it landed in. `select` and `selected` are the index.
pub class Segmented extends Widget {
    pub fn init(context: Option<render.UiContext> = none) {
        super.init(WidgetKind.segmented, context)
    }

    pub static fn of(choices: List<string>) -> Result<Segmented> {
        WidgetKind.segmented.demand()?
        var bar: Segmented = new Segmented()
        bar.set_items(choices)?
        return ok(bar)
    }

    /// Replaces every choice.
    pub fn set_items(choices: List<string>) -> Result<bool> {
        if self.is_rendered() {
            let choice: render.SegmentedRender = (self.render_object()? as? render.SegmentedRender).expect("shared segmented control")
            return choice.replace_items(choices)
        }
        unsafe {
            host.check(host.ctd_items_clear(self.handle().raw) as int,
                       "clear a segmented control")?
        }
        for choice: string in choices {
            self.add_item(choice)?
        }
        return ok(true)
    }

    pub fn add_item(text: string) -> Result<bool> {
        if self.is_rendered() {
            let choice: render.SegmentedRender = (self.render_object()? as? render.SegmentedRender).expect("shared segmented control")
            return choice.add_item(text)
        }
        let buffer: Bytes = host.HostText.encode(text, "add a segment")?
        unsafe {
            return host.check(
                host.ctd_items_add(self.handle().raw, host.HostText.pointer(buffer),
                                   buffer.len() as i32) as int,
                "add a segment")
        }
    }

    pub fn count() -> Result<int> {
        if self.is_rendered() {
            let choice: render.SegmentedRender = (self.render_object()? as? render.SegmentedRender).expect("shared segmented control")
            return ok(choice.count())
        }
        let scratch: host.HostScratch = host.HostScratch.instance
        var found: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_items_count(self.handle().raw, slot) as int,
                       "count a segmented control's choices")?
            found = slot.read()
        }
        return ok(found as int)
    }

    pub fn item_at(index: int) -> Result<string> {
        if self.is_rendered() {
            let choice: render.SegmentedRender = (self.render_object()? as? render.SegmentedRender).expect("shared segmented control")
            return choice.item_at(index)
        }
        let raw: u64 = self.handle().raw
        return host.HostText.read("read a segment's words",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_items_at(raw, index as i32, out, cap) }
            })
    }

    /// Which one is chosen, or -1 for none.
    pub fn selected() -> Result<int> {
        return self.read_property(host.P_SELECTED)
    }

    /// Choose one, or -1 for none.
    pub fn select(index: int) -> Result<bool> {
        return self.set_property(host.P_SELECTED, index)
    }

    pub override fn display_text() -> Result<string> {
        let at: int = self.selected().or(-1)
        if at < 0 { return ok("") }
        return self.item_at(at)
    }
}
