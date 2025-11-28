//! nvlatency - NVIDIA Reflex & Frame Latency Tools for Linux
//!
//! A comprehensive toolkit for measuring, analyzing, and reducing input-to-display
//! latency on NVIDIA GPUs under Linux. Brings Windows-level Reflex functionality
//! to the Linux gaming ecosystem.
//!
//! ## Features
//!
//! - **Frame Latency Measurement** - Precise end-to-end latency tracking
//! - **NVIDIA Reflex Integration** - Low latency mode via VK_NV_low_latency2
//! - **Latency Visualization** - Real-time metrics and logging
//! - **Game Integration** - Automatic injection for supported games
//!
//! ## Example
//!
//! ```zig
//! const nvlatency = @import("nvlatency");
//!
//! // Create latency context with nvvk backend
//! var ctx = try nvlatency.LatencyContext.init(allocator, device, swapchain);
//! defer ctx.deinit();
//!
//! // Enable Reflex with boost
//! try ctx.setReflexMode(.boost);
//!
//! // In render loop
//! ctx.beginFrame();
//! // ... game simulation ...
//! ctx.markSimulationEnd();
//! // ... rendering ...
//! ctx.markRenderSubmit();
//! // ... present ...
//! ctx.endFrame();
//!
//! // Get latency metrics
//! const metrics = ctx.getMetrics();
//! ```

const std = @import("std");
const nvvk = @import("nvvk");

// Re-export sub-modules
pub const timing = @import("timing.zig");
pub const metrics = @import("metrics.zig");
pub const reflex = @import("reflex.zig");

// Re-export commonly used types
pub const LatencyContext = reflex.LatencyContext;
pub const ReflexMode = reflex.ReflexMode;
pub const LatencyMetrics = metrics.LatencyMetrics;
pub const FrameTimings = metrics.FrameTimings;
pub const Timer = timing.Timer;

/// Library version
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

/// Check if running on NVIDIA GPU
pub fn isNvidiaGpu() bool {
    return nvvk.isNvidiaGpu();
}

/// Get NVIDIA driver version
pub fn getNvidiaDriverVersion(allocator: std.mem.Allocator) ?[]const u8 {
    return nvvk.getNvidiaDriverVersion(allocator);
}

/// Extension names required for full functionality
pub const required_extensions = struct {
    pub const low_latency2 = nvvk.vulkan.VK_NV_LOW_LATENCY_2_EXTENSION_NAME;

    pub fn all() []const [*:0]const u8 {
        return &[_][*:0]const u8{
            low_latency2,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "version" {
    try std.testing.expectEqual(@as(u8, 0), version.major);
    try std.testing.expectEqual(@as(u8, 1), version.minor);
    try std.testing.expectEqual(@as(u8, 0), version.patch);
}

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
}
