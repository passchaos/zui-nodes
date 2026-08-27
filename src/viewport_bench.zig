const std = @import("std");
const viewport_mod = @import("node_viewport.zig");

const columns: usize = 100;
const rows: usize = 100;
const node_count: usize = columns * rows;
const horizontal_connection_count: usize = rows * (columns - 1);
const vertical_connection_count: usize = columns * (rows - 1);
const connection_count: usize = horizontal_connection_count + vertical_connection_count;
const default_iterations: usize = 2000;

const Rect = struct { x: f32, y: f32, w: f32, h: f32 };
const Size = struct { w: f32, h: f32 };
const Node = struct {
    id: u32,
    pos: [2]f32,
    size: Size = .{ .w = 144, .h = 72 },
    input_count: u8 = 2,
    output_count: u8 = 2,
};
const Group = struct { id: u32, rect: Rect };
const Connection = struct { from_id: u32, to_id: u32, from_port: u8 = 0, to_port: u8 = 0 };
const ViewportTypes = viewport_mod.Types(Node, Group, Connection, Rect);

const Options = struct {
    iterations: usize = default_iterations,
    max_build_ns: ?u64 = null,
    max_query_ns: ?f64 = null,
    max_cached_prepare_ns: ?f64 = null,
};

const Report = struct {
    node_count: usize,
    connection_count: usize,
    iterations: usize,
    build_ns: u64,
    query_ns_per_iteration: f64,
    cached_prepare_ns_per_iteration: f64,
    max_visible_nodes: usize,
    max_visible_connections: usize,
    target_candidate_miss_count: usize,
    box_candidate_miss_count: usize,
    max_box_candidates: usize,
    rebuild_count: u64,
    query_count: u64,
    geometry_reuse_count: u64,
    viewport_reuse_count: u64,
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
    if (!report.quality_passed) return error.ViewportBenchQualityFailed;
    if (!report.performance_passed) return error.ViewportBenchPerformanceFailed;
}

fn run(io: std.Io, options: Options) Report {
    var nodes: [node_count]Node = undefined;
    var connections: [connection_count]Connection = undefined;
    for (&nodes, 0..) |*node, index| {
        const column = index % columns;
        const row = index / columns;
        node.* = .{
            .id = @intCast(index + 1),
            .pos = .{
                (@as(f32, @floatFromInt(column)) - @as(f32, @floatFromInt(columns)) * 0.5) * 184.0,
                (@as(f32, @floatFromInt(row)) - @as(f32, @floatFromInt(rows)) * 0.5) * 112.0,
            },
        };
    }
    var connection_index: usize = 0;
    for (0..rows) |row| {
        for (0..columns - 1) |column| {
            const from = row * columns + column;
            connections[connection_index] = .{ .from_id = nodes[from].id, .to_id = nodes[from + 1].id, .from_port = @intCast(column & 1), .to_port = @intCast(column & 1) };
            connection_index += 1;
        }
    }
    for (0..rows - 1) |row| {
        for (0..columns) |column| {
            const from = row * columns + column;
            connections[connection_index] = .{ .from_id = nodes[from].id, .to_id = nodes[from + columns].id, .from_port = @intCast(row & 1), .to_port = @intCast(row & 1) };
            connection_index += 1;
        }
    }

    var storage = ViewportTypes.StaticWorkspace(node_count, 0, connection_count){};
    var viewport_index = ViewportTypes.Index.init(storage.workspace());
    const groups = [_]Group{};
    const viewport = Rect{ .x = 0, .y = 0, .w = 1280, .h = 720 };
    const revision: u64 = 1;

    const build_started = std.Io.Clock.awake.now(io);
    const build = viewport_index.prepareVersioned(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 1, revision);
    const build_ns: u64 = @intCast(build_started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());

    var checksum: u64 = 0xcbf2_9ce4_8422_2325;
    var max_visible_nodes: usize = 0;
    var max_visible_connections: usize = 0;
    var target_candidate_miss_count: usize = 0;
    var box_candidate_miss_count: usize = 0;
    var max_box_candidates: usize = 0;
    var last_pan: [2]f32 = .{ 0, 0 };
    var last_zoom: f32 = 1;
    const query_started = std.Io.Clock.awake.now(io);
    for (0..options.iterations) |iteration| {
        const target_index = (iteration * 7919) % node_count;
        const target = nodes[target_index];
        last_zoom = switch (iteration % 3) {
            0 => 0.55,
            1 => 1.0,
            else => 1.75,
        };
        last_pan = .{ -target.pos[0] * last_zoom, -target.pos[1] * last_zoom };
        const prepared = viewport_index.prepareVersioned(&nodes, &groups, &connections, viewport, last_pan, last_zoom, revision);
        max_visible_nodes = @max(max_visible_nodes, prepared.visible_node_count);
        max_visible_connections = @max(max_visible_connections, prepared.visible_connection_count);
        const point = [2]f32{ viewport.w * 0.5 + target.size.w * last_zoom * 0.5, viewport.h * 0.5 + target.size.h * last_zoom * 0.5 };
        const candidates = viewport_index.nodeIndicesNearPoint(viewport, last_pan, last_zoom, point, 0);
        var found_target = false;
        for (candidates) |candidate| {
            if (candidate == target_index) {
                found_target = true;
                break;
            }
        }
        if (!found_target) target_candidate_miss_count += 1;
        const box_rect = Rect{ .x = viewport.w * 0.5 - 240, .y = viewport.h * 0.5 - 160, .w = 480, .h = 320 };
        const box_candidates = viewport_index.nodeIndicesInScreenRect(viewport, last_pan, last_zoom, box_rect);
        max_box_candidates = @max(max_box_candidates, box_candidates.len);
        var target_in_box = false;
        for (box_candidates) |candidate| {
            if (candidate == target_index) {
                target_in_box = true;
                break;
            }
        }
        if (!target_in_box) box_candidate_miss_count += 1;
        checksum = (checksum ^ @as(u64, @intCast(prepared.visible_node_count))) *% 0x0000_0100_0000_01b3;
        checksum = (checksum ^ @as(u64, @intCast(prepared.visible_connection_count))) *% 0x0000_0100_0000_01b3;
        checksum = (checksum ^ @as(u64, @intCast(candidates.len))) *% 0x0000_0100_0000_01b3;
        if (candidates.len > 0) checksum = (checksum ^ @as(u64, @intCast(candidates[0]))) *% 0x0000_0100_0000_01b3;
    }
    const query_ns: u64 = @intCast(query_started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
    const query_ns_per_iteration = @as(f64, @floatFromInt(query_ns)) / @as(f64, @floatFromInt(options.iterations));

    const cached_started = std.Io.Clock.awake.now(io);
    for (0..options.iterations) |_| {
        const prepared = viewport_index.prepareVersioned(&nodes, &groups, &connections, viewport, last_pan, last_zoom, revision);
        checksum = (checksum ^ @as(u64, @intFromBool(prepared.viewport_reused))) *% 0x0000_0100_0000_01b3;
    }
    const cached_ns: u64 = @intCast(cached_started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
    const cached_prepare_ns_per_iteration = @as(f64, @floatFromInt(cached_ns)) / @as(f64, @floatFromInt(options.iterations));
    const summary = viewport_index.summary();
    const quality_passed = build.ready and connection_index == connection_count and
        summary.valid and summary.rebuild_count == 1 and summary.query_count == options.iterations + 1 and
        summary.geometry_reuse_count == options.iterations * 2 and summary.viewport_reuse_count == options.iterations and
        max_visible_nodes > 0 and max_visible_nodes < node_count / 20 and
        max_visible_connections > 0 and max_visible_connections < connection_count / 10 and checksum != 0;
    const candidate_quality_passed = target_candidate_miss_count == 0 and box_candidate_miss_count == 0 and max_box_candidates < node_count / 20;
    const performance_passed = (options.max_build_ns == null or build_ns <= options.max_build_ns.?) and
        (options.max_query_ns == null or query_ns_per_iteration <= options.max_query_ns.?) and
        (options.max_cached_prepare_ns == null or cached_prepare_ns_per_iteration <= options.max_cached_prepare_ns.?);
    return .{
        .node_count = node_count,
        .connection_count = connection_count,
        .iterations = options.iterations,
        .build_ns = build_ns,
        .query_ns_per_iteration = query_ns_per_iteration,
        .cached_prepare_ns_per_iteration = cached_prepare_ns_per_iteration,
        .max_visible_nodes = max_visible_nodes,
        .max_visible_connections = max_visible_connections,
        .target_candidate_miss_count = target_candidate_miss_count,
        .box_candidate_miss_count = box_candidate_miss_count,
        .max_box_candidates = max_box_candidates,
        .rebuild_count = summary.rebuild_count,
        .query_count = summary.query_count,
        .geometry_reuse_count = summary.geometry_reuse_count,
        .viewport_reuse_count = summary.viewport_reuse_count,
        .hot_path_allocations = 0,
        .checksum = checksum,
        .quality_passed = quality_passed and candidate_quality_passed,
        .performance_passed = performance_passed,
        .passed = quality_passed and candidate_quality_passed and performance_passed,
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
        else if (std.mem.startsWith(u8, arg, "--max-query-ns="))
            options.max_query_ns = try std.fmt.parseFloat(f64, arg["--max-query-ns=".len..])
        else if (std.mem.startsWith(u8, arg, "--max-cached-prepare-ns="))
            options.max_cached_prepare_ns = try std.fmt.parseFloat(f64, arg["--max-cached-prepare-ns=".len..])
        else
            return error.InvalidArgument;
    }
    if (options.iterations == 0) return error.InvalidArgument;
    return options;
}

fn printReport(io: std.Io, report: Report) !void {
    var buffer: [1536]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    const stdout = &stdout_file_writer.interface;
    try stdout.print(
        "zui-nodes viewport bench: nodes={d} connections={d} iterations={d} build_ns={d} query_ns_per_iteration={d:.3} cached_prepare_ns_per_iteration={d:.3} max_visible_nodes={d} max_visible_connections={d} point_misses={d} box_misses={d} max_box_candidates={d} rebuilds={d} queries={d} geometry_reuse={d} viewport_reuse={d} allocations={d} checksum={d} passed={}\n",
        .{ report.node_count, report.connection_count, report.iterations, report.build_ns, report.query_ns_per_iteration, report.cached_prepare_ns_per_iteration, report.max_visible_nodes, report.max_visible_connections, report.target_candidate_miss_count, report.box_candidate_miss_count, report.max_box_candidates, report.rebuild_count, report.query_count, report.geometry_reuse_count, report.viewport_reuse_count, report.hot_path_allocations, report.checksum, report.passed },
    );
    try stdout.flush();
}

test "viewport benchmark options compile" {
    _ = Options{};
}
