// The computer a program is running on, as opposed to anything it drew.
package device

import cortado.host
import cortado.platform

/// Two questions about the machine: **can I reach anything, and what is this
/// costing.**
///
/// **Neither is privacy-gated**, which is what sets this apart from everything
/// else in this package. Every call below was run from a bare binary with no
/// bundle and no usage description, across a turn of the run loop — which is
/// where a privacy death lands — and the process was still alive afterwards.
/// So unlike `Permission`, these answer for real under `beansc run` and in an
/// ordinary test. Nothing here constructs a location or Bluetooth object, and
/// nothing here can.
///
/// A program hears about changes by registering for `net_changed` and
/// `power_changed` on the application's router, which is also what starts the
/// platform's own monitor: there is no separate watch call because
/// `EventRouter.on` already is one.
pub class Machine {
    fn init() {}

    /// What the last answer about the network was.
    ///
    /// `NetworkPath.unknown` until something has answered, which on macOS and
    /// iOS is a turn of the loop after the first ask. The other two hosts can
    /// be asked directly and answer at once. A program that wants one line of
    /// code on every platform asks, runs the loop briefly, and asks again.
    pub static fn path() -> Result<NetworkPath> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var kind: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_net_path(slot, RawPtr.null()) as int,
                       "ask what this machine can reach")?
            kind = slot.read()
        }
        return ok(NetworkPath.of(kind as int))
    }

    /// Whether the path costs money by the byte — a cellular connection, a
    /// personal hotspot, a metered network.
    ///
    /// Worth asking before a program downloads something large on somebody
    /// else's data plan. GIO does not tell "expensive" and "constrained"
    /// apart, so the GTK host answers both or neither.
    pub static fn expensive() -> Result<bool> {
        return Machine.flag(host.NET_F_EXPENSIVE)
    }

    /// Whether the system has asked for less traffic — Low Data Mode, or a
    /// metered connection.
    pub static fn constrained() -> Result<bool> {
        return Machine.flag(host.NET_F_CONSTRAINED)
    }

    priv static fn flag(bit: int) -> Result<bool> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var flags: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_net_path(RawPtr.null(), slot) as int,
                       "ask what this machine's network costs")?
            flags = slot.read()
        }
        return ok(((flags as int) & bit) != 0)
    }

    /// What is running the machine.
    pub static fn power() -> Result<PowerSource> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var source: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_power_source(slot) as int,
                       "ask what is running this machine")?
            source = slot.read()
        }
        return ok(PowerSource.of(source as int))
    }

    /// How full the battery is, 0 to 1.
    ///
    /// Refused as `unsupported` where there is no battery, which is a real
    /// answer and not a missing feature: a desktop has none, and a program
    /// drawing a meter should draw nothing rather than a full one.
    pub static fn charge() -> Result<f64> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_power_charge(scratch.reals) as int,
                       "ask how full this machine's battery is")?
        }
        return ok(scratch.real(0))
    }

    /// Whether the system is in its own low-power mode.
    pub static fn saving() -> Result<bool> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var on: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_power_saving(slot) as int,
                       "ask whether this machine is saving power")?
            on = slot.read()
        }
        return ok(on != 0)
    }

    /// How hot the machine is.
    pub static fn heat() -> Result<ThermalState> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var state: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_thermal_state(slot) as int,
                       "ask how hot this machine is")?
            state = slot.read()
        }
        return ok(ThermalState.of(state as int))
    }

    /// Whether this platform can answer the network questions at all.
    pub static fn knows_network() -> bool {
        return platform.Capability.network.available()
    }

    /// Whether it can answer the power ones.
    pub static fn knows_power() -> bool {
        return platform.Capability.power.available()
    }
}
