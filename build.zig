const std = @import("std");

/// Single source of truth for the CLI version string: build.zig.zon.
const cli_version: []const u8 = @import("build.zig.zon").version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_png = b.option(bool, "enable-png", "Enable PNG rendering and PNG decode via libpng (default: true)") orelse true;

    const options = b.addOptions();
    options.addOption(bool, "enable_png", enable_png);
    options.addOption([]const u8, "cli_version", cli_version);
    const options_mod = options.createModule();

    const zqr_dep = b.dependency("zqr", .{
        .target = target,
        .optimize = optimize,
        .@"enable-png" = enable_png,
    });
    const zargs_dep = b.dependency("zargs", .{
        .target = target,
        .optimize = optimize,
    });
    const zprint_dep = b.dependency("z_print", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zqr", .module = zqr_dep.module("zqr") },
            .{ .name = "zargs", .module = zargs_dep.module("zargs") },
            .{ .name = "z_print", .module = zprint_dep.module("z_print") },
            .{ .name = "cli_options", .module = options_mod },
        },
    });
    if (enable_png) {
        exe_mod.addCSourceFile(.{
            .file = b.path("c/png_read.c"),
            .flags = &[_][]const u8{ "-std=c99", "-Wall", "-Wextra" },
        });
        exe_mod.addIncludePath(b.path("c"));
        exe_mod.linkSystemLibrary("png", .{});
    }

    const exe = b.addExecutable(.{
        .name = "zqr",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the zqr command-line tool");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zqr", .module = zqr_dep.module("zqr") },
            .{ .name = "zargs", .module = zargs_dep.module("zargs") },
            .{ .name = "z_print", .module = zprint_dep.module("z_print") },
            .{ .name = "cli_options", .module = options_mod },
        },
    });
    if (enable_png) {
        test_mod.addCSourceFile(.{
            .file = b.path("c/png_read.c"),
            .flags = &[_][]const u8{ "-std=c99", "-Wall", "-Wextra" },
        });
        test_mod.addIncludePath(b.path("c"));
        test_mod.linkSystemLibrary("png", .{});
    }
    const cli_tests = b.addTest(.{ .root_module = test_mod });
    const run_cli_tests = b.addRunArtifact(cli_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_cli_tests.step);
}
