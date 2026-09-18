#include "gpu_backend.h"
#include "include/gpu/ganesh/vk/GrVkDirectContext.h"
#include "include/gpu/vk/VulkanBackendContext.h"
#include "include/gpu/vk/VulkanExtensions.h"
#include <windows.h>
#include <vector>

namespace {
struct VkDeviceOwner final : CtdGpuDevice {
    HMODULE loader = nullptr;
    VkInstance instance = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    PFN_vkDestroyDevice destroy_device = nullptr;
    PFN_vkDestroyInstance destroy_instance = nullptr;
    skgpu::VulkanExtensions extensions;
    ~VkDeviceOwner() override {
        if (context && !context->abandoned()) context->flushAndSubmit(GrSyncCpu::kYes);
        context.reset();
        if (device && destroy_device) destroy_device(device, nullptr);
        if (instance && destroy_instance) destroy_instance(instance, nullptr);
        if (loader) FreeLibrary(loader);
    }
};
}

std::unique_ptr<CtdGpuDevice> ctd_make_vulkan() {
    auto gpu = std::make_unique<VkDeviceOwner>();
    gpu->loader = LoadLibraryW(L"vulkan-1.dll");
    if (!gpu->loader) return nullptr;
    auto get_instance = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(gpu->loader, "vkGetInstanceProcAddr"));
    if (!get_instance) return nullptr;
    auto enumerate_version = reinterpret_cast<PFN_vkEnumerateInstanceVersion>(
        get_instance(VK_NULL_HANDLE, "vkEnumerateInstanceVersion"));
    if (!enumerate_version) return nullptr;
    uint32_t api_version = VK_API_VERSION_1_0;
    if (enumerate_version(&api_version) != VK_SUCCESS) return nullptr;
    if (VK_VERSION_MAJOR(api_version) < 1 ||
        (VK_VERSION_MAJOR(api_version) == 1 && VK_VERSION_MINOR(api_version) < 1)) return nullptr;
    auto create_instance = reinterpret_cast<PFN_vkCreateInstance>(get_instance(VK_NULL_HANDLE, "vkCreateInstance"));
    if (!create_instance) return nullptr;
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "Cortado Skia";
    app.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo instance_info{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    instance_info.pApplicationInfo = &app;
    if (create_instance(&instance_info, nullptr, &gpu->instance) != VK_SUCCESS) return nullptr;
    gpu->destroy_instance = reinterpret_cast<PFN_vkDestroyInstance>(
        get_instance(gpu->instance, "vkDestroyInstance"));
    auto enumerate_devices = reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(
        get_instance(gpu->instance, "vkEnumeratePhysicalDevices"));
    auto get_properties = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(
        get_instance(gpu->instance, "vkGetPhysicalDeviceProperties"));
    auto get_queue_families = reinterpret_cast<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(
        get_instance(gpu->instance, "vkGetPhysicalDeviceQueueFamilyProperties"));
    auto create_device = reinterpret_cast<PFN_vkCreateDevice>(get_instance(gpu->instance, "vkCreateDevice"));
    auto get_device_proc = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
        get_instance(gpu->instance, "vkGetDeviceProcAddr"));
    if (!gpu->destroy_instance || !enumerate_devices || !get_properties || !get_queue_families ||
        !create_device || !get_device_proc) return nullptr;
    uint32_t count = 0;
    if (enumerate_devices(gpu->instance, &count, nullptr) != VK_SUCCESS || !count) return nullptr;
    std::vector<VkPhysicalDevice> physical(count);
    if (enumerate_devices(gpu->instance, &count, physical.data()) != VK_SUCCESS) return nullptr;
    for (VkPhysicalDevice candidate : physical) {
        VkPhysicalDeviceProperties properties{};
        get_properties(candidate, &properties);
        if (properties.apiVersion < VK_API_VERSION_1_1) continue;
        uint32_t families = 0;
        get_queue_families(candidate, &families, nullptr);
        std::vector<VkQueueFamilyProperties> queues(families);
        get_queue_families(candidate, &families, queues.data());
        for (uint32_t index = 0; index < families; ++index) {
            if (!(queues[index].queueFlags & VK_QUEUE_GRAPHICS_BIT)) continue;
            float priority = 1.0f;
            VkDeviceQueueCreateInfo queue_info{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
            queue_info.queueFamilyIndex = index;
            queue_info.queueCount = 1;
            queue_info.pQueuePriorities = &priority;
            VkDeviceCreateInfo device_info{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
            device_info.queueCreateInfoCount = 1;
            device_info.pQueueCreateInfos = &queue_info;
            if (create_device(candidate, &device_info, nullptr, &gpu->device) != VK_SUCCESS) continue;
            gpu->destroy_device = reinterpret_cast<PFN_vkDestroyDevice>(
                get_device_proc(gpu->device, "vkDestroyDevice"));
            auto get_queue = reinterpret_cast<PFN_vkGetDeviceQueue>(
                get_device_proc(gpu->device, "vkGetDeviceQueue"));
            if (!gpu->destroy_device || !get_queue) return nullptr;
            VkQueue queue = VK_NULL_HANDLE;
            get_queue(gpu->device, index, 0, &queue);
            skgpu::VulkanBackendContext backend;
            backend.fInstance = gpu->instance;
            backend.fPhysicalDevice = candidate;
            backend.fDevice = gpu->device;
            backend.fQueue = queue;
            backend.fGraphicsQueueIndex = index;
            backend.fMaxAPIVersion = VK_API_VERSION_1_1;
            backend.fGetProc = [get_instance, get_device_proc](const char* name, VkInstance instance, VkDevice device) {
                return device ? get_device_proc(device, name) : get_instance(instance, name);
            };
            gpu->extensions.init(backend.fGetProc, gpu->instance, candidate, 0, nullptr, 0, nullptr);
            backend.fVkExtensions = &gpu->extensions;
            gpu->context = GrDirectContexts::MakeVulkan(backend);
            if (gpu->context) return gpu;
            gpu->destroy_device(gpu->device, nullptr);
            gpu->device = VK_NULL_HANDLE;
        }
    }
    return nullptr;
}
