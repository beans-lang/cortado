// Whether anything is reachable, and over what.
package device

import cortado.host

/// What a path to the rest of the world is made of.
///
/// **`unknown` is a real answer and not a failure.** One platform's answer is
/// a push: `nw_path_monitor` has no synchronous read at all, so the first
/// question asked of a fresh program is answered a turn of the loop later. A
/// program asks, lets the loop turn once, and asks again — which is what it
/// does anyway, because it wants to be told when the answer changes.
///
/// `other` is the honest answer where a platform knows there is a path and not
/// what it runs over. GIO, which is what the GTK host uses, has no notion of
/// the medium at all: it answers whether the network is available and whether
/// it is metered, and those are the two facts a program acts on.
pub enum(u8) NetworkPath {
    /// Nothing has answered yet.
    unknown
    /// Answered, and there is nothing to reach.
    none
    wifi
    wired
    cellular
    /// There is a path, over something this platform will not name.
    other

    pub fn code() -> int {
        return match self {
            unknown => host.NET_UNKNOWN,
            none => host.NET_NONE,
            wifi => host.NET_WIFI,
            wired => host.NET_WIRED,
            cellular => host.NET_CELLULAR,
            other => host.NET_OTHER,
        }
    }

    pub static fn of(code: int) -> NetworkPath {
        if code == host.NET_NONE { return NetworkPath.none }
        if code == host.NET_WIFI { return NetworkPath.wifi }
        if code == host.NET_WIRED { return NetworkPath.wired }
        if code == host.NET_CELLULAR { return NetworkPath.cellular }
        if code == host.NET_OTHER { return NetworkPath.other }
        return NetworkPath.unknown
    }

    /// Whether there is anything to reach. `unknown` is not yes: a program
    /// that treated "nobody has said" as "go ahead" would make its first
    /// request before it knew there was anywhere to send it.
    pub fn reachable() -> bool {
        return self != NetworkPath.unknown && self != NetworkPath.none
    }

    pub fn name() -> string {
        return match self {
            unknown => "unknown",
            none => "none",
            wifi => "wifi",
            wired => "wired",
            cellular => "cellular",
            other => "other",
        }
    }
}
