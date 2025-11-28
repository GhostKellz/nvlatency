const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build option for static vs shared library
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Library linkage (static or dynamic)") orelse .dynamic;

    // =========================================================================
    // Fetch nvvk dependency
    // =========================================================================
    const nvvk_dep = b.dependency("nvvk", .{
        .target = target,
        .optimize = optimize,
    });
    const nvvk_mod = nvvk_dep.module("nvvk");

    // =========================================================================
    // Core nvlatency module (Zig API)
    // =========================================================================
    const nvlatency_mod = b.addModule("nvlatency", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "nvvk", .module = nvvk_mod },
        },
    });

    // =========================================================================
    // Library with C ABI exports (libnvlatency.so / libnvlatency.a)
    // =========================================================================
    const lib = b.addLibrary(.{
        .linkage = linkage,
        .name = "nvlatency",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "nvlatency", .module = nvlatency_mod },
                .{ .name = "nvvk", .module = nvvk_mod },
            },
        }),
    });

    // Link Vulkan
    lib.linkSystemLibrary("vulkan");

    // Install library
    b.installArtifact(lib);

    // Install C headers
    b.installFile("include/nvlatency.h", "include/nvlatency.h");

    // =========================================================================
    // CLI tool
    // =========================================================================
    const exe = b.addExecutable(.{
        .name = "nvlatency",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "nvlatency", .module = nvlatency_mod },
                .{ .name = "nvvk", .module = nvvk_mod },
            },
        }),
    });
    exe.linkSystemLibrary("vulkan");
    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the CLI tool");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // =========================================================================
    // Tests
    // =========================================================================
    const mod_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "nvvk", .module = nvvk_mod },
            },
        }),
    });
    mod_tests.linkSystemLibrary("vulkan");

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_mod_tests.step);
}
