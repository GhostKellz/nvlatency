//! Latency metrics collection and analysis
//!
//! Provides structured latency data with rolling averages,
//! percentiles, and breakdown by pipeline stage.

const std = @import("std");
const timing = @import("timing.zig");

/// Individual frame timing breakdown
pub const FrameTimings = struct {
    frame_id: u64 = 0,

    /// Time spent in game simulation (CPU)
    simulation_us: u64 = 0,

    /// Time spent submitting render commands (CPU → GPU)
    render_submit_us: u64 = 0,

    /// Time spent in present/flip
    present_us: u64 = 0,

    /// Total frame time
    total_us: u64 = 0,

    /// Input to render latency (if measured)
    input_latency_us: u64 = 0,

    /// GPU render time (from Vulkan timestamps, if available)
    gpu_render_us: u64 = 0,

    /// Calculate total CPU time
    pub fn cpuTimeUs(self: *const FrameTimings) u64 {
        return self.simulation_us + self.render_submit_us;
    }

    /// Calculate implied GPU time (total - cpu - present)
    pub fn impliedGpuTimeUs(self: *const FrameTimings) u64 {
        const cpu = self.cpuTimeUs();
        const present = self.present_us;
        if (self.total_us > cpu + present) {
            return self.total_us - cpu - present;
        }
        return 0;
    }

    /// Convert to milliseconds for display
    pub fn totalMs(self: *const FrameTimings) f64 {
        return @as(f64, @floatFromInt(self.total_us)) / 1000.0;
    }

    /// Calculate FPS from frame time
    pub fn fps(self: *const FrameTimings) f64 {
        if (self.total_us == 0) return 0;
        return 1_000_000.0 / @as(f64, @floatFromInt(self.total_us));
    }
};

/// Aggregated latency metrics with rolling averages
pub const LatencyMetrics = struct {
    const HISTORY_SIZE = 120; // ~2 seconds at 60fps

    /// Rolling averages
    frame_time_avg: timing.RollingAverage(HISTORY_SIZE) = .{},
    simulation_avg: timing.RollingAverage(HISTORY_SIZE) = .{},
    render_submit_avg: timing.RollingAverage(HISTORY_SIZE) = .{},
    present_avg: timing.RollingAverage(HISTORY_SIZE) = .{},
    input_latency_avg: timing.RollingAverage(HISTORY_SIZE) = .{},

    /// Frame counter
    total_frames: u64 = 0,

    /// Current frame data
    current_frame: FrameTimings = .{},

    /// Record a completed frame's timings
    pub fn recordFrame(self: *LatencyMetrics, frame: FrameTimings) void {
        self.current_frame = frame;
        self.total_frames += 1;

        self.frame_time_avg.add(frame.total_us);
        self.simulation_avg.add(frame.simulation_us);
        self.render_submit_avg.add(frame.render_submit_us);
        self.present_avg.add(frame.present_us);

        if (frame.input_latency_us > 0) {
            self.input_latency_avg.add(frame.input_latency_us);
        }
    }

    /// Get average frame time in microseconds
    pub fn avgFrameTimeUs(self: *const LatencyMetrics) u64 {
        return self.frame_time_avg.average();
    }

    /// Get average frame time in milliseconds
    pub fn avgFrameTimeMs(self: *const LatencyMetrics) f64 {
        return @as(f64, @floatFromInt(self.avgFrameTimeUs())) / 1000.0;
    }

    /// Get average FPS
    pub fn avgFps(self: *const LatencyMetrics) f64 {
        const avg_us = self.avgFrameTimeUs();
        if (avg_us == 0) return 0;
        return 1_000_000.0 / @as(f64, @floatFromInt(avg_us));
    }

    /// Get 1% low FPS
    pub fn fps1Low(self: *const LatencyMetrics) f64 {
        const worst_us = self.frame_time_avg.max();
        if (worst_us == 0) return 0;
        return 1_000_000.0 / @as(f64, @floatFromInt(worst_us));
    }

    /// Get average input latency in milliseconds
    pub fn avgInputLatencyMs(self: *const LatencyMetrics) f64 {
        return @as(f64, @floatFromInt(self.input_latency_avg.average())) / 1000.0;
    }

    /// Get breakdown of average frame time by stage
    pub fn getBreakdown(self: *const LatencyMetrics) LatencyBreakdown {
        return .{
            .simulation_us = self.simulation_avg.average(),
            .render_submit_us = self.render_submit_avg.average(),
            .present_us = self.present_avg.average(),
            .total_us = self.frame_time_avg.average(),
        };
    }

    /// Reset all metrics
    pub fn reset(self: *LatencyMetrics) void {
        self.* = .{};
    }
};

/// Breakdown of latency by pipeline stage
pub const LatencyBreakdown = struct {
    simulation_us: u64 = 0,
    render_submit_us: u64 = 0,
    present_us: u64 = 0,
    total_us: u64 = 0,

    /// Get simulation percentage of total
    pub fn simulationPercent(self: *const LatencyBreakdown) f64 {
        if (self.total_us == 0) return 0;
        return @as(f64, @floatFromInt(self.simulation_us)) / @as(f64, @floatFromInt(self.total_us)) * 100.0;
    }

    /// Get render submit percentage of total
    pub fn renderSubmitPercent(self: *const LatencyBreakdown) f64 {
        if (self.total_us == 0) return 0;
        return @as(f64, @floatFromInt(self.render_submit_us)) / @as(f64, @floatFromInt(self.total_us)) * 100.0;
    }

    /// Get present percentage of total
    pub fn presentPercent(self: *const LatencyBreakdown) f64 {
        if (self.total_us == 0) return 0;
        return @as(f64, @floatFromInt(self.present_us)) / @as(f64, @floatFromInt(self.total_us)) * 100.0;
    }

    /// Format as string for display
    pub fn format(self: *const LatencyBreakdown, buf: []u8) []const u8 {
        const result = std.fmt.bufPrint(buf,
            \\Sim: {d:.2}ms ({d:.1}%)
            \\Submit: {d:.2}ms ({d:.1}%)
            \\Present: {d:.2}ms ({d:.1}%)
            \\Total: {d:.2}ms
        , .{
            @as(f64, @floatFromInt(self.simulation_us)) / 1000.0,
            self.simulationPercent(),
            @as(f64, @floatFromInt(self.render_submit_us)) / 1000.0,
            self.renderSubmitPercent(),
            @as(f64, @floatFromInt(self.present_us)) / 1000.0,
            self.presentPercent(),
            @as(f64, @floatFromInt(self.total_us)) / 1000.0,
        }) catch return "format error";
        return result;
    }
};

/// Reflex-specific latency data (from VK_NV_low_latency2)
pub const ReflexTimings = struct {
    /// Frame ID from Reflex
    frame_id: u64 = 0,

    /// Timestamps from GetLatencyTimingsNV
    simulation_start_us: u64 = 0,
    simulation_end_us: u64 = 0,
    render_submit_start_us: u64 = 0,
    render_submit_end_us: u64 = 0,
    present_start_us: u64 = 0,
    present_end_us: u64 = 0,
    driver_start_us: u64 = 0,
    driver_end_us: u64 = 0,
    os_queue_us: u64 = 0,
    gpu_render_start_us: u64 = 0,
    gpu_render_end_us: u64 = 0,

    /// Calculate game latency (input → render submit)
    pub fn gameLatencyUs(self: *const ReflexTimings) u64 {
        if (self.render_submit_end_us > self.simulation_start_us) {
            return self.render_submit_end_us - self.simulation_start_us;
        }
        return 0;
    }

    /// Calculate render latency (render submit → present)
    pub fn renderLatencyUs(self: *const ReflexTimings) u64 {
        if (self.present_end_us > self.render_submit_end_us) {
            return self.present_end_us - self.render_submit_end_us;
        }
        return 0;
    }

    /// Calculate total PC latency
    pub fn totalLatencyUs(self: *const ReflexTimings) u64 {
        return self.gameLatencyUs() + self.renderLatencyUs();
    }
};

// =============================================================================
// Tests
// =============================================================================

test "FrameTimings fps calculation" {
    const frame = FrameTimings{
        .total_us = 16667, // ~60fps
    };
    const fps_val = frame.fps();
    try std.testing.expect(fps_val > 59.0 and fps_val < 61.0);
}

test "LatencyMetrics rolling average" {
    var metrics_data = LatencyMetrics{};

    // Add some frames
    for (0..10) |i| {
        metrics_data.recordFrame(.{
            .frame_id = i,
            .total_us = 16667,
            .simulation_us = 2000,
            .render_submit_us = 1000,
            .present_us = 500,
        });
    }

    try std.testing.expectEqual(@as(u64, 10), metrics_data.total_frames);
    try std.testing.expectEqual(@as(u64, 16667), metrics_data.avgFrameTimeUs());
}

test "LatencyBreakdown percentages" {
    const breakdown = LatencyBreakdown{
        .simulation_us = 2000,
        .render_submit_us = 1000,
        .present_us = 500,
        .total_us = 5000,
    };

    try std.testing.expectEqual(@as(f64, 40.0), breakdown.simulationPercent());
    try std.testing.expectEqual(@as(f64, 20.0), breakdown.renderSubmitPercent());
    try std.testing.expectEqual(@as(f64, 10.0), breakdown.presentPercent());
}
