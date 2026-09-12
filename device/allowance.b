// The answer to "may this program do that".
package device

import cortado.host

/// What the system says about one permission.
pub enum(u8) Allowance {
    /// There is no answer to be had.
    ///
    /// The platform has no such grant, or — on macOS and iOS — this process
    /// has no bundle, and so no privacy identity of its own. That second case
    /// is not a shortcoming cortado could fix: the system answers for whatever
    /// process is *responsible* for a bare binary, which is usually a
    /// terminal, and a terminal's grants are not this program's. A probe read
    /// "microphone: authorized" from a program with no usage description at
    /// all, because Terminal.app holds that grant.
    ///
    /// So this is what `beansc run` always sees, and what a test binary run
    /// straight from a build directory sees. A bundled, signed application is
    /// the only thing that gets a real answer.
    unavailable
    granted
    /// Refused — by the user, or by a policy they cannot change. Cortado does
    /// not tell those apart, because no program can do anything with the
    /// difference and a third word would be a third branch in every one.
    denied
    /// Nobody has been asked yet. `Permission.request` is how one asks.
    undecided

    pub fn name() -> string {
        return match self {
            unavailable => "unavailable",
            granted => "granted",
            denied => "denied",
            undecided => "undecided",
        }
    }

    pub static fn of(code: int) -> Allowance {
        if code == host.ALLOW_GRANTED { return Allowance.granted }
        if code == host.ALLOW_DENIED { return Allowance.denied }
        if code == host.ALLOW_UNDECIDED { return Allowance.undecided }
        return Allowance.unavailable
    }

    /// Every answer, in the order they are declared.
    pub static fn all() -> List<Allowance> {
        var every: List<Allowance> = []
        every.push(Allowance.unavailable)
        every.push(Allowance.granted)
        every.push(Allowance.denied)
        every.push(Allowance.undecided)
        return move every
    }
}
