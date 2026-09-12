// Where the machine is, what is nearby, what it can see and hear, and what is
// on its screen.
package device

import cortado.host
import cortado.platform

/// The four services the operating system will not let a program have for
/// free.
///
/// **Every call here can only work from a signed bundle**, and that is not a
/// cortado limitation. macOS does not refuse a program that reaches a
/// privacy-gated framework without the matching usage description in its
/// Info.plist — it *terminates* it, on a later turn of the run loop, in
/// unrelated code, with nothing on stderr. So nothing here touches a framework
/// until three things are true: the process has a bundle, the bundle says what
/// it wants the permission for, and the permission is not already denied.
///
/// A call that fails any of the three answers `unsupported` and touches
/// nothing. That makes all of it unreachable under `beansc run`, where the
/// process is `beansc`, and from any program that was not built into a bundle
/// — `tools/bundle.sh` builds the one these need.
///
/// The static class shape, rather than an object to hold: there is one
/// location manager, one radio and one screen per process, and handing out a
/// second object that shared them would be two names for one thing.
pub class Gated {
    fn init() {}

    // ---- where the machine is ----

    /// Starts the platform's own location updates. A program hears each fix as
    /// a `location` event, and `where_now` reads the last one.
    pub static fn watch_place() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_location_start() as int,
                              "start watching where this machine is")
        }
    }

    pub static fn stop_place() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_location_stop() as int,
                              "stop watching where this machine is")
        }
    }

    /// The last fix.
    ///
    /// Refused as `wrong_moment` before one has arrived, which is a real state
    /// and not an error: a fix takes seconds, and four zeroes are a place in
    /// the Gulf of Guinea.
    pub static fn where_now() -> Result<Place> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_location_last(scratch.reals) as int,
                       "ask where this machine is")?
        }
        return ok(Place { latitude: scratch.real(0), longitude: scratch.real(1),
                          accuracy: scratch.real(2), heading: scratch.real(3) })
    }

    // ---- what is nearby ----

    /// Starts or stops a Bluetooth scan.
    ///
    /// Everything seen is a *row*, numbered from zero in the order it was
    /// first seen, and a row keeps its number for as long as the scan does —
    /// which is what lets a `ble_found` event name one with an integer instead
    /// of a string.
    ///
    /// Refused as `wrong_moment` while the radio is still coming up, which
    /// takes a moment after the first call and which CoreBluetooth otherwise
    /// ignores without saying so.
    pub static fn scan(on: bool) -> Result<bool> {
        var flag: i32 = 0
        if on { flag = 1 }
        unsafe {
            return host.check(host.ctd_ble_scan(flag) as int,
                              "scan for what is nearby")
        }
    }

    /// How many have been seen.
    pub static fn nearby_count() -> int {
        unsafe {
            return host.ctd_ble_count() as int
        }
    }

    /// What a device calls itself, which is **often empty** — a peripheral is
    /// not obliged to advertise a name and most do not until connected.
    pub static fn nearby_name(row: int) -> Result<string> {
        let at: i32 = row as i32
        return host.HostText.read("name what is nearby",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_ble_name(at, out, cap) }
            })
    }

    /// The identifier this machine knows it by. **Not the hardware address** —
    /// Apple does not hand that out — but stable for this machine and this
    /// device, which is what a program storing it needs.
    pub static fn nearby_id(row: int) -> Result<string> {
        let at: i32 = row as i32
        return host.HostText.read("identify what is nearby",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_ble_id(at, out, cap) }
            })
    }

    /// Signal strength in dBm: negative, and closer to zero when nearer.
    pub static fn nearby_signal(row: int) -> Result<f64> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_ble_signal(row as i32, scratch.reals) as int,
                       "ask how strong a nearby signal is")?
        }
        return ok(scratch.real(0))
    }

    /// Connects to one, or drops it. The answer arrives as a `ble_link` event,
    /// because a connection takes as long as it takes.
    pub static fn connect(row: int, on: bool) -> Result<bool> {
        var flag: i32 = 0
        if on { flag = 1 }
        unsafe {
            return host.check(host.ctd_ble_connect(row as i32, flag) as int,
                              "connect to what is nearby")
        }
    }

    pub static fn connected(row: int) -> bool {
        unsafe {
            return host.ctd_ble_linked(row as i32) != 0
        }
    }

    // ---- what it can see and hear ----

    /// How many cameras or microphones there are.
    pub static fn capture_count(kind: CaptureKind) -> int {
        unsafe {
            return host.ctd_capture_count(kind.code() as i32) as int
        }
    }

    pub static fn capture_name(kind: CaptureKind, row: int) -> Result<string> {
        let which: i32 = kind.code() as i32
        let at: i32 = row as i32
        return host.HostText.read("name a {kind.name()}",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_capture_name(which, at, out, cap) }
            })
    }

    /// Whether this is the one the system would pick. A program offering a
    /// list should have it already selected.
    pub static fn capture_is_default(kind: CaptureKind, row: int) -> bool {
        unsafe {
            return host.ctd_capture_is_default(kind.code() as i32, row as i32) != 0
        }
    }

    // ---- what is on the screen ----

    /// How many displays can be recorded.
    pub static fn screen_count() -> int {
        unsafe {
            return host.ctd_screen_count() as int
        }
    }

    /// A display's size, in pixels rather than points — which is what a frame
    /// of it will be.
    pub static fn screen_size(display: int) -> Result<geometry_size> {
        let scratch: host.HostScratch = host.HostScratch.instance
        unsafe {
            host.check(host.ctd_screen_size(display as i32, scratch.reals) as int,
                       "measure a display")?
        }
        return ok(geometry_size { width: scratch.real(0), height: scratch.real(1) })
    }

    /// Asks for one frame of a display.
    ///
    /// **Asked for rather than returned**, because it takes time. There used
    /// to be a plain call for this on macOS and version 15 removed it — not
    /// deprecated, removed — and what replaced it delivers on a queue. So the
    /// answer arrives as a `screen_frame` event carrying `token` back, and
    /// `take_frame` reads the pixels.
    pub static fn capture_screen(display: int, token: int) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_screen_capture(display as i32, token as i64) as int,
                              "ask for a picture of a display")
        }
    }

    /// The pixels a token is holding, **once**: a Retina display is thirty
    /// megabytes a frame, and holding the last one for a caller that may never
    /// ask again would be thirty megabytes kept for nothing. A token nobody
    /// filled in, or one already taken, is refused as `wrong_moment`.
    pub static fn take_frame(token: int) -> Result<int> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var length: int = 0
        unsafe {
            let answer: i32 = host.ctd_screen_take(token as i64, scratch.reals,
                                                   RawPtr.null(), 0)
            host.check(answer as int, "ask how big a picture of a display is")?
            length = answer as int
        }
        return ok(length)
    }

    // ---- what this platform has ----

    pub static fn knows_place() -> bool { return platform.Capability.location.available() }
    pub static fn knows_nearby() -> bool { return platform.Capability.bluetooth.available() }
    pub static fn knows_capture() -> bool { return platform.Capability.capture.available() }
    pub static fn knows_screen() -> bool { return platform.Capability.screen.available() }
}

/// A width and a height. `geometry.Size` would do, and importing geometry into
/// this package for one struct would pull the whole layout vocabulary into a
/// program that only wanted to know how big a display is.
pub struct geometry_size {
    pub width: f64
    pub height: f64
}
