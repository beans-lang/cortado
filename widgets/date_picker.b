// A day, picked from a calendar.
package widgets

import cortado.host

/// A date picker.
///
/// `NSDatePicker`, `UIDatePicker`, `GtkCalendar`, `SysDateTimePick32` — real
/// on all four, which is rarer than it sounds for a control this complicated.
///
/// **It holds a day, not an instant**, and that is cortado's decision rather
/// than a platform's. Three of the four can show a time; `GtkCalendar` is a
/// grid of squares with nowhere to put one. A control whose value round-trips
/// an afternoon on three platforms and silently loses it on the fourth is the
/// sort of difference a user finds rather than a gate, so every host floors
/// what is written to midnight UTC of the day it names, and that is what comes
/// back.
///
/// UTC and not the machine's zone, for the same reason. A picker left local
/// would answer a different day either side of midnight depending on where the
/// computer is, and the number crossing the ABI would stop meaning one thing.
///
/// The unit is seconds since 1970-01-01, as an `f64`. Before the epoch is a
/// negative number and is as valid as any other — a date picker that refused
/// 1969 would be cortado inventing a limit no platform has.
pub class DatePicker extends Widget {
    pub fn init() {
        super.init(WidgetKind.date_picker)
    }

    /// A picker already showing a day.
    pub static fn of(seconds: f64) -> Result<DatePicker> {
        WidgetKind.date_picker.demand()?
        var picker: DatePicker = new DatePicker()
        picker.set_day(seconds)?
        return ok(picker)
    }

    /// Shows the day `seconds` falls in.
    ///
    /// Any instant in a day names that day; the host floors it. So a program
    /// that has a timestamp does not have to round it first, and two
    /// timestamps in the same day are the same write.
    pub fn set_day(seconds: f64) -> Result<bool> {
        return self.set_property_real(host.P_DATE, seconds)
    }

    /// Midnight UTC of the day being shown.
    pub fn day() -> Result<f64> {
        return self.read_real(host.P_DATE, "read the day a date picker is showing")
    }

    /// The same day as a whole number of days since 1970-01-01.
    ///
    /// The unit a caller usually wants, and the one arithmetic is safe in:
    /// adding 86400.0 to a number of seconds is a day everywhere UTC is, which
    /// is everywhere cortado's date picker is — but a caller who reaches for
    /// seconds tends to reach for a local calendar next. This is the number
    /// that has no such trap.
    pub fn day_number() -> Result<int> {
        let seconds: f64 = self.day()?
        return ok((seconds / 86400.0) as int)
    }
}
