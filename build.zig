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

    const topology_bench_mod = b.createModule(.{
        .root_source_file = b.path("src/topology_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const topology_bench = b.addExecutable(.{
        .name = "zui-nodes-topology-bench",
        .root_module = topology_bench_mod,
    });
    const run_topology_bench = b.addRunArtifact(topology_bench);
    if (b.args) |args| run_topology_bench.addArgs(args);
    const topology_bench_step = b.step("bench-topology", "Benchmark large node-graph topology indexing and traversal");
    if (can_run_target) {
        topology_bench_step.dependOn(&run_topology_bench.step);
    } else {
        topology_bench_step.dependOn(&topology_bench.step);
    }

    const verify_topology_bench = b.addRunArtifact(topology_bench);
    verify_topology_bench.addArgs(&.{
        "--iterations=1000",
        "--max-build-ns=20000000",
        "--max-cached-traversal-ns=1000000",
    });
    const verify_topology_step = b.step("verify-topology-performance", "Verify large node-graph topology performance and zero-allocation traversal");
    if (can_run_target) {
        verify_topology_step.dependOn(&verify_topology_bench.step);
    } else {
        verify_topology_step.dependOn(&topology_bench.step);
    }
}
