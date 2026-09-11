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
