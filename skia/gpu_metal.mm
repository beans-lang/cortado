#include "gpu_backend.h"
#include "include/gpu/ganesh/mtl/GrMtlBackendContext.h"
#include "include/gpu/ganesh/mtl/GrMtlDirectContext.h"
#import <Metal/Metal.h>

std::unique_ptr<CtdGpuDevice> ctd_make_metal() {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) return nullptr;
        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (!queue) return nullptr;
        GrMtlBackendContext backend;
        backend.fDevice.retain((GrMTLHandle)(__bridge const void*)device);
        backend.fQueue.retain((GrMTLHandle)(__bridge const void*)queue);
        auto result = std::make_unique<CtdGpuDevice>();
        result->context = GrDirectContexts::MakeMetal(backend);
        return result->context ? std::move(result) : nullptr;
    }
}
