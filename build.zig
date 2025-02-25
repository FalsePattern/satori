const std = @import("std");
const koishi = @import("koishi");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const verbose = b.option(bool, "verbose", "Verbose logging for configure phase. [default: false]") orelse false;
    const impl: ?Backend = b.option(Backend, "impl", "Which implementation to use. Leave empty to autodetect.");
    const thread_safe = b.option(bool, "threadsafe", "Whether multiple coroutines can be ran on different threads at once (needs compiler support) [default: true]") orelse true;
    const valgrind = b.option(bool, "valgrind", "Enable support for running under Valgrind (for debugging) [default: false]") orelse false;
    const linkage: std.builtin.LinkMode = b.option(std.builtin.LinkMode, "linkage", "Whether the koishi library should be statically or dynamically linked. [default: static]") orelse .static;

    const koishi_dep = if (impl) |_impl| b.dependency("koishi", .{
        .target = target,
        .optimize = optimize,
        .verbose = verbose,
        .impl = _impl,
        .threadsafe = thread_safe,
        .valgrind = valgrind,
        .linkage = linkage,
    }) else b.dependency("koishi", .{
        .target = target,
        .optimize = optimize,
        .verbose = verbose,
        .threadsafe = thread_safe,
        .valgrind = valgrind,
        .linkage = linkage,
    });

    const translateC = b.addTranslateC(.{
        .root_source_file = koishi_dep.namedLazyPath("koishi_include").path(b, "koishi.h"),
        .target = target,
        .optimize = optimize,
    });
    const koishi_lib = koishi_dep.artifact("koishi");
    const satori_module = b.addModule("satori", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    satori_module.linkLibrary(koishi_lib);
    satori_module.addImport("koishi_h", translateC.createModule());

    const satori_tests = b.addTest(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/test.zig"),
    });
    satori_tests.root_module.addImport("satori", satori_module);

    const satori_run_tests = b.addRunArtifact(satori_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&satori_run_tests.step);
}

pub const Backend = koishi.Backend;