//! nvlatency Vulkan Layer
//!
//! Implicit Vulkan layer that automatically injects NVIDIA Reflex
//! low latency markers using VK_NV_low_latency2.
//!
//! When enabled via NVLATENCY=1, this layer:
//! - Enables Reflex on swapchain creation
//! - Marks frame boundaries at vkQueuePresentKHR
//! - Marks render submit at vkQueueSubmit
//! - Provides latency metrics via shared memory

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Vulkan Types
// ============================================================================

const VkResult = enum(i32) {
    VK_SUCCESS = 0,
    VK_NOT_READY = 1,
    VK_TIMEOUT = 2,
    VK_INCOMPLETE = 5,
    VK_SUBOPTIMAL_KHR = 1000001003,
    VK_ERROR_OUT_OF_HOST_MEMORY = -1,
    VK_ERROR_OUT_OF_DEVICE_MEMORY = -2,
    VK_ERROR_INITIALIZATION_FAILED = -3,
    VK_ERROR_DEVICE_LOST = -4,
    VK_ERROR_LAYER_NOT_PRESENT = -6,
    VK_ERROR_EXTENSION_NOT_PRESENT = -7,
    VK_ERROR_OUT_OF_DATE_KHR = -1000001004,
    _,
};

const VkStructureType = enum(i32) {
    VK_STRUCTURE_TYPE_APPLICATION_INFO = 0,
    VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1,
    VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = 3,
    VK_STRUCTURE_TYPE_SUBMIT_INFO = 4,
    VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO = 47,
    VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO = 48,
    VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = 1000001000,
    VK_STRUCTURE_TYPE_PRESENT_INFO_KHR = 1000001001,
    // VK_NV_low_latency2 types
    VK_STRUCTURE_TYPE_SWAPCHAIN_LATENCY_CREATE_INFO_NV = 1000505002,
    VK_STRUCTURE_TYPE_LATENCY_SLEEP_MODE_INFO_NV = 1000505000,
    VK_STRUCTURE_TYPE_LATENCY_SUBMISSION_PRESENT_ID_NV = 1000505003,
    VK_STRUCTURE_TYPE_GET_LATENCY_MARKER_INFO_NV = 1000505004,
    VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV = 1000505005,
    VK_STRUCTURE_TYPE_LATENCY_TIMINGS_FRAME_REPORT_NV = 1000505006,
    _,
};

const VkLayerFunction = enum(i32) {
    VK_LAYER_LINK_INFO = 0,
    VK_LOADER_DATA_CALLBACK = 1,
    VK_LOADER_LAYER_CREATE_DEVICE_CALLBACK = 2,
    VK_LOADER_FEATURES = 3,
};

// Vulkan handles
const VkInstance = ?*anyopaque;
const VkPhysicalDevice = ?*anyopaque;
const VkDevice = ?*anyopaque;
const VkQueue = ?*anyopaque;
const VkSemaphore = u64;
const VkSwapchainKHR = u64;
const VkFence = u64;

// Function pointer type
const PFN_vkVoidFunction = ?*const fn () callconv(.c) void;
const PFN_vkGetInstanceProcAddr = *const fn (VkInstance, [*:0]const u8) callconv(.c) PFN_vkVoidFunction;
const PFN_vkGetDeviceProcAddr = *const fn (VkDevice, [*:0]const u8) callconv(.c) PFN_vkVoidFunction;

// ============================================================================
// Vulkan Structures
// ============================================================================

const VkApplicationInfo = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_APPLICATION_INFO,
    pNext: ?*const anyopaque = null,
    pApplicationName: ?[*:0]const u8 = null,
    applicationVersion: u32 = 0,
    pEngineName: ?[*:0]const u8 = null,
    engineVersion: u32 = 0,
    apiVersion: u32 = 0,
};

const VkInstanceCreateInfo = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    pApplicationInfo: ?*const VkApplicationInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
};

const VkDeviceQueueCreateInfo = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueFamilyIndex: u32 = 0,
    queueCount: u32 = 0,
    pQueuePriorities: ?[*]const f32 = null,
};

const VkDeviceCreateInfo = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueCreateInfoCount: u32 = 0,
    pQueueCreateInfos: ?[*]const VkDeviceQueueCreateInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
    pEnabledFeatures: ?*const anyopaque = null,
};

const VkSwapchainCreateInfoKHR = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    surface: u64 = 0,
    minImageCount: u32 = 0,
    imageFormat: i32 = 0,
    imageColorSpace: i32 = 0,
    imageExtent: extern struct { width: u32, height: u32 } = .{ .width = 0, .height = 0 },
    imageArrayLayers: u32 = 0,
    imageUsage: u32 = 0,
    imageSharingMode: i32 = 0,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    preTransform: u32 = 0,
    compositeAlpha: u32 = 0,
    presentMode: i32 = 0,
    clipped: u32 = 0,
    oldSwapchain: VkSwapchainKHR = 0,
};

const VkPresentInfoKHR = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    swapchainCount: u32 = 0,
    pSwapchains: ?[*]const VkSwapchainKHR = null,
    pImageIndices: ?[*]const u32 = null,
    pResults: ?[*]VkResult = null,
};

const VkSubmitInfo = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    pWaitDstStageMask: ?[*]const u32 = null,
    commandBufferCount: u32 = 0,
    pCommandBuffers: ?[*]const ?*anyopaque = null,
    signalSemaphoreCount: u32 = 0,
    pSignalSemaphores: ?[*]const VkSemaphore = null,
};

// Layer chain structures
const VkLayerInstanceLink = extern struct {
    pNext: ?*VkLayerInstanceLink,
    pfnNextGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfnNextGetPhysicalDeviceProcAddr: ?*const anyopaque,
};

const VkLayerDeviceLink = extern struct {
    pNext: ?*VkLayerDeviceLink,
    pfnNextGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfnNextGetDeviceProcAddr: PFN_vkGetDeviceProcAddr,
};

const VkLayerInstanceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    function: VkLayerFunction,
    u: extern union {
        pLayerInfo: *VkLayerInstanceLink,
        pfnSetInstanceLoaderData: ?*const anyopaque,
        loaderFeatures: u32,
    },
};

const VkLayerDeviceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    function: VkLayerFunction,
    u: extern union {
        pLayerInfo: *VkLayerDeviceLink,
        pfnSetDeviceLoaderData: ?*const anyopaque,
    },
};

// VK_NV_low_latency2 structures
const VkSwapchainLatencyCreateInfoNV = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_SWAPCHAIN_LATENCY_CREATE_INFO_NV,
    pNext: ?*const anyopaque = null,
    latencyModeEnable: u32 = 1, // VK_TRUE
};

const VkLatencySleepModeInfoNV = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_LATENCY_SLEEP_MODE_INFO_NV,
    pNext: ?*const anyopaque = null,
    lowLatencyMode: u32 = 1, // VK_TRUE
    lowLatencyBoost: u32 = 0, // VK_FALSE initially
    minimumIntervalUs: u32 = 0,
};

const VkLatencyMarkerNV = enum(i32) {
    VK_LATENCY_MARKER_SIMULATION_START_NV = 0,
    VK_LATENCY_MARKER_SIMULATION_END_NV = 1,
    VK_LATENCY_MARKER_RENDERSUBMIT_START_NV = 2,
    VK_LATENCY_MARKER_RENDERSUBMIT_END_NV = 3,
    VK_LATENCY_MARKER_PRESENT_START_NV = 4,
    VK_LATENCY_MARKER_PRESENT_END_NV = 5,
    VK_LATENCY_MARKER_INPUT_SAMPLE_NV = 6,
    VK_LATENCY_MARKER_TRIGGER_FLASH_NV = 7,
    VK_LATENCY_MARKER_OUT_OF_BAND_RENDERSUBMIT_START_NV = 8,
    VK_LATENCY_MARKER_OUT_OF_BAND_RENDERSUBMIT_END_NV = 9,
    VK_LATENCY_MARKER_OUT_OF_BAND_PRESENT_START_NV = 10,
    VK_LATENCY_MARKER_OUT_OF_BAND_PRESENT_END_NV = 11,
};

const VkSetLatencyMarkerInfoNV = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV,
    pNext: ?*const anyopaque = null,
    presentID: u64 = 0,
    marker: VkLatencyMarkerNV = .VK_LATENCY_MARKER_SIMULATION_START_NV,
};

const VkLatencySubmissionPresentIdNV = extern struct {
    sType: VkStructureType = .VK_STRUCTURE_TYPE_LATENCY_SUBMISSION_PRESENT_ID_NV,
    pNext: ?*const anyopaque = null,
    presentID: u64 = 0,
};

// ============================================================================
// Function Types
// ============================================================================

const PFN_vkCreateInstance = *const fn (*const VkInstanceCreateInfo, ?*const anyopaque, *VkInstance) callconv(.c) VkResult;
const PFN_vkDestroyInstance = *const fn (VkInstance, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreateDevice = *const fn (VkPhysicalDevice, *const VkDeviceCreateInfo, ?*const anyopaque, *VkDevice) callconv(.c) VkResult;
const PFN_vkDestroyDevice = *const fn (VkDevice, ?*const anyopaque) callconv(.c) void;
const PFN_vkCreateSwapchainKHR = *const fn (VkDevice, *const VkSwapchainCreateInfoKHR, ?*const anyopaque, *VkSwapchainKHR) callconv(.c) VkResult;
const PFN_vkDestroySwapchainKHR = *const fn (VkDevice, VkSwapchainKHR, ?*const anyopaque) callconv(.c) void;
const PFN_vkQueuePresentKHR = *const fn (VkQueue, *const VkPresentInfoKHR) callconv(.c) VkResult;
const PFN_vkQueueSubmit = *const fn (VkQueue, u32, [*]const VkSubmitInfo, VkFence) callconv(.c) VkResult;

// VK_NV_low_latency2 function types
const PFN_vkSetLatencySleepModeNV = *const fn (VkDevice, VkSwapchainKHR, *const VkLatencySleepModeInfoNV) callconv(.c) VkResult;
const PFN_vkSetLatencyMarkerNV = *const fn (VkDevice, VkSwapchainKHR, *const VkSetLatencyMarkerInfoNV) callconv(.c) void;

// ============================================================================
// Per-Instance Data
// ============================================================================

const InstanceData = struct {
    instance: VkInstance,
    pfn_GetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfn_DestroyInstance: PFN_vkDestroyInstance,
    pfn_CreateDevice: PFN_vkCreateDevice,
};

// ============================================================================
// Per-Device Data
// ============================================================================

const DeviceData = struct {
    device: VkDevice,
    instance_data: *InstanceData,
    pfn_GetDeviceProcAddr: PFN_vkGetDeviceProcAddr,
    pfn_DestroyDevice: PFN_vkDestroyDevice,
    pfn_CreateSwapchainKHR: ?PFN_vkCreateSwapchainKHR,
    pfn_DestroySwapchainKHR: ?PFN_vkDestroySwapchainKHR,
    pfn_QueuePresentKHR: ?PFN_vkQueuePresentKHR,
    pfn_QueueSubmit: ?PFN_vkQueueSubmit,
    // VK_NV_low_latency2
    pfn_SetLatencySleepModeNV: ?PFN_vkSetLatencySleepModeNV,
    pfn_SetLatencyMarkerNV: ?PFN_vkSetLatencyMarkerNV,
    low_latency_supported: bool,
};

// ============================================================================
// Per-Swapchain Data
// ============================================================================

const SwapchainData = struct {
    swapchain: VkSwapchainKHR,
    device_data: *DeviceData,
    reflex_enabled: bool,
    frame_id: u64,
};

// ============================================================================
// Global State
// ============================================================================

/// Use c_allocator since we link libc
const c_alloc = std.heap.c_allocator;
var allocator: std.mem.Allocator = c_alloc;
var initialized = false;
var layer_enabled = false;
var reflex_mode: enum { off, on, boost } = .on;

// Maps for tracking objects
var instance_map: std.AutoHashMap(usize, *InstanceData) = undefined;
var device_map: std.AutoHashMap(usize, *DeviceData) = undefined;
var swapchain_map: std.AutoHashMap(u64, *SwapchainData) = undefined;

// Thread safety
var global_mutex: std.c.pthread_mutex_t = std.c.PTHREAD_MUTEX_INITIALIZER;

fn initGlobalState() void {
    _ = std.c.pthread_mutex_lock(&global_mutex);
    defer _ = std.c.pthread_mutex_unlock(&global_mutex);

    if (initialized) return;

    instance_map = std.AutoHashMap(usize, *InstanceData).init(allocator);
    device_map = std.AutoHashMap(usize, *DeviceData).init(allocator);
    swapchain_map = std.AutoHashMap(u64, *SwapchainData).init(allocator);

    // Check environment for layer enable
    if (std.c.getenv("NVLATENCY")) |val| {
        layer_enabled = !std.mem.eql(u8, std.mem.sliceTo(val, 0), "0");
    } else {
        layer_enabled = false;
    }

    // Check Reflex mode
    if (std.c.getenv("NVLATENCY_REFLEX_MODE")) |mode_ptr| {
        const mode = std.mem.sliceTo(mode_ptr, 0);
        if (std.mem.eql(u8, mode, "off")) {
            reflex_mode = .off;
        } else if (std.mem.eql(u8, mode, "boost")) {
            reflex_mode = .boost;
        } else {
            reflex_mode = .on;
        }
    }

    initialized = true;
}

// ============================================================================
// Layer Implementation
// ============================================================================

export fn nvlatency_CreateInstance(
    pCreateInfo: *const VkInstanceCreateInfo,
    pAllocator: ?*const anyopaque,
    pInstance: *VkInstance,
) callconv(.c) VkResult {
    initGlobalState();

    // Find layer link info
    var layer_info: ?*VkLayerInstanceCreateInfo = null;
    {
        var info: ?*const VkLayerInstanceCreateInfo = @ptrCast(@alignCast(pCreateInfo.pNext));
        while (info) |i| {
            if (i.sType == .VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO and
                i.function == .VK_LAYER_LINK_INFO)
            {
                layer_info = @constCast(i);
                break;
            }
            info = @ptrCast(@alignCast(i.pNext));
        }
    }

    if (layer_info == null) {
        return .VK_ERROR_INITIALIZATION_FAILED;
    }

    const layer_link = layer_info.?.u.pLayerInfo;
    const pfn_GetInstanceProcAddr = layer_link.pfnNextGetInstanceProcAddr;

    // Advance chain for next layer
    layer_info.?.u.pLayerInfo = layer_link.pNext.?;

    // Get vkCreateInstance from next layer
    const pfn_CreateInstance: ?PFN_vkCreateInstance = @ptrCast(pfn_GetInstanceProcAddr(null, "vkCreateInstance"));
    if (pfn_CreateInstance == null) {
        return .VK_ERROR_INITIALIZATION_FAILED;
    }

    // Call next layer
    const result = pfn_CreateInstance.?(pCreateInfo, pAllocator, pInstance);
    if (result != .VK_SUCCESS) {
        return result;
    }

    // Store instance data
    const instance = pInstance.*;
    const pfn_DestroyInstance: ?PFN_vkDestroyInstance = @ptrCast(pfn_GetInstanceProcAddr(instance, "vkDestroyInstance"));
    const pfn_CreateDevice: ?PFN_vkCreateDevice = @ptrCast(pfn_GetInstanceProcAddr(instance, "vkCreateDevice"));

    const data = allocator.create(InstanceData) catch return .VK_ERROR_OUT_OF_HOST_MEMORY;
    data.* = .{
        .instance = instance,
        .pfn_GetInstanceProcAddr = pfn_GetInstanceProcAddr,
        .pfn_DestroyInstance = pfn_DestroyInstance.?,
        .pfn_CreateDevice = pfn_CreateDevice.?,
    };

    _ = std.c.pthread_mutex_lock(&global_mutex);
    instance_map.put(@intFromPtr(instance), data) catch {
        _ = std.c.pthread_mutex_unlock(&global_mutex);
        return .VK_ERROR_OUT_OF_HOST_MEMORY;
    };
    _ = std.c.pthread_mutex_unlock(&global_mutex);

    return .VK_SUCCESS;
}

export fn nvlatency_DestroyInstance(
    instance: VkInstance,
    pAllocator: ?*const anyopaque,
) callconv(.c) void {
    _ = std.c.pthread_mutex_lock(&global_mutex);
    const data = instance_map.get(@intFromPtr(instance));
    if (data) |d| {
        _ = instance_map.remove(@intFromPtr(instance));
        _ = std.c.pthread_mutex_unlock(&global_mutex);
        d.pfn_DestroyInstance(instance, pAllocator);
        allocator.destroy(d);
    } else {
        _ = std.c.pthread_mutex_unlock(&global_mutex);
    }
}

export fn nvlatency_CreateDevice(
    physicalDevice: VkPhysicalDevice,
    pCreateInfo: *const VkDeviceCreateInfo,
    pAllocator: ?*const anyopaque,
    pDevice: *VkDevice,
) callconv(.c) VkResult {
    // Find layer link info
    var layer_info: ?*VkLayerDeviceCreateInfo = null;
    {
        var info: ?*const VkLayerDeviceCreateInfo = @ptrCast(@alignCast(pCreateInfo.pNext));
        while (info) |i| {
            if (i.sType == .VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO and
                i.function == .VK_LAYER_LINK_INFO)
            {
                layer_info = @constCast(i);
                break;
            }
            info = @ptrCast(@alignCast(i.pNext));
        }
    }

    if (layer_info == null) {
        return .VK_ERROR_INITIALIZATION_FAILED;
    }

    const layer_link = layer_info.?.u.pLayerInfo;
    const pfn_GetInstanceProcAddr = layer_link.pfnNextGetInstanceProcAddr;
    const pfn_GetDeviceProcAddr = layer_link.pfnNextGetDeviceProcAddr;

    // Advance chain
    layer_info.?.u.pLayerInfo = layer_link.pNext.?;

    // Get instance data
    _ = std.c.pthread_mutex_lock(&global_mutex);
    var instance_data: ?*InstanceData = null;
    var iter = instance_map.valueIterator();
    while (iter.next()) |d| {
        instance_data = d.*;
        break;
    }
    _ = std.c.pthread_mutex_unlock(&global_mutex);

    if (instance_data == null) {
        return .VK_ERROR_INITIALIZATION_FAILED;
    }

    // Get vkCreateDevice
    const pfn_CreateDevice: ?PFN_vkCreateDevice = @ptrCast(pfn_GetInstanceProcAddr(instance_data.?.instance, "vkCreateDevice"));
    if (pfn_CreateDevice == null) {
        return .VK_ERROR_INITIALIZATION_FAILED;
    }

    // Call next layer
    const result = pfn_CreateDevice.?(physicalDevice, pCreateInfo, pAllocator, pDevice);
    if (result != .VK_SUCCESS) {
        return result;
    }

    const device = pDevice.*;

    // Get device function pointers
    const pfn_DestroyDevice: ?PFN_vkDestroyDevice = @ptrCast(pfn_GetDeviceProcAddr(device, "vkDestroyDevice"));
    const pfn_CreateSwapchainKHR: ?PFN_vkCreateSwapchainKHR = @ptrCast(pfn_GetDeviceProcAddr(device, "vkCreateSwapchainKHR"));
    const pfn_DestroySwapchainKHR: ?PFN_vkDestroySwapchainKHR = @ptrCast(pfn_GetDeviceProcAddr(device, "vkDestroySwapchainKHR"));
    const pfn_QueuePresentKHR: ?PFN_vkQueuePresentKHR = @ptrCast(pfn_GetDeviceProcAddr(device, "vkQueuePresentKHR"));
    const pfn_QueueSubmit: ?PFN_vkQueueSubmit = @ptrCast(pfn_GetDeviceProcAddr(device, "vkQueueSubmit"));

    // Check for VK_NV_low_latency2 support
    const pfn_SetLatencySleepModeNV: ?PFN_vkSetLatencySleepModeNV = @ptrCast(pfn_GetDeviceProcAddr(device, "vkSetLatencySleepModeNV"));
    const pfn_SetLatencyMarkerNV: ?PFN_vkSetLatencyMarkerNV = @ptrCast(pfn_GetDeviceProcAddr(device, "vkSetLatencyMarkerNV"));
    const low_latency_supported = pfn_SetLatencySleepModeNV != null and pfn_SetLatencyMarkerNV != null;

    // Store device data
    const data = allocator.create(DeviceData) catch return .VK_ERROR_OUT_OF_HOST_MEMORY;
    data.* = .{
        .device = device,
        .instance_data = instance_data.?,
        .pfn_GetDeviceProcAddr = pfn_GetDeviceProcAddr,
        .pfn_DestroyDevice = pfn_DestroyDevice.?,
        .pfn_CreateSwapchainKHR = pfn_CreateSwapchainKHR,
        .pfn_DestroySwapchainKHR = pfn_DestroySwapchainKHR,
        .pfn_QueuePresentKHR = pfn_QueuePresentKHR,
        .pfn_QueueSubmit = pfn_QueueSubmit,
        .pfn_SetLatencySleepModeNV = pfn_SetLatencySleepModeNV,
        .pfn_SetLatencyMarkerNV = pfn_SetLatencyMarkerNV,
        .low_latency_supported = low_latency_supported,
    };

    _ = std.c.pthread_mutex_lock(&global_mutex);
    device_map.put(@intFromPtr(device), data) catch {
        _ = std.c.pthread_mutex_unlock(&global_mutex);
        return .VK_ERROR_OUT_OF_HOST_MEMORY;
    };
    _ = std.c.pthread_mutex_unlock(&global_mutex);

    return .VK_SUCCESS;
}

export fn nvlatency_DestroyDevice(
    device: VkDevice,
    pAllocator: ?*const anyopaque,
) callconv(.c) void {
    _ = std.c.pthread_mutex_lock(&global_mutex);
    const data = device_map.get(@intFromPtr(device));
    if (data) |d| {
        _ = device_map.remove(@intFromPtr(device));
        _ = std.c.pthread_mutex_unlock(&global_mutex);
        d.pfn_DestroyDevice(device, pAllocator);
        allocator.destroy(d);
    } else {
        _ = std.c.pthread_mutex_unlock(&global_mutex);
    }
}

export fn nvlatency_CreateSwapchainKHR(
    device: VkDevice,
    pCreateInfo: *const VkSwapchainCreateInfoKHR,
    pAllocator: ?*const anyopaque,
    pSwapchain: *VkSwapchainKHR,
) callconv(.c) VkResult {
    _ = std.c.pthread_mutex_lock(&global_mutex);
    const device_data = device_map.get(@intFromPtr(device));
    _ = std.c.pthread_mutex_unlock(&global_mutex);

    if (device_data == null or device_data.?.pfn_CreateSwapchainKHR == null) {
        return .VK_ERROR_INITIALIZATION_FAILED;
    }

    const dd = device_data.?;

    // If low latency supported and enabled, chain latency create info
    var latency_info = VkSwapchainLatencyCreateInfoNV{
        .sType = .VK_STRUCTURE_TYPE_SWAPCHAIN_LATENCY_CREATE_INFO_NV,
        .pNext = pCreateInfo.pNext,
        .latencyModeEnable = if (layer_enabled and dd.low_latency_supported and reflex_mode != .off) 1 else 0,
    };

    // Create modified create info with latency chained
    var modified_create_info = pCreateInfo.*;
    if (layer_enabled and dd.low_latency_supported and reflex_mode != .off) {
        modified_create_info.pNext = &latency_info;
    }

    // Call next layer
    const result = dd.pfn_CreateSwapchainKHR.?(device, &modified_create_info, pAllocator, pSwapchain);
    if (result != .VK_SUCCESS) {
        return result;
    }

    const swapchain = pSwapchain.*;

    // Set latency sleep mode if supported
    var reflex_enabled = false;
    if (layer_enabled and dd.low_latency_supported and reflex_mode != .off) {
        if (dd.pfn_SetLatencySleepModeNV) |setMode| {
            const mode_info = VkLatencySleepModeInfoNV{
                .sType = .VK_STRUCTURE_TYPE_LATENCY_SLEEP_MODE_INFO_NV,
                .pNext = null,
                .lowLatencyMode = 1,
                .lowLatencyBoost = if (reflex_mode == .boost) 1 else 0,
                .minimumIntervalUs = 0,
            };
            const mode_result = setMode(device, swapchain, &mode_info);
            reflex_enabled = (mode_result == .VK_SUCCESS);
        }
    }

    // Store swapchain data
    const sc_data = allocator.create(SwapchainData) catch return .VK_ERROR_OUT_OF_HOST_MEMORY;
    sc_data.* = .{
        .swapchain = swapchain,
        .device_data = dd,
        .reflex_enabled = reflex_enabled,
        .frame_id = 0,
    };

    _ = std.c.pthread_mutex_lock(&global_mutex);
    swapchain_map.put(swapchain, sc_data) catch {
        _ = std.c.pthread_mutex_unlock(&global_mutex);
        return .VK_ERROR_OUT_OF_HOST_MEMORY;
    };
    _ = std.c.pthread_mutex_unlock(&global_mutex);

    return .VK_SUCCESS;
}

export fn nvlatency_DestroySwapchainKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pAllocator: ?*const anyopaque,
) callconv(.c) void {
    _ = std.c.pthread_mutex_lock(&global_mutex);
    const device_data = device_map.get(@intFromPtr(device));
    const sc_data = swapchain_map.get(swapchain);
    if (sc_data) |s| {
        _ = swapchain_map.remove(swapchain);
        allocator.destroy(s);
    }
    _ = std.c.pthread_mutex_unlock(&global_mutex);

    if (device_data) |dd| {
        if (dd.pfn_DestroySwapchainKHR) |destroy| {
            destroy(device, swapchain, pAllocator);
        }
    }
}

export fn nvlatency_QueuePresentKHR(
    queue: VkQueue,
    pPresentInfo: *const VkPresentInfoKHR,
) callconv(.c) VkResult {
    // Get swapchain data for first swapchain
    var sc_data: ?*SwapchainData = null;
    if (pPresentInfo.swapchainCount > 0 and pPresentInfo.pSwapchains != null) {
        _ = std.c.pthread_mutex_lock(&global_mutex);
        sc_data = swapchain_map.get(pPresentInfo.pSwapchains.?[0]);
        _ = std.c.pthread_mutex_unlock(&global_mutex);
    }

    if (sc_data) |sd| {
        sd.frame_id += 1;

        // Mark present start
        if (sd.reflex_enabled) {
            if (sd.device_data.pfn_SetLatencyMarkerNV) |setMarker| {
                const marker_info = VkSetLatencyMarkerInfoNV{
                    .sType = .VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV,
                    .pNext = null,
                    .presentID = sd.frame_id,
                    .marker = .VK_LATENCY_MARKER_PRESENT_START_NV,
                };
                setMarker(sd.device_data.device, sd.swapchain, &marker_info);
            }
        }

        // Call actual present
        const result = if (sd.device_data.pfn_QueuePresentKHR) |present|
            present(queue, pPresentInfo)
        else
            VkResult.VK_SUCCESS;

        // Mark present end
        if (sd.reflex_enabled) {
            if (sd.device_data.pfn_SetLatencyMarkerNV) |setMarker| {
                const marker_info = VkSetLatencyMarkerInfoNV{
                    .sType = .VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV,
                    .pNext = null,
                    .presentID = sd.frame_id,
                    .marker = .VK_LATENCY_MARKER_PRESENT_END_NV,
                };
                setMarker(sd.device_data.device, sd.swapchain, &marker_info);
            }
        }

        return result;
    }

    // No swapchain data - find any device and call present
    _ = std.c.pthread_mutex_lock(&global_mutex);
    var device_data: ?*DeviceData = null;
    var iter = device_map.valueIterator();
    while (iter.next()) |d| {
        device_data = d.*;
        break;
    }
    _ = std.c.pthread_mutex_unlock(&global_mutex);

    if (device_data) |dd| {
        if (dd.pfn_QueuePresentKHR) |present| {
            return present(queue, pPresentInfo);
        }
    }

    return .VK_SUCCESS;
}

export fn nvlatency_QueueSubmit(
    queue: VkQueue,
    submitCount: u32,
    pSubmits: [*]const VkSubmitInfo,
    fence: VkFence,
) callconv(.c) VkResult {
    // Find device data
    _ = std.c.pthread_mutex_lock(&global_mutex);
    var device_data: ?*DeviceData = null;
    var iter = device_map.valueIterator();
    while (iter.next()) |d| {
        device_data = d.*;
        break;
    }
    _ = std.c.pthread_mutex_unlock(&global_mutex);

    if (device_data == null or device_data.?.pfn_QueueSubmit == null) {
        return .VK_ERROR_INITIALIZATION_FAILED;
    }

    const dd = device_data.?;

    // Mark render submit start if Reflex enabled
    if (layer_enabled and dd.low_latency_supported and reflex_mode != .off) {
        _ = std.c.pthread_mutex_lock(&global_mutex);
        var sc_iter = swapchain_map.valueIterator();
        while (sc_iter.next()) |sd_ptr| {
            const sd = sd_ptr.*;
            if (sd.reflex_enabled) {
                if (dd.pfn_SetLatencyMarkerNV) |setMarker| {
                    const marker_info = VkSetLatencyMarkerInfoNV{
                        .sType = .VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV,
                        .pNext = null,
                        .presentID = sd.frame_id + 1, // Next frame
                        .marker = .VK_LATENCY_MARKER_RENDERSUBMIT_START_NV,
                    };
                    setMarker(dd.device, sd.swapchain, &marker_info);
                }
                break;
            }
        }
        _ = std.c.pthread_mutex_unlock(&global_mutex);
    }

    // Call actual submit
    const result = dd.pfn_QueueSubmit.?(queue, submitCount, pSubmits, fence);

    // Mark render submit end
    if (layer_enabled and dd.low_latency_supported and reflex_mode != .off) {
        _ = std.c.pthread_mutex_lock(&global_mutex);
        var sc_iter = swapchain_map.valueIterator();
        while (sc_iter.next()) |sd_ptr| {
            const sd = sd_ptr.*;
            if (sd.reflex_enabled) {
                if (dd.pfn_SetLatencyMarkerNV) |setMarker| {
                    const marker_info = VkSetLatencyMarkerInfoNV{
                        .sType = .VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV,
                        .pNext = null,
                        .presentID = sd.frame_id + 1,
                        .marker = .VK_LATENCY_MARKER_RENDERSUBMIT_END_NV,
                    };
                    setMarker(dd.device, sd.swapchain, &marker_info);
                }
                break;
            }
        }
        _ = std.c.pthread_mutex_unlock(&global_mutex);
    }

    return result;
}

// ============================================================================
// Layer Entry Points
// ============================================================================

export fn nvlatency_GetInstanceProcAddr(instance: VkInstance, pName: [*:0]const u8) callconv(.c) PFN_vkVoidFunction {
    const name = std.mem.span(pName);

    // Return our hooks
    if (std.mem.eql(u8, name, "vkCreateInstance")) return @ptrCast(&nvlatency_CreateInstance);
    if (std.mem.eql(u8, name, "vkDestroyInstance")) return @ptrCast(&nvlatency_DestroyInstance);
    if (std.mem.eql(u8, name, "vkCreateDevice")) return @ptrCast(&nvlatency_CreateDevice);
    if (std.mem.eql(u8, name, "vkGetInstanceProcAddr")) return @ptrCast(&nvlatency_GetInstanceProcAddr);

    // Pass through to next layer
    if (instance != null) {
        _ = std.c.pthread_mutex_lock(&global_mutex);
        const data = instance_map.get(@intFromPtr(instance));
        _ = std.c.pthread_mutex_unlock(&global_mutex);
        if (data) |d| {
            return d.pfn_GetInstanceProcAddr(instance, pName);
        }
    }

    return null;
}

export fn nvlatency_GetDeviceProcAddr(device: VkDevice, pName: [*:0]const u8) callconv(.c) PFN_vkVoidFunction {
    const name = std.mem.span(pName);

    // Return our hooks
    if (std.mem.eql(u8, name, "vkDestroyDevice")) return @ptrCast(&nvlatency_DestroyDevice);
    if (std.mem.eql(u8, name, "vkCreateSwapchainKHR")) return @ptrCast(&nvlatency_CreateSwapchainKHR);
    if (std.mem.eql(u8, name, "vkDestroySwapchainKHR")) return @ptrCast(&nvlatency_DestroySwapchainKHR);
    if (std.mem.eql(u8, name, "vkQueuePresentKHR")) return @ptrCast(&nvlatency_QueuePresentKHR);
    if (std.mem.eql(u8, name, "vkQueueSubmit")) return @ptrCast(&nvlatency_QueueSubmit);
    if (std.mem.eql(u8, name, "vkGetDeviceProcAddr")) return @ptrCast(&nvlatency_GetDeviceProcAddr);

    // Pass through to next layer
    if (device != null) {
        _ = std.c.pthread_mutex_lock(&global_mutex);
        const data = device_map.get(@intFromPtr(device));
        _ = std.c.pthread_mutex_unlock(&global_mutex);
        if (data) |d| {
            return d.pfn_GetDeviceProcAddr(device, pName);
        }
    }

    return null;
}

export fn vkNegotiateLoaderLayerInterfaceVersion(pVersionStruct: *anyopaque) callconv(.c) VkResult {
    _ = pVersionStruct;
    initGlobalState();
    return .VK_SUCCESS;
}

// ============================================================================
// Layer Info
// ============================================================================

pub const layer_name = "VK_LAYER_NVLATENCY_reflex";
pub const layer_description = "nvlatency - NVIDIA Reflex Low Latency Layer";
pub const layer_version = "1.0.0";
