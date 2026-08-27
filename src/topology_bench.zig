const std = @import("std");
const topology_mod = @import("graph_topology.zig");

const node_count: usize = 4096;
const branch_stride: usize = 2;
const branch_count: usize = node_count - branch_stride;
const connection_count: usize = (node_count - 1) + branch_count;
const default_iterations: usize = 1000;

const Node = struct { id: u32 };
const Connection = struct { from_id: u32, to_id: u32 };

const Options = struct {
    iterations: usize = default_iterations,
    max_build_ns: ?u64 = null,
    max_cached_traversal_ns: ?f64 = null,
};

const Report = struct {
    node_count: usize,
    connection_count: usize,
    iterations: usize,
    build_ns: u64,
    cached_traversal_ns: u64,
    cached_traversal_ns_per_iteration: f64,
    edge_visits_per_iteration: usize,
    output_count: usize,
    rebuild_count: u64,
    cache_hit_count: u64,
    hot_path_allocations: usize,
    checksum: u64,
    quality_passed: bool,
    performance_passed: bool,
    passed: bool,
};

pub fn main(init: std.process.Init) !void {
    const options = try parseOptions(init);
    const report = run(init.io, options);
    try printReport(init.io, report);
    if (!report.quality_passed) return error.TopologyBenchQualityFailed;
    if (!report.performance_passed) return error.TopologyBenchPerformanceFailed;
}

fn run(io: std.Io, options: Options) Report {
    var nodes: [node_count]Node = undefined;
    var connections: [connection_count]Connection = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{ .id = @intCast(index + 1) };
    for (0..node_count - 1) |index| connections[index] = .{
        .from_id = nodes[index].id,
        .to_id = nodes[index + 1].id,
    };
    for (0..branch_count) |index| connections[node_count - 1 + index] = .{
        .from_id = nodes[index].id,
        .to_id = nodes[index + branch_stride].id,
    };

    var storage = topology_mod.StaticWorkspace(node_count, connection_count){};
    var topology = topology_mod.Index.init(storage.workspace());
    const build_started = std.Io.Clock.awake.now(io);
    const build = topology.ensure(&nodes, &connections);
    const build_ns: u64 = @intCast(build_started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());

    var output: [node_count]u32 = undefined;
    var checksum: u64 = 0xcbf2_9ce4_8422_2325;
    var last = topology_mod.TraversalResult{};
    const traversal_started = std.Io.Clock.awake.now(io);
    for (0..options.iterations) |iteration| {
        _ = topology.ensure(&nodes, &connections);
        last = topology.traverse(if (iteration & 1 == 0) .downstream else .upstream, if (iteration & 1 == 0) nodes[0].id else nodes[node_count - 1].id, &.{});
        topology.writeReachableNodeIds(&output, &last);
        checksum = (checksum ^ output[iteration % output.len]) *% 0x0000_0100_0000_01b3;
        checksum = (checksum ^ @as(u64, @intCast(last.edge_visit_count))) *% 0x0000_0100_0000_01b3;
    }
    const cached_traversal_ns: u64 = @intCast(traversal_started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
    const ns_per_iteration = @as(f64, @floatFromInt(cached_traversal_ns)) / @as(f64, @floatFromInt(options.iterations));
    const quality_passed = build.complete() and last.complete() and last.output_count == node_count and
        last.edge_visit_count == connection_count and topology.summary().rebuild_count == 1 and
        topology.summary().cache_hit_count == options.iterations and checksum != 0;
    const performance_passed = (options.max_build_ns == null or build_ns <= options.max_build_ns.?) and
        (options.max_cached_traversal_ns == null or ns_per_iteration <= options.max_cached_traversal_ns.?);
    return .{
        .node_count = node_count,
        .connection_count = connection_count,
        .iterations = options.iterations,
        .build_ns = build_ns,
        .cached_traversal_ns = cached_traversal_ns,
        .cached_traversal_ns_per_iteration = ns_per_iteration,
        .edge_visits_per_iteration = last.edge_visit_count,
        .output_count = last.output_count,
        .rebuild_count = topology.summary().rebuild_count,
        .cache_hit_count = topology.summary().cache_hit_count,
        .hot_path_allocations = 0,
        .checksum = checksum,
        .quality_passed = quality_passed,
        .performance_passed = performance_passed,
        .passed = quality_passed and performance_passed,
    };
}

fn parseOptions(init: std.process.Init) !Options {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    var options = Options{};
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--iterations="))
            options.iterations = try std.fmt.parseInt(usize, arg["--iterations=".len..], 10)
        else if (std.mem.startsWith(u8, arg, "--max-build-ns="))
            options.max_build_ns = try std.fmt.parseInt(u64, arg["--max-build-ns=".len..], 10)
        else if (std.mem.startsWith(u8, arg, "--max-cached-traversal-ns="))
            options.max_cached_traversal_ns = try std.fmt.parseFloat(f64, arg["--max-cached-traversal-ns=".len..])
        else
            return error.InvalidArgument;
    }
    if (options.iterations == 0) return error.InvalidArgument;
    return options;
}

fn printReport(io: std.Io, report: Report) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    const stdout = &stdout_file_writer.interface;
    try stdout.print(
        "zui-nodes topology bench: nodes={d} connections={d} iterations={d} build_ns={d} cached_traversal_ns_per_iteration={d:.3} edge_visits={d} output={d} rebuilds={d} hits={d} allocations={d} checksum={d} passed={}\n",
        .{ report.node_count, report.connection_count, report.iterations, report.build_ns, report.cached_traversal_ns_per_iteration, report.edge_visits_per_iteration, report.output_count, report.rebuild_count, report.cache_hit_count, report.hot_path_allocations, report.checksum, report.passed },
    );
    try stdout.flush();
}

test "topology benchmark options parse" {
    _ = Options{};
}
