cmake_minimum_required(VERSION 3.20)
project(cortado_skia_engine LANGUAGES CXX)
if(NOT SKIA_SDK OR NOT SKIA_LIB)
  message(FATAL_ERROR "Set SKIA_SDK and SKIA_LIB to a pinned SDK prepared by prepare_skia.py")
endif()
add_library(cortado_skia_engine SHARED bridge.cpp gpu_stub.cpp)
target_compile_features(cortado_skia_engine PRIVATE cxx_std_17)
target_include_directories(cortado_skia_engine PRIVATE "${SKIA_SDK}")
option(CORTADO_SANITIZE "Instrument the C++ bridge with address/undefined sanitizers" OFF)
if(CORTADO_SANITIZE)
  if(MSVC)
    message(FATAL_ERROR "The sanitizer bridge requires a Clang/GCC toolchain")
  endif()
  target_compile_options(cortado_skia_engine PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
  target_link_options(cortado_skia_engine PRIVATE -fsanitize=address,undefined)
endif()
file(GLOB SKIA_ARCHIVES "${SKIA_LIB}/*.a" "${SKIA_LIB}/*.lib")
if(NOT SKIA_ARCHIVES)
  message(FATAL_ERROR "No Skia archives in ${SKIA_LIB}")
endif()
# One source of truth for which device this build has: the stub supplies every
# factory this does not define, so a platform file and its stub cannot disagree.
if(APPLE)
  enable_language(OBJCXX)
  target_sources(cortado_skia_engine PRIVATE gpu_metal.mm)
  target_compile_definitions(cortado_skia_engine PRIVATE CORTADO_SKIA_METAL=1)
  target_compile_options(cortado_skia_engine PRIVATE "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
  target_link_libraries(cortado_skia_engine PRIVATE ${SKIA_ARCHIVES}
    "-framework CoreText" "-framework CoreGraphics" "-framework CoreFoundation"
    "-framework ApplicationServices" "-framework Metal" "-framework QuartzCore" "-framework Foundation")
elseif(WIN32)
  # Skia's archives are built against the static CRT. CMake defaults to the
  # dynamic one, and then every object fails to link with LNK2038.
  set_property(TARGET cortado_skia_engine PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  set_target_properties(cortado_skia_engine PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
  # gpu_vulkan_win.cpp is not built: the pinned pack has no Vulkan backend in it
  # — the linker finds GrD3DRootSignature and no GrDirectContexts::MakeVulkan —
  # so Windows draws on the CPU until a Direct3D device is written. skia.lib
  # still references D3D12 whether or not we use it, hence the two libraries.
  target_link_libraries(cortado_skia_engine PRIVATE ${SKIA_ARCHIVES}
    dwrite ole32 user32 gdi32 uuid windowscodecs opengl32 d3d12 dxgi d3dcompiler)
else()
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(FONTCONFIG REQUIRED IMPORTED_TARGET fontconfig)
  pkg_check_modules(EGL REQUIRED IMPORTED_TARGET egl)
  pkg_check_modules(GL REQUIRED IMPORTED_TARGET gl)
  target_sources(cortado_skia_engine PRIVATE gpu_gl_linux.cpp)
  target_compile_definitions(cortado_skia_engine PRIVATE CORTADO_SKIA_GL=1)
  target_link_libraries(cortado_skia_engine PRIVATE "-Wl,--start-group" ${SKIA_ARCHIVES}
    "-Wl,--end-group" PkgConfig::FONTCONFIG PkgConfig::EGL PkgConfig::GL dl pthread)
endif()
