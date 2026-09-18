#include "gpu_backend.h"
#if !defined(__APPLE__)
std::unique_ptr<CtdGpuDevice> ctd_make_metal() { return nullptr; }
#endif
#if !defined(_WIN32)
std::unique_ptr<CtdGpuDevice> ctd_make_vulkan() { return nullptr; }
#endif
#if !defined(__linux__)
std::unique_ptr<CtdGpuDevice> ctd_make_opengl() { return nullptr; }
#endif
