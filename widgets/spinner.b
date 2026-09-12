// Something is happening and nobody knows for how long.
package widgets

import cortado.host

/// A spinner.
///
/// A spinning `NSProgressIndicator`, a `UIActivityIndicatorView`, a
/// `GtkSpinner` — and **not on every platform**: the Win32 common controls
/// have no spinner. A marquee progress bar is the nearest thing Windows has
/// and it is a different control with a different shape, so cortado refuses
/// rather than substituting one.
///
/// It carries one thing: whether it is turning. A spinner that is not turning
/// looks broken rather than idle, so a program with nothing to wait for hides
/// it — but stopping it is still the honest way to say the work finished, and
/// every platform that has one has a stop.
///
/// A spinner is not a progress bar with an unknown total. That is
/// `ProgressBar.set_indeterminate`, and it means something else: the work has
/// a beginning and an end and only the end is unknown. A spinner makes no
/// claim about either.
pub class Spinner extends Widget {
    pub fn init() {
        super.init(WidgetKind.spinner)
    }

    /// A spinner, already turning or not.
    pub static fn of(turning: bool) -> Result<Spinner> {
        WidgetKind.spinner.demand()?
        var wheel: Spinner = new Spinner()
        wheel.set_turning(turning)?
        return ok(wheel)
    }

    pub fn set_turning(on: bool) -> Result<bool> {
        return self.set_flag(host.P_ANIMATING, on, "start or stop a spinner")
    }

    pub fn is_turning() -> Result<bool> {
        return self.read_flag(host.P_ANIMATING, "read whether a spinner is turning")
    }
}
