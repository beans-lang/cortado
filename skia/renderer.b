package cortado_skia

import cortado.geometry
import cortado.paint
import cortado.host
import cortado.widgets

pub enum Backend {
    software
    metal
    vulkan
    opengl
    automatic

    pub fn code() -> i32 {
        return match self {
            software => 0,
            metal => 1,
            vulkan => 2,
            opengl => 3,
            automatic => 4,
        }
    }
    pub static fn of(code: i32) -> Backend {
        if code == 1 { return Backend.metal }
        if code == 2 { return Backend.vulkan }
        if code == 3 { return Backend.opengl }
        return Backend.software
    }
    pub fn name() -> string {
        return match self {
            software => "software",
            metal => "Metal",
            vulkan => "Vulkan",
            opengl => "OpenGL",
            automatic => "automatic",
        }
    }
}

class Engine {
    raw: RawPtr<u8> = RawPtr.null()
    scratch: RawPtr<f64> = RawPtr.null()
    pub fn init() {
        unsafe { self.raw = ctd_skia_new(); self.scratch = RawPtr.alloc(4) }
    }
    fn close() {
        unsafe {
            if !self.raw.is_null() { ctd_skia_delete(self.raw); self.raw = RawPtr.null() }
        }
    }
    fn deinit() { self.close(); unsafe { self.scratch.free() } }
    fn checked(code: i32) -> Result<bool> {
        if code < 0 { return err("Skia operation refused ({code})", "renderer_error") }
        return ok(true)
    }
    fn value(index: int) -> f64 { unsafe { return self.scratch.offset(index).read() } }
}

class SkiaParagraph implements paint.Paragraph {
    engine: Engine
    id: u64
    measured: geometry.Size
    pub fn init(engine: Engine, id: u64, measured: geometry.Size) {
        self.engine = engine; self.id = id; self.measured = measured
    }
    pub fn size() -> geometry.Size { return self.measured }
    pub fn hit_test(x: f64, y: f64) -> int {
        unsafe { return ctd_skia_paragraph_hit(self.engine.raw, self.id, x, y) as int }
    }
    pub fn caret(byte_offset: int) -> geometry.Rect {
        unsafe {
            if ctd_skia_paragraph_caret(self.engine.raw, self.id, byte_offset as i32, self.engine.scratch) < 0 {
                return geometry.Rect.zero()
            }
        }
        return geometry.Rect.of(self.engine.value(0), self.engine.value(1), self.engine.value(2), self.engine.value(3))
    }
    pub fn selection(first_byte: int, last_byte: int) -> Result<List<geometry.Rect>> {
        var answer: List<geometry.Rect> = []
        unsafe {
            let count: i32 = ctd_skia_paragraph_selection(self.engine.raw, self.id,
                first_byte as i32, last_byte as i32, RawPtr.null(), 0)
            self.engine.checked(count)?
            if count > 0 {
                let out: RawPtr<f64> = RawPtr.alloc(count as int * 4)
                let wrote: i32 = ctd_skia_paragraph_selection(self.engine.raw, self.id,
                    first_byte as i32, last_byte as i32, out, count)
                if wrote < 0 { out.free(); return err("could not measure text selection", "renderer_error") }
                for index: int in 0..wrote as int {
                    answer.push(geometry.Rect.of(out.offset(index * 4).read(), out.offset(index * 4 + 1).read(),
                        out.offset(index * 4 + 2).read(), out.offset(index * 4 + 3).read()))
                }
                out.free()
            }
        }
        return ok(move answer)
    }
    fn deinit() { unsafe { ctd_skia_paragraph_release(self.engine.raw, self.id) } }
}

class SkiaImage implements paint.ImageResource {
    engine: Engine
    id: u64
    measured: geometry.Size
    pub fn init(engine: Engine, id: u64, measured: geometry.Size) {
        self.engine = engine; self.id = id; self.measured = measured
    }
    pub fn size() -> geometry.Size { return self.measured }
    fn deinit() { unsafe { ctd_skia_image_release(self.engine.raw, self.id) } }
}

/// Skia graphics renderer. GPU frames are read back for the current Canvas host.
pub class SkiaRenderer implements paint.Renderer {
    engine: Engine
    revision_value: int = 0
    pub fn init(preferred: Option<Backend> = none) {
        self.engine = new Engine()
        match preferred {
            some(backend) => {
                if backend != Backend.software {
                    unsafe { ctd_skia_select_backend(self.engine.raw, backend.code()) }
                }
            }
            none => {}
        }
    }
    pub fn close() { self.engine.close() }
    pub fn backend() -> Backend {
        unsafe { return Backend.of(ctd_skia_backend(self.engine.raw)) }
    }
    pub fn revision() -> int { return self.revision_value }
    pub fn select_backend(preferred: Backend) -> Result<bool> {
        unsafe { self.engine.checked(ctd_skia_select_backend(self.engine.raw, preferred.code()))? }
        self.revision_value += 1
        return ok(true)
    }
    pub fn recover_software() -> Result<bool> {
        unsafe { self.engine.checked(ctd_skia_recover_software(self.engine.raw))? }
        self.revision_value += 1
        return ok(true)
    }
    pub fn paragraph(text: string, size: f64, width: f64, color: int) -> Result<paint.Paragraph> {
        let bytes: Bytes = Bytes.from(text)
        var id: u64 = 0
        unsafe {
            id = ctd_skia_paragraph_new(self.engine.raw, host.HostText.pointer(bytes),
                bytes.len() as i32, size, width, color as u32)
        }
        if id == 0 { return err("Skia could not shape paragraph", "renderer_error") }
        unsafe { self.engine.checked(ctd_skia_paragraph_size(self.engine.raw, id, self.engine.scratch))? }
        return ok(new SkiaParagraph(self.engine, id, geometry.Size.of(self.engine.value(0), self.engine.value(1))))
    }
    pub fn begin(size: geometry.Size, scale: f64, background: int) -> Result<paint.Canvas> {
        unsafe { self.engine.checked(ctd_skia_begin(self.engine.raw, size.width, size.height, scale, background as u32))? }
        return ok(new SkiaCanvas(self.engine))
    }
    pub fn end() -> Result<bool> { unsafe { return self.engine.checked(ctd_skia_end(self.engine.raw)) } }
    pub fn graphemes(text: string) -> Result<List<int>> {
        let bytes: Bytes = Bytes.from(text)
        var answer: List<int> = []
        unsafe {
            let count: i32 = ctd_skia_graphemes(self.engine.raw, host.HostText.pointer(bytes), bytes.len() as i32, RawPtr.null(), 0)
            self.engine.checked(count)?
            let out: RawPtr<i32> = RawPtr.alloc(count as int)
            let wrote: i32 = ctd_skia_graphemes(self.engine.raw, host.HostText.pointer(bytes), bytes.len() as i32, out, count)
            if wrote < 0 { out.free(); return err("Skia could not segment text", "renderer_error") }
            for index: int in 0..wrote as int { answer.push(out.offset(index).read() as int) }
            out.free()
        }
        return ok(move answer)
    }
    pub fn image(source: string) -> Result<paint.ImageResource> {
        let bytes: Bytes = Bytes.from(source)
        var id: u64 = 0
        unsafe { id = ctd_skia_image_new(self.engine.raw, host.HostText.pointer(bytes), bytes.len() as i32) }
        if id == 0 { return err("Skia could not load image: {source}", "image_load") }
        unsafe { self.engine.checked(ctd_skia_image_size(self.engine.raw, id, self.engine.scratch))? }
        return ok(new SkiaImage(self.engine, id, geometry.Size.of(self.engine.value(0), self.engine.value(1))))
    }
    pub fn snapshot() -> Result<widgets.Snapshot> {
        let owner: Engine = self.engine
        return widgets.Snapshot.read("read Skia frame", fn(size: RawPtr<f64>, out: RawPtr<i8>, capacity: i32) -> i32 {
            unsafe { return ctd_skia_pixels(owner.raw, size, out, capacity) }
        })
    }
    /// Present an independent readback. Reusing a persistent pixel buffer was
    /// slower in the native presentation benchmark; keep the measured path.
    pub fn present_to(canvas: widgets.Canvas) -> Result<bool> {
        return canvas.present(self.snapshot()?)
    }
    pub fn write_png(path: string) -> Result<bool> {
        let bytes: Bytes = Bytes.from(path)
        unsafe { return self.engine.checked(ctd_skia_png(self.engine.raw, host.HostText.pointer(bytes), bytes.len() as i32)) }
    }
}

class SkiaCanvas implements paint.Canvas {
    engine: Engine
    pub fn init(engine: Engine) { self.engine = engine }
    pub fn save() -> Result<bool> { unsafe { return self.engine.checked(ctd_skia_save(self.engine.raw)) } }
    pub fn restore() -> Result<bool> { unsafe { return self.engine.checked(ctd_skia_restore(self.engine.raw)) } }
    pub fn translate(x: f64, y: f64) -> Result<bool> {
        unsafe { return self.engine.checked(ctd_skia_translate(self.engine.raw, x, y)) }
    }
    pub fn rotate(degrees: f64) -> Result<bool> {
        unsafe { return self.engine.checked(ctd_skia_rotate(self.engine.raw, degrees)) }
    }
    pub fn scale(x: f64, y: f64) -> Result<bool> {
        unsafe { return self.engine.checked(ctd_skia_scale(self.engine.raw, x, y)) }
    }
    pub fn clip(rect: geometry.Rect, radius: f64) -> Result<bool> {
        unsafe { return self.engine.checked(ctd_skia_clip(self.engine.raw, rect.x, rect.y, rect.width, rect.height, radius)) }
    }
    pub fn rectangle(rect: geometry.Rect, radius: f64, color: int, stroke: f64) -> Result<bool> {
        unsafe { return self.engine.checked(ctd_skia_rect(self.engine.raw, rect.x, rect.y, rect.width, rect.height, radius, color as u32, stroke)) }
    }
    pub fn ellipse(rect: geometry.Rect, fill: int, outline: int, stroke: f64) -> Result<bool> {
        unsafe { return self.engine.checked(ctd_skia_ellipse(self.engine.raw, rect.x, rect.y,
            rect.width, rect.height, fill as u32, outline as u32, stroke)) }
    }
    pub fn path(data: string, fill: int, outline: int, stroke: f64) -> Result<bool> {
        let bytes: Bytes = Bytes.from(data)
        unsafe { return self.engine.checked(ctd_skia_path(self.engine.raw, host.HostText.pointer(bytes),
            bytes.len() as i32, fill as u32, outline as u32, stroke)) }
    }
    pub fn visual(kind: int, rect: geometry.Rect, data: string, style: paint.VisualStyle) -> Result<bool> {
        let bytes: Bytes = Bytes.from(data)
        unsafe { return self.engine.checked(ctd_skia_visual(self.engine.raw, kind as i32,
            rect.x, rect.y, rect.width, rect.height, host.HostText.pointer(bytes), bytes.len() as i32,
            style.fill as u32, style.outline as u32, style.stroke_width,
            style.gradient_start as u32, style.gradient_end as u32,
            if style.gradient_enabled { 1 } else { 0 }, style.shadow_color as u32,
            style.shadow_blur, style.shadow_dx, style.shadow_dy, style.clip_radius)) }
    }
    pub fn image(value: paint.ImageResource, rect: geometry.Rect) -> Result<bool> {
        match value as? SkiaImage {
            none => { return err("image belongs to another renderer", "bad_owner") }
            some(decoded) => {
                unsafe { if decoded.engine.raw.address() != self.engine.raw.address() {
                    return err("image belongs to another renderer", "bad_owner")
                } }
                unsafe { return self.engine.checked(ctd_skia_image_draw(self.engine.raw, decoded.id,
                    rect.x, rect.y, rect.width, rect.height)) }
            }
        }
    }
    pub fn paragraph(value: paint.Paragraph, x: f64, y: f64) -> Result<bool> {
        match value as? SkiaParagraph {
            none => { return err("paragraph belongs to another renderer", "bad_owner") }
            some(shaped) => {
                unsafe { if shaped.engine.raw.address() != self.engine.raw.address() { return err("paragraph belongs to another renderer", "bad_owner") } }
                unsafe { return self.engine.checked(ctd_skia_paragraph_paint(self.engine.raw, shaped.id, x, y)) }
            }
        }
    }
}
