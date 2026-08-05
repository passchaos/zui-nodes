//! Node editor adapter helpers shared by core and tests.
//!
//! The node editor domain implementation lives in `node_editor.zig`; this
//! module keeps the small compatibility wrappers and element-aware helpers out
//! of `core.zig` while preserving the older core API names.

const zui = @import("zui");
const ui_base = zui.ui_base;
const node_editor = @import("node_editor.zig");

const Rect = ui_base.Rect;
const Size = ui_base.Size;
const NodeEditorState = node_editor.State;
const NodeEditorNode = node_editor.Node;
const NodeEditorNodeTemplate = node_editor.NodeTemplate;
const NodeEditorGroup = node_editor.Group;
const NodeEditorConnection = node_editor.Connection;
const NodeEditorPortType = node_editor.PortType;
const NodeEditorMinimapSnapshot = node_editor.MinimapSnapshot;

pub fn nodeFrom(value: anytype) NodeEditorNode {
    return .{
        .id = value.id,
        .title = value.title,
        .pos = value.pos,
        .size = value.size,
        .color = value.color,
        .input_count = value.input_count,
        .output_count = value.output_count,
        .input_labels = value.input_labels,
        .output_labels = value.output_labels,
        .input_types = compatiblePortTypes(value.input_types),
        .output_types = compatiblePortTypes(value.output_types),
    };
}

pub fn connectionFrom(value: anytype) NodeEditorConnection {
    return .{
        .from_id = value.from_id,
        .to_id = value.to_id,
        .from_port = value.from_port,
        .to_port = value.to_port,
        .color = value.color,
    };
}

pub fn groupFrom(value: anytype) NodeEditorGroup {
    return .{
        .id = value.id,
        .title = value.title,
        .rect = value.rect,
        .color = value.color,
        .border_color = value.border_color,
        .text_color = value.text_color,
        .title_height = value.title_height,
        .radius = value.radius,
    };
}

pub fn templateFrom(value: anytype) NodeEditorNodeTemplate {
    return .{
        .title = value.title,
        .size = value.size,
        .color = value.color,
        .input_count = value.input_count,
        .output_count = value.output_count,
        .input_labels = value.input_labels,
        .output_labels = value.output_labels,
        .input_types = compatiblePortTypes(value.input_types),
        .output_types = compatiblePortTypes(value.output_types),
    };
}

pub fn portTypeFrom(value: anytype) NodeEditorPortType {
    return switch (value) {
        .any => .any,
        .flow => .flow,
        .float => .float,
        .vector => .vector,
        .color => .color,
        .image => .image,
        .mask => .mask,
        .geometry => .geometry,
    };
}

fn compatiblePortTypes(value: anytype) []const NodeEditorPortType {
    return if (@TypeOf(value) == []const NodeEditorPortType) value else &.{};
}

pub fn copyNodesFrom(comptime SourceNode: type, source: []const SourceNode, out: []NodeEditorNode) usize {
    const count = @min(source.len, out.len);
    for (source[0..count], 0..) |item, index| out[index] = nodeFrom(item);
    return count;
}

pub fn copyConnectionsFrom(comptime SourceConnection: type, source: []const SourceConnection, out: []NodeEditorConnection) usize {
    const count = @min(source.len, out.len);
    for (source[0..count], 0..) |item, index| out[index] = connectionFrom(item);
    return count;
}

pub fn copyGroupsFrom(comptime SourceGroup: type, source: []const SourceGroup, out: []NodeEditorGroup) usize {
    const count = @min(source.len, out.len);
    for (source[0..count], 0..) |item, index| out[index] = groupFrom(item);
    return count;
}

test "zui-nodes adapters copy native node editor model values" {
    const source_nodes = [_]NodeEditorNode{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 }, .output_types = &.{.image} },
        .{ .id = 2, .title = "B", .pos = .{ 100, 0 }, .input_types = &.{.image} },
    };
    const source_connections = [_]NodeEditorConnection{
        .{ .from_id = 1, .to_id = 2 },
    };
    const source_groups = [_]NodeEditorGroup{
        .{ .id = 7, .title = "Group", .rect = .{ .x = 0, .y = 0, .w = 120, .h = 80 } },
    };
    var nodes: [2]NodeEditorNode = undefined;
    var connections: [1]NodeEditorConnection = undefined;
    var groups: [1]NodeEditorGroup = undefined;

    try @import("std").testing.expectEqual(@as(usize, 2), copyNodesFrom(NodeEditorNode, &source_nodes, &nodes));
    try @import("std").testing.expectEqual(@as(usize, 1), copyConnectionsFrom(NodeEditorConnection, &source_connections, &connections));
    try @import("std").testing.expectEqual(@as(usize, 1), copyGroupsFrom(NodeEditorGroup, &source_groups, &groups));
    try @import("std").testing.expectEqual(@as(u32, 1), nodes[0].id);
    try @import("std").testing.expectEqual(NodeEditorPortType.image, portTypeFrom(source_nodes[0].output_types[0]));
    try @import("std").testing.expectEqual(@as(u32, 2), connections[0].to_id);
    try @import("std").testing.expectEqual(@as(u32, 7), groups[0].id);
}


pub fn Helpers(comptime NodeEditorElement: type) type {
    return struct {
        pub fn nodeEditorGraphToScreen(rect: Rect, state: NodeEditorState, point: [2]f32) [2]f32 {
            return node_editor.graphToScreen(rect, state, point);
        }

        pub fn nodeEditorNodeGraphRect(node: NodeEditorNode) Rect {
            return node_editor.nodeGraphRect(node);
        }

        pub fn nodeEditorDefaultInsertPosition(nodes: []const NodeEditorNode) [2]f32 {
            return node_editor.defaultInsertPosition(nodes);
        }

        pub fn includeNodeEditorBounds(bounds: *?Rect, rect: Rect) void {
            node_editor.includeBounds(bounds, rect);
        }

        pub fn nodeEditorGraphBounds(nodes: []const NodeEditorNode, groups: []const NodeEditorGroup) Rect {
            return node_editor.graphBounds(nodes, groups);
        }

        pub fn paddedNodeEditorBounds(bounds: Rect, frac: f32) Rect {
            return node_editor.paddedBounds(bounds, frac);
        }

        pub fn nodeEditorMinimapPoint(minimap: Rect, bounds: Rect, point: [2]f32) [2]f32 {
            return node_editor.minimapPoint(minimap, bounds, point);
        }

        pub fn nodeEditorGraphPointFromMinimap(minimap: Rect, bounds: Rect, point: [2]f32) [2]f32 {
            return node_editor.graphPointFromMinimap(minimap, bounds, point);
        }

        pub fn nodeEditorMinimapNodeRect(minimap: Rect, bounds: Rect, node: NodeEditorNode) Rect {
            return node_editor.minimapNodeRect(minimap, bounds, node);
        }

        pub fn nodeEditorMinimapGroupRect(minimap: Rect, bounds: Rect, group: NodeEditorGroup) Rect {
            return node_editor.minimapGroupRect(minimap, bounds, group);
        }

        pub fn nodeEditorMinimapViewportRect(minimap: Rect, bounds: Rect, viewport: Rect, state: NodeEditorState) Rect {
            return node_editor.minimapViewportRect(minimap, bounds, viewport, state);
        }

        pub fn nodeEditorMinimapSnapshot(viewport: Rect, state: NodeEditorState, nodes: []const NodeEditorNode, groups: []const NodeEditorGroup, minimap_size: Size) NodeEditorMinimapSnapshot {
            return node_editor.minimapSnapshot(viewport, state, nodes, groups, minimap_size);
        }

        pub fn screenToNodeEditorGraph(rect: Rect, state: NodeEditorState, point: [2]f32) [2]f32 {
            return node_editor.screenToGraph(rect, state, point);
        }

        pub fn rectIntersects(a: Rect, b: Rect) bool {
            return node_editor.rectIntersects(a, b);
        }

        pub fn nodeEditorNodeRect(rect: Rect, editor: NodeEditorElement, node: NodeEditorNode) Rect {
            return node_editor.nodeRectFromState(rect, editor.state.*, node);
        }

        pub fn nodeEditorGroupRect(rect: Rect, editor: NodeEditorElement, group: NodeEditorGroup) Rect {
            return node_editor.groupRect(rect, editor.state.*, group);
        }

        pub fn nodeEditorNodeRectFromState(rect: Rect, state: NodeEditorState, node: NodeEditorNode) Rect {
            return node_editor.nodeRectFromState(rect, state, node);
        }

        pub fn nodeEditorInputPortPosition(rect: Rect, editor: NodeEditorElement, node: NodeEditorNode) [2]f32 {
            return node_editor.inputPortPosition(rect, editor.state.*, node);
        }

        pub fn nodeEditorInputPortPositionAt(rect: Rect, editor: NodeEditorElement, node: NodeEditorNode, port_index: u8) [2]f32 {
            return node_editor.inputPortPositionAt(rect, editor.state.*, node, port_index);
        }

        pub fn nodeEditorOutputPortPosition(rect: Rect, editor: NodeEditorElement, node: NodeEditorNode) [2]f32 {
            return node_editor.outputPortPosition(rect, editor.state.*, node);
        }

        pub fn nodeEditorOutputPortPositionAt(rect: Rect, editor: NodeEditorElement, node: NodeEditorNode, port_index: u8) [2]f32 {
            return node_editor.outputPortPositionAt(rect, editor.state.*, node, port_index);
        }

        pub fn nodeEditorInputPortCount(node: NodeEditorNode) u8 {
            return node_editor.inputPortCount(node);
        }

        pub fn nodeEditorOutputPortCount(node: NodeEditorNode) u8 {
            return node_editor.outputPortCount(node);
        }

        pub fn nodeEditorInputPortLabel(node: NodeEditorNode, port_index: u8) ?[]const u8 {
            return node_editor.inputPortLabel(node, port_index);
        }

        pub fn nodeEditorOutputPortLabel(node: NodeEditorNode, port_index: u8) ?[]const u8 {
            return node_editor.outputPortLabel(node, port_index);
        }

        pub fn nodeEditorInputPortType(node: NodeEditorNode, port_index: u8) NodeEditorPortType {
            return node_editor.inputPortType(node, port_index);
        }

        pub fn nodeEditorOutputPortType(node: NodeEditorNode, port_index: u8) NodeEditorPortType {
            return node_editor.outputPortType(node, port_index);
        }

        pub fn nodeEditorConnectionPortsCompatible(nodes: []const NodeEditorNode, connection: NodeEditorConnection) bool {
            return node_editor.connectionPortsCompatible(nodes, connection);
        }

        pub fn nodeEditorNodeIndexById(nodes: []const NodeEditorNode, id: u32) ?usize {
            return node_editor.nodeIndexById(nodes, id);
        }

        pub fn nodeEditorNodeFromTemplate(template: NodeEditorNodeTemplate, id: u32, pos: [2]f32) NodeEditorNode {
            return node_editor.nodeFromTemplate(template, id, pos);
        }

        pub fn nodeEditorGroupIndexById(groups: []const NodeEditorGroup, id: u32) ?usize {
            return node_editor.groupIndexById(groups, id);
        }

        pub fn uniqueNodeEditorGroupId(groups: []const NodeEditorGroup, base_id: u32) u32 {
            return node_editor.uniqueGroupId(groups, base_id);
        }

        pub fn nodeEditorAdjacentNodeId(nodes: []const NodeEditorNode, anchor_id: u32, avoid_id: u32, direction: node_editor.AdjacentNodeDirection) ?u32 {
            return node_editor.adjacentNodeId(nodes, anchor_id, avoid_id, direction);
        }

        pub fn nodeEditorReconnectCandidateValid(active_connections: []const NodeEditorConnection, selected: NodeEditorConnection, replacement: NodeEditorConnection, nodes: []const NodeEditorNode) bool {
            if (replacement.from_id == replacement.to_id) return false;
            if (NodeEditorState.connectionEndpointsEqual(selected, replacement)) return false;
            if (!nodeEditorConnectionPortsCompatible(nodes, replacement)) return false;
            for (active_connections) |connection| {
                if (NodeEditorState.connectionEndpointsEqual(connection, replacement) and !NodeEditorState.connectionEndpointsEqual(connection, selected)) return false;
            }
            return true;
        }

        pub fn nodeEditorPortY(node_rect: Rect, port_count: u8, port_index: u8) f32 {
            return node_editor.portY(node_rect, port_count, port_index);
        }

        pub fn nodeEditorPortHit(pos: [2]f32, point: [2]f32) bool {
            return node_editor.portHit(pos, point);
        }

        pub fn nodeEditorConnectionHit(rect: Rect, editor: NodeEditorElement, connection: NodeEditorConnection, point: [2]f32) bool {
            return node_editor.connectionHit(rect, editor.state.*, editor.nodes, connection, point);
        }

        pub fn nodeEditorNodeById(nodes: []const NodeEditorNode, id: u32) ?NodeEditorNode {
            return node_editor.nodeById(nodes, id);
        }
    };
}

test "node editor adapters expose minimap and port helpers" {
    const Element = struct { state: *NodeEditorState };
    const H = Helpers(Element);
    const state = NodeEditorState{};
    const nodes = [_]NodeEditorNode{.{ .id = 1, .title = "A", .pos = .{ 0, 0 } }};
    const snapshot = H.nodeEditorMinimapSnapshot(.{ .x = 0, .y = 0, .w = 100, .h = 80 }, state, &nodes, &.{}, .{ .w = 40, .h = 32 });
    try @import("std").testing.expect(snapshot.graph_bounds.w >= 1.0);
    _ = H.nodeEditorDefaultInsertPosition(&nodes);
}
