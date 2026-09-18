// A box the user ticks.
package widgets

import cortado.host
import cortado.render

/// A check box with a label beside it.
///
/// Toggling it produces a `value_changed` event. Read `state()` in the
/// handler rather than tracking it separately: the platform owns the control's
/// state, and a second copy in Beans is a second thing that can be wrong.
pub class CheckBox extends Widget {
    pub fn init(context: Option<render.UiContext> = none) {
        super.init(WidgetKind.check_box, context)
    }

    pub static fn of(title: string) -> Result<CheckBox> {
        var box: CheckBox = new CheckBox()
        box.set_title(title)?
        return ok(box)
    }

    pub fn set_title(title: string) -> Result<bool> {
        return self.set_text_raw(title)
    }

    pub fn title() -> Result<string> {
        return self.text_raw()
    }

    pub fn set_state(state: CheckState) -> Result<bool> {
        if self.is_rendered() { return self.set_property(host.P_CHECKED, state.code()) }
        unsafe {
            return host.check(
                host.ctd_set_int(self.handle().raw, host.P_CHECKED as i32,
                                 state.code() as i64) as int,
                "set the state of a check box")
        }
    }

    pub fn state() -> Result<CheckState> {
        if self.is_rendered() { return ok(CheckState.of(self.read_property(host.P_CHECKED)?)) }
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_get_int(self.handle().raw, host.P_CHECKED as i32,
                                        scratch.ints) as int,
                       "read the state of a check box")?
        }
        return ok(CheckState.of(scratch.integer() as int))
    }

    pub override fn display_text() -> Result<string> {
        return self.title()
    }
}
