// The GPU, through Metal.
//
// This file is the whole of what "drawing that is not a control" means on
// macOS. Everything else in this host asks AppKit for a control and lets
// AppKit paint it; here cortado asks the machine for its GPU and hands it
// work directly.
//
// **Why the near-identical twin in src/ios/ is not shared with this file.**
// Metal is Metal, and today these two files differ only in a comment. The
// temptation is a shared translation unit, and it is the wrong move twice
// over: `tools/check_hosts.sh` reads each platform directory for the entry
// points it defines — a host that got its symbols from somewhere else would
// read as incomplete — and the two platforms genuinely do diverge further in
// (a managed storage mode that exists only here, a layer that hangs off an
// NSView rather than a UIView, a simulator whose device reports different
// limits from the machine it runs on). What keeps them honest is not shared
// source but `tests/gpu.out`, which is compared byte for byte through both:
// drift between these files is a failing test rather than a thing to notice.

#import "internal.h"
#import <Metal/Metal.h>

// Metal, and only Metal. A host that accepted two languages would say so by
// setting two bits; this one speaks MSL and refuses the rest by name rather
// than failing to compile a shader and blaming the shader.
uint32_t ctd_gpu_shader_langs(void) {
    return CTD_SHADER_MSL;
}

// The object behind a handle, if it really is a GPU device.
//
// Metal's own protocol conformance is the type check, which is worth saying
// because it is not obvious that it works: a device is an instance of a
// private class — AGXG13GDevice on this machine — and what makes it a device
// is that the class declares <MTLDevice>. A buffer answers no to that and yes
// to <MTLBuffer>, so the same mechanism keeps the kinds apart as this file
// grows.
static id<MTLDevice> ctd_gpu_device_of(ctd_handle handle, ctd_status *problem) {
    id object = ctd_resolve(handle);
    if (!object) { *problem = CTD_ERR_STALE; return nil; }
    if (![object conformsToProtocol:@protocol(MTLDevice)]) {
        *problem = CTD_ERR_KIND;
        return nil;
    }
    *problem = CTD_OK;
    return (id<MTLDevice>)object;
}

// Whether a handle names something this file made. One place, so that every
// GPU kind added later is added to the release path at the same moment it
// becomes releasable.
static int ctd_gpu_is_object(id object) {
    return [object conformsToProtocol:@protocol(MTLDevice)];
}

ctd_handle ctd_gpu_device_new(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return 0;
    ctd_handle handle = ctd_track(device, -1);
    // A Create function hands back a reference of its own. The table took one
    // when it tracked it, so this one goes back — and when the table was full
    // and took none, this is what stops the device leaking.
    [device release];
    return handle;
}

int32_t ctd_gpu_device_name(ctd_handle device, char *out, int32_t cap) {
    ctd_status problem;
    id<MTLDevice> found = ctd_gpu_device_of(device, &problem);
    if (!found) return problem;
    return ctd_copy_out([found name], out, cap);
}

ctd_status ctd_gpu_device_limit(ctd_handle device, int32_t which, double *out) {
    ctd_status problem;
    id<MTLDevice> found = ctd_gpu_device_of(device, &problem);
    if (!found) return problem;
    if (!out) return CTD_ERR_RANGE;
    switch (which) {
        case CTD_GPU_UNIFIED_MEMORY:
            out[0] = [found hasUnifiedMemory] ? 1.0 : 0.0;
            return CTD_OK;
        case CTD_GPU_MAX_BUFFER_BYTES:
            out[0] = (double)[found maxBufferLength];
            return CTD_OK;
        case CTD_GPU_MEMORY_BYTES:
            // Zero where the driver has no opinion, which is the contract and
            // not a failure — the iOS Simulator's device answers exactly that.
            out[0] = (double)[found recommendedMaxWorkingSetSize];
            return CTD_OK;
        default:
            return CTD_ERR_RANGE;
    }
}

ctd_status ctd_gpu_release(ctd_handle object) {
    id found = ctd_resolve(object);
    if (!found) return CTD_ERR_STALE;
    if (!ctd_gpu_is_object(found)) return CTD_ERR_KIND;
    ctd_untrack(object);
    return CTD_OK;
}
