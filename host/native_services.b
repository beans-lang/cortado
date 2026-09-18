package host

/// Thin ABI bridge. OS text and accessibility policy belongs to render/.
pub class NativeServices {
    pub static fn clipboard_write(text: string) -> Result<bool> {
        let bytes: Bytes = HostText.encode(text, "copy text")?
        unsafe { check(ctd_clipboard_write(HostText.pointer(bytes), bytes.len() as i32) as int, "copy text")? }
        return ok(true)
    }
    pub static fn clipboard_read() -> Result<string> {
        return HostText.read("paste text", fn(out: RawPtr<i8>, cap: i32) -> i32 {
            unsafe { return ctd_clipboard_read(out, cap) }
        })
    }
    pub static fn text_state(canvas: Handle, mode: int, text: string, anchor: int, caret: int,
                             x: f64, y: f64, width: f64, height: f64) -> Result<bool> {
        let bytes: Bytes = HostText.encode(text, "update input method")?
        unsafe { check(ctd_canvas_text_state(canvas.raw, mode as i32,
              HostText.pointer(bytes), bytes.len() as i32, anchor as i32, caret as i32,
              x, y, width, height) as int, "update input method")? }
        return ok(true)
    }
    pub static fn semantics_clear(canvas: Handle) -> Result<bool> {
        unsafe { check(ctd_canvas_semantics_clear(canvas.raw) as int, "clear accessibility tree")? }
        return ok(true)
    }
    pub static fn semantics_add(canvas: Handle, id: u64, role: string, label: string,
                                value: string, x: f64, y: f64, width: f64,
                                height: f64, enabled: bool, focused: bool) -> Result<bool> {
        let role_bytes: Bytes = HostText.encode(role, "set accessibility role")?
        let label_bytes: Bytes = HostText.encode(label, "set accessibility label")?
        let value_bytes: Bytes = HostText.encode(value, "set accessibility value")?
        unsafe { check(ctd_canvas_semantics_add(canvas.raw, id,
              HostText.pointer(role_bytes), role_bytes.len() as i32,
              HostText.pointer(label_bytes), label_bytes.len() as i32,
              HostText.pointer(value_bytes), value_bytes.len() as i32,
              x, y, width, height, if enabled { 1 } else { 0 }, if focused { 1 } else { 0 }) as int,
              "set accessibility node")? }
        return ok(true)
    }
    pub static fn semantics_end(canvas: Handle) -> Result<bool> {
        unsafe { check(ctd_canvas_semantics_end(canvas.raw) as int, "publish accessibility tree")? }
        return ok(true)
    }
}
