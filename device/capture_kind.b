// Cameras and microphones.
package device

import cortado.host

/// Which kind of thing a machine looks or listens through.
pub enum(u8) CaptureKind {
    camera
    microphone

    pub fn code() -> int {
        return match self {
            camera => host.CAPTURE_CAMERA,
            microphone => host.CAPTURE_MICROPHONE,
        }
    }

    pub fn name() -> string {
        return match self {
            camera => "camera",
            microphone => "microphone",
        }
    }

    /// The permission this kind needs, which is not the same for both: a
    /// program that only wants to hear should not be asking to see.
    pub fn permission() -> Permission {
        return match self {
            camera => Permission.camera,
            microphone => Permission.microphone,
        }
    }
}
