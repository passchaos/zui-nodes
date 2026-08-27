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

    const viewport_bench_mod = b.createModule(.{
        .root_source_file = b.path("src/viewport_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const viewport_bench = b.addExecutable(.{
        .name = "zui-nodes-viewport-bench",
        .root_module = viewport_bench_mod,
    });
    const run_viewport_bench = b.addRunArtifact(viewport_bench);
    if (b.args) |args| run_viewport_bench.addArgs(args);
    const viewport_bench_step = b.step("bench-viewport", "Benchmark 10k-node viewport indexing and hit candidates");
    if (can_run_target) {
        viewport_bench_step.dependOn(&run_viewport_bench.step);
    } else {
        viewport_bench_step.dependOn(&viewport_bench.step);
    }

    const verify_viewport_bench = b.addRunArtifact(viewport_bench);
    verify_viewport_bench.addArgs(&.{
        "--iterations=2000",
        "--max-build-ns=50000000",
        "--max-query-ns=100000",
        "--max-cached-prepare-ns=1000",
    });
    const verify_viewport_step = b.step("verify-viewport-performance", "Verify 10k-node viewport culling, reuse, and zero-allocation queries");
    if (can_run_target) {
        verify_viewport_step.dependOn(&verify_viewport_bench.step);
    } else {
        verify_viewport_step.dependOn(&viewport_bench.step);
    }

    const editor_bench_mod = b.createModule(.{
        .root_source_file = b.path("src/editor_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "zui", .module = zui_dep.module("zui") }},
    });
    const editor_bench = b.addExecutable(.{
        .name = "zui-nodes-editor-bench",
        .root_module = editor_bench_mod,
    });
    const run_editor_bench = b.addRunArtifact(editor_bench);
    if (b.args) |args| run_editor_bench.addArgs(args);
    const editor_bench_step = b.step("bench-editor-frame", "Benchmark 10k-node paint, snapping, and connection multi-selection");
    if (can_run_target) {
        editor_bench_step.dependOn(&run_editor_bench.step);
    } else {
        editor_bench_step.dependOn(&editor_bench.step);
    }

    const verify_editor_bench = b.addRunArtifact(editor_bench);
    verify_editor_bench.addArgs(&.{
        "--iterations=1000",
        "--max-paint-ns=1000000",
        "--max-multi-drag-ns=100000",
    });
    const verify_editor_step = b.step("verify-editor-performance", "Verify 10k-node paint, snapping, connection multi-selection, and zero allocation");
    if (can_run_target) {
        verify_editor_step.dependOn(&verify_editor_bench.step);
    } else {
        verify_editor_step.dependOn(&editor_bench.step);
    }
}
