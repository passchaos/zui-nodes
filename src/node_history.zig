//! Capacity-safe undo/redo storage for node graphs.
//!
//! Small editors can use the inline snapshot storage. Larger editors bind a
//! caller-owned static workspace or an allocated `HistoryStorage`. Snapshot
//! capture is all-or-nothing: exceeding any capacity rejects the transaction
//! instead of silently truncating graph state.

const std = @import("std");

pub fn Types(comptime Node: type, comptime Group: type, comptime Connection: type) type {
    return struct {
        pub const HistorySnapshot = struct {
            nodes: [16]Node = undefined,
            node_len: usize = 0,
            groups: [16]Group = undefined,
            group_len: usize = 0,
            connections: [32]Connection = undefined,
            connection_len: usize = 0,
            selected_node_ids: [64]u32 = .{0} ** 64,
            selected_node_len: usize = 0,
            selected_connections: [64]Connection = undefined,
            selected_connection_len: usize = 0,
            selected_node_id: ?u32 = null,
            selected_group_id: ?u32 = null,
            selected_connection: ?Connection = null,
            storage_slot: ?usize = null,
            complete: bool = true,
        };

        pub const HistoryWorkspace = struct {
            nodes: []Node,
            groups: []Group,
            connections: []Connection,
            selected_node_ids: []u32,
            selected_connections: []Connection,
            slot_count: usize,
            node_capacity: usize,
            group_capacity: usize,
            connection_capacity: usize,
            selection_capacity: usize,

            pub fn valid(self: HistoryWorkspace) bool {
                if (self.slot_count < History.stack_capacity + 1) return false;
                const node_len = std.math.mul(usize, self.slot_count, self.node_capacity) catch return false;
                const group_len = std.math.mul(usize, self.slot_count, self.group_capacity) catch return false;
                const connection_len = std.math.mul(usize, self.slot_count, self.connection_capacity) catch return false;
                const selection_len = std.math.mul(usize, self.slot_count, self.selection_capacity) catch return false;
                return self.nodes.len >= node_len and self.groups.len >= group_len and
                    self.connections.len >= connection_len and self.selected_node_ids.len >= selection_len and
                    self.selected_connections.len >= selection_len;
            }
        };

        pub const HistoryStorage = struct {
            allocator: std.mem.Allocator,
            nodes: []Node,
            groups: []Group,
            connections: []Connection,
            selected_node_ids: []u32,
            selected_connections: []Connection,
            node_capacity: usize,
            group_capacity: usize,
            connection_capacity: usize,
            selection_capacity: usize,

            /// Allocate storage for retained undo states plus the transient
            /// current state needed while moving an entry between stacks.
            /// This storage must outlive every History bound to its workspace.
            pub fn init(allocator: std.mem.Allocator, node_capacity: usize, group_capacity: usize, connection_capacity: usize, selection_capacity: usize) !HistoryStorage {
                const slot_count = History.stack_capacity + 1;
                const nodes = try allocator.alloc(Node, try std.math.mul(usize, slot_count, node_capacity));
                errdefer allocator.free(nodes);
                const groups = try allocator.alloc(Group, try std.math.mul(usize, slot_count, group_capacity));
                errdefer allocator.free(groups);
                const connections = try allocator.alloc(Connection, try std.math.mul(usize, slot_count, connection_capacity));
                errdefer allocator.free(connections);
                const selected_node_ids = try allocator.alloc(u32, try std.math.mul(usize, slot_count, selection_capacity));
                errdefer allocator.free(selected_node_ids);
                const selected_connections = try allocator.alloc(Connection, try std.math.mul(usize, slot_count, selection_capacity));
                return .{
                    .allocator = allocator,
                    .nodes = nodes,
                    .groups = groups,
                    .connections = connections,
                    .selected_node_ids = selected_node_ids,
                    .selected_connections = selected_connections,
                    .node_capacity = node_capacity,
                    .group_capacity = group_capacity,
                    .connection_capacity = connection_capacity,
                    .selection_capacity = selection_capacity,
                };
            }

            pub fn deinit(self: *HistoryStorage) void {
                self.allocator.free(self.nodes);
                self.allocator.free(self.groups);
                self.allocator.free(self.connections);
                self.allocator.free(self.selected_node_ids);
                self.allocator.free(self.selected_connections);
                self.* = undefined;
            }

            pub fn workspace(self: *HistoryStorage) HistoryWorkspace {
                return .{
                    .nodes = self.nodes,
                    .groups = self.groups,
                    .connections = self.connections,
                    .selected_node_ids = self.selected_node_ids,
                    .selected_connections = self.selected_connections,
                    .slot_count = History.stack_capacity + 1,
                    .node_capacity = self.node_capacity,
                    .group_capacity = self.group_capacity,
                    .connection_capacity = self.connection_capacity,
                    .selection_capacity = self.selection_capacity,
                };
            }
        };

        pub fn StaticHistoryWorkspace(
            comptime node_capacity: usize,
            comptime group_capacity: usize,
            comptime connection_capacity: usize,
            comptime selection_capacity: usize,
        ) type {
            const slot_count = History.stack_capacity + 1;
            return struct {
                nodes: [slot_count * node_capacity]Node = undefined,
                groups: [slot_count * group_capacity]Group = undefined,
                connections: [slot_count * connection_capacity]Connection = undefined,
                selected_node_ids: [slot_count * selection_capacity]u32 = .{0} ** (slot_count * selection_capacity),
                selected_connections: [slot_count * selection_capacity]Connection = undefined,

                pub fn workspace(self: *@This()) HistoryWorkspace {
                    return .{
                        .nodes = &self.nodes,
                        .groups = &self.groups,
                        .connections = &self.connections,
                        .selected_node_ids = &self.selected_node_ids,
                        .selected_connections = &self.selected_connections,
                        .slot_count = slot_count,
                        .node_capacity = node_capacity,
                        .group_capacity = group_capacity,
                        .connection_capacity = connection_capacity,
                        .selection_capacity = selection_capacity,
                    };
                }
            };
        }

        pub const HistorySummary = struct {
            available: bool = false,
            undo_len: usize = 0,
            redo_len: usize = 0,
            external_workspace: bool = false,
            node_capacity: usize = 16,
            group_capacity: usize = 16,
            connection_capacity: usize = 32,
            selection_capacity: usize = 64,
            rejected_snapshot_count: u64 = 0,
            dropped_snapshot_count: u64 = 0,
        };

        pub const History = struct {
            pub const stack_capacity: usize = 16;

            undo_stack: [stack_capacity]HistorySnapshot = undefined,
            undo_len: usize = 0,
            redo_stack: [stack_capacity]HistorySnapshot = undefined,
            redo_len: usize = 0,
            workspace: ?HistoryWorkspace = null,
            rejected_snapshot_count: u64 = 0,
            dropped_snapshot_count: u64 = 0,

            pub fn bindWorkspace(self: *History, workspace: HistoryWorkspace) bool {
                if (!workspace.valid()) return false;
                self.reset();
                self.workspace = workspace;
                return true;
            }

            pub fn unbindWorkspace(self: *History) void {
                self.reset();
                self.workspace = null;
            }

            pub fn reset(self: *History) void {
                self.undo_len = 0;
                self.redo_len = 0;
                self.rejected_snapshot_count = 0;
                self.dropped_snapshot_count = 0;
            }

            pub fn capture(self: *History, state: anytype, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize) HistorySnapshot {
                return self.captureHistorySnapshot(state, nodes, node_len, &.{}, connections, connection_len);
            }

            pub fn captureWithGroups(self: *History, state: anytype, nodes: []const Node, node_len: usize, groups: []const Group, connections: []const Connection, connection_len: usize) HistorySnapshot {
                return self.captureHistorySnapshot(state, nodes, node_len, groups, connections, connection_len);
            }

            fn captureHistorySnapshot(self: *History, state: anytype, nodes: []const Node, node_len: usize, groups: []const Group, connections: []const Connection, connection_len: usize) HistorySnapshot {
                var snapshot = HistorySnapshot{};
                const active_node_len = @min(node_len, nodes.len);
                const active_connection_len = @min(connection_len, connections.len);
                const selection_len = state.boundedSelectionLen();
                const connection_selection_len = state.boundedConnectionSelectionLen();
                if (!self.canCaptureCounts(active_node_len, groups.len, active_connection_len, selection_len, connection_selection_len)) {
                    snapshot.complete = false;
                    self.rejected_snapshot_count +%= 1;
                    return snapshot;
                }
                snapshot.node_len = active_node_len;
                snapshot.group_len = groups.len;
                snapshot.connection_len = active_connection_len;
                snapshot.selected_node_len = selection_len;
                snapshot.selected_connection_len = connection_selection_len;
                if (self.workspace) |workspace| {
                    const slot = self.availableStorageSlot() orelse {
                        snapshot.complete = false;
                        self.rejected_snapshot_count +%= 1;
                        return snapshot;
                    };
                    snapshot.storage_slot = slot;
                    if (snapshot.node_len > 0) @memcpy(slotSlice(Node, workspace.nodes, workspace.node_capacity, slot)[0..snapshot.node_len], nodes[0..snapshot.node_len]);
                    if (snapshot.group_len > 0) @memcpy(slotSlice(Group, workspace.groups, workspace.group_capacity, slot)[0..snapshot.group_len], groups);
                    if (snapshot.connection_len > 0) @memcpy(slotSlice(Connection, workspace.connections, workspace.connection_capacity, slot)[0..snapshot.connection_len], connections[0..snapshot.connection_len]);
                    if (snapshot.selected_node_len > 0) @memcpy(slotSlice(u32, workspace.selected_node_ids, workspace.selection_capacity, slot)[0..snapshot.selected_node_len], state.selected_node_ids[0..snapshot.selected_node_len]);
                    if (snapshot.selected_connection_len > 0) {
                        const destination = slotSlice(Connection, workspace.selected_connections, workspace.selection_capacity, slot)[0..snapshot.selected_connection_len];
                        writeSelectedConnections(state, destination);
                    }
                } else {
                    if (snapshot.node_len > 0) @memcpy(snapshot.nodes[0..snapshot.node_len], nodes[0..snapshot.node_len]);
                    if (snapshot.group_len > 0) @memcpy(snapshot.groups[0..snapshot.group_len], groups);
                    if (snapshot.connection_len > 0) @memcpy(snapshot.connections[0..snapshot.connection_len], connections[0..snapshot.connection_len]);
                    if (snapshot.selected_node_len > 0) @memcpy(snapshot.selected_node_ids[0..snapshot.selected_node_len], state.selected_node_ids[0..snapshot.selected_node_len]);
                    if (snapshot.selected_connection_len > 0) writeSelectedConnections(state, snapshot.selected_connections[0..snapshot.selected_connection_len]);
                }
                snapshot.selected_node_id = state.selected_node_id;
                snapshot.selected_group_id = state.selected_group_id;
                snapshot.selected_connection = state.selected_connection;
                return snapshot;
            }

            pub fn canCapture(self: *const History, state: anytype, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize) bool {
                return self.canCaptureWithGroups(state, nodes, node_len, &.{}, connections, connection_len);
            }

            pub fn canCaptureWithGroups(self: *const History, state: anytype, nodes: []const Node, node_len: usize, groups: []const Group, connections: []const Connection, connection_len: usize) bool {
                return self.canCaptureCounts(@min(node_len, nodes.len), groups.len, @min(connection_len, connections.len), state.boundedSelectionLen(), state.boundedConnectionSelectionLen());
            }

            pub fn supportsGraphCapacity(self: *const History, node_capacity: usize, group_capacity: usize, connection_capacity: usize, selection_capacity: usize) bool {
                return self.canCaptureCounts(node_capacity, group_capacity, connection_capacity, selection_capacity, selection_capacity);
            }

            pub fn supportsGraphCapacityWithSelections(self: *const History, node_capacity: usize, group_capacity: usize, connection_capacity: usize, node_selection_capacity: usize, connection_selection_capacity: usize) bool {
                return self.canCaptureCounts(node_capacity, group_capacity, connection_capacity, node_selection_capacity, connection_selection_capacity);
            }

            pub fn pushBefore(self: *History, state: anytype, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize) bool {
                return self.pushBeforeWithGroups(state, nodes, node_len, &.{}, connections, connection_len);
            }

            pub fn pushBeforeWithGroups(self: *History, state: anytype, nodes: []const Node, node_len: usize, groups: []const Group, connections: []const Connection, connection_len: usize) bool {
                if (!self.canCaptureWithGroups(state, nodes, node_len, groups, connections, connection_len)) {
                    self.rejected_snapshot_count +%= 1;
                    return false;
                }
                const snapshot = self.captureWithGroups(state, nodes, node_len, groups, connections, connection_len);
                return self.commitBefore(snapshot);
            }

            pub fn commitBefore(self: *History, snapshot: HistorySnapshot) bool {
                if (!snapshot.complete) return false;
                if (snapshot.storage_slot != null and self.workspace == null) return false;
                self.clearRedo();
                self.pushUndo(snapshot);
                return true;
            }

            pub fn undo(self: *History, state: anytype, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize) bool {
                if (self.undo_len == 0) return false;
                const current = self.capture(state.*, nodes, node_len.*, connections, connection_len.*);
                if (!current.complete or !self.canApplySnapshot(self.undo_stack[self.undo_len - 1], nodes.len, 0, connections.len, state.selected_node_ids.len, connectionSelectionCapacity(state))) return false;
                self.pushRedo(current);
                self.undo_len -= 1;
                return self.applyHistorySnapshot(state, nodes, node_len, connections, connection_len, self.undo_stack[self.undo_len]);
            }

            pub fn undoWithGroups(self: *History, state: anytype, nodes: []Node, node_len: *usize, groups: []Group, group_len: ?*usize, connections: []Connection, connection_len: *usize) bool {
                if (self.undo_len == 0) return false;
                const current_group_len = if (group_len) |len| @min(len.*, groups.len) else groups.len;
                const current = self.captureWithGroups(state.*, nodes, node_len.*, groups[0..current_group_len], connections, connection_len.*);
                if (!current.complete or !self.canApplySnapshot(self.undo_stack[self.undo_len - 1], nodes.len, groups.len, connections.len, state.selected_node_ids.len, connectionSelectionCapacity(state))) return false;
                self.pushRedo(current);
                self.undo_len -= 1;
                return self.applyHistorySnapshotWithGroups(state, nodes, node_len, groups, group_len, connections, connection_len, self.undo_stack[self.undo_len]);
            }

            pub fn redo(self: *History, state: anytype, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize) bool {
                if (self.redo_len == 0) return false;
                const current = self.capture(state.*, nodes, node_len.*, connections, connection_len.*);
                if (!current.complete or !self.canApplySnapshot(self.redo_stack[self.redo_len - 1], nodes.len, 0, connections.len, state.selected_node_ids.len, connectionSelectionCapacity(state))) return false;
                self.pushUndo(current);
                self.redo_len -= 1;
                return self.applyHistorySnapshot(state, nodes, node_len, connections, connection_len, self.redo_stack[self.redo_len]);
            }

            pub fn redoWithGroups(self: *History, state: anytype, nodes: []Node, node_len: *usize, groups: []Group, group_len: ?*usize, connections: []Connection, connection_len: *usize) bool {
                if (self.redo_len == 0) return false;
                const current_group_len = if (group_len) |len| @min(len.*, groups.len) else groups.len;
                const current = self.captureWithGroups(state.*, nodes, node_len.*, groups[0..current_group_len], connections, connection_len.*);
                if (!current.complete or !self.canApplySnapshot(self.redo_stack[self.redo_len - 1], nodes.len, groups.len, connections.len, state.selected_node_ids.len, connectionSelectionCapacity(state))) return false;
                self.pushUndo(current);
                self.redo_len -= 1;
                return self.applyHistorySnapshotWithGroups(state, nodes, node_len, groups, group_len, connections, connection_len, self.redo_stack[self.redo_len]);
            }

            pub fn canUndo(self: *const History) bool {
                return self.undo_len > 0;
            }

            pub fn canRedo(self: *const History) bool {
                return self.redo_len > 0;
            }

            pub fn canUndoFor(self: *const History, node_capacity: usize, group_capacity: usize, connection_capacity: usize, selection_capacity: usize) bool {
                return self.canUndoForSelections(node_capacity, group_capacity, connection_capacity, selection_capacity, selection_capacity);
            }

            pub fn canRedoFor(self: *const History, node_capacity: usize, group_capacity: usize, connection_capacity: usize, selection_capacity: usize) bool {
                return self.canRedoForSelections(node_capacity, group_capacity, connection_capacity, selection_capacity, selection_capacity);
            }

            pub fn canUndoForSelections(self: *const History, node_capacity: usize, group_capacity: usize, connection_capacity: usize, node_selection_capacity: usize, connection_selection_capacity: usize) bool {
                return self.undo_len > 0 and self.canApplySnapshot(self.undo_stack[self.undo_len - 1], node_capacity, group_capacity, connection_capacity, node_selection_capacity, connection_selection_capacity);
            }

            pub fn canRedoForSelections(self: *const History, node_capacity: usize, group_capacity: usize, connection_capacity: usize, node_selection_capacity: usize, connection_selection_capacity: usize) bool {
                return self.redo_len > 0 and self.canApplySnapshot(self.redo_stack[self.redo_len - 1], node_capacity, group_capacity, connection_capacity, node_selection_capacity, connection_selection_capacity);
            }

            pub fn summary(self: *const History) HistorySummary {
                const workspace = self.workspace;
                return .{
                    .available = true,
                    .undo_len = self.undo_len,
                    .redo_len = self.redo_len,
                    .external_workspace = workspace != null,
                    .node_capacity = if (workspace) |value| value.node_capacity else 16,
                    .group_capacity = if (workspace) |value| value.group_capacity else 16,
                    .connection_capacity = if (workspace) |value| value.connection_capacity else 32,
                    .selection_capacity = if (workspace) |value| value.selection_capacity else 64,
                    .rejected_snapshot_count = self.rejected_snapshot_count,
                    .dropped_snapshot_count = self.dropped_snapshot_count,
                };
            }

            fn pushUndo(self: *History, snapshot: HistorySnapshot) void {
                self.pushSnapshot(&self.undo_stack, &self.undo_len, snapshot);
            }

            fn pushRedo(self: *History, snapshot: HistorySnapshot) void {
                self.pushSnapshot(&self.redo_stack, &self.redo_len, snapshot);
            }

            fn pushSnapshot(self: *History, stack: *[stack_capacity]HistorySnapshot, len: *usize, snapshot: HistorySnapshot) void {
                if (len.* >= stack.len) {
                    var i: usize = 1;
                    while (i < stack.len) : (i += 1) stack[i - 1] = stack[i];
                    len.* = stack.len - 1;
                    self.dropped_snapshot_count +%= 1;
                }
                stack[len.*] = snapshot;
                len.* += 1;
            }

            fn clearRedo(self: *History) void {
                self.redo_len = 0;
            }

            fn canCaptureCounts(self: *const History, node_len: usize, group_len: usize, connection_len: usize, selection_len: usize, connection_selection_len: usize) bool {
                if (self.workspace) |workspace| return workspace.valid() and node_len <= workspace.node_capacity and group_len <= workspace.group_capacity and connection_len <= workspace.connection_capacity and selection_len <= workspace.selection_capacity and connection_selection_len <= workspace.selection_capacity;
                return node_len <= 16 and group_len <= 16 and connection_len <= 32 and selection_len <= 64 and connection_selection_len <= 64;
            }

            fn availableStorageSlot(self: *const History) ?usize {
                const workspace = self.workspace orelse return null;
                var slot: usize = 0;
                while (slot < workspace.slot_count) : (slot += 1) {
                    var used = false;
                    for (self.undo_stack[0..self.undo_len]) |snapshot| if (snapshot.storage_slot == slot) {
                        used = true;
                        break;
                    };
                    if (!used) for (self.redo_stack[0..self.redo_len]) |snapshot| if (snapshot.storage_slot == slot) {
                        used = true;
                        break;
                    };
                    if (!used) return slot;
                }
                return null;
            }

            fn canApplySnapshot(_: *const History, snapshot: HistorySnapshot, node_capacity: usize, group_capacity: usize, connection_capacity: usize, node_selection_capacity: usize, connection_selection_capacity: usize) bool {
                return snapshot.complete and snapshot.node_len <= node_capacity and snapshot.group_len <= group_capacity and snapshot.connection_len <= connection_capacity and snapshot.selected_node_len <= node_selection_capacity and snapshot.selected_connection_len <= connection_selection_capacity;
            }

            fn applyHistorySnapshot(self: *History, state: anytype, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize, snapshot: HistorySnapshot) bool {
                return self.applyHistorySnapshotWithGroups(state, nodes, node_len, &.{}, null, connections, connection_len, snapshot);
            }

            fn applyHistorySnapshotWithGroups(self: *History, state: anytype, nodes: []Node, node_len: *usize, groups: []Group, group_len: ?*usize, connections: []Connection, connection_len: *usize, snapshot: HistorySnapshot) bool {
                const new_node_len = @min(snapshot.node_len, nodes.len);
                const new_group_len = @min(snapshot.group_len, groups.len);
                const new_connection_len = @min(snapshot.connection_len, connections.len);
                if (snapshot.storage_slot) |slot| {
                    const workspace = self.workspace orelse return false;
                    if (new_node_len > 0) @memcpy(nodes[0..new_node_len], slotSlice(Node, workspace.nodes, workspace.node_capacity, slot)[0..new_node_len]);
                    if (new_group_len > 0) @memcpy(groups[0..new_group_len], slotSlice(Group, workspace.groups, workspace.group_capacity, slot)[0..new_group_len]);
                    if (new_connection_len > 0) @memcpy(connections[0..new_connection_len], slotSlice(Connection, workspace.connections, workspace.connection_capacity, slot)[0..new_connection_len]);
                } else {
                    if (new_node_len > 0) @memcpy(nodes[0..new_node_len], snapshot.nodes[0..new_node_len]);
                    if (new_group_len > 0) @memcpy(groups[0..new_group_len], snapshot.groups[0..new_group_len]);
                    if (new_connection_len > 0) @memcpy(connections[0..new_connection_len], snapshot.connections[0..new_connection_len]);
                }
                node_len.* = new_node_len;
                if (group_len) |len| len.* = new_group_len;
                connection_len.* = new_connection_len;
                _ = state.clearSelection();
                state.selected_node_id = snapshot.selected_node_id;
                state.selected_group_id = snapshot.selected_group_id;
                state.selected_node_len = @min(snapshot.selected_node_len, state.selected_node_ids.len);
                if (state.selected_node_len > 0) {
                    if (snapshot.storage_slot) |slot| {
                        const workspace = self.workspace orelse return false;
                        @memcpy(state.selected_node_ids[0..state.selected_node_len], slotSlice(u32, workspace.selected_node_ids, workspace.selection_capacity, slot)[0..state.selected_node_len]);
                    } else {
                        @memcpy(state.selected_node_ids[0..state.selected_node_len], snapshot.selected_node_ids[0..state.selected_node_len]);
                    }
                } else if (snapshot.selected_node_id) |id| {
                    if (state.selected_node_ids.len > 0) {
                        state.selected_node_ids[0] = id;
                        state.selected_node_len = 1;
                    }
                }
                state.selected_connection_len = 0;
                if (snapshot.selected_connection_len > 0 and state.selected_connections.len > 0) {
                    state.selected_connection_len = snapshot.selected_connection_len;
                    if (snapshot.storage_slot) |slot| {
                        const workspace = self.workspace orelse return false;
                        @memcpy(state.selected_connections[0..state.selected_connection_len], slotSlice(Connection, workspace.selected_connections, workspace.selection_capacity, slot)[0..state.selected_connection_len]);
                    } else {
                        @memcpy(state.selected_connections[0..state.selected_connection_len], snapshot.selected_connections[0..state.selected_connection_len]);
                    }
                }
                state.selected_connection = snapshot.selected_connection;
                resetInteractionState(state);
                return true;
            }
        };

        fn resetInteractionState(state: anytype) void {
            state.dragging_canvas = false;
            state.dragging_node_id = null;
            state.dragging_group_id = null;
            state.resizing_group_id = null;
            state.resizing_group_edges = .{};
            if (comptime @hasField(@TypeOf(state.*), "resizing_node_id")) {
                state.resizing_node_id = null;
                state.resizing_node_edges = .{};
            }
            state.interaction_history_pushed = false;
            state.node_drag_tracking = false;
            state.node_drag_origin = .{ 0, 0 };
            state.node_drag_accumulated_delta = .{ 0, 0 };
            state.node_drag_applied_delta = .{ 0, 0 };
            state.snap_guide_x = null;
            state.snap_guide_y = null;
            state.snap_guide_x_span = null;
            state.snap_guide_y_span = null;
            state.spacing_guide_x = null;
            state.spacing_guide_y = null;
            state.dragging_connection_from_id = null;
            state.dragging_connection_from_port = 0;
            state.reconnecting_connection = null;
            if (comptime @hasField(@TypeOf(state.*), "selected_connection_waypoint")) {
                state.selected_connection_waypoint = null;
                state.dragging_connection_waypoint = null;
            }
            if (comptime @hasField(@TypeOf(state.*), "connection_cut_stroke")) {
                _ = state.connection_cut_stroke.cancel();
            }
            state.pending_connection = null;
            state.hover_node_id = null;
            state.hover_group_id = null;
            state.hover_input_node_id = null;
            state.hover_output_node_id = null;
            state.hover_connection = null;
            state.box_selecting = false;
            state.box_select_mode = .replace;
            state.box_select_scope = .nodes_only;
            state.box_select_start = .{ 0, 0 };
            state.box_select_end = .{ 0, 0 };
            state.box_select_origin_x = 0;
            state.box_select_crossing = false;
            state.navigation_candidate_count = 0;
        }

        fn writeSelectedConnections(state: anytype, destination: []Connection) void {
            for (destination, 0..) |*selected, index| {
                selected.* = state.connectionSelectionAt(index).?;
            }
        }

        fn connectionSelectionCapacity(state: anytype) usize {
            return if (state.selected_connections.len > 0) state.selected_connections.len else 1;
        }

        fn slotSlice(comptime T: type, storage: []T, capacity: usize, slot: usize) []T {
            const start = slot * capacity;
            return storage[start .. start + capacity];
        }
    };
}
