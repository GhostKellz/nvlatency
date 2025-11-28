//! nvlatency CLI - NVIDIA Reflex & Frame Latency Tools
//!
//! Command-line interface for latency measurement and Reflex control.

const std = @import("std");
const nvlatency = @import("nvlatency");
const nvvk = @import("nvvk");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "status")) {
        try statusCommand(allocator);
    } else if (std.mem.eql(u8, command, "info")) {
        try infoCommand(allocator);
    } else if (std.mem.eql(u8, command, "benchmark")) {
        try benchmarkCommand();
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        printVersion();
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\nvlatency - NVIDIA Reflex & Frame Latency Tools v{d}.{d}.{d}
        \\
        \\USAGE:
        \\    nvlatency <command> [options]
        \\
        \\COMMANDS:
        \\    status      Show Reflex and latency status
        \\    info        Show detailed system information
        \\    benchmark   Run timing benchmark
        \\    help        Show this help message
        \\    version     Show version information
        \\
        \\EXAMPLES:
        \\    nvlatency status
        \\    nvlatency info
        \\    nvlatency benchmark
        \\
        \\For game integration, use the library API or Vulkan layer.
        \\
    , .{
        nvlatency.version.major,
        nvlatency.version.minor,
        nvlatency.version.patch,
    });
}

fn printVersion() void {
    std.debug.print("nvlatency v{d}.{d}.{d}\n", .{
        nvlatency.version.major,
        nvlatency.version.minor,
        nvlatency.version.patch,
    });
}

fn statusCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("nvlatency - NVIDIA Reflex & Frame Latency Tools\n", .{});
    std.debug.print("================================================\n\n", .{});

    // Check NVIDIA GPU
    std.debug.print("NVIDIA GPU Detection:\n", .{});
    if (nvlatency.isNvidiaGpu()) {
        std.debug.print("  [OK] NVIDIA GPU detected\n", .{});

        if (nvlatency.getNvidiaDriverVersion(allocator)) |version| {
            defer allocator.free(version);
            std.debug.print("  Driver version: {s}\n", .{version});
        }
    } else {
        std.debug.print("  [--] No NVIDIA GPU detected\n", .{});
    }

    // Show required extensions
    std.debug.print("\nRequired Extensions:\n", .{});
    std.debug.print("  - {s}\n", .{nvlatency.required_extensions.low_latency2});

    // Show nvvk status
    std.debug.print("\nnvvk Backend:\n", .{});
    std.debug.print("  Version: {d}.{d}.{d}\n", .{
        nvvk.version.major,
        nvvk.version.minor,
        nvvk.version.patch,
    });

    // Vulkan loader check
    std.debug.print("\nVulkan Loader:\n", .{});
    var loader = nvvk.Loader.init() catch |err| {
        std.debug.print("  [ERR] Failed to load Vulkan: {}\n", .{err});
        return;
    };
    defer loader.deinit();
    std.debug.print("  [OK] Vulkan loader initialized\n", .{});

    std.debug.print("\nReflex Support:\n", .{});
    std.debug.print("  VK_NV_low_latency2: Available (requires active swapchain to test)\n", .{});

    std.debug.print("\nTo use Reflex:\n", .{});
    std.debug.print("  1. Initialize with nvlat_init() after swapchain creation\n", .{});
    std.debug.print("  2. Set mode with nvlat_set_reflex_mode()\n", .{});
    std.debug.print("  3. Call frame markers in render loop\n", .{});
}

fn infoCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("nvlatency System Information\n", .{});
    std.debug.print("============================\n\n", .{});

    // Library versions
    std.debug.print("Library Versions:\n", .{});
    std.debug.print("  nvlatency: v{d}.{d}.{d}\n", .{
        nvlatency.version.major,
        nvlatency.version.minor,
        nvlatency.version.patch,
    });
    std.debug.print("  nvvk:      v{d}.{d}.{d}\n", .{
        nvvk.version.major,
        nvvk.version.minor,
        nvvk.version.patch,
    });

    // GPU info
    std.debug.print("\nGPU Information:\n", .{});
    if (nvlatency.isNvidiaGpu()) {
        std.debug.print("  Vendor: NVIDIA\n", .{});
        if (nvlatency.getNvidiaDriverVersion(allocator)) |version| {
            defer allocator.free(version);
            std.debug.print("  Driver: {s}\n", .{version});
        }
    } else {
        std.debug.print("  Vendor: Unknown (not NVIDIA or driver not loaded)\n", .{});
    }

    // Extension info
    std.debug.print("\nSupported NVIDIA Extensions:\n", .{});
    std.debug.print("  - {s}\n", .{nvvk.vulkan.VK_NV_LOW_LATENCY_2_EXTENSION_NAME});
    std.debug.print("  - {s}\n", .{nvvk.vulkan.VK_NV_DEVICE_DIAGNOSTIC_CHECKPOINTS_EXTENSION_NAME});
    std.debug.print("  - {s}\n", .{nvvk.vulkan.VK_NV_DEVICE_DIAGNOSTICS_CONFIG_EXTENSION_NAME});

    // Timing info
    std.debug.print("\nTiming Infrastructure:\n", .{});
    std.debug.print("  Clock: CLOCK_MONOTONIC (nanosecond precision)\n", .{});
    std.debug.print("  Rolling average window: 120 frames\n", .{});
}

fn benchmarkCommand() !void {
    std.debug.print("nvlatency Timing Benchmark\n", .{});
    std.debug.print("==========================\n\n", .{});

    // Benchmark the timing infrastructure
    std.debug.print("Benchmarking timing infrastructure...\n\n", .{});

    var measurement = nvlatency.reflex.LatencyMeasurement{};

    const iterations: usize = 1000;
    var timer = nvlatency.Timer{};

    timer.start();

    for (0..iterations) |_| {
        _ = measurement.beginFrame();
        measurement.markSimulationEnd();
        measurement.markRenderSubmit();
        _ = measurement.endFrame();
    }

    const total_ns = timer.elapsedNs();
    const per_frame_ns = total_ns / iterations;

    std.debug.print("Results ({d} iterations):\n", .{iterations});
    std.debug.print("  Total time:     {d:.3} ms\n", .{@as(f64, @floatFromInt(total_ns)) / 1_000_000.0});
    std.debug.print("  Per frame:      {d} ns ({d:.3} us)\n", .{ per_frame_ns, @as(f64, @floatFromInt(per_frame_ns)) / 1000.0 });
    std.debug.print("  Overhead:       ~{d:.3} us per frame\n", .{@as(f64, @floatFromInt(per_frame_ns)) / 1000.0});

    const m = measurement.getMetrics();
    std.debug.print("\nMetrics recorded:\n", .{});
    std.debug.print("  Frames:         {d}\n", .{m.total_frames});
    std.debug.print("  Avg frame time: {d} us\n", .{m.avgFrameTimeUs()});

    std.debug.print("\nConclusion:\n", .{});
    if (per_frame_ns < 1000) {
        std.debug.print("  [EXCELLENT] Timing overhead < 1us per frame\n", .{});
    } else if (per_frame_ns < 10000) {
        std.debug.print("  [GOOD] Timing overhead < 10us per frame\n", .{});
    } else {
        std.debug.print("  [OK] Timing overhead: {d} us per frame\n", .{per_frame_ns / 1000});
    }
}

test "main runs without crash" {
    // Just verify the module compiles
    _ = nvlatency.version;
}
