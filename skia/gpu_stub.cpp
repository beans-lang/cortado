#include "gpu_backend.h"
// Every device the build did not compile in. CMakeLists defines one macro per
// platform file it adds, so this and that list cannot drift apart.
#if !defined(CORTADO_SKIA_METAL)
std::unique_ptr<CtdGpuDevice> ctd_make_metal() { return nullptr; }
#endif
#if !defined(CORTADO_SKIA_VULKAN)
std::unique_ptr<CtdGpuDevice> ctd_make_vulkan() { return nullptr; }
#endif
#if !defined(CORTADO_SKIA_GL)
std::unique_ptr<CtdGpuDevice> ctd_make_opengl() { return nullptr; }
#endif
