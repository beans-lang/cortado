// The GPU, which this host does not have.
//
// Every entry point here answers CTD_ERR_UNSUPPORTED and
// `ctd_capability(CTD_CAP_GPU)` answers no, so a program asks once and draws
// something else rather than finding out one call at a time.
//
// It is not a stub in the sense of unfinished work waiting for somebody's
// afternoon. The declarations in "the GPU" section of cortado_host.h are
// WebGPU-shaped precisely so that a Direct3D 12 host can fill them — a device, a
// buffer, a shader, a pipeline, a pass — and the shape is what makes that a
// possible piece of work rather than a redesign. What stops it happening here
// and now is that a Vulkan backend is a project of its own: a loader, a
// physical-device choice, a swapchain, memory heaps and a shader language
// this host would have to accept in SPIR-V rather than MSL.
//
// So the honest answer is the one the header demands of anything a platform
// cannot do: refuse, by name, every time.

#include "internal.h"

uint32_t ctd_gpu_shader_langs(void) {
    // No language, because there is nothing here to compile one for. A host
    // that answered SPIR-V while refusing every call would be worse than this
    // — it would tell a program to write shaders it can never run.
    return 0;
}

ctd_handle ctd_gpu_device_new(void) {
    return 0;
}

int32_t ctd_gpu_device_name(ctd_handle device, char *out, int32_t cap) {
    (void)device; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_device_limit(ctd_handle device, int32_t which, double *out) {
    (void)device; (void)which; (void)out;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_release(ctd_handle object) {
    (void)object;
    return CTD_ERR_UNSUPPORTED;
}

// ---------------------------------------------------------- what you draw with
//
// The same answer, eighteen more times. Each one is written out rather than
// folded into a macro or a shared file, because `tools/check_hosts.sh` reads
// this directory for the entry points it defines and a host whose symbols came
// from somewhere else would read as incomplete — and because a refusal is a
// place somebody will one day put an implementation, one function at a time.

ctd_handle ctd_gpu_buffer_new(ctd_handle device, const float *data, int32_t count) {
    (void)device; (void)data; (void)count;
    return 0;
}

ctd_status ctd_gpu_buffer_write(ctd_handle buffer, int32_t first,
                                const float *data, int32_t count) {
    (void)buffer; (void)first; (void)data; (void)count;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_buffer_count(ctd_handle buffer, int32_t *out) {
    (void)buffer; (void)out;
    return CTD_ERR_UNSUPPORTED;
}

ctd_handle ctd_gpu_target_new(ctd_handle device, int32_t width, int32_t height) {
    (void)device; (void)width; (void)height;
    return 0;
}

int32_t ctd_gpu_target_read(ctd_handle target, double *out_size, char *out, int32_t cap) {
    (void)target; (void)out_size; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

ctd_handle ctd_gpu_shader_new(ctd_handle device, int32_t language,
                              const char *source, int32_t len) {
    (void)device; (void)language; (void)source; (void)len;
    return 0;
}

int32_t ctd_gpu_shader_problem(ctd_handle device, char *out, int32_t cap) {
    (void)device; (void)out; (void)cap;
    return CTD_ERR_UNSUPPORTED;
}

ctd_handle ctd_gpu_pipeline_new(ctd_handle shader,
                                const char *vertex, int32_t vertex_len,
                                const char *fragment, int32_t fragment_len) {
    (void)shader; (void)vertex; (void)vertex_len; (void)fragment; (void)fragment_len;
    return 0;
}

ctd_status ctd_gpu_pipeline_attr(ctd_handle pipeline, int32_t index,
                                 int32_t floats, int32_t offset) {
    (void)pipeline; (void)index; (void)floats; (void)offset;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_pipeline_stride(ctd_handle pipeline, int32_t floats) {
    (void)pipeline; (void)floats;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_pipeline_blend(ctd_handle pipeline, int32_t blend) {
    (void)pipeline; (void)blend;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_pipeline_build(ctd_handle pipeline) {
    (void)pipeline;
    return CTD_ERR_UNSUPPORTED;
}

ctd_handle ctd_gpu_pass_begin(ctd_handle target, double r, double g, double b, double a) {
    (void)target; (void)r; (void)g; (void)b; (void)a;
    return 0;
}

ctd_status ctd_gpu_pass_pipeline(ctd_handle pass, ctd_handle pipeline) {
    (void)pass; (void)pipeline;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_pass_vertices(ctd_handle pass, ctd_handle buffer) {
    (void)pass; (void)buffer;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_pass_uniform(ctd_handle pass, const float *data, int32_t count) {
    (void)pass; (void)data; (void)count;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_pass_draw(ctd_handle pass, int32_t shape, int32_t first, int32_t count) {
    (void)pass; (void)shape; (void)first; (void)count;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_pass_end(ctd_handle pass) {
    (void)pass;
    return CTD_ERR_UNSUPPORTED;
}

// --------------------------------------------------------------- the canvas
//
// `CTD_W_CANVAS` is a real widget here: the solver lays it out, it is in the
// tree, and it has an accessibility role like any other control. What it
// cannot do is have anything drawn into it, so it is an empty area rather than
// a missing one — which is the right shape for a control whose contents are a
// program's own drawing.

ctd_status ctd_gpu_canvas_attach(ctd_handle widget, ctd_handle device) {
    (void)device;
    // The kind is checked here, before the refusal, and that is not ceremony.
    // "This is not a canvas" is the caller's bug and "this platform has no
    // GPU" is not, and a host that answered the second to both would make the
    // first invisible on three platforms out of four. It is the same mistake
    // CTD_P_ENABLED cost four hosts once already.
    if (!ctd_window(widget)) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_CANVAS) return CTD_ERR_KIND;
    return CTD_ERR_UNSUPPORTED;
}

ctd_handle ctd_gpu_canvas_next(ctd_handle widget) {
    (void)widget;
    return 0;
}

ctd_status ctd_gpu_pass_present(ctd_handle pass) {
    (void)pass;
    return CTD_ERR_UNSUPPORTED;
}

ctd_status ctd_gpu_pipeline_pixels(ctd_handle pipeline, int32_t pixels) {
    (void)pipeline; (void)pixels;
    return CTD_ERR_UNSUPPORTED;
}
