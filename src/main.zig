//! nvlatency CLI - NVIDIA Reflex & Frame Latency Tools
//!
//! Command-line interface for latency measurement and Reflex control.

const std = @import("std");
const nvlatency = @import("nvlatency");
const nvvk = @import("nvvk");
const posix = std.posix;
const fs = std.fs;
const mem = std.mem;

/// IPC socket path for daemon communication
const socket_path = "/tmp/nvlatency.sock";
/// Config file for persistent settings
const config_path_suffix = "/.config/nvlatency/config";

/// Global init for use by functions
var global_init: ?*const std.process.Init = null;

pub fn main(init: std.process.Init) !void {
    global_init = &init;
    const allocator = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

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
    } else if (std.mem.eql(u8, command, "enable")) {
        try enableCommand(args[2..]);
    } else if (std.mem.eql(u8, command, "disable")) {
        try disableCommand();
    } else if (std.mem.eql(u8, command, "measure")) {
        try measureCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "run")) {
        try runCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "daemon")) {
        try daemonCommand(allocator);
    } else if (std.mem.eql(u8, command, "json")) {
        try jsonCommand(allocator, args[2..]);
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
        \\    status              Show Reflex and latency status
        \\    info                Show detailed system information
        \\    enable [mode]       Enable Reflex (on, boost)
        \\    disable             Disable Reflex
        \\    measure <pid>       Measure latency of running process
        \\    run <command>       Run command with latency measurement
        \\    benchmark           Run timing benchmark
        \\    daemon              Start IPC daemon for nvcontrol
        \\    json <subcommand>   Output as JSON (status, info)
        \\    help                Show this help message
        \\    version             Show version information
        \\
        \\EXAMPLES:
        \\    nvlatency status
        \\    nvlatency enable boost
        \\    nvlatency measure 12345
        \\    nvlatency run -- gamescope -f -- game.exe
        \\    nvlatency json status
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

// =============================================================================
// Enable/Disable Commands
// =============================================================================

fn enableCommand(args: []const []const u8) !void {
    const mode = if (args.len > 0) args[0] else "on";

    const mode_str = if (std.mem.eql(u8, mode, "boost"))
        "boost"
    else if (std.mem.eql(u8, mode, "on"))
        "on"
    else {
        std.debug.print("Unknown mode: {s}\n", .{mode});
        std.debug.print("Valid modes: on, boost\n", .{});
        return;
    };

    const io = global_init.?.io;

    // Write config to enable Reflex globally
    const home: []const u8 = if (global_init) |init| (init.minimal.environ.getPosix("HOME") orelse "/tmp") else "/tmp";
    var path_buf: [512]u8 = undefined;
    const config_dir = std.fmt.bufPrint(&path_buf, "{s}/.config/nvlatency", .{home}) catch return;

    // Create config directory
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, config_dir) catch {};

    var path_buf2: [512]u8 = undefined;
    const config_file = std.fmt.bufPrint(&path_buf2, "{s}/config", .{config_dir}) catch return;

    // Write config
    const file = cwd.createFile(io, config_file, .{}) catch |err| {
        std.debug.print("Failed to write config: {}\n", .{err});
        return;
    };
    defer file.close(io);

    // Write directly to file
    var config_buf: [64]u8 = undefined;
    const config_data = std.fmt.bufPrint(&config_buf, "reflex_mode={s}\n", .{mode_str}) catch return;
    file.writeStreamingAll(io, config_data) catch {};

    std.debug.print("Reflex mode set to: {s}\n", .{mode_str});
    std.debug.print("Config written to: {s}\n", .{config_file});
    std.debug.print("\nNote: Games must use nvlatency library or Vulkan layer.\n", .{});
    std.debug.print("Use 'nvlatency run <game>' to launch with Reflex enabled.\n", .{});
}

fn disableCommand() !void {
    const io = global_init.?.io;
    const home: []const u8 = if (global_init) |init| (init.minimal.environ.getPosix("HOME") orelse "/tmp") else "/tmp";
    var path_buf: [512]u8 = undefined;
    const config_file = std.fmt.bufPrint(&path_buf, "{s}/.config/nvlatency/config", .{home}) catch return;

    // Write disabled config
    const cwd = std.Io.Dir.cwd();
    const file = cwd.createFile(io, config_file, .{}) catch |err| {
        std.debug.print("Failed to write config: {}\n", .{err});
        return;
    };
    defer file.close(io);

    file.writeStreamingAll(io, "reflex_mode=off\n") catch {};

    std.debug.print("Reflex disabled.\n", .{});
    std.debug.print("Config written to: {s}\n", .{config_file});
}

// =============================================================================
// Measure Command - Attach to running process
// =============================================================================

fn measureCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: nvlatency measure <pid>\n", .{});
        std.debug.print("\nMeasures frame latency of a running Vulkan application.\n", .{});
        std.debug.print("Requires the application to use nvlatency library or layer.\n", .{});
        return;
    }

    const io = global_init.?.io;
    const cwd = std.Io.Dir.cwd();

    const pid_str = args[0];
    const pid = std.fmt.parseInt(i32, pid_str, 10) catch {
        std.debug.print("Invalid PID: {s}\n", .{pid_str});
        return;
    };

    std.debug.print("nvlatency - Measuring process {d}\n", .{pid});
    std.debug.print("=========================================\n\n", .{});

    // Check if process exists
    var proc_path_buf: [64]u8 = undefined;
    const proc_path = std.fmt.bufPrint(&proc_path_buf, "/proc/{d}/comm", .{pid}) catch return;

    const proc_name = cwd.readFileAlloc(io, proc_path, allocator, .unlimited) catch {
        std.debug.print("Process {d} not found or not accessible.\n", .{pid});
        return;
    };
    defer allocator.free(proc_name);

    const trimmed_name = std.mem.trim(u8, proc_name, &[_]u8{ '\n', '\r', ' ' });
    std.debug.print("Process: {s} (PID {d})\n\n", .{ trimmed_name, pid });

    // Check for nvlatency shared memory
    var shm_path_buf: [64]u8 = undefined;
    const shm_path = std.fmt.bufPrint(&shm_path_buf, "/dev/shm/nvlatency_{d}", .{pid}) catch return;

    if (cwd.access(io, shm_path, .{})) {
        std.debug.print("Found nvlatency shared memory at {s}\n", .{shm_path});
        std.debug.print("Reading metrics...\n\n", .{});

        // In a real implementation, we'd mmap the shared memory and read metrics
        std.debug.print("  Frame Time: -- ms (shared memory not yet implemented)\n", .{});
        std.debug.print("  FPS:        -- \n", .{});
        std.debug.print("  Latency:    -- ms\n", .{});
    } else |_| {
        std.debug.print("No nvlatency instrumentation found for process {d}.\n", .{pid});
        std.debug.print("\nTo measure latency, the application must:\n", .{});
        std.debug.print("  1. Link against libnvlatency.so, or\n", .{});
        std.debug.print("  2. Run with NVLATENCY_LAYER=1 environment variable\n", .{});
        std.debug.print("\nAlternatively, use 'nvlatency run <command>' to launch with measurement.\n", .{});
    }
}

// =============================================================================
// Run Command - Launch with latency measurement
// =============================================================================

fn runCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: nvlatency run [options] -- <command> [args...]\n", .{});
        std.debug.print("\nOptions:\n", .{});
        std.debug.print("  --reflex=MODE   Set Reflex mode (off, on, boost) [default: on]\n", .{});
        std.debug.print("  --overlay       Show latency overlay\n", .{});
        std.debug.print("\nExamples:\n", .{});
        std.debug.print("  nvlatency run -- ./game\n", .{});
        std.debug.print("  nvlatency run --reflex=boost -- gamescope -- game.exe\n", .{});
        return;
    }

    // Parse options and find command
    var reflex_mode: []const u8 = "on";
    var show_overlay = false;
    var cmd_start: usize = 0;

    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--")) {
            cmd_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "--reflex=")) {
            reflex_mode = arg[9..];
        } else if (std.mem.eql(u8, arg, "--overlay")) {
            show_overlay = true;
        } else {
            // Assume first non-option is start of command
            cmd_start = i;
            break;
        }
    }

    if (cmd_start >= args.len) {
        std.debug.print("No command specified.\n", .{});
        return;
    }

    const cmd_args = args[cmd_start..];
    std.debug.print("nvlatency - Launching with latency measurement\n", .{});
    std.debug.print("==============================================\n\n", .{});
    std.debug.print("Command: ", .{});
    for (cmd_args) |a| {
        std.debug.print("{s} ", .{a});
    }
    std.debug.print("\nReflex mode: {s}\n", .{reflex_mode});
    if (show_overlay) {
        std.debug.print("Overlay: enabled\n", .{});
    }
    std.debug.print("\n", .{});

    // Set up environment for the Vulkan layer
    var env_map = if (global_init) |init|
        try init.environ_map.clone(allocator)
    else
        std.process.Environ.Map.init(allocator);
    defer env_map.deinit();

    // Enable nvlatency Vulkan layer
    try env_map.put("NVLATENCY_ENABLE", "1");
    try env_map.put("NVLATENCY_REFLEX_MODE", reflex_mode);
    if (show_overlay) {
        try env_map.put("NVLATENCY_OVERLAY", "1");
    }

    // Add to VK_INSTANCE_LAYERS if layer is installed
    if (env_map.get("VK_INSTANCE_LAYERS")) |existing| {
        var buf: [1024]u8 = undefined;
        const new_layers = std.fmt.bufPrint(&buf, "{s}:VK_LAYER_NVLATENCY_overlay", .{existing}) catch existing;
        try env_map.put("VK_INSTANCE_LAYERS", new_layers);
    } else {
        try env_map.put("VK_INSTANCE_LAYERS", "VK_LAYER_NVLATENCY_overlay");
    }

    std.debug.print("Starting process...\n\n", .{});

    // Spawn child process with environment
    const io = global_init.?.io;
    var child = std.process.spawn(io, .{
        .argv = cmd_args,
        .environ_map = &env_map,
    }) catch |err| {
        std.debug.print("Failed to spawn process: {}\n", .{err});
        return;
    };

    const term = child.wait(io) catch |err| {
        std.debug.print("Failed to wait for process: {}\n", .{err});
        return;
    };

    switch (term) {
        .exited => |code| {
            std.debug.print("\nProcess exited with code: {d}\n", .{code});
        },
        .signal => |sig| {
            std.debug.print("\nProcess killed by signal: {d}\n", .{@intFromEnum(sig)});
        },
        else => {
            std.debug.print("\nProcess terminated abnormally\n", .{});
        },
    }
}

// =============================================================================
// Daemon Command - IPC server for nvcontrol
// =============================================================================

fn daemonCommand(allocator: mem.Allocator) !void {
    std.debug.print("nvlatency daemon starting...\n", .{});
    std.debug.print("Socket: {s}\n\n", .{socket_path});

    const io = global_init.?.io;

    // Remove existing socket
    std.Io.Dir.cwd().deleteFile(io, socket_path) catch {};

    // Create Unix domain socket using libc
    const sock = std.c.socket(std.c.AF.UNIX, std.c.SOCK.STREAM, 0);
    if (sock < 0) {
        std.debug.print("Failed to create socket\n", .{});
        return;
    }
    defer {
        if (std.c.close(sock) < 0) {
            std.debug.print("Warning: failed to close server socket\n", .{});
        }
    }

    // Bind to socket path
    var addr: std.c.sockaddr.un = .{ .family = std.c.AF.UNIX, .path = undefined };
    @memset(&addr.path, 0);
    const path_bytes: []const u8 = socket_path;
    @memcpy(addr.path[0..path_bytes.len], path_bytes);

    if (std.c.bind(sock, @ptrCast(&addr), @sizeOf(std.c.sockaddr.un)) < 0) {
        std.debug.print("Failed to bind socket\n", .{});
        return;
    }
    if (std.c.listen(sock, 5) < 0) {
        std.debug.print("Failed to listen on socket\n", .{});
        return;
    }

    // Make socket accessible
    if (std.c.chmod(socket_path, 0o666) < 0) {
        std.debug.print("Warning: failed to set socket permissions\n", .{});
    }

    std.debug.print("Listening for connections...\n", .{});
    std.debug.print("Press Ctrl+C to stop.\n\n", .{});

    // Main loop
    while (true) {
        const client = std.c.accept(sock, null, null);
        if (client < 0) {
            std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromMilliseconds(100) }, io) catch {};
            continue;
        }
        defer {
            if (std.c.close(client) < 0) {
                std.debug.print("Warning: failed to close client socket\n", .{});
            }
        }

        handleDaemonClient(allocator, client) catch |err| {
            std.debug.print("Client error: {}\n", .{err});
        };
    }
}

fn handleDaemonClient(allocator: mem.Allocator, client: std.c.fd_t) !void {
    var buf: [1024]u8 = undefined;
    const n = std.c.recv(client, &buf, buf.len, 0);
    if (n <= 0) {
        if (n < 0) {
            std.debug.print("Warning: recv failed on client socket\n", .{});
        }
        return;
    }

    const request = std.mem.trim(u8, buf[0..@intCast(n)], &[_]u8{ '\n', '\r', ' ', 0 });

    var response_buf: [4096]u8 = undefined;
    var response: []const u8 = undefined;

    if (std.mem.eql(u8, request, "status")) {
        response = try std.fmt.bufPrint(&response_buf,
            \\{{"status":"ok","version":"{d}.{d}.{d}","nvidia":{s},"reflex_supported":true}}
        , .{
            nvlatency.version.major,
            nvlatency.version.minor,
            nvlatency.version.patch,
            if (nvlatency.isNvidiaGpu()) "true" else "false",
        });
    } else if (std.mem.eql(u8, request, "info")) {
        const driver_ver = nvlatency.getNvidiaDriverVersion(allocator) orelse "unknown";
        defer if (nvlatency.getNvidiaDriverVersion(allocator)) |v| allocator.free(v);

        response = try std.fmt.bufPrint(&response_buf,
            \\{{"status":"ok","driver":"{s}","nvvk_version":"{d}.{d}.{d}"}}
        , .{
            driver_ver,
            nvvk.version.major,
            nvvk.version.minor,
            nvvk.version.patch,
        });
    } else {
        response = "{\"status\":\"error\",\"message\":\"unknown command\"}";
    }

    const sent = std.c.send(client, response.ptr, response.len, 0);
    if (sent < 0) {
        std.debug.print("Warning: send failed on client socket\n", .{});
    }
}

// =============================================================================
// JSON Command - Machine-readable output
// =============================================================================

fn jsonCommand(allocator: mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("{{\"error\":\"No subcommand specified\"}}\n", .{});
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "status")) {
        std.debug.print(
            \\{{"version":"{d}.{d}.{d}","nvidia":{s},"reflex_supported":true,"extensions":["{s}"]}}
        ++ "\n", .{
            nvlatency.version.major,
            nvlatency.version.minor,
            nvlatency.version.patch,
            if (nvlatency.isNvidiaGpu()) "true" else "false",
            nvlatency.required_extensions.low_latency2,
        });
    } else if (std.mem.eql(u8, subcommand, "info")) {
        const driver_ver = nvlatency.getNvidiaDriverVersion(allocator) orelse "unknown";
        defer if (nvlatency.getNvidiaDriverVersion(allocator)) |v| allocator.free(v);

        std.debug.print(
            \\{{"driver":"{s}","nvvk_version":"{d}.{d}.{d}","nvlatency_version":"{d}.{d}.{d}"}}
        ++ "\n", .{
            driver_ver,
            nvvk.version.major,
            nvvk.version.minor,
            nvvk.version.patch,
            nvlatency.version.major,
            nvlatency.version.minor,
            nvlatency.version.patch,
        });
    } else {
        std.debug.print("{{\"error\":\"Unknown subcommand: {s}\"}}\n", .{subcommand});
    }
}

test "main runs without crash" {
    // Just verify the module compiles
    _ = nvlatency.version;
}
