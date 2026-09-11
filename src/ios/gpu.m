// The GPU, through Metal — the same framework the Mac draws with.
//
// A phone is the platform where drawing on the GPU matters most, and iOS is
// where Metal came from, so this host is real rather than a refusal. It was
// proven that way before it was written: in the Simulator on this machine a
// device comes back, MSL compiles at run time, and a command queue is made.
//
// **Two things the Simulator answers differently from the Mac it runs on**,
// which is why no golden in this suite prints a number from here. Its device
// is "Apple iOS simulator GPU", not the host machine's; it reports *no*
// unified memory on a machine that has it; its largest buffer is 256 MB
// against the Mac's 9.5 GB; and `recommendedMaxWorkingSetSize` answers zero.
// The last is a real value and not an error — the driver has no opinion —
// which is why the contract says zero means unsaid rather than refusing.
//
// **Why this is a near-copy of src/mac/gpu.m rather than shared source.**
// `tools/check_hosts.sh` reads each platform directory for the entry points
// it defines, so a host that got its symbols from a shared file would read as
// incomplete; and the two platforms do diverge (a managed storage mode that
// exists only on the Mac, a layer that hangs off a UIView rather than an
// NSView). What holds them together is `tests/gpu.out`, compared byte for
// byte through both: drift here is a failing test, not a thing to notice.

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
// Metal's own protocol conformance is the type check. A device is an instance
// of a private class whose name differs on every machine and in the Simulator
// again; what makes it a device is that the class declares <MTLDevice>. A
// buffer answers no to that and yes to <MTLBuffer>, so the same mechanism
// keeps the kinds apart as this file grows.
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
