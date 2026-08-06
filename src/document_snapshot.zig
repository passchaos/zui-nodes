//! Node graph document persistence for the zui-nodes extension.
//!
//! Zui core owns generic workspace/session persistence, but node-graph payloads
//! are extension data.  Keeping the snapshot JSON format here lets applications
//! save node editors without reintroducing graph-domain storage into Zui core.

const std = @import("std");
const zui = @import("zui");
const node_editor = @import("node_editor.zig");

pub const State = node_editor.State;
pub const Node = node_editor.Node;
pub const Connection = node_editor.Connection;
pub const Group = node_editor.Group;
pub const Rect = zui.Rect;

pub const DocumentSnapshotVersion: u32 = 1;

pub const DocumentSnapshot = struct {
    version: u32 = DocumentSnapshotVersion,
    name: []const u8 = "",
    revision: u64 = 0,
    dirty: bool = false,
    viewport: Rect = .zero,
    pan: [2]f32 = .{ 0.0, 0.0 },
    zoom: f32 = 1.0,
    selected_node_id: ?u32 = null,
    selected_node_ids: []const u32 = &.{},
    selected_group_id: ?u32 = null,
    selected_connection: ?Connection = null,
    nodes: []const Node = &.{},
    connections: []const Connection = &.{},
    groups: []const Group = &.{},

    pub fn toJsonAlloc(self: DocumentSnapshot, allocator: std.mem.Allocator) ![]u8 {
        return try writeDocumentSnapshotJson(allocator, self);
    }
};

pub const CaptureOptions = struct {
    name: []const u8 = "",
    revision: u64 = 0,
    dirty: bool = false,
    viewport: Rect = .zero,
    state: *const State,
    nodes: []const Node = &.{},
    node_len: ?usize = null,
    connections: []const Connection = &.{},
    connection_len: ?usize = null,
    groups: []const Group = &.{},
    group_len: ?usize = null,
};

pub const ApplyOptions = struct {
    snapshot: DocumentSnapshot,
    state: *State,
    nodes: []Node,
    node_len: *usize,
    connections: []Connection = &.{},
    connection_len: ?*usize = null,
    groups: []Group = &.{},
    group_len: ?*usize = null,
};

pub const ApplyResult = struct {
    node_count: usize = 0,
    connection_count: usize = 0,
    group_count: usize = 0,
    selected_node_count: usize = 0,
    selection_truncated: bool = false,
};

pub const ValidationReport = struct {
    version_supported: bool = false,
    node_count: usize = 0,
    connection_count: usize = 0,
    group_count: usize = 0,
    duplicate_node_id_count: usize = 0,
    duplicate_group_id_count: usize = 0,
    orphan_connection_count: usize = 0,
    selected_node_present: bool = false,
    selected_group_present: bool = false,
    selected_connection_present: bool = false,

    pub fn valid(self: ValidationReport) bool {
        return self.version_supported and
            self.duplicate_node_id_count == 0 and
            self.duplicate_group_id_count == 0 and
            self.orphan_connection_count == 0 and
            self.selected_node_present and
            self.selected_group_present and
            self.selected_connection_present;
    }
};

pub const Summary = struct {
    node_count: usize = 0,
    connection_count: usize = 0,
    group_count: usize = 0,
    selected_node_count: usize = 0,
    selected_node_id: ?u32 = null,
    selected_group_id: ?u32 = null,
    has_selected_connection: bool = false,
    bounds: Rect = .zero,
    valid: bool = false,

    pub fn hasSelection(self: Summary) bool {
        return self.selected_node_count > 0 or self.selected_group_id != null or self.has_selected_connection;
    }
};

pub fn captureDocumentSnapshot(options: CaptureOptions) DocumentSnapshot {
    const node_count = @min(options.node_len orelse options.nodes.len, options.nodes.len);
    const connection_count = @min(options.connection_len orelse options.connections.len, options.connections.len);
    const group_count = @min(options.group_len orelse options.groups.len, options.groups.len);
    return .{
        .version = DocumentSnapshotVersion,
        .name = options.name,
        .revision = options.revision,
        .dirty = options.dirty,
        .viewport = options.viewport,
        .pan = options.state.pan,
        .zoom = options.state.zoom,
        .selected_node_id = options.state.selected_node_id,
        .selected_node_ids = options.state.selected_node_ids[0..options.state.boundedSelectionLen()],
        .selected_group_id = options.state.selected_group_id,
        .selected_connection = options.state.selected_connection,
        .nodes = options.nodes[0..node_count],
        .connections = options.connections[0..connection_count],
        .groups = options.groups[0..group_count],
    };
}

pub fn applyDocumentSnapshot(options: ApplyOptions) !ApplyResult {
    const snapshot = options.snapshot;
    if (snapshot.version != DocumentSnapshotVersion) return error.UnsupportedNodeGraphDocumentSnapshot;
    if (snapshot.nodes.len > options.nodes.len) return error.NodeStorageTooSmall;
    if (options.connection_len == null and snapshot.connections.len > 0) return error.ConnectionStorageUnavailable;
    if (options.connection_len != null and snapshot.connections.len > options.connections.len) return error.ConnectionStorageTooSmall;
    if (options.group_len == null and snapshot.groups.len > 0) return error.GroupStorageUnavailable;
    if (options.group_len != null and snapshot.groups.len > options.groups.len) return error.GroupStorageTooSmall;

    if (snapshot.nodes.len > 0) @memcpy(options.nodes[0..snapshot.nodes.len], snapshot.nodes);
    options.node_len.* = snapshot.nodes.len;

    if (options.connection_len) |len| {
        if (snapshot.connections.len > 0) @memcpy(options.connections[0..snapshot.connections.len], snapshot.connections);
        len.* = snapshot.connections.len;
    }

    if (options.group_len) |len| {
        if (snapshot.groups.len > 0) @memcpy(options.groups[0..snapshot.groups.len], snapshot.groups);
        len.* = snapshot.groups.len;
    }

    options.state.pan = snapshot.pan;
    options.state.zoom = snapshot.zoom;
    options.state.selected_node_id = snapshot.selected_node_id;
    options.state.selected_group_id = snapshot.selected_group_id;
    options.state.selected_connection = snapshot.selected_connection;
    const selected_count = @min(snapshot.selected_node_ids.len, options.state.selected_node_ids.len);
    options.state.selected_node_len = selected_count;
    if (selected_count > 0) {
        @memcpy(options.state.selected_node_ids[0..selected_count], snapshot.selected_node_ids[0..selected_count]);
    }
    options.state.dragging_canvas = false;
    options.state.dragging_node_id = null;
    options.state.dragging_group_id = null;
    options.state.resizing_group_id = null;
    options.state.dragging_connection_from_id = null;
    options.state.reconnecting_connection = null;
    options.state.pending_connection = null;
    options.state.hover_node_id = null;
    options.state.hover_group_id = null;
    options.state.hover_connection = null;
    options.state.box_selecting = false;
    options.state.dragging_minimap = false;

    return .{
        .node_count = snapshot.nodes.len,
        .connection_count = snapshot.connections.len,
        .group_count = snapshot.groups.len,
        .selected_node_count = selected_count,
        .selection_truncated = selected_count < snapshot.selected_node_ids.len,
    };
}

pub fn summarizeDocumentSnapshot(snapshot: DocumentSnapshot) Summary {
    const validation = validateDocumentSnapshot(snapshot);
    return .{
        .node_count = snapshot.nodes.len,
        .connection_count = snapshot.connections.len,
        .group_count = snapshot.groups.len,
        .selected_node_count = snapshot.selected_node_ids.len,
        .selected_node_id = snapshot.selected_node_id,
        .selected_group_id = snapshot.selected_group_id,
        .has_selected_connection = snapshot.selected_connection != null,
        .bounds = node_editor.graphBounds(snapshot.nodes, snapshot.groups),
        .valid = validation.valid(),
    };
}

pub fn validateDocumentSnapshot(snapshot: DocumentSnapshot) ValidationReport {
    var report = ValidationReport{
        .version_supported = snapshot.version == DocumentSnapshotVersion,
        .node_count = snapshot.nodes.len,
        .connection_count = snapshot.connections.len,
        .group_count = snapshot.groups.len,
        .selected_node_present = snapshot.selected_node_id == null,
        .selected_group_present = snapshot.selected_group_id == null,
        .selected_connection_present = snapshot.selected_connection == null,
    };

    for (snapshot.nodes, 0..) |node, index| {
        var later = index + 1;
        while (later < snapshot.nodes.len) : (later += 1) {
            if (snapshot.nodes[later].id == node.id) report.duplicate_node_id_count += 1;
        }
        if (snapshot.selected_node_id == node.id) report.selected_node_present = true;
    }
    for (snapshot.groups, 0..) |group, index| {
        var later = index + 1;
        while (later < snapshot.groups.len) : (later += 1) {
            if (snapshot.groups[later].id == group.id) report.duplicate_group_id_count += 1;
        }
        if (snapshot.selected_group_id == group.id) report.selected_group_present = true;
    }
    for (snapshot.connections) |connection| {
        const from_present = nodeIdPresent(snapshot.nodes, connection.from_id);
        const to_present = nodeIdPresent(snapshot.nodes, connection.to_id);
        if (!from_present or !to_present) report.orphan_connection_count += 1;
        if (snapshot.selected_connection) |selected| {
            if (std.meta.eql(selected, connection)) report.selected_connection_present = true;
        }
    }
    return report;
}

pub fn writeDocumentSnapshotJson(allocator: std.mem.Allocator, snapshot: DocumentSnapshot) ![]u8 {
    return try std.json.Stringify.valueAlloc(allocator, snapshot, .{ .whitespace = .indent_2 });
}

pub fn parseDocumentSnapshotJson(
    allocator: std.mem.Allocator,
    json: []const u8,
) !std.json.Parsed(DocumentSnapshot) {
    return try std.json.parseFromSlice(DocumentSnapshot, allocator, json, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

fn nodeIdPresent(nodes: []const Node, id: u32) bool {
    for (nodes) |node| {
        if (node.id == id) return true;
    }
    return false;
}

test "zui-nodes document snapshot round-trips and restores graph state" {
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected, .pan = .{ 22.0, -8.0 }, .zoom = 1.5 };
    const nodes = [_]Node{
        .{ .id = 1, .title = "Source", .pos = .{ -40.0, 0.0 }, .output_types = &.{.image} },
        .{ .id = 2, .title = "Grade", .pos = .{ 140.0, 24.0 }, .input_types = &.{.image}, .output_types = &.{.color} },
    };
    const connections = [_]Connection{.{ .from_id = 1, .to_id = 2 }};
    const groups = [_]Group{.{ .id = 10, .title = "Comp", .rect = .{ .x = -64.0, .y = -16.0, .w = 380.0, .h = 160.0 } }};
    try std.testing.expect(state.setSingleSelection(2));

    const snapshot = captureDocumentSnapshot(.{
        .name = "shot graph",
        .revision = 7,
        .dirty = true,
        .viewport = .{ .x = 0, .y = 0, .w = 640, .h = 360 },
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .groups = &groups,
    });
    const json = try snapshot.toJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"shot graph\"") != null);

    var parsed = try parseDocumentSnapshotJson(std.testing.allocator, json);
    defer parsed.deinit();
    const summary = summarizeDocumentSnapshot(parsed.value);
    try std.testing.expect(summary.valid);
    try std.testing.expect(summary.hasSelection());
    try std.testing.expectEqual(@as(usize, 2), summary.node_count);
    try std.testing.expectEqual(@as(?u32, 2), summary.selected_node_id);
    try std.testing.expect(summary.bounds.w > 0.0);

    var restored_selected: [4]u32 = .{0} ** 4;
    var restored_state = State{ .selected_node_ids = &restored_selected };
    var restored_nodes: [4]Node = undefined;
    var restored_node_len: usize = 0;
    var restored_connections: [4]Connection = undefined;
    var restored_connection_len: usize = 0;
    var restored_groups: [2]Group = undefined;
    var restored_group_len: usize = 0;
    const applied = try applyDocumentSnapshot(.{
        .snapshot = parsed.value,
        .state = &restored_state,
        .nodes = &restored_nodes,
        .node_len = &restored_node_len,
        .connections = &restored_connections,
        .connection_len = &restored_connection_len,
        .groups = &restored_groups,
        .group_len = &restored_group_len,
    });
    try std.testing.expectEqual(@as(usize, 2), applied.node_count);
    try std.testing.expectEqual(@as(usize, 1), applied.connection_count);
    try std.testing.expectEqual(@as(usize, 1), applied.group_count);
    try std.testing.expectEqual(@as(usize, 2), restored_node_len);
    try std.testing.expectEqual(@as(usize, 1), restored_connection_len);
    try std.testing.expectEqual(@as(?u32, 2), restored_state.selected_node_id);
    try std.testing.expectEqual(@as(usize, 1), restored_state.boundedSelectionLen());
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), restored_state.zoom, 0.001);
}

test "zui-nodes document validation reports duplicate and orphan graph data" {
    const nodes = [_]Node{
        .{ .id = 1, .title = "A", .pos = .{ 0.0, 0.0 } },
        .{ .id = 1, .title = "B", .pos = .{ 100.0, 0.0 } },
    };
    const connections = [_]Connection{.{ .from_id = 1, .to_id = 99 }};
    const snapshot = DocumentSnapshot{
        .selected_node_id = 42,
        .nodes = &nodes,
        .connections = &connections,
    };
    const report = validateDocumentSnapshot(snapshot);
    try std.testing.expect(report.version_supported);
    try std.testing.expectEqual(@as(usize, 1), report.duplicate_node_id_count);
    try std.testing.expectEqual(@as(usize, 1), report.orphan_connection_count);
    try std.testing.expect(!report.selected_node_present);
    try std.testing.expect(!report.valid());
}
