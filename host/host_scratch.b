// The buffer host calls write their answers into.
package host

/// One reusable landing area for values the host returns through a pointer.
///
/// A layout pass reads the frame of every widget in the tree, so allocating a
/// four-double buffer per read would put an allocation and a free on the
/// hottest path cortado has. There is exactly one buffer instead, allocated
/// once and never freed, because it lives as long as the process does.
///
/// This is safe for the same reason the rest of cortado's host boundary is:
/// **every call into the host happens on the UI thread**, by contract, and the
/// host itself answers `wrong_thread` to anything that tries otherwise. Work
/// on other threads reaches the UI through `Application.post`, which carries an
/// integer and nothing else.
pub singleton class HostScratch {
    pub reals: RawPtr<f64> = RawPtr.null()
    pub ints: RawPtr<i64> = RawPtr.null()

    fn init() {
        unsafe {
            // Four doubles is the widest answer in the ABI: a frame.
            self.reals = RawPtr.alloc(4)
            self.ints = RawPtr.alloc(1)
        }
    }

    /// The n-th double the last call wrote.
    pub fn real(index: int) -> f64 {
        unsafe {
            return self.reals.offset(index).read()
        }
    }

    pub fn integer() -> i64 {
        unsafe {
            return self.ints.read()
        }
    }
}
