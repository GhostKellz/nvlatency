//! C ABI exports for nvlatency library
//!
//! Provides C-compatible function exports for integration with
//! games, overlays, and other tools.

const std = @import("std");
const nvlatency = @import("nvlatency");
const nvvk = @import("nvvk");

// =============================================================================
// Type Aliases for C ABI
// =============================================================================

pub const NvlatDevice = *anyopaque;
pub const NvlatSwapchain = u64;
pub const NvlatSemaphore = u64;

pub const NvlatResult = enum(i32) {
    success = 0,
    error_not_supported = -1,
    error_invalid_handle = -2,
    error_out_of_memory = -3,
    error_unknown = -5,
};

pub const NvlatReflexMode = enum(i32) {
    off = 0,
    on = 1,
    boost = 2,
};

/// Frame timing data for C consumers
pub const NvlatFrameTimings = extern struct {
    frame_id: u64,
    simulation_us: u64,
    render_submit_us: u64,
    present_us: u64,
    total_us: u64,
    input_latency_us: u64,
};

/// Aggregated metrics for C consumers
pub const NvlatMetrics = extern struct {
    total_frames: u64,
    avg_frame_time_us: u64,
    avg_fps: f32,
    fps_1_low: f32,
    avg_input_latency_us: u64,
};

// =============================================================================
// Opaque Handle
// =============================================================================

const LatencyHandle = struct {
    ctx: nvlatency.LatencyContext,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// =============================================================================
// Initialization
// =============================================================================

/// Initialize latency context
export fn nvlat_init(
    device: NvlatDevice,
    swapchain: NvlatSwapchain,
    get_device_proc_addr: *const fn (*anyopaque, [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void,
) ?*LatencyHandle {
    const allocator = gpa.allocator();

    const handle = allocator.create(LatencyHandle) catch return null;

    const vk_device: nvvk.VkDevice = @ptrCast(device);
    handle.ctx = nvlatency.LatencyContext.init(
        allocator,
        vk_device,
        swapchain,
        @ptrCast(get_device_proc_addr),
    );

    return handle;
}

/// Destroy latency context
export fn nvlat_destroy(handle: ?*LatencyHandle) void {
    if (handle) |h| {
        gpa.allocator().destroy(h);
    }
}

/// Check if Reflex is supported
export fn nvlat_is_supported(handle: ?*const LatencyHandle) bool {
    if (handle) |h| {
        return h.ctx.isSupported();
    }
    return false;
}

// =============================================================================
// Reflex Control
// =============================================================================

/// Set Reflex mode
export fn nvlat_set_reflex_mode(handle: ?*LatencyHandle, mode: NvlatReflexMode) NvlatResult {
    const h = handle orelse return .error_invalid_handle;

    const zig_mode: nvlatency.ReflexMode = switch (mode) {
        .off => .off,
        .on => .on,
        .boost => .boost,
    };

    h.ctx.setReflexMode(zig_mode) catch |err| {
        return switch (err) {
            error.ReflexNotSupported => .error_not_supported,
            else => .error_unknown,
        };
    };

    return .success;
}

/// Get current Reflex mode
export fn nvlat_get_reflex_mode(handle: ?*const LatencyHandle) NvlatReflexMode {
    const h = handle orelse return .off;
    return switch (h.ctx.getReflexMode()) {
        .off => .off,
        .on => .on,
        .boost => .boost,
    };
}

// =============================================================================
// Frame Marking
// =============================================================================

/// Begin a new frame
export fn nvlat_begin_frame(handle: ?*LatencyHandle) u64 {
    const h = handle orelse return 0;
    return h.ctx.beginFrame();
}

/// Mark input sample
export fn nvlat_mark_input_sample(handle: ?*LatencyHandle) void {
    const h = handle orelse return;
    h.ctx.markInputSample();
}

/// Mark end of simulation
export fn nvlat_mark_simulation_end(handle: ?*LatencyHandle) void {
    const h = handle orelse return;
    h.ctx.markSimulationEnd();
}

/// Mark start of render submit
export fn nvlat_mark_render_submit_start(handle: ?*LatencyHandle) void {
    const h = handle orelse return;
    h.ctx.markRenderSubmitStart();
}

/// Mark end of render submit
export fn nvlat_mark_render_submit_end(handle: ?*LatencyHandle) void {
    const h = handle orelse return;
    h.ctx.markRenderSubmitEnd();
}

/// Mark start of present
export fn nvlat_mark_present_start(handle: ?*LatencyHandle) void {
    const h = handle orelse return;
    h.ctx.markPresentStart();
}

/// Mark end of present
export fn nvlat_mark_present_end(handle: ?*LatencyHandle) void {
    const h = handle orelse return;
    h.ctx.markPresentEnd();
}

/// End frame and get timings
export fn nvlat_end_frame(handle: ?*LatencyHandle, out_timings: ?*NvlatFrameTimings) void {
    const h = handle orelse return;
    const frame = h.ctx.endFrame();

    if (out_timings) |t| {
        t.* = .{
            .frame_id = frame.frame_id,
            .simulation_us = frame.simulation_us,
            .render_submit_us = frame.render_submit_us,
            .present_us = frame.present_us,
            .total_us = frame.total_us,
            .input_latency_us = frame.input_latency_us,
        };
    }
}

/// Reflex sleep
export fn nvlat_sleep(handle: ?*LatencyHandle, semaphore: NvlatSemaphore, value: u64) NvlatResult {
    const h = handle orelse return .error_invalid_handle;
    h.ctx.sleep(semaphore, value) catch return .error_not_supported;
    return .success;
}

// =============================================================================
// Metrics
// =============================================================================

/// Get aggregated metrics
export fn nvlat_get_metrics(handle: ?*const LatencyHandle, out_metrics: ?*NvlatMetrics) void {
    const h = handle orelse return;
    const m = h.ctx.getMetrics();

    if (out_metrics) |out| {
        out.* = .{
            .total_frames = m.total_frames,
            .avg_frame_time_us = m.avgFrameTimeUs(),
            .avg_fps = @floatCast(m.avgFps()),
            .fps_1_low = @floatCast(m.fps1Low()),
            .avg_input_latency_us = m.input_latency_avg.average(),
        };
    }
}

/// Get current frame ID
export fn nvlat_get_frame_id(handle: ?*const LatencyHandle) u64 {
    const h = handle orelse return 0;
    return h.ctx.getFrameId();
}

/// Reset metrics
export fn nvlat_reset_metrics(handle: ?*LatencyHandle) void {
    const h = handle orelse return;
    h.ctx.resetMetrics();
}

// =============================================================================
// Version and Info
// =============================================================================

/// Get library version (major.minor.patch encoded as uint32)
export fn nvlat_get_version() u32 {
    return (@as(u32, nvlatency.version.major) << 16) |
        (@as(u32, nvlatency.version.minor) << 8) |
        @as(u32, nvlatency.version.patch);
}

/// Check if running on NVIDIA GPU
export fn nvlat_is_nvidia_gpu() bool {
    return nvlatency.isNvidiaGpu();
}
