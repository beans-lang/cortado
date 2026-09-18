#include "gpu_backend.h"
#include "include/gpu/ganesh/gl/GrGLDirectContext.h"
#include "include/gpu/ganesh/gl/GrGLAssembleInterface.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <dlfcn.h>

namespace {
struct GlDevice final : CtdGpuDevice {
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLContext gl = EGL_NO_CONTEXT;
    ~GlDevice() override {
        if (display != EGL_NO_DISPLAY && gl != EGL_NO_CONTEXT)
            eglMakeCurrent(display, surface, surface, gl);
        context.reset();
        if (display != EGL_NO_DISPLAY) {
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            if (gl != EGL_NO_CONTEXT) eglDestroyContext(display, gl);
            if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface);
            eglTerminate(display);
        }
    }
};
}

std::unique_ptr<CtdGpuDevice> ctd_make_opengl() {
    auto gpu = std::make_unique<GlDevice>();
    gpu->display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    EGLint major = 0, minor = 0;
    if (gpu->display == EGL_NO_DISPLAY || !eglInitialize(gpu->display, &major, &minor)) {
        gpu->display = EGL_NO_DISPLAY;
        auto get_platform = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
            eglGetProcAddress("eglGetPlatformDisplayEXT"));
#ifdef EGL_PLATFORM_SURFACELESS_MESA
        if (get_platform) gpu->display = get_platform(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, nullptr);
#endif
        if (gpu->display == EGL_NO_DISPLAY || !eglInitialize(gpu->display, &major, &minor)) return nullptr;
    }
    if (!eglBindAPI(EGL_OPENGL_API)) return nullptr;
    const EGLint config_attrs[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE,
                                   EGL_OPENGL_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
                                   EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
    EGLConfig config = nullptr;
    EGLint count = 0;
    if (!eglChooseConfig(gpu->display, config_attrs, &config, 1, &count) || count == 0) return nullptr;
    const EGLint pbuffer_attrs[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
    gpu->surface = eglCreatePbufferSurface(gpu->display, config, pbuffer_attrs);
    if (gpu->surface == EGL_NO_SURFACE) return nullptr;
    gpu->gl = eglCreateContext(gpu->display, config, EGL_NO_CONTEXT, nullptr);
    if (gpu->gl == EGL_NO_CONTEXT || !eglMakeCurrent(gpu->display, gpu->surface, gpu->surface, gpu->gl)) return nullptr;
    auto interface = GrGLMakeAssembledGLInterface(nullptr, [](void*, const char* name) -> GrGLFuncPtr {
        auto proc = eglGetProcAddress(name);
        if (!proc) proc = reinterpret_cast<__eglMustCastToProperFunctionPointerType>(dlsym(RTLD_DEFAULT, name));
        return reinterpret_cast<GrGLFuncPtr>(proc);
    });
    gpu->context = interface ? GrDirectContexts::MakeGL(interface) : nullptr;
    return gpu->context ? std::move(gpu) : nullptr;
}
