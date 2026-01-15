//! NVIDIA Reflex integration via nvvk
//!
//! Provides high-level Reflex control and latency reduction
//! using VK_NV_low_latency2 through the nvvk library.

const std = @import("std");
const nvvk = @import("nvvk");
const timing = @import("timing.zig");
const metrics = @import("metrics.zig");

/// Reflex operating mode
pub const ReflexMode = enum {
    /// Reflex disabled
    off,
    /// Reflex enabled (normal mode)
    on,
    /// Reflex enabled with GPU boost
    boost,

    /// Convert to nvvk ModeConfig
    pub fn toModeConfig(self: ReflexMode) nvvk.ModeConfig {
        return switch (self) {
            .off => nvvk.ModeConfig.disabled(),
            .on => .{ .enabled = true, .boost = false, .min_interval_us = 0 },
            .boost => nvvk.ModeConfig.maxPerformance(),
        };
    }
};

/// Main latency context - wraps nvvk and provides higher-level API
pub const LatencyContext = struct {
    allocator: std.mem.Allocator,

    // nvvk components
    device: nvvk.VkDevice,
    swapchain: u64,
    dispatch: nvvk.DeviceDispatch,
    low_latency: nvvk.LowLatencyContext,

    // Current state
    mode: ReflexMode = .off,
    frame_id: u64 = 0,
    reflex_supported: bool = false,

    // Timing capture
    frame_timestamps: timing.FrameTimestamps = .{},
    latency_metrics: metrics.LatencyMetrics = .{},

    // Last frame timings
    last_frame: metrics.FrameTimings = .{},

    /// Initialize latency context
    pub fn init(
        allocator: std.mem.Allocator,
        device: nvvk.VkDevice,
        swapchain: u64,
        get_device_proc_addr: nvvk.vulkan.PFN_vkGetDeviceProcAddr,
    ) LatencyContext {
        var dispatch = nvvk.DeviceDispatch.init(device, get_device_proc_addr);
        var ll = nvvk.LowLatencyContext.init(device, swapchain, &dispatch);

        return .{
            .allocator = allocator,
            .device = device,
            .swapchain = swapchain,
            .dispatch = dispatch,
            .low_latency = ll,
            .reflex_supported = ll.isSupported(),
        };
    }

    /// Check if Reflex is supported
    pub fn isSupported(self: *const LatencyContext) bool {
        return self.reflex_supported;
    }

    /// Set Reflex mode
    pub fn setReflexMode(self: *LatencyContext, mode: ReflexMode) !void {
        if (!self.reflex_supported and mode != .off) {
            return error.ReflexNotSupported;
        }

        try self.low_latency.setMode(mode.toModeConfig());
        self.mode = mode;
    }

    /// Get current Reflex mode
    pub fn getReflexMode(self: *const LatencyContext) ReflexMode {
        return self.mode;
    }

    /// Begin a new frame - call at start of game loop
    pub fn beginFrame(self: *LatencyContext) u64 {
        self.frame_id += 1;
        self.frame_timestamps.reset(self.frame_id);
        self.frame_timestamps.simulation_start = timing.Timestamp.now();

        // Set simulation start marker via nvvk
        if (self.reflex_supported and self.mode != .off) {
            _ = self.low_latency.beginFrame();
        }

        return self.frame_id;
    }

    /// Mark input sample time
    pub fn markInputSample(self: *LatencyContext) void {
        self.frame_timestamps.input_sample = timing.Timestamp.now();

        if (self.reflex_supported and self.mode != .off) {
            self.low_latency.setMarker(.input_sample);
        }
    }

    /// Mark end of simulation/game logic
    pub fn markSimulationEnd(self: *LatencyContext) void {
        self.frame_timestamps.simulation_end = timing.Timestamp.now();

        if (self.reflex_supported and self.mode != .off) {
            self.low_latency.endSimulation();
        }
    }

    /// Mark start of render command submission
    pub fn markRenderSubmitStart(self: *LatencyContext) void {
        self.frame_timestamps.render_submit_start = timing.Timestamp.now();

        if (self.reflex_supported and self.mode != .off) {
            self.low_latency.beginRenderSubmit();
        }
    }

    /// Mark end of render command submission
    pub fn markRenderSubmitEnd(self: *LatencyContext) void {
        self.frame_timestamps.render_submit_end = timing.Timestamp.now();

        if (self.reflex_supported and self.mode != .off) {
            self.low_latency.endRenderSubmit();
        }
    }

    /// Mark start of present
    pub fn markPresentStart(self: *LatencyContext) void {
        self.frame_timestamps.present_start = timing.Timestamp.now();

        if (self.reflex_supported and self.mode != .off) {
            self.low_latency.beginPresent();
        }
    }

    /// Mark end of present
    pub fn markPresentEnd(self: *LatencyContext) void {
        self.frame_timestamps.present_end = timing.Timestamp.now();

        if (self.reflex_supported and self.mode != .off) {
            self.low_latency.endPresent();
        }
    }

    /// End frame and record metrics
    pub fn endFrame(self: *LatencyContext) metrics.FrameTimings {
        // Ensure present end is marked
        if (!self.frame_timestamps.present_end.isValid()) {
            self.markPresentEnd();
        }

        // Build frame timings
        self.last_frame = .{
            .frame_id = self.frame_id,
            .simulation_us = self.frame_timestamps.simulationTimeUs(),
            .render_submit_us = self.frame_timestamps.renderSubmitTimeUs(),
            .present_us = self.frame_timestamps.presentTimeUs(),
            .total_us = self.frame_timestamps.totalFrameTimeUs(),
            .input_latency_us = self.frame_timestamps.inputToRenderUs(),
        };

        // Record in metrics
        self.latency_metrics.recordFrame(self.last_frame);

        return self.last_frame;
    }

    /// Sleep until optimal frame start (Reflex sleep)
    pub fn sleep(self: *LatencyContext, semaphore: u64, value: u64) !void {
        if (!self.reflex_supported or self.mode == .off) {
            return;
        }
        try self.low_latency.sleep(semaphore, value);
    }

    /// Get current latency metrics
    pub fn getMetrics(self: *const LatencyContext) *const metrics.LatencyMetrics {
        return &self.latency_metrics;
    }

    /// Get last frame timings
    pub fn getLastFrame(self: *const LatencyContext) metrics.FrameTimings {
        return self.last_frame;
    }

    /// Get current frame ID
    pub fn getFrameId(self: *const LatencyContext) u64 {
        return self.frame_id;
    }

    /// Get Reflex timings from driver (if available)
    pub fn getReflexTimings(self: *LatencyContext) ?metrics.ReflexTimings {
        if (!self.reflex_supported or self.mode == .off) {
            return null;
        }

        const nvvk_timings = self.low_latency.getTimings() catch return null;

        return .{
            .frame_id = nvvk_timings.present_id,
            .simulation_start_us = nvvk_timings.simulation_start_us,
            .simulation_end_us = nvvk_timings.simulation_end_us,
            .render_submit_start_us = nvvk_timings.rendersubmit_start_us,
            .render_submit_end_us = nvvk_timings.rendersubmit_end_us,
            .present_start_us = nvvk_timings.present_start_us,
            .present_end_us = nvvk_timings.present_end_us,
            .driver_start_us = nvvk_timings.driver_start_us,
            .driver_end_us = nvvk_timings.driver_end_us,
            .gpu_render_start_us = nvvk_timings.gpurender_start_us,
            .gpu_render_end_us = nvvk_timings.gpurender_end_us,
        };
    }

    /// Reset all metrics
    pub fn resetMetrics(self: *LatencyContext) void {
        self.latency_metrics.reset();
    }
};

/// Standalone latency measurement (no Reflex, just timing)
pub const LatencyMeasurement = struct {
    frame_timestamps: timing.FrameTimestamps = .{},
    latency_metrics: metrics.LatencyMetrics = .{},
    frame_id: u64 = 0,

    pub fn beginFrame(self: *LatencyMeasurement) u64 {
        self.frame_id += 1;
        self.frame_timestamps.reset(self.frame_id);
        self.frame_timestamps.simulation_start = timing.Timestamp.now();
        return self.frame_id;
    }

    pub fn markSimulationEnd(self: *LatencyMeasurement) void {
        self.frame_timestamps.simulation_end = timing.Timestamp.now();
    }

    pub fn markRenderSubmit(self: *LatencyMeasurement) void {
        self.frame_timestamps.render_submit_start = timing.Timestamp.now();
        self.frame_timestamps.render_submit_end = timing.Timestamp.now();
    }

    pub fn endFrame(self: *LatencyMeasurement) metrics.FrameTimings {
        self.frame_timestamps.present_end = timing.Timestamp.now();

        const frame = metrics.FrameTimings{
            .frame_id = self.frame_id,
            .simulation_us = self.frame_timestamps.simulationTimeUs(),
            .render_submit_us = self.frame_timestamps.renderSubmitTimeUs(),
            .total_us = self.frame_timestamps.totalFrameTimeUs(),
        };

        self.latency_metrics.recordFrame(frame);
        return frame;
    }

    pub fn getMetrics(self: *const LatencyMeasurement) *const metrics.LatencyMetrics {
        return &self.latency_metrics;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "ReflexMode to ModeConfig" {
    const off = ReflexMode.off.toModeConfig();
    try std.testing.expect(!off.enabled);

    const on = ReflexMode.on.toModeConfig();
    try std.testing.expect(on.enabled);
    try std.testing.expect(!on.boost);

    const boost = ReflexMode.boost.toModeConfig();
    try std.testing.expect(boost.enabled);
    try std.testing.expect(boost.boost);
}

test "LatencyMeasurement basic flow" {
    const io = std.testing.io;
    var measurement = LatencyMeasurement{};

    _ = measurement.beginFrame();
    try std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromMilliseconds(1) }, io); // 1ms sim
    measurement.markSimulationEnd();
    try std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromNanoseconds(500_000) }, io); // 0.5ms render
    measurement.markRenderSubmit();
    const frame = measurement.endFrame();

    try std.testing.expect(frame.total_us > 1000);
    try std.testing.expectEqual(@as(u64, 1), frame.frame_id);
}
