// What the operating system will let this program do.
package device

import cortado.host

/// Something a program has to be allowed to do.
///
/// Not a capability. `platform.Capability` asks whether a *platform* has a
/// feature, and the answer is the same for every program on it;
/// this asks whether *this program, on this machine, for this user* is allowed
/// to use one, and the answer changes while the program is running.
pub enum(u8) Permission {
    bluetooth
    location
    camera
    microphone
    screen_capture
    photos
    motion

    fn code() -> int {
        return match self {
            bluetooth => host.PERM_BLUETOOTH,
            location => host.PERM_LOCATION,
            camera => host.PERM_CAMERA,
            microphone => host.PERM_MICROPHONE,
            screen_capture => host.PERM_SCREEN_CAPTURE,
            photos => host.PERM_PHOTOS,
            motion => host.PERM_MOTION,
        }
    }

    pub fn name() -> string {
        return match self {
            bluetooth => "bluetooth",
            location => "location",
            camera => "camera",
            microphone => "microphone",
            screen_capture => "screen_capture",
            photos => "photos",
            motion => "motion",
        }
    }

    /// Every permission, in the order they are declared.
    pub static fn all() -> List<Permission> {
        var every: List<Permission> = []
        every.push(Permission.bluetooth)
        every.push(Permission.location)
        every.push(Permission.camera)
        every.push(Permission.microphone)
        every.push(Permission.screen_capture)
        every.push(Permission.photos)
        every.push(Permission.motion)
        return move every
    }

    /// What the system says about this program and this permission, now.
    ///
    /// Reading it touches nothing: the host reads the usage description the
    /// program declared and the framework's own static query, and constructs
    /// no manager and opens no device. That is not an implementation detail —
    /// on macOS, touching a gated framework without a usage description ends
    /// the process, on a later turn of the run loop, with nothing on stderr.
    pub fn status() -> Result<Allowance> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var answer: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_permission_status(self.code() as i32, slot) as int,
                       "read whether {self.name()} is allowed")?
            answer = slot.read()
        }
        return ok(Allowance.of(answer as int))
    }

    /// Asks the user, and answers later through `EventKind.permission`.
    ///
    /// `token` comes back on the event, so one handler can tell which request
    /// it is about.
    ///
    /// Refused where a prompt cannot appear, which is every platform but macOS
    /// and iOS — and on those, any program without a bundle or without the
    /// usage description this permission needs. That refusal is the whole
    /// point: asking without one is what kills the process.
    pub fn request(token: int) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_permission_request(self.code() as i32, token as i64) as int,
                "ask the user about {self.name()}")
        }
    }
}
