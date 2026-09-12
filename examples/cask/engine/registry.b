// Which databases this build can open.
package engine

/// The drivers compiled into this copy of cask.
///
/// DBeaver's driver manager, minus the part that downloads a JDBC jar: these
/// are compiled in, so there is nothing to configure and nothing that can be
/// missing at run time. What it is for is the same — given something a person
/// typed, decide which driver opens it, and be able to say what the choices
/// were when none of them does.
pub class Registry {
    priv drivers: List<Driver> = []

    pub fn init() {}

    pub fn add(driver: Driver) {
        self.drivers.push(driver)
    }

    pub fn count() -> int { return self.drivers.len() }

    pub fn names() -> List<string> {
        var out: List<string> = []
        for driver: Driver in self.drivers {
            out.push(driver.name())
        }
        return move out
    }

    /// The first driver that owns up to `target`, or a refusal naming every
    /// driver there is — which is the error message a person needs, rather
    /// than one driver's guess about why its own format did not match.
    pub fn open(target: string) -> Result<Connection> {
        for driver: Driver in self.drivers {
            if driver.handles(target) {
                return driver.connect(target)
            }
        }
        var offered: string = ""
        for driver: Driver in self.drivers {
            offered = "{offered}\n  {driver.name()}: {driver.target_hint()}"
        }
        return err("nothing here opens {target}. What this build has:{offered}",
            "no_driver")
    }
}
