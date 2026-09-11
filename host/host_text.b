// Moving text across the C boundary.
package host

/// UTF-8 in and out of the host.
///
/// Two rules hold everywhere in cortado, and this class is where they live.
///
/// Text is never NUL-terminated. Every host entry point that takes text takes
/// a pointer and a byte count, so the host reads exactly that many bytes and
/// never scans for a terminator — a length is never guessed, and a string is
/// never one byte short.
///
/// What that does **not** buy is an embedded NUL, and the distinction is worth
/// being exact about because the first version of this comment got it wrong.
/// No platform text control can hold a zero byte: `NSString`'s `UTF8String`
/// ends at it, GTK takes a `const char *`, and `SetWindowTextW` ends at it
/// too. A string with one went out whole and came back cut in half, silently,
/// on every host. So it is refused here instead — while the caller's own
/// string is still in view and the message can name it — and refused again at
/// the ABI, where `ctd_set_text` answers `CTD_ERR_RANGE`.
///
/// Text is copied at the boundary, immediately. After a call returns, no Beans
/// value points into memory the host owns — which means the host is free to
/// recycle its buffer, and it does.
pub class HostText {
    /// The UTF-8 bytes of `text`, ready to pass as (pointer, length).
    ///
    /// The returned `Bytes` must stay alive for the duration of the call it
    /// feeds; hold it in a local, do not inline the `.as_ptr()` into a longer
    /// expression that might drop it first.
    ///
    /// `attempt` names what the caller was doing, and lands in the message a
    /// zero byte earns. It is a `Result` so that this one function is the only
    /// way text reaches the boundary and the check cannot be walked past.
    pub static fn encode(text: string, attempt: string) -> Result<Bytes> {
        if text.contains("\u{0}") {
            return err("could not {attempt}: the text has a NUL byte in it, and no platform's text control can hold one",
                       "text_has_nul")
        }
        return ok(Bytes.from(text))
    }

    /// The same address seen as the `const char *` the host declares. Beans
    /// keeps `u8` and `i8` pointers apart; the C ABI does not.
    pub static fn pointer(buffer: Bytes) -> RawPtr<i8> {
        unsafe {
            return RawPtr.from_address(buffer.as_ptr().address())
        }
    }

    /// Reads text out of the host with the two-call shape.
    ///
    /// `probe` is called first with a null buffer and a capacity of zero to
    /// learn the length, then again with a buffer that size. Guessing a
    /// capacity instead would truncate exactly the strings that matter — long
    /// labels, pasted text — and would do it silently.
    ///
    /// A negative answer from either call is a host status, not a length.
    /// Copies a string the host handed over with an explicit length.
    ///
    /// Used for the text on an event, where the host owns the bytes and they
    /// are valid only while it is raising the event. Copying here rather than
    /// keeping the pointer is the whole point: every handler runs after the
    /// call that carried it.
    ///
    /// A null pointer or a non-positive length answers "", which is what an
    /// event of a kind that carries no text has.
    pub static fn copy_in(pointer: RawPtr<i8>, length: int) -> string {
        if pointer.is_null() || length <= 0 {
            return ""
        }
        unsafe {
            let bytes: RawPtr<u8> = RawPtr.from_address(pointer.address())
            let copy: Bytes = Bytes.from_raw(bytes, length)
            return copy.to_string()
        }
    }

    pub static fn read(attempt: string, probe: fn(RawPtr<i8>, i32) -> i32) -> Result<string> {
        let needed: int = probe(RawPtr.null(), 0) as int
        check(needed, attempt)?
        if needed == 0 {
            return ok("")
        }
        var buffer: Bytes = Bytes.filled(needed, 0)
        let written: int = probe(HostText.pointer(buffer), needed as i32) as int
        check(written, attempt)?
        // A host that answers a larger length the second time has changed the
        // text between the two calls. Trusting the first length would read
        // whatever the buffer happened to hold past the copy.
        if written != needed {
            return err("could not {attempt}: the text changed while it was being read",
                       "host_raced")
        }
        return ok(buffer.to_string())
    }
}
