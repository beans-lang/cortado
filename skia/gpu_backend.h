#pragma once

#include "include/gpu/ganesh/GrDirectContext.h"
#include <memory>

// One platform device per renderer. Its context outlives every GPU surface.
struct CtdGpuDevice {
    sk_sp<GrDirectContext> context;
    virtual ~CtdGpuDevice() { context.reset(); }
};

std::unique_ptr<CtdGpuDevice> ctd_make_metal();
std::unique_ptr<CtdGpuDevice> ctd_make_vulkan();
std::unique_ptr<CtdGpuDevice> ctd_make_opengl();
