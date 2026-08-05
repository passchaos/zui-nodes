const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const can_run_target = target.result.os.tag == builtin.os.tag and target.result.cpu.arch == builtin.cpu.arch;

    const zui_dep = b.dependency("zui", .{ .target = target, .optimize = optimize });
    const mod = b.addModule("zui-nodes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zui", .module = zui_dep.module("zui") }},
    });

    const tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run zui-nodes unit tests");
    if (can_run_target) {
        test_step.dependOn(&b.addRunArtifact(tests).step);
    } else {
        test_step.dependOn(&tests.step);
    }
}
