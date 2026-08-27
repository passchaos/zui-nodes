//! Allocation-free viewport candidate index for large node graphs.
//!
//! Geometry is stored as X-sorted intervals with prefix maximum extents. A
//! query skips every object ending before the viewport and stops once object
//! starts pass it, while a final Y test keeps the candidate set conservative.
//! Safe preparation fingerprints geometry automatically. Versioned preparation
//! avoids that scan and requires the caller to advance its geometry revision.

const std = @import("std");

pub fn Types(comptime Node: type, comptime Group: type, comptime Connection: type, comptime Rect: type) type {
    return struct {
        pub const Workspace = struct {
            node_bounds: []Rect,
            node_order: []usize,
            node_prefix_max_x: []f32,
            node_ids: []u32,
            node_id_order: []usize,
            visible_node_indices: []usize,
            node_hit_indices: []usize,
            group_bounds: []Rect,
            group_order: []usize,
            group_prefix_max_x: []f32,
            visible_group_indices: []usize,
            group_hit_indices: []usize,
            connection_bounds: []Rect,
            connection_order: []usize,
            connection_prefix_max_x: []f32,
            visible_connection_indices: []usize,
            connection_hit_indices: []usize,
        };

        /// Owns dynamically sized workspace memory for graphs whose capacities
        /// are not known at compile time. Allocation happens only during init;
        /// rebuilds, viewport queries, and hit candidate queries stay allocation-free.
        pub const Storage = struct {
            allocator: std.mem.Allocator,
            bounds: []Rect,
            indices: []usize,
            prefix_max_x: []f32,
            node_ids: []u32,
            node_capacity: usize,
            group_capacity: usize,
            connection_capacity: usize,

            pub fn init(allocator: std.mem.Allocator, node_capacity: usize, group_capacity: usize, connection_capacity: usize) !Storage {
                const interval_capacity = try capacitySum(node_capacity, group_capacity, connection_capacity);
                const node_indices = try std.math.mul(usize, node_capacity, 4);
                const group_indices = try std.math.mul(usize, group_capacity, 3);
                const connection_indices = try std.math.mul(usize, connection_capacity, 3);
                const index_capacity = try capacitySum(node_indices, group_indices, connection_indices);
                const bounds = try allocator.alloc(Rect, interval_capacity);
                errdefer allocator.free(bounds);
                const indices = try allocator.alloc(usize, index_capacity);
                errdefer allocator.free(indices);
                const prefix_max_x = try allocator.alloc(f32, interval_capacity);
                errdefer allocator.free(prefix_max_x);
                const node_ids = try allocator.alloc(u32, node_capacity);
                return .{
                    .allocator = allocator,
                    .bounds = bounds,
                    .indices = indices,
                    .prefix_max_x = prefix_max_x,
                    .node_ids = node_ids,
                    .node_capacity = node_capacity,
                    .group_capacity = group_capacity,
                    .connection_capacity = connection_capacity,
                };
            }

            pub fn deinit(self: *Storage) void {
                self.allocator.free(self.bounds);
                self.allocator.free(self.indices);
                self.allocator.free(self.prefix_max_x);
                self.allocator.free(self.node_ids);
                self.* = undefined;
            }

            pub fn workspace(self: *Storage) Workspace {
                const node_end = self.node_capacity;
                const group_end = node_end + self.group_capacity;
                const connection_end = group_end + self.connection_capacity;

                var index_offset: usize = 0;
                const node_order = takeIndices(self.indices, &index_offset, self.node_capacity);
                const node_id_order = takeIndices(self.indices, &index_offset, self.node_capacity);
                const visible_node_indices = takeIndices(self.indices, &index_offset, self.node_capacity);
                const node_hit_indices = takeIndices(self.indices, &index_offset, self.node_capacity);
                const group_order = takeIndices(self.indices, &index_offset, self.group_capacity);
                const visible_group_indices = takeIndices(self.indices, &index_offset, self.group_capacity);
                const group_hit_indices = takeIndices(self.indices, &index_offset, self.group_capacity);
                const connection_order = takeIndices(self.indices, &index_offset, self.connection_capacity);
                const visible_connection_indices = takeIndices(self.indices, &index_offset, self.connection_capacity);
                const connection_hit_indices = takeIndices(self.indices, &index_offset, self.connection_capacity);

                return .{
                    .node_bounds = self.bounds[0..node_end],
                    .node_order = node_order,
                    .node_prefix_max_x = self.prefix_max_x[0..node_end],
                    .node_ids = self.node_ids,
                    .node_id_order = node_id_order,
                    .visible_node_indices = visible_node_indices,
                    .node_hit_indices = node_hit_indices,
                    .group_bounds = self.bounds[node_end..group_end],
                    .group_order = group_order,
                    .group_prefix_max_x = self.prefix_max_x[node_end..group_end],
                    .visible_group_indices = visible_group_indices,
                    .group_hit_indices = group_hit_indices,
                    .connection_bounds = self.bounds[group_end..connection_end],
                    .connection_order = connection_order,
                    .connection_prefix_max_x = self.prefix_max_x[group_end..connection_end],
                    .visible_connection_indices = visible_connection_indices,
                    .connection_hit_indices = connection_hit_indices,
                };
            }

            fn takeIndices(indices: []usize, offset: *usize, count: usize) []usize {
                const start = offset.*;
                offset.* += count;
                return indices[start..offset.*];
            }

            fn capacitySum(a: usize, b: usize, c: usize) !usize {
                return std.math.add(usize, try std.math.add(usize, a, b), c);
            }
        };

        pub fn StaticWorkspace(comptime node_capacity: usize, comptime group_capacity: usize, comptime connection_capacity: usize) type {
            return struct {
                node_bounds: [node_capacity]Rect = undefined,
                node_order: [node_capacity]usize = undefined,
                node_prefix_max_x: [node_capacity]f32 = undefined,
                node_ids: [node_capacity]u32 = .{0} ** node_capacity,
                node_id_order: [node_capacity]usize = undefined,
                visible_node_indices: [node_capacity]usize = undefined,
                node_hit_indices: [node_capacity]usize = undefined,
                group_bounds: [group_capacity]Rect = undefined,
                group_order: [group_capacity]usize = undefined,
                group_prefix_max_x: [group_capacity]f32 = undefined,
                visible_group_indices: [group_capacity]usize = undefined,
                group_hit_indices: [group_capacity]usize = undefined,
                connection_bounds: [connection_capacity]Rect = undefined,
                connection_order: [connection_capacity]usize = undefined,
                connection_prefix_max_x: [connection_capacity]f32 = undefined,
                visible_connection_indices: [connection_capacity]usize = undefined,
                connection_hit_indices: [connection_capacity]usize = undefined,

                pub fn workspace(self: *@This()) Workspace {
                    return .{
                        .node_bounds = &self.node_bounds,
                        .node_order = &self.node_order,
                        .node_prefix_max_x = &self.node_prefix_max_x,
                        .node_ids = &self.node_ids,
                        .node_id_order = &self.node_id_order,
                        .visible_node_indices = &self.visible_node_indices,
                        .node_hit_indices = &self.node_hit_indices,
                        .group_bounds = &self.group_bounds,
                        .group_order = &self.group_order,
                        .group_prefix_max_x = &self.group_prefix_max_x,
                        .visible_group_indices = &self.visible_group_indices,
                        .group_hit_indices = &self.group_hit_indices,
                        .connection_bounds = &self.connection_bounds,
                        .connection_order = &self.connection_order,
                        .connection_prefix_max_x = &self.connection_prefix_max_x,
                        .visible_connection_indices = &self.visible_connection_indices,
                        .connection_hit_indices = &self.connection_hit_indices,
                    };
                }
            };
        }

        pub const PrepareResult = struct {
            ready: bool = false,
            geometry_reused: bool = false,
            viewport_reused: bool = false,
            workspace_too_small: bool = false,
            duplicate_node_id_count: usize = 0,
            orphan_connection_count: usize = 0,
            visible_node_count: usize = 0,
            visible_group_count: usize = 0,
            visible_connection_count: usize = 0,
        };

        pub const Summary = struct {
            valid: bool = false,
            node_count: usize = 0,
            group_count: usize = 0,
            connection_count: usize = 0,
            indexed_connection_count: usize = 0,
            visible_node_count: usize = 0,
            visible_group_count: usize = 0,
            visible_connection_count: usize = 0,
            orphan_connection_count: usize = 0,
            duplicate_node_id_count: usize = 0,
            rebuild_count: u64 = 0,
            query_count: u64 = 0,
            geometry_reuse_count: u64 = 0,
            viewport_reuse_count: u64 = 0,
        };

        pub const Index = struct {
            workspace: Workspace,
            node_count: usize = 0,
            group_count: usize = 0,
            connection_count: usize = 0,
            indexed_connection_count: usize = 0,
            visible_node_len: usize = 0,
            visible_group_len: usize = 0,
            visible_connection_len: usize = 0,
            orphan_connection_count: usize = 0,
            duplicate_node_id_count: usize = 0,
            geometry_fingerprint: u64 = 0,
            revision_mode: bool = false,
            graph_bounds: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            has_graph_bounds: bool = false,
            viewport: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            pan: [2]f32 = .{ 0, 0 },
            zoom: f32 = 1.0,
            valid: bool = false,
            viewport_valid: bool = false,
            rebuild_count: u64 = 0,
            query_count: u64 = 0,
            geometry_reuse_count: u64 = 0,
            viewport_reuse_count: u64 = 0,

            pub fn init(workspace: Workspace) Index {
                return .{ .workspace = workspace };
            }

            pub fn invalidate(self: *Index) void {
                self.valid = false;
                self.viewport_valid = false;
            }

            pub fn invalidateViewport(self: *Index) void {
                self.viewport_valid = false;
            }

            pub fn prepare(self: *Index, nodes: []const Node, groups: []const Group, connections: []const Connection, viewport: Rect, pan: [2]f32, zoom_value: f32) PrepareResult {
                const fingerprint = geometryFingerprint(nodes, groups, connections);
                return self.prepareWithKey(nodes, groups, connections, viewport, pan, zoom_value, fingerprint, false);
            }

            /// Prepare with an application-owned geometry revision. Callers
            /// must increment the revision whenever node/group geometry or
            /// connection endpoints change. This avoids the O(N + E) safety
            /// fingerprint on unchanged frames and pointer events.
            pub fn prepareVersioned(self: *Index, nodes: []const Node, groups: []const Group, connections: []const Connection, viewport: Rect, pan: [2]f32, zoom_value: f32, geometry_revision: u64) PrepareResult {
                return self.prepareWithKey(nodes, groups, connections, viewport, pan, zoom_value, geometry_revision, true);
            }

            fn prepareWithKey(self: *Index, nodes: []const Node, groups: []const Group, connections: []const Connection, viewport: Rect, pan: [2]f32, zoom_value: f32, geometry_key: u64, revision_mode: bool) PrepareResult {
                const zoom = @max(0.001, zoom_value);
                var geometry_reused = false;
                if (self.valid and self.node_count == nodes.len and self.group_count == groups.len and self.connection_count == connections.len and self.geometry_fingerprint == geometry_key and self.revision_mode == revision_mode) {
                    geometry_reused = true;
                    self.geometry_reuse_count +%= 1;
                } else {
                    const rebuilt = self.rebuild(nodes, groups, connections, geometry_key, revision_mode);
                    if (!self.valid) return rebuilt;
                }

                if (self.viewport_valid and rectEqual(self.viewport, viewport) and pointEqual(self.pan, pan) and self.zoom == zoom) {
                    self.viewport_reuse_count +%= 1;
                    return self.prepareResult(geometry_reused, true, false);
                }
                self.query(viewport, pan, zoom);
                return self.prepareResult(geometry_reused, false, false);
            }

            pub fn visibleNodeIndices(self: *const Index) []const usize {
                return self.workspace.visible_node_indices[0..self.visible_node_len];
            }

            pub fn visibleGroupIndices(self: *const Index) []const usize {
                return self.workspace.visible_group_indices[0..self.visible_group_len];
            }

            pub fn visibleConnectionIndices(self: *const Index) []const usize {
                return self.workspace.visible_connection_indices[0..self.visible_connection_len];
            }

            pub fn nodeIndicesNearPoint(self: *Index, viewport: Rect, pan: [2]f32, zoom_value: f32, point: [2]f32, radius_pixels: f32) []const usize {
                if (!self.valid) return &.{};
                const query_rect = graphPointRect(viewport, pan, @max(0.001, zoom_value), point, radius_pixels);
                const count = queryIntervals(self.workspace.node_bounds[0..self.node_count], self.workspace.node_order[0..self.node_count], self.workspace.node_prefix_max_x[0..self.node_count], query_rect, self.workspace.node_hit_indices);
                std.sort.pdq(usize, self.workspace.node_hit_indices[0..count], {}, std.sort.asc(usize));
                return self.workspace.node_hit_indices[0..count];
            }

            pub fn groupIndicesNearPoint(self: *Index, viewport: Rect, pan: [2]f32, zoom_value: f32, point: [2]f32, radius_pixels: f32) []const usize {
                if (!self.valid) return &.{};
                const query_rect = graphPointRect(viewport, pan, @max(0.001, zoom_value), point, radius_pixels);
                const count = queryIntervals(self.workspace.group_bounds[0..self.group_count], self.workspace.group_order[0..self.group_count], self.workspace.group_prefix_max_x[0..self.group_count], query_rect, self.workspace.group_hit_indices);
                std.sort.pdq(usize, self.workspace.group_hit_indices[0..count], {}, std.sort.asc(usize));
                return self.workspace.group_hit_indices[0..count];
            }

            pub fn connectionIndicesNearPoint(self: *Index, viewport: Rect, pan: [2]f32, zoom_value: f32, point: [2]f32, radius_pixels: f32) []const usize {
                if (!self.valid) return &.{};
                const zoom = @max(0.001, zoom_value);
                const query_rect = expandRect(graphPointRect(viewport, pan, zoom, point, radius_pixels), 40.0 / zoom, 17.0 / zoom);
                const count = queryIntervals(self.workspace.connection_bounds[0..self.connection_count], self.workspace.connection_order[0..self.indexed_connection_count], self.workspace.connection_prefix_max_x[0..self.indexed_connection_count], query_rect, self.workspace.connection_hit_indices);
                std.sort.pdq(usize, self.workspace.connection_hit_indices[0..count], {}, std.sort.asc(usize));
                return self.workspace.connection_hit_indices[0..count];
            }

            pub fn nodeIndexForId(self: *const Index, id: u32) ?usize {
                if (!self.valid) return null;
                return self.nodeIndex(id);
            }

            pub fn graphBounds(self: *const Index) ?Rect {
                return if (self.valid and self.has_graph_bounds) self.graph_bounds else null;
            }

            pub fn summary(self: *const Index) Summary {
                return .{
                    .valid = self.valid and self.viewport_valid,
                    .node_count = self.node_count,
                    .group_count = self.group_count,
                    .connection_count = self.connection_count,
                    .indexed_connection_count = self.indexed_connection_count,
                    .visible_node_count = self.visible_node_len,
                    .visible_group_count = self.visible_group_len,
                    .visible_connection_count = self.visible_connection_len,
                    .orphan_connection_count = self.orphan_connection_count,
                    .duplicate_node_id_count = self.duplicate_node_id_count,
                    .rebuild_count = self.rebuild_count,
                    .query_count = self.query_count,
                    .geometry_reuse_count = self.geometry_reuse_count,
                    .viewport_reuse_count = self.viewport_reuse_count,
                };
            }

            fn rebuild(self: *Index, nodes: []const Node, groups: []const Group, connections: []const Connection, geometry_key: u64, revision_mode: bool) PrepareResult {
                self.valid = false;
                self.viewport_valid = false;
                self.node_count = nodes.len;
                self.group_count = groups.len;
                self.connection_count = connections.len;
                self.indexed_connection_count = 0;
                self.visible_node_len = 0;
                self.visible_group_len = 0;
                self.visible_connection_len = 0;
                self.orphan_connection_count = 0;
                self.duplicate_node_id_count = 0;
                self.geometry_fingerprint = geometry_key;
                self.revision_mode = revision_mode;
                self.graph_bounds = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
                self.has_graph_bounds = false;
                self.rebuild_count +%= 1;
                if (!self.workspaceFits(nodes.len, groups.len, connections.len)) return self.prepareResult(false, false, true);

                const node_bounds = self.workspace.node_bounds[0..nodes.len];
                const node_order = self.workspace.node_order[0..nodes.len];
                const node_ids = self.workspace.node_ids[0..nodes.len];
                const node_id_order = self.workspace.node_id_order[0..nodes.len];
                for (nodes, 0..) |node, index| {
                    node_bounds[index] = nodeRect(node);
                    includeRect(&self.graph_bounds, &self.has_graph_bounds, node_bounds[index]);
                    node_order[index] = index;
                    node_ids[index] = node.id;
                    node_id_order[index] = index;
                }
                std.sort.pdq(usize, node_order, node_bounds, boundsIndexLessThan);
                buildPrefixMax(node_bounds, node_order, self.workspace.node_prefix_max_x[0..nodes.len]);
                std.sort.pdq(usize, node_id_order, node_ids, idIndexLessThan);
                if (node_id_order.len > 1) {
                    for (node_id_order[1..], node_id_order[0 .. node_id_order.len - 1]) |current, previous| {
                        if (node_ids[current] == node_ids[previous]) self.duplicate_node_id_count += 1;
                    }
                }
                if (self.duplicate_node_id_count != 0) return self.prepareResult(false, false, false);

                const group_bounds = self.workspace.group_bounds[0..groups.len];
                const group_order = self.workspace.group_order[0..groups.len];
                for (groups, 0..) |group, index| {
                    group_bounds[index] = group.rect;
                    includeRect(&self.graph_bounds, &self.has_graph_bounds, group.rect);
                    group_order[index] = index;
                }
                std.sort.pdq(usize, group_order, group_bounds, boundsIndexLessThan);
                buildPrefixMax(group_bounds, group_order, self.workspace.group_prefix_max_x[0..groups.len]);

                const connection_bounds = self.workspace.connection_bounds[0..connections.len];
                const connection_order = self.workspace.connection_order[0..connections.len];
                for (connections, 0..) |connection, index| {
                    const from_index = self.nodeIndex(connection.from_id);
                    const to_index = self.nodeIndex(connection.to_id);
                    if (from_index == null or to_index == null) {
                        self.orphan_connection_count += 1;
                        continue;
                    }
                    connection_bounds[index] = connectionBounds(nodes[from_index.?], nodes[to_index.?]);
                    connection_order[self.indexed_connection_count] = index;
                    self.indexed_connection_count += 1;
                }
                std.sort.pdq(usize, connection_order[0..self.indexed_connection_count], connection_bounds, boundsIndexLessThan);
                buildPrefixMax(connection_bounds, connection_order[0..self.indexed_connection_count], self.workspace.connection_prefix_max_x[0..self.indexed_connection_count]);
                self.valid = true;
                return self.prepareResult(false, false, false);
            }

            fn query(self: *Index, viewport: Rect, pan: [2]f32, zoom: f32) void {
                const query_rect = graphViewport(viewport, pan, zoom, 8.0);
                const connection_query_rect = expandRect(query_rect, 40.0 / zoom, 17.0 / zoom);
                self.visible_node_len = queryIntervals(
                    self.workspace.node_bounds[0..self.node_count],
                    self.workspace.node_order[0..self.node_count],
                    self.workspace.node_prefix_max_x[0..self.node_count],
                    query_rect,
                    self.workspace.visible_node_indices,
                );
                self.visible_group_len = queryIntervals(
                    self.workspace.group_bounds[0..self.group_count],
                    self.workspace.group_order[0..self.group_count],
                    self.workspace.group_prefix_max_x[0..self.group_count],
                    query_rect,
                    self.workspace.visible_group_indices,
                );
                self.visible_connection_len = queryIntervals(
                    self.workspace.connection_bounds[0..self.connection_count],
                    self.workspace.connection_order[0..self.indexed_connection_count],
                    self.workspace.connection_prefix_max_x[0..self.indexed_connection_count],
                    connection_query_rect,
                    self.workspace.visible_connection_indices,
                );
                std.sort.pdq(usize, self.workspace.visible_node_indices[0..self.visible_node_len], {}, std.sort.asc(usize));
                std.sort.pdq(usize, self.workspace.visible_group_indices[0..self.visible_group_len], {}, std.sort.asc(usize));
                std.sort.pdq(usize, self.workspace.visible_connection_indices[0..self.visible_connection_len], {}, std.sort.asc(usize));
                self.viewport = viewport;
                self.pan = pan;
                self.zoom = zoom;
                self.viewport_valid = true;
                self.query_count +%= 1;
            }

            fn workspaceFits(self: *const Index, nodes: usize, groups: usize, connections: usize) bool {
                return self.workspace.node_bounds.len >= nodes and self.workspace.node_order.len >= nodes and
                    self.workspace.node_prefix_max_x.len >= nodes and self.workspace.node_ids.len >= nodes and
                    self.workspace.node_id_order.len >= nodes and self.workspace.visible_node_indices.len >= nodes and
                    self.workspace.node_hit_indices.len >= nodes and
                    self.workspace.group_bounds.len >= groups and self.workspace.group_order.len >= groups and
                    self.workspace.group_prefix_max_x.len >= groups and self.workspace.visible_group_indices.len >= groups and self.workspace.group_hit_indices.len >= groups and
                    self.workspace.connection_bounds.len >= connections and self.workspace.connection_order.len >= connections and
                    self.workspace.connection_prefix_max_x.len >= connections and self.workspace.visible_connection_indices.len >= connections and self.workspace.connection_hit_indices.len >= connections;
            }

            fn nodeIndex(self: *const Index, id: u32) ?usize {
                var low: usize = 0;
                var high = self.node_count;
                while (low < high) {
                    const mid = low + (high - low) / 2;
                    const index = self.workspace.node_id_order[mid];
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

            fn prepareResult(self: *const Index, geometry_reused: bool, viewport_reused: bool, workspace_too_small: bool) PrepareResult {
                return .{
                    .ready = self.valid and self.viewport_valid,
                    .geometry_reused = geometry_reused,
                    .viewport_reused = viewport_reused,
                    .workspace_too_small = workspace_too_small,
                    .duplicate_node_id_count = self.duplicate_node_id_count,
                    .orphan_connection_count = self.orphan_connection_count,
                    .visible_node_count = self.visible_node_len,
                    .visible_group_count = self.visible_group_len,
                    .visible_connection_count = self.visible_connection_len,
                };
            }
        };

        fn nodeRect(node: Node) Rect {
            return .{ .x = node.pos[0], .y = node.pos[1], .w = node.size.w, .h = node.size.h };
        }

        fn connectionBounds(from: Node, to: Node) Rect {
            const a_x = from.pos[0] + from.size.w;
            const b_x = to.pos[0];
            const dx = @abs(b_x - a_x) * 0.5;
            const min_x = @min(@min(a_x, b_x), @min(a_x + dx, b_x - dx));
            const max_x = @max(@max(a_x, b_x), @max(a_x + dx, b_x - dx));
            // The query expands by the screen-space port inset, so this
            // zoom-invariant node hull conservatively contains every curve.
            const min_y = @min(from.pos[1], to.pos[1]);
            const max_y = @max(from.pos[1] + from.size.h, to.pos[1] + to.size.h);
            return .{ .x = min_x, .y = min_y, .w = max_x - min_x, .h = max_y - min_y };
        }

        fn boundsIndexLessThan(bounds: []const Rect, a: usize, b: usize) bool {
            if (bounds[a].x != bounds[b].x) return bounds[a].x < bounds[b].x;
            return a < b;
        }

        fn idIndexLessThan(ids: []const u32, a: usize, b: usize) bool {
            if (ids[a] != ids[b]) return ids[a] < ids[b];
            return a < b;
        }

        fn buildPrefixMax(bounds: []const Rect, order: []const usize, out: []f32) void {
            var max_x = -std.math.inf(f32);
            for (order, 0..) |index, order_index| {
                max_x = @max(max_x, bounds[index].x + bounds[index].w);
                out[order_index] = max_x;
            }
        }

        fn queryIntervals(bounds: []const Rect, order: []const usize, prefix_max_x: []const f32, query_rect: Rect, out: []usize) usize {
            if (order.len == 0) return 0;
            const query_right = query_rect.x + query_rect.w;
            var low: usize = 0;
            var high = order.len;
            while (low < high) {
                const mid = low + (high - low) / 2;
                if (prefix_max_x[mid] < query_rect.x)
                    low = mid + 1
                else
                    high = mid;
            }
            var count: usize = 0;
            for (order[low..]) |index| {
                const item = bounds[index];
                if (item.x > query_right) break;
                if (!rectIntersects(item, query_rect)) continue;
                out[count] = index;
                count += 1;
            }
            return count;
        }

        fn graphViewport(viewport: Rect, pan: [2]f32, zoom: f32, padding_pixels: f32) Rect {
            const padding = padding_pixels / zoom;
            const center_x = viewport.x + viewport.w * 0.5 + pan[0];
            const center_y = viewport.y + viewport.h * 0.5 + pan[1];
            const left = (viewport.x - center_x) / zoom - padding;
            const top = (viewport.y - center_y) / zoom - padding;
            return .{
                .x = left,
                .y = top,
                .w = viewport.w / zoom + padding * 2.0,
                .h = viewport.h / zoom + padding * 2.0,
            };
        }

        fn graphPointRect(viewport: Rect, pan: [2]f32, zoom: f32, point: [2]f32, radius_pixels: f32) Rect {
            const center_x = viewport.x + viewport.w * 0.5 + pan[0];
            const center_y = viewport.y + viewport.h * 0.5 + pan[1];
            const radius = @max(0.0, radius_pixels) / zoom;
            const graph_x = (point[0] - center_x) / zoom;
            const graph_y = (point[1] - center_y) / zoom;
            return .{ .x = graph_x - radius, .y = graph_y - radius, .w = radius * 2.0, .h = radius * 2.0 };
        }

        fn expandRect(rect: Rect, amount_x: f32, amount_y: f32) Rect {
            return .{ .x = rect.x - amount_x, .y = rect.y - amount_y, .w = rect.w + amount_x * 2.0, .h = rect.h + amount_y * 2.0 };
        }

        fn rectIntersects(a: Rect, b: Rect) bool {
            return a.x <= b.x + b.w and a.x + a.w >= b.x and a.y <= b.y + b.h and a.y + a.h >= b.y;
        }

        fn rectEqual(a: Rect, b: Rect) bool {
            return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
        }

        fn includeRect(bounds: *Rect, has_bounds: *bool, item: Rect) void {
            if (!has_bounds.*) {
                bounds.* = item;
                has_bounds.* = true;
                return;
            }
            const min_x = @min(bounds.x, item.x);
            const min_y = @min(bounds.y, item.y);
            const max_x = @max(bounds.x + bounds.w, item.x + item.w);
            const max_y = @max(bounds.y + bounds.h, item.y + item.h);
            bounds.* = .{ .x = min_x, .y = min_y, .w = @max(1.0, max_x - min_x), .h = @max(1.0, max_y - min_y) };
        }

        fn pointEqual(a: [2]f32, b: [2]f32) bool {
            return a[0] == b[0] and a[1] == b[1];
        }

        fn geometryFingerprint(nodes: []const Node, groups: []const Group, connections: []const Connection) u64 {
            var hash: u64 = 0xcbf29ce484222325;
            mix(&hash, nodes.len);
            mix(&hash, groups.len);
            mix(&hash, connections.len);
            for (nodes) |node| {
                mix(&hash, node.id);
                mixFloat(&hash, node.pos[0]);
                mixFloat(&hash, node.pos[1]);
                mixFloat(&hash, node.size.w);
                mixFloat(&hash, node.size.h);
                mix(&hash, node.input_count);
                mix(&hash, node.output_count);
            }
            for (groups) |group| {
                mix(&hash, group.id);
                mixFloat(&hash, group.rect.x);
                mixFloat(&hash, group.rect.y);
                mixFloat(&hash, group.rect.w);
                mixFloat(&hash, group.rect.h);
            }
            for (connections) |connection| {
                mix(&hash, connection.from_id);
                mix(&hash, connection.to_id);
                mix(&hash, connection.from_port);
                mix(&hash, connection.to_port);
            }
            return hash;
        }

        fn mix(hash: *u64, value: anytype) void {
            hash.* = (hash.* ^ @as(u64, @intCast(value))) *% 0x0000_0100_0000_01b3;
        }

        fn mixFloat(hash: *u64, value: f32) void {
            mix(hash, @as(u32, @bitCast(value)));
        }
    };
}

const TestRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

const TestSize = struct {
    w: f32,
    h: f32,
};

const TestNode = struct {
    id: u32,
    pos: [2]f32,
    size: TestSize = .{ .w = 80, .h = 40 },
    input_count: u8 = 1,
    output_count: u8 = 1,
};

const TestGroup = struct {
    id: u32,
    rect: TestRect,
};

const TestConnection = struct {
    from_id: u32,
    to_id: u32,
    from_port: u8 = 0,
    to_port: u8 = 0,
};

const TestIndexTypes = Types(TestNode, TestGroup, TestConnection, TestRect);

test "viewport index culls nodes groups and connections in storage order" {
    const nodes = [_]TestNode{
        .{ .id = 10, .pos = .{ -40, -10 } },
        .{ .id = 20, .pos = .{ 80, 20 } },
        .{ .id = 30, .pos = .{ 600, 20 } },
        .{ .id = 40, .pos = .{ 1200, 20 } },
    };
    const groups = [_]TestGroup{
        .{ .id = 1, .rect = .{ .x = -80, .y = -30, .w = 260, .h = 140 } },
        .{ .id = 2, .rect = .{ .x = 1100, .y = 0, .w = 200, .h = 100 } },
    };
    const connections = [_]TestConnection{
        .{ .from_id = 10, .to_id = 20 },
        .{ .from_id = 20, .to_id = 30 },
        .{ .from_id = 30, .to_id = 40 },
    };
    var storage = TestIndexTypes.StaticWorkspace(nodes.len, groups.len, connections.len){};
    var index = TestIndexTypes.Index.init(storage.workspace());
    const viewport = TestRect{ .x = 0, .y = 0, .w = 320, .h = 180 };

    const prepared = index.prepare(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 1);
    try std.testing.expect(prepared.ready);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, index.visibleNodeIndices());
    try std.testing.expectEqualSlices(usize, &.{0}, index.visibleGroupIndices());
    // The second edge begins at node 20's right-hand port just inside the
    // padded viewport, so the conservative broad phase must retain it.
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, index.visibleConnectionIndices());
    const point = [2]f32{ viewport.w * 0.5 + 80, viewport.h * 0.5 + 40 };
    try std.testing.expectEqualSlices(usize, &.{1}, index.nodeIndicesNearPoint(viewport, .{ 0, 0 }, 1, point, 1));
    try std.testing.expectEqualSlices(usize, &.{0}, index.connectionIndicesNearPoint(viewport, .{ 0, 0 }, 1, point, 8));

    const repeated = index.prepare(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 1);
    try std.testing.expect(repeated.geometry_reused);
    try std.testing.expect(repeated.viewport_reused);
    try std.testing.expectEqual(@as(u64, 1), index.summary().viewport_reuse_count);
}

test "viewport index versioned mode rebuilds only on geometry revision" {
    var nodes = [_]TestNode{
        .{ .id = 1, .pos = .{ 0, 0 } },
        .{ .id = 2, .pos = .{ 1000, 0 } },
    };
    const groups = [_]TestGroup{};
    const connections = [_]TestConnection{.{ .from_id = 1, .to_id = 2 }};
    var storage = TestIndexTypes.StaticWorkspace(nodes.len, groups.len, connections.len){};
    var index = TestIndexTypes.Index.init(storage.workspace());
    const viewport = TestRect{ .x = 0, .y = 0, .w = 320, .h = 180 };

    try std.testing.expect(index.prepareVersioned(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 1, 7).ready);
    try std.testing.expectEqual(@as(usize, 1), index.visibleNodeIndices().len);
    nodes[1].pos = .{ 100, 0 };
    const unchanged_revision = index.prepareVersioned(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 1, 7);
    try std.testing.expect(unchanged_revision.viewport_reused);
    try std.testing.expectEqual(@as(usize, 1), index.visibleNodeIndices().len);
    const changed_revision = index.prepareVersioned(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 1, 8);
    try std.testing.expect(!changed_revision.geometry_reused);
    try std.testing.expectEqual(@as(usize, 2), index.visibleNodeIndices().len);
    const zoomed = index.prepareVersioned(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 2, 8);
    try std.testing.expect(zoomed.geometry_reused);
    try std.testing.expect(!zoomed.viewport_reused);
    try std.testing.expectEqual(@as(u64, 2), index.summary().rebuild_count);
}

test "viewport index reports invalid graph and workspace capacity" {
    const duplicate_nodes = [_]TestNode{
        .{ .id = 1, .pos = .{ 0, 0 } },
        .{ .id = 1, .pos = .{ 100, 0 } },
    };
    const groups = [_]TestGroup{};
    const connections = [_]TestConnection{};
    var storage = TestIndexTypes.StaticWorkspace(2, 0, 0){};
    var index = TestIndexTypes.Index.init(storage.workspace());
    const viewport = TestRect{ .x = 0, .y = 0, .w = 320, .h = 180 };
    const duplicate = index.prepare(&duplicate_nodes, &groups, &connections, viewport, .{ 0, 0 }, 1);
    try std.testing.expect(!duplicate.ready);
    try std.testing.expectEqual(@as(usize, 1), duplicate.duplicate_node_id_count);

    const nodes = [_]TestNode{
        .{ .id = 1, .pos = .{ 0, 0 } },
        .{ .id = 2, .pos = .{ 100, 0 } },
        .{ .id = 3, .pos = .{ 200, 0 } },
    };
    const too_small = index.prepare(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 1);
    try std.testing.expect(too_small.workspace_too_small);
}

test "viewport storage supports runtime graph capacities" {
    var storage = try TestIndexTypes.Storage.init(std.testing.allocator, 3, 2, 4);
    defer storage.deinit();
    var index = TestIndexTypes.Index.init(storage.workspace());
    const nodes = [_]TestNode{
        .{ .id = 1, .pos = .{ -40, -20 } },
        .{ .id = 2, .pos = .{ 100, -20 } },
        .{ .id = 3, .pos = .{ 900, 0 } },
    };
    const groups = [_]TestGroup{.{ .id = 7, .rect = .{ .x = -60, .y = -40, .w = 260, .h = 120 } }};
    const connections = [_]TestConnection{.{ .from_id = 1, .to_id = 2 }};
    const prepared = index.prepareVersioned(&nodes, &groups, &connections, .{ .x = 0, .y = 0, .w = 320, .h = 180 }, .{ 0, 0 }, 1, 1);
    try std.testing.expect(prepared.ready);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, index.visibleNodeIndices());
    try std.testing.expectEqual(@as(usize, 3), index.summary().node_count);
}
