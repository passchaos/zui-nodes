//! Reusable, allocation-free topology index for large node graphs.
//!
//! Callers own the workspace so rebuilding the index does not allocate. The
//! index fingerprints graph topology, reuses unchanged adjacency data, and
//! keeps traversal output in node-storage order for deterministic editor state.

const std = @import("std");

pub const Direction = enum(u8) {
    upstream,
    downstream,
};

pub const Workspace = struct {
    node_ids: []u32,
    node_order: []usize,
    forward_offsets: []usize,
    reverse_offsets: []usize,
    forward_neighbors: []usize,
    reverse_neighbors: []usize,
    queue: []usize,
    visited: []bool,
};

pub fn StaticWorkspace(comptime node_capacity: usize, comptime connection_capacity: usize) type {
    return struct {
        node_ids: [node_capacity]u32 = .{0} ** node_capacity,
        node_order: [node_capacity]usize = .{0} ** node_capacity,
        forward_offsets: [node_capacity + 1]usize = .{0} ** (node_capacity + 1),
        reverse_offsets: [node_capacity + 1]usize = .{0} ** (node_capacity + 1),
        forward_neighbors: [connection_capacity]usize = .{0} ** connection_capacity,
        reverse_neighbors: [connection_capacity]usize = .{0} ** connection_capacity,
        queue: [node_capacity]usize = .{0} ** node_capacity,
        visited: [node_capacity]bool = .{false} ** node_capacity,

        pub fn workspace(self: *@This()) Workspace {
            return .{
                .node_ids = &self.node_ids,
                .node_order = &self.node_order,
                .forward_offsets = &self.forward_offsets,
                .reverse_offsets = &self.reverse_offsets,
                .forward_neighbors = &self.forward_neighbors,
                .reverse_neighbors = &self.reverse_neighbors,
                .queue = &self.queue,
                .visited = &self.visited,
            };
        }
    };
}

pub const BuildResult = struct {
    node_count: usize = 0,
    connection_count: usize = 0,
    indexed_connection_count: usize = 0,
    orphan_connection_count: usize = 0,
    duplicate_node_id_count: usize = 0,
    workspace_too_small: bool = false,
    cache_hit: bool = false,

    pub fn usable(self: BuildResult) bool {
        return !self.workspace_too_small and self.duplicate_node_id_count == 0;
    }

    pub fn complete(self: BuildResult) bool {
        return self.usable() and self.orphan_connection_count == 0 and
            self.indexed_connection_count == self.connection_count;
    }
};

pub const TraversalResult = struct {
    requested_seed_count: usize = 0,
    matched_seed_count: usize = 0,
    visited_node_count: usize = 0,
    edge_visit_count: usize = 0,
    output_count: usize = 0,
    output_too_small: bool = false,
    topology_unavailable: bool = false,

    pub fn complete(self: TraversalResult) bool {
        return !self.topology_unavailable and !self.output_too_small;
    }
};

pub const Summary = struct {
    valid: bool = false,
    node_count: usize = 0,
    connection_count: usize = 0,
    indexed_connection_count: usize = 0,
    orphan_connection_count: usize = 0,
    duplicate_node_id_count: usize = 0,
    rebuild_count: u64 = 0,
    cache_hit_count: u64 = 0,
};

pub const Index = struct {
    workspace: Workspace,
    node_count: usize = 0,
    connection_count: usize = 0,
    indexed_connection_count: usize = 0,
    orphan_connection_count: usize = 0,
    duplicate_node_id_count: usize = 0,
    topology_fingerprint: u64 = 0,
    valid: bool = false,
    rebuild_count: u64 = 0,
    cache_hit_count: u64 = 0,

    pub fn init(workspace: Workspace) Index {
        return .{ .workspace = workspace };
    }

    pub fn invalidate(self: *Index) void {
        self.valid = false;
    }

    pub fn ensure(self: *Index, nodes: anytype, connections: anytype) BuildResult {
        const fingerprint = topologyFingerprint(nodes, connections);
        if (self.valid and self.node_count == nodes.len and self.connection_count == connections.len and self.topology_fingerprint == fingerprint) {
            self.cache_hit_count +%= 1;
            return self.buildResult(true);
        }
        return self.rebuild(nodes, connections, fingerprint);
    }

    pub fn traverse(self: *Index, direction: Direction, primary_seed: ?u32, seed_ids: []const u32) TraversalResult {
        const no_connections = [_]struct { from_id: u32, to_id: u32 }{};
        return self.traverseWithConnectionSeeds(direction, primary_seed, seed_ids, &no_connections);
    }

    pub fn traverseWithConnectionSeeds(self: *Index, direction: Direction, primary_seed: ?u32, seed_ids: []const u32, seed_connections: anytype) TraversalResult {
        var result = TraversalResult{ .requested_seed_count = seed_ids.len + seed_connections.len + @as(usize, if (primary_seed != null) 1 else 0) };
        if (!self.valid) {
            result.topology_unavailable = true;
            return result;
        }

        const visited = self.workspace.visited[0..self.node_count];
        const queue = self.workspace.queue[0..self.node_count];
        @memset(visited, false);
        var queue_len: usize = 0;
        if (primary_seed) |id| self.enqueueSeed(id, visited, queue, &queue_len, &result);
        for (seed_ids) |id| self.enqueueSeed(id, visited, queue, &queue_len, &result);
        for (seed_connections) |connection| {
            self.enqueueSeed(switch (direction) {
                .upstream => connection.from_id,
                .downstream => connection.to_id,
            }, visited, queue, &queue_len, &result);
        }

        var scan: usize = 0;
        while (scan < queue_len) : (scan += 1) {
            const node_index = queue[scan];
            const offsets = switch (direction) {
                .upstream => self.workspace.reverse_offsets,
                .downstream => self.workspace.forward_offsets,
            };
            const neighbors = switch (direction) {
                .upstream => self.workspace.reverse_neighbors,
                .downstream => self.workspace.forward_neighbors,
            };
            for (neighbors[offsets[node_index]..offsets[node_index + 1]]) |neighbor| {
                result.edge_visit_count += 1;
                if (visited[neighbor]) continue;
                visited[neighbor] = true;
                queue[queue_len] = neighbor;
                queue_len += 1;
            }
        }
        result.visited_node_count = queue_len;
        return result;
    }

    pub fn writeReachableNodeIds(self: *const Index, out: []u32, result: *TraversalResult) void {
        if (!self.valid or result.topology_unavailable) return;
        var write: usize = 0;
        for (self.workspace.node_ids[0..self.node_count], 0..) |id, index| {
            if (!self.workspace.visited[index]) continue;
            if (write >= out.len) {
                result.output_too_small = true;
                continue;
            }
            out[write] = id;
            write += 1;
        }
        result.output_count = write;
    }

    pub fn nodeReachableAt(self: *const Index, node_index: usize) bool {
        return self.valid and node_index < self.node_count and self.workspace.visited[node_index];
    }

    pub fn summary(self: *const Index) Summary {
        return .{
            .valid = self.valid,
            .node_count = self.node_count,
            .connection_count = self.connection_count,
            .indexed_connection_count = self.indexed_connection_count,
            .orphan_connection_count = self.orphan_connection_count,
            .duplicate_node_id_count = self.duplicate_node_id_count,
            .rebuild_count = self.rebuild_count,
            .cache_hit_count = self.cache_hit_count,
        };
    }

    fn rebuild(self: *Index, nodes: anytype, connections: anytype, fingerprint: u64) BuildResult {
        self.valid = false;
        self.rebuild_count +%= 1;
        self.node_count = nodes.len;
        self.connection_count = connections.len;
        self.indexed_connection_count = 0;
        self.orphan_connection_count = 0;
        self.duplicate_node_id_count = 0;
        self.topology_fingerprint = fingerprint;

        if (!self.workspaceFits(nodes.len, connections.len)) {
            return self.buildResultWithWorkspace(false, true);
        }

        const node_ids: []u32 = self.workspace.node_ids[0..nodes.len];
        const node_order: []usize = self.workspace.node_order[0..nodes.len];
        for (nodes, 0..) |node, index| {
            node_ids[index] = node.id;
            node_order[index] = index;
        }
        std.sort.pdq(usize, node_order, node_ids, nodeIndexLessThan);
        if (node_order.len > 1) {
            for (node_order[1..], node_order[0 .. node_order.len - 1]) |current, previous| {
                if (node_ids[current] == node_ids[previous]) self.duplicate_node_id_count += 1;
            }
        }
        if (self.duplicate_node_id_count != 0) return self.buildResult(false);

        const forward_offsets = self.workspace.forward_offsets[0 .. nodes.len + 1];
        const reverse_offsets = self.workspace.reverse_offsets[0 .. nodes.len + 1];
        @memset(forward_offsets, 0);
        @memset(reverse_offsets, 0);
        for (connections) |connection| {
            const from_index = self.nodeIndex(connection.from_id);
            const to_index = self.nodeIndex(connection.to_id);
            if (from_index == null or to_index == null) {
                self.orphan_connection_count += 1;
                continue;
            }
            forward_offsets[from_index.? + 1] += 1;
            reverse_offsets[to_index.? + 1] += 1;
            self.indexed_connection_count += 1;
        }
        prefixOffsets(forward_offsets);
        prefixOffsets(reverse_offsets);

        const cursors = self.workspace.queue[0..nodes.len];
        @memcpy(cursors, forward_offsets[0..nodes.len]);
        for (connections) |connection| {
            const from_index = self.nodeIndex(connection.from_id) orelse continue;
            const to_index = self.nodeIndex(connection.to_id) orelse continue;
            self.workspace.forward_neighbors[cursors[from_index]] = to_index;
            cursors[from_index] += 1;
        }
        @memcpy(cursors, reverse_offsets[0..nodes.len]);
        for (connections) |connection| {
            const from_index = self.nodeIndex(connection.from_id) orelse continue;
            const to_index = self.nodeIndex(connection.to_id) orelse continue;
            self.workspace.reverse_neighbors[cursors[to_index]] = from_index;
            cursors[to_index] += 1;
        }

        self.valid = true;
        return self.buildResult(false);
    }

    fn workspaceFits(self: *const Index, node_count: usize, connection_count: usize) bool {
        return self.workspace.node_ids.len >= node_count and
            self.workspace.node_order.len >= node_count and
            self.workspace.forward_offsets.len >= node_count + 1 and
            self.workspace.reverse_offsets.len >= node_count + 1 and
            self.workspace.forward_neighbors.len >= connection_count and
            self.workspace.reverse_neighbors.len >= connection_count and
            self.workspace.queue.len >= node_count and
            self.workspace.visited.len >= node_count;
    }

    fn buildResult(self: *const Index, cache_hit: bool) BuildResult {
        return self.buildResultWithWorkspace(cache_hit, false);
    }

    fn buildResultWithWorkspace(self: *const Index, cache_hit: bool, workspace_too_small: bool) BuildResult {
        return .{
            .node_count = self.node_count,
            .connection_count = self.connection_count,
            .indexed_connection_count = self.indexed_connection_count,
            .orphan_connection_count = self.orphan_connection_count,
            .duplicate_node_id_count = self.duplicate_node_id_count,
            .workspace_too_small = workspace_too_small,
            .cache_hit = cache_hit,
        };
    }

    fn nodeIndex(self: *const Index, id: u32) ?usize {
        var low: usize = 0;
        var high = self.node_count;
        while (low < high) {
            const mid = low + (high - low) / 2;
            const index = self.workspace.node_order[mid];
            const candidate = self.workspace.node_ids[index];
            if (candidate < id) {
                low = mid + 1;
            } else if (candidate > id) {
                high = mid;
            } else {
                return index;
            }
        }
        return null;
    }

    fn enqueueSeed(self: *const Index, id: u32, visited: []bool, queue: []usize, queue_len: *usize, result: *TraversalResult) void {
        const index = self.nodeIndex(id) orelse return;
        result.matched_seed_count += 1;
        if (visited[index]) return;
        visited[index] = true;
        queue[queue_len.*] = index;
        queue_len.* += 1;
    }
};

fn nodeIndexLessThan(node_ids: []const u32, a: usize, b: usize) bool {
    if (node_ids[a] != node_ids[b]) return node_ids[a] < node_ids[b];
    return a < b;
}

fn prefixOffsets(offsets: []usize) void {
    var index: usize = 1;
    while (index < offsets.len) : (index += 1) offsets[index] += offsets[index - 1];
}

fn topologyFingerprint(nodes: anytype, connections: anytype) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    mixFingerprint(&hash, nodes.len);
    mixFingerprint(&hash, connections.len);
    for (nodes) |node| mixFingerprint(&hash, node.id);
    for (connections) |connection| {
        mixFingerprint(&hash, connection.from_id);
        mixFingerprint(&hash, connection.to_id);
    }
    return hash;
}

fn mixFingerprint(hash: *u64, value: anytype) void {
    hash.* ^= @as(u64, @intCast(value));
    hash.* *%= 0x100000001b3;
}

const TestNode = struct { id: u32 };
const TestConnection = struct { from_id: u32, to_id: u32 };

test "topology index traverses large graphs in stable storage order" {
    const node_count = 256;
    var nodes: [node_count]TestNode = undefined;
    var connections: [node_count - 1]TestConnection = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{ .id = @intCast(1000 + index) };
    for (&connections, 0..) |*connection, index| connection.* = .{
        .from_id = nodes[index].id,
        .to_id = nodes[index + 1].id,
    };
    var storage = StaticWorkspace(node_count, connections.len){};
    var topology = Index.init(storage.workspace());

    const build = topology.ensure(&nodes, &connections);
    try std.testing.expect(build.complete());
    try std.testing.expectEqual(@as(u64, 1), topology.summary().rebuild_count);

    var reachable: [node_count]u32 = undefined;
    var traversal = topology.traverse(.downstream, nodes[0].id, &.{});
    topology.writeReachableNodeIds(&reachable, &traversal);
    try std.testing.expect(traversal.complete());
    try std.testing.expectEqual(node_count, traversal.visited_node_count);
    try std.testing.expectEqual(connections.len, traversal.edge_visit_count);
    for (nodes, reachable) |node, id| try std.testing.expectEqual(node.id, id);

    var bounded: [32]u32 = undefined;
    var bounded_traversal = topology.traverse(.downstream, nodes[0].id, &.{});
    topology.writeReachableNodeIds(&bounded, &bounded_traversal);
    try std.testing.expect(!bounded_traversal.complete());
    try std.testing.expect(bounded_traversal.output_too_small);
    try std.testing.expectEqual(bounded.len, bounded_traversal.output_count);
    try std.testing.expectEqual(node_count, bounded_traversal.visited_node_count);

    const cached = topology.ensure(&nodes, &connections);
    try std.testing.expect(cached.cache_hit);
    try std.testing.expectEqual(@as(u64, 1), topology.summary().cache_hit_count);

    connections[0].to_id = nodes[2].id;
    const rebuilt = topology.ensure(&nodes, &connections);
    try std.testing.expect(!rebuilt.cache_hit);
    try std.testing.expectEqual(@as(u64, 2), topology.summary().rebuild_count);
}

test "topology index reports orphans duplicates and workspace limits" {
    const duplicate_nodes = [_]TestNode{ .{ .id = 7 }, .{ .id = 7 } };
    var duplicate_storage = StaticWorkspace(2, 1){};
    var duplicate_index = Index.init(duplicate_storage.workspace());
    const duplicate = duplicate_index.ensure(&duplicate_nodes, &.{});
    try std.testing.expectEqual(@as(usize, 1), duplicate.duplicate_node_id_count);
    try std.testing.expect(!duplicate.usable());

    const nodes = [_]TestNode{ .{ .id = 1 }, .{ .id = 2 }, .{ .id = 3 } };
    const connections = [_]TestConnection{ .{ .from_id = 1, .to_id = 2 }, .{ .from_id = 2, .to_id = 99 } };
    var storage = StaticWorkspace(3, 2){};
    var topology = Index.init(storage.workspace());
    const build = topology.ensure(&nodes, &connections);
    try std.testing.expect(build.usable());
    try std.testing.expect(!build.complete());
    try std.testing.expectEqual(@as(usize, 1), build.indexed_connection_count);
    try std.testing.expectEqual(@as(usize, 1), build.orphan_connection_count);

    var small_storage = StaticWorkspace(2, 2){};
    var small = Index.init(small_storage.workspace());
    try std.testing.expect(small.ensure(&nodes, &connections).workspace_too_small);
    try std.testing.expectEqual(@as(u64, 1), small.summary().rebuild_count);
}
