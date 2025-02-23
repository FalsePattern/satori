const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const koishi = b.dependency("koishi", .{
        .target = target,
        .optimize = optimize,
    });

    const translateC = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    translateC.addIncludePath(koishi.namedLazyPath("koishi_include"));
    const koishi_lib = koishi.artifact("koishi");

    const exe = b.addExecutable(.{
        .name = "satori",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(koishi_lib);
    exe.root_module.addImport("c", translateC.createModule());

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
