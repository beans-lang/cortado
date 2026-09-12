// What is running the machine.
package device

import cortado.host

/// Where the machine's power is coming from.
pub enum(u8) PowerSource {
    /// Nobody can say. A phone simulator answers this and always will: there
    /// is no battery behind it.
    unknown
    /// The wall. A machine with no battery at all answers this, because it is
    /// running and nothing else is running it.
    mains
    battery

    pub fn code() -> int {
        return match self {
            unknown => host.POWER_UNKNOWN,
            mains => host.POWER_MAINS,
            battery => host.POWER_BATTERY,
        }
    }

    pub static fn of(code: int) -> PowerSource {
        if code == host.POWER_MAINS { return PowerSource.mains }
        if code == host.POWER_BATTERY { return PowerSource.battery }
        return PowerSource.unknown
    }

    pub fn name() -> string {
        return match self {
            unknown => "unknown",
            mains => "mains",
            battery => "battery",
        }
    }
}
