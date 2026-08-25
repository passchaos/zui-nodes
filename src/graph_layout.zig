//! Deterministic graph layout helpers for zui-nodes.

const std = @import("std");
const graph_validation = @import("graph_validation.zig");

pub const LayeredLayoutDirection = enum(u8) {
    left_to_right,
    right_to_left,
    top_to_bottom,
    bottom_to_top,
};

pub const LayeredLayoutOptions = struct {
    direction: LayeredLayoutDirection = .left_to_right,
    origin: [2]f32 = .{ 0.0, 0.0 },
    layer_gap: f32 = 220.0,
    node_gap: f32 = 36.0,
    include_unconnected: bool = true,
    preserve_order: bool = true,
    connection_policy: graph_validation.ConnectionPolicy = .strict_dataflow,
};

pub const LayeredLayoutResult = struct {
    node_count: usize = 0,
    connection_count: usize = 0,
    moved_count: usize = 0,
    layer_count: usize = 0,
    max_layer_occupancy: usize = 0,
    cycle_detected: bool = false,
    invalid_graph: bool = false,
    workspace_too_small: bool = false,

    pub fn changed(self: LayeredLayoutResult) bool {
        return self.moved_count > 0;
    }

    pub fn ok(self: LayeredLayoutResult) bool {
        return !self.invalid_graph and !self.workspace_too_small;
    }
};

pub const LayeredLayoutWorkspace = struct {
    ranks: []u16 = &.{},
    layer_counts: []usize = &.{},
};

pub fn StaticLayeredLayoutWorkspace(comptime node_capacity: usize, comptime layer_capacity: usize) type {
    return struct {
        ranks: [node_capacity]u16 = .{0} ** node_capacity,
        layer_counts: [layer_capacity]usize = .{0} ** layer_capacity,

        pub fn workspace(self: *@This()) LayeredLayoutWorkspace {
            return .{
                .ranks = &self.ranks,
                .layer_counts = &self.layer_counts,
            };
        }
    };
}

pub fn canLayoutLayered(nodes: anytype, node_len: usize, connections: anytype, workspace: LayeredLayoutWorkspace, options: LayeredLayoutOptions) bool {
    const count = @min(node_len, nodes.len);
    if (count == 0) return false;
    if (workspace.ranks.len < count or workspace.layer_counts.len == 0) return false;
    if (!options.connection_policy.allow_cycles and !graph_validation.validateGraph(nodes[0..count], connections, options.connection_policy).validFor(options.connection_policy)) return false;
    return true;
}

pub fn layoutLayered(nodes: anytype, node_len: usize, connections: anytype, workspace: LayeredLayoutWorkspace, options: LayeredLayoutOptions) LayeredLayoutResult {
    const count = @min(node_len, nodes.len);
    var result = LayeredLayoutResult{
        .node_count = count,
        .connection_count = connections.len,
    };
    if (count == 0) return result;
    if (workspace.ranks.len < count or workspace.layer_counts.len == 0) {
        result.workspace_too_small = true;
        return result;
    }

    if (!options.connection_policy.allow_cycles) {
        const report = graph_validation.validateGraph(nodes[0..count], connections, options.connection_policy);
        result.invalid_graph = !report.validFor(options.connection_policy);
        result.cycle_detected = report.cycle_count != 0;
        if (result.invalid_graph) return result;
    }

    const ranks = workspace.ranks[0..count];
    @memset(ranks, 0);
    @memset(workspace.layer_counts, 0);

    const max_rank = @as(u16, @intCast(@min(workspace.layer_counts.len - 1, std.math.maxInt(u16))));
    var pass: usize = 0;
    while (pass < count) : (pass += 1) {
        var changed = false;
        for (connections) |connection| {
            const from_index = nodeIndexById(nodes[0..count], connection.from_id) orelse continue;
            const to_index = nodeIndexById(nodes[0..count], connection.to_id) orelse continue;
            if (from_index == to_index) {
                result.cycle_detected = true;
                continue;
            }
            const next_rank_raw = @as(usize, ranks[from_index]) + 1;
            if (next_rank_raw > max_rank) result.workspace_too_small = true;
            const next_rank = @as(u16, @intCast(@min(next_rank_raw, max_rank)));
            if (ranks[to_index] < next_rank) {
                ranks[to_index] = next_rank;
                changed = true;
            }
        }
        if (!changed) break;
        if (pass + 1 == count) result.cycle_detected = true;
    }

    if (!options.connection_policy.allow_cycles and result.cycle_detected) {
        result.invalid_graph = true;
        return result;
    }

    var max_seen_rank: u16 = 0;
    for (ranks) |rank| max_seen_rank = @max(max_seen_rank, rank);
    result.layer_count = @as(usize, max_seen_rank) + 1;
    if (result.layer_count > workspace.layer_counts.len) {
        result.layer_count = workspace.layer_counts.len;
        result.workspace_too_small = true;
    }
    for (ranks) |rank| {
        const layer = @min(@as(usize, rank), workspace.layer_counts.len - 1);
        workspace.layer_counts[layer] += 1;
        result.max_layer_occupancy = @max(result.max_layer_occupancy, workspace.layer_counts[layer]);
    }

    for (nodes[0..count], 0..) |*node, index| {
        if (!options.include_unconnected and !nodeHasIncidentConnection(node.id, connections)) continue;
        const rank = @min(@as(usize, ranks[index]), workspace.layer_counts.len - 1);
        const offset = nodeOffsetInLayer(nodes[0..count], ranks, index, rank, options);
        const before = node.pos;
        switch (options.direction) {
            .left_to_right => node.pos = .{
                options.origin[0] + @as(f32, @floatFromInt(rank)) * options.layer_gap,
                options.origin[1] + offset,
            },
            .right_to_left => node.pos = .{
                options.origin[0] - @as(f32, @floatFromInt(rank)) * options.layer_gap,
                options.origin[1] + offset,
            },
            .top_to_bottom => node.pos = .{
                options.origin[0] + offset,
                options.origin[1] + @as(f32, @floatFromInt(rank)) * options.layer_gap,
            },
            .bottom_to_top => node.pos = .{
                options.origin[0] + offset,
                options.origin[1] - @as(f32, @floatFromInt(rank)) * options.layer_gap,
            },
        }
        if (@abs(before[0] - node.pos[0]) > 0.001 or @abs(before[1] - node.pos[1]) > 0.001) {
            result.moved_count += 1;
        }
    }

    return result;
}

fn nodeOffsetInLayer(nodes: anytype, ranks: []const u16, node_index: usize, rank: usize, options: LayeredLayoutOptions) f32 {
    var offset: f32 = 0.0;
    for (nodes[0..node_index], 0..) |node, index| {
        if (@as(usize, ranks[index]) != rank) continue;
        offset += crossSize(node, options.direction) + options.node_gap;
    }
    if (!options.preserve_order) {
        offset = 0.0;
        for (nodes, 0..) |node, index| {
            if (index == node_index or @as(usize, ranks[index]) != rank) continue;
            if (node.id < nodes[node_index].id or (node.id == nodes[node_index].id and index < node_index)) {
                offset += crossSize(node, options.direction) + options.node_gap;
            }
        }
    }
    return offset;
}

fn nodeIndexById(nodes: anytype, id: u32) ?usize {
    for (nodes, 0..) |node, index| {
        if (node.id == id) return index;
    }
    return null;
}

fn nodeHasIncidentConnection(id: u32, connections: anytype) bool {
    for (connections) |connection| {
        if (connection.from_id == id or connection.to_id == id) return true;
    }
    return false;
}

fn crossSize(node: anytype, direction: LayeredLayoutDirection) f32 {
    if (!@hasField(@TypeOf(node), "size")) return 1.0;
    return switch (direction) {
        .left_to_right, .right_to_left => @max(1.0, node.size.h),
        .top_to_bottom, .bottom_to_top => @max(1.0, node.size.w),
    };
}

const TestNode = struct {
    id: u32,
    pos: [2]f32 = .{ 0.0, 0.0 },
    size: struct { w: f32 = 80.0, h: f32 = 40.0 } = .{},
    input_count: u8 = 1,
    output_count: u8 = 1,
};

const TestConnection = struct {
    from_id: u32,
    to_id: u32,
    from_port: u8 = 0,
    to_port: u8 = 0,
};

test "layered layout ranks nodes from directed connections" {
    var nodes = [_]TestNode{
        .{ .id = 1 },
        .{ .id = 2 },
        .{ .id = 3 },
    };
    const connections = [_]TestConnection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
    };
    var storage = StaticLayeredLayoutWorkspace(8, 8){};
    const result = layoutLayered(&nodes, nodes.len, &connections, storage.workspace(), .{ .origin = .{ 10, 20 }, .layer_gap = 200, .node_gap = 24 });
    try std.testing.expect(result.ok());
    try std.testing.expectEqual(@as(usize, 3), result.layer_count);
    try std.testing.expectEqual(@as(f32, 10), nodes[0].pos[0]);
    try std.testing.expectEqual(@as(f32, 210), nodes[1].pos[0]);
    try std.testing.expectEqual(@as(f32, 410), nodes[2].pos[0]);
}

test "layered layout strict policy refuses cyclic graph mutation" {
    var nodes = [_]TestNode{
        .{ .id = 1, .pos = .{ 11, 7 } },
        .{ .id = 2, .pos = .{ 21, 7 } },
    };
    const before = nodes;
    const connections = [_]TestConnection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 1 },
    };
    var storage = StaticLayeredLayoutWorkspace(8, 8){};
    const result = layoutLayered(&nodes, nodes.len, &connections, storage.workspace(), .{ .connection_policy = .strict_dataflow });
    try std.testing.expect(result.invalid_graph);
    try std.testing.expect(result.cycle_detected);
    try std.testing.expectEqual(before, nodes);
}
