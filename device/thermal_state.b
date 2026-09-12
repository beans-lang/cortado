// How hot the machine is, which is the number that says whether to do less.
package device

import cortado.host

/// The system's own judgement about heat.
///
/// **Only Apple's platforms have one.** A temperature in a sysfs file is a
/// reading; this is a judgement, and what counts as hot depends on the
/// machine. Turning the first into the second would mean inventing the
/// judgement rather than reporting one, so everywhere else the answer is
/// `unknown` — and a program that throttles itself asks, and does nothing when
/// nobody knows.
pub enum(u8) ThermalState {
    unknown
    nominal
    fair
    serious
    critical

    pub fn code() -> int {
        return match self {
            unknown => host.THERMAL_UNKNOWN,
            nominal => host.THERMAL_NOMINAL,
            fair => host.THERMAL_FAIR,
            serious => host.THERMAL_SERIOUS,
            critical => host.THERMAL_CRITICAL,
        }
    }

    pub static fn of(code: int) -> ThermalState {
        if code == host.THERMAL_NOMINAL { return ThermalState.nominal }
        if code == host.THERMAL_FAIR { return ThermalState.fair }
        if code == host.THERMAL_SERIOUS { return ThermalState.serious }
        if code == host.THERMAL_CRITICAL { return ThermalState.critical }
        return ThermalState.unknown
    }

    /// Whether the system is asking for less work. `unknown` is not: a program
    /// that did less because nobody knew would do less for ever on three of
    /// the four platforms.
    pub fn under_strain() -> bool {
        return self == ThermalState.serious || self == ThermalState.critical
    }

    pub fn name() -> string {
        return match self {
            unknown => "unknown",
            nominal => "nominal",
            fair => "fair",
            serious => "serious",
            critical => "critical",
        }
    }
}
