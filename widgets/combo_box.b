// A choice from a list.
package widgets

import cortado.host
import cortado.render

/// A control that shows one of several choices and lets the user pick another.
///
/// The items are replaced wholesale rather than patched, and that is a
/// decision rather than a shortcut. A list of choices is almost always rebuilt
/// from whatever the program is showing, and an insert-and-move API would mean
/// a second reconciler — with its own bugs — for a control whose contents are
/// strings. When a list is long enough that rebuilding it shows, the answer is
/// a control with a data source, not a diffed item list.
///
/// The selection is an **index**, not the text. Two items may legitimately
/// read the same, and a selection by text could not tell them apart.
pub class ComboBox extends Widget {
    pub fn init(context: Option<render.UiContext> = none) {
        super.init(WidgetKind.combo_box, context)
    }

    pub static fn of(items: List<string>) -> Result<ComboBox> {
        var control: ComboBox = new ComboBox()
        control.set_items(items)?
        return ok(control)
    }

    /// Replaces every item. The selection afterwards is the first item, or
    /// none when the list is empty.
    pub fn set_items(items: List<string>) -> Result<bool> {
        if self.is_rendered() {
            let choice: render.ComboBoxRender = (self.render_object()? as? render.ComboBoxRender).expect("shared combo box")
            return choice.replace_items(items)
        }
        unsafe {
            host.check(host.ctd_items_clear(self.slot.raw) as int,
                       "empty a combo box")?
        }
        for item: string in items {
            self.add_item(item)?
        }
        return ok(true)
    }

    pub fn add_item(text: string) -> Result<bool> {
        if self.is_rendered() {
            let choice: render.ComboBoxRender = (self.render_object()? as? render.ComboBoxRender).expect("shared combo box")
            return choice.add_item(text)
        }
        let buffer: Bytes = host.HostText.encode(text, "add an item to a combo box")?
        unsafe {
            return host.check(
                host.ctd_items_add(self.slot.raw, host.HostText.pointer(buffer),
                                   buffer.len() as i32) as int,
                "add an item to a combo box")
        }
    }

    pub fn count() -> Result<int> {
        if self.is_rendered() {
            let choice: render.ComboBoxRender = (self.render_object()? as? render.ComboBoxRender).expect("shared combo box")
            return ok(choice.count())
        }
        let scratch: host.HostScratch = host.HostScratch.instance
        var total: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_items_count(self.slot.raw, slot) as int,
                       "count a combo box's items")?
            total = slot.read()
        }
        return ok(total as int)
    }

    pub fn item_at(index: int) -> Result<string> {
        if self.is_rendered() {
            let choice: render.ComboBoxRender = (self.render_object()? as? render.ComboBoxRender).expect("shared combo box")
            return choice.item_at(index)
        }
        let raw: u64 = self.slot.raw
        let at: i32 = index as i32
        return host.HostText.read(
            "read item {index} of a combo box",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_items_at(raw, at, out, cap) }
            })
    }

    /// Which item is chosen, or -1 for none.
    pub fn selected() -> Result<int> {
        if self.is_rendered() { return self.read_property(host.P_SELECTED) }
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_get_int(self.slot.raw, host.P_SELECTED as i32,
                                        scratch.ints) as int,
                       "read a combo box's selection")?
        }
        return ok(scratch.integer())
    }

    pub fn select(index: int) -> Result<bool> {
        return self.set_property(host.P_SELECTED, index)
    }

    /// The text of the chosen item, or "" when nothing is chosen.
    pub override fn display_text() -> Result<string> {
        if self.is_rendered() {
            let choice: render.ComboBoxRender = (self.render_object()? as? render.ComboBoxRender).expect("shared combo box")
            return ok(choice.selected_text())
        }
        return self.text_raw()
    }
}
