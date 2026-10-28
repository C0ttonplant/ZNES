const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = .fast,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    const exe = b.addExecutable(.{ .name = "ZNES", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    }) });

    exe.root_module.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run ZNES (zig build run -- rom.nes)");
    run_step.dependOn(&run_cmd.step);

    b.installArtifact(exe);

    // emulator core without a window, prints a hash per frame (see src/headless.zig)
    const headless = b.addExecutable(.{ .name = "znes-headless", .root_module = b.createModule(.{
        .root_source_file = b.path("src/headless.zig"),
        .optimize = optimize,
        .target = target,
    }) });
    b.installArtifact(headless);

    const headless_cmd = b.addRunArtifact(headless);
    headless_cmd.addPassthruArgs();
    const headless_step = b.step("headless", "Run a ROM without a window (zig build headless -- rom.nes frames)");
    headless_step.dependOn(&headless_cmd.step);
}
