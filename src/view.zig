//! Zui view adapter for the zui-nodes extension.
//!
//! The extension owns node graph/editor UI.  Zui core only provides reusable
//! canvas/custom-paint, event bubbling, focus and layout primitives.

const std = @import("std");
const zui = @import("zui");
const node_editor = @import("node_editor.zig");

pub const ViewContext = zui.ViewContext;
pub const ElementNode = zui.ElementNode;
pub const ElementEvent = zui.ElementEvent;
pub const Style = zui.Style;
pub const Color = zui.Color;
pub const Rect = zui.Rect;
pub const DrawCmd = zui.DrawCmd;

pub const NodeEditorCanvasHitKind = enum(u8) {
    node,
    group,
    input_port,
    output_port,
    connection,

    pub fn label(self: NodeEditorCanvasHitKind) []const u8 {
        return switch (self) {
            .node => "node",
            .group => "group",
            .input_port => "input_port",
            .output_port => "output_port",
            .connection => "connection",
        };
    }
};

/// Canvas hit ids are domain-owned by zui-nodes.  The high byte stores the
/// logical hit kind so generic Zui diagnostics can report stable hover/capture
/// transitions without knowing node graph semantics.
pub fn packCanvasHitId(kind: NodeEditorCanvasHitKind, local_id: u32) u64 {
    return (@as(u64, @intFromEnum(kind)) << 56) | @as(u64, local_id);
}

pub const NodeEditorViewOptions = struct {
    tag: u32 = 0,
    /// Optional host canvas state supplied by applications that want shared Zui
    /// diagnostics, dirty-region tracking, and generic hover/capture summaries.
    /// The node graph transform remains in `node_editor.State` because it uses
    /// graph-centered coordinates and owns node-editor domain invariants.
    canvas_state: ?*zui.CanvasState = null,
    /// Optional generic canvas layer cache. zui-nodes owns the cached payload
    /// semantics; Zui core only tracks layer ids, bounds, and typed invalidation.
    canvas_layers: ?*zui.CanvasLayerCache = null,
    connection_path_cache: ?*node_editor.ConnectionPathCache = null,
    /// Optional persistent path-command slots, one per active connection. The
    /// workspace must outlive this view's retained draw list. Undersized
    /// workspaces safely fall back to owned path payloads.
    connection_draw_workspace: ?*node_editor.ConnectionDrawWorkspace = null,
    /// Optional caller-owned broad-phase index shared by painting and hit tests.
    viewport_index: ?*node_editor.ViewportIndex = null,
    /// Optional application-owned geometry revision. When supplied, callers
    /// must increment it after external node/group/link geometry changes.
    geometry_revision: ?u64 = null,
    state: *node_editor.State,
    nodes: []const node_editor.Node,
    connections: []const node_editor.Connection = &.{},
    groups: []const node_editor.Group = &.{},
    mutable_nodes: ?[]node_editor.Node = null,
    mutable_node_len: ?*usize = null,
    mutable_connections: ?[]node_editor.Connection = null,
    mutable_connection_len: ?*usize = null,
    history: ?*node_editor.History = null,
    mutable_groups: ?[]node_editor.Group = null,
    mutable_group_len: ?*usize = null,
    move_group_contents: bool = true,
    group_resize_margin: f32 = 8.0,
    group_min_size: zui.ui_base.Size = .{ .w = 72.0, .h = 48.0 },
    background: Color = Color.rgb8(15, 23, 42),
    grid_color: Color = Color.rgba8(148, 163, 184, 40),
    node_text_color: Color = Color.rgb8(248, 250, 252),
    selected_color: Color = Color.rgb8(96, 165, 250),
    port_color: Color = Color.rgb8(226, 232, 240),
    font_size: f32 = 12.0,
    grid_spacing: f32 = 32.0,
    show_minimap: bool = true,
    minimap_size: zui.ui_base.Size = .{ .w = 150.0, .h = 96.0 },
    minimap_max_node_marks: usize = 512,
    minimap_max_group_marks: usize = 128,
    semantic_zoom: node_editor.SemanticZoomOptions = .{},
    clipboard: ?*node_editor.Clipboard = null,
    connection_policy: node_editor.ConnectionPolicy = .default,
    style: Style = .{},
};

const Binding = struct {
    canvas_state: ?*zui.CanvasState = null,
    canvas_layers: ?*zui.CanvasLayerCache = null,
    connection_path_cache: ?*node_editor.ConnectionPathCache = null,
    connection_draw_workspace: ?*node_editor.ConnectionDrawWorkspace = null,
    viewport_index: ?*node_editor.ViewportIndex = null,
    geometry_revision: ?u64 = null,
    state: *node_editor.State,
    nodes: []const node_editor.Node,
    connections: []const node_editor.Connection = &.{},
    groups: []const node_editor.Group = &.{},
    mutable_nodes: ?[]node_editor.Node = null,
    mutable_node_len: ?*usize = null,
    mutable_connections: ?[]node_editor.Connection = null,
    mutable_connection_len: ?*usize = null,
    history: ?*node_editor.History = null,
    mutable_groups: ?[]node_editor.Group = null,
    mutable_group_len: ?*usize = null,
    move_group_contents: bool = true,
    group_resize_margin: f32 = 8.0,
    group_min_size: zui.ui_base.Size = .{ .w = 72.0, .h = 48.0 },
    background: Color = Color.rgb8(15, 23, 42),
    grid_color: Color = Color.rgba8(148, 163, 184, 40),
    node_text_color: Color = Color.rgb8(248, 250, 252),
    selected_color: Color = Color.rgb8(96, 165, 250),
    port_color: Color = Color.rgb8(226, 232, 240),
    font_size: f32 = 12.0,
    grid_spacing: f32 = 32.0,
    show_minimap: bool = true,
    minimap_size: zui.ui_base.Size = .{ .w = 150.0, .h = 96.0 },
    minimap_max_node_marks: usize = 512,
    minimap_max_group_marks: usize = 128,
    semantic_zoom: node_editor.SemanticZoomOptions = .{},
    clipboard: ?*node_editor.Clipboard = null,
    connection_policy: node_editor.ConnectionPolicy = .default,

    fn editor(self: *const Binding) node_editor.Options(node_editor.State) {
        return .{
            .state = self.state,
            .nodes = self.nodes,
            .groups = self.groups,
            .connections = self.connections,
            .mutable_connections = self.mutable_connections,
            .mutable_connection_len = self.mutable_connection_len,
            .history = self.history,
            .mutable_groups = self.mutable_groups,
            .mutable_group_len = self.mutable_group_len,
            .move_group_contents = self.move_group_contents,
            .group_resize_margin = self.group_resize_margin,
            .group_min_size = self.group_min_size,
            .mutable_node_len = self.mutable_node_len,
            .mutable_nodes = self.mutable_nodes,
            .background = self.background,
            .grid_color = self.grid_color,
            .node_text_color = self.node_text_color,
            .selected_color = self.selected_color,
            .port_color = self.port_color,
            .font_size = self.font_size,
            .grid_spacing = self.grid_spacing,
            .show_minimap = self.show_minimap,
            .minimap_size = self.minimap_size,
            .minimap_max_node_marks = self.minimap_max_node_marks,
            .minimap_max_group_marks = self.minimap_max_group_marks,
            .semantic_zoom = self.semantic_zoom,
            .clipboard = self.clipboard,
            .connection_path_cache = self.connection_path_cache,
            .connection_draw_workspace = self.connection_draw_workspace,
            .viewport_index = self.viewport_index,
            .geometry_revision = self.geometry_revision,
            .connection_policy = self.connection_policy,
        };
    }
};

pub fn nodeEditorView(ctx: *ViewContext, options: NodeEditorViewOptions) !*ElementNode {
    const binding = try ctx.allocator.create(Binding);
    binding.* = .{
        .canvas_state = options.canvas_state,
        .canvas_layers = options.canvas_layers,
        .connection_path_cache = options.connection_path_cache,
        .connection_draw_workspace = options.connection_draw_workspace,
        .viewport_index = options.viewport_index,
        .geometry_revision = options.geometry_revision,
        .state = options.state,
        .nodes = options.nodes,
        .connections = options.connections,
        .groups = options.groups,
        .mutable_nodes = options.mutable_nodes,
        .mutable_node_len = options.mutable_node_len,
        .mutable_connections = options.mutable_connections,
        .mutable_connection_len = options.mutable_connection_len,
        .history = options.history,
        .mutable_groups = options.mutable_groups,
        .mutable_group_len = options.mutable_group_len,
        .move_group_contents = options.move_group_contents,
        .group_resize_margin = options.group_resize_margin,
        .group_min_size = options.group_min_size,
        .background = options.background,
        .grid_color = options.grid_color,
        .node_text_color = options.node_text_color,
        .selected_color = options.selected_color,
        .port_color = options.port_color,
        .font_size = options.font_size,
        .grid_spacing = options.grid_spacing,
        .show_minimap = options.show_minimap,
        .minimap_size = options.minimap_size,
        .minimap_max_node_marks = options.minimap_max_node_marks,
        .minimap_max_group_marks = options.minimap_max_group_marks,
        .semantic_zoom = options.semantic_zoom,
        .clipboard = options.clipboard,
        .connection_policy = options.connection_policy,
    };
    var style = options.style;
    if (style.background.a == 0 and style.background_paint == .none) style.background = options.background;
    return try zui.canvasView(ctx, .{
        .tag = options.tag,
        .state = options.canvas_state,
        .paint = paintNodeEditor,
        .event = nodeEditorViewEvent,
        .hit_test = nodeEditorCanvasHitTest,
        .user_data = binding,
        .cursor_shape = .default,
        .style = style,
    });
}

fn paintNodeEditor(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, layer: i32, user_data: ?*anyopaque) anyerror!void {
    const binding: *Binding = if (user_data) |ptr| @ptrCast(@alignCast(ptr)) else return;
    _ = try node_editor.appendNodeEditor(allocator, out, rect, binding.editor(), layer);
}

fn nodeEditorViewEvent(node: *ElementNode, event: *ElementEvent, user_data: ?*anyopaque) bool {
    const binding: *Binding = if (user_data) |ptr| @ptrCast(@alignCast(ptr)) else return false;
    const before = InteractionSnapshot.capture(binding.state);
    const editor = binding.editor();
    const changed = node_editor.handleEditorEvent(node.rect, .{
        .shift_down = node.input_shift_down,
        .control_down = node.input_control_down,
        .super_down = node.input_super_down,
        .alt_down = node.input_alt_down,
    }, editor, event);
    markCanvasInvalidation(binding, node.rect, event.*, before, changed);
    return changed;
}

fn nodeEditorCanvasHitTest(node: *const ElementNode, point: [2]f32, user_data: ?*anyopaque) ?u64 {
    const binding: *const Binding = if (user_data) |ptr| @ptrCast(@alignCast(ptr)) else return null;
    const editor = binding.editor();
    const viewport_index = node_editor.prepareNodeEditorViewportIndex(node.rect, editor);
    if (node_editor.inputPortAtEditorPoint(node.rect, editor, viewport_index, point)) |hit| {
        return packCanvasHitId(.input_port, editor.nodes[hit.node_index].id);
    }
    if (node_editor.outputPortAtEditorPoint(node.rect, editor, viewport_index, point)) |hit| {
        return packCanvasHitId(.output_port, editor.nodes[hit.node_index].id);
    }
    if (node_editor.nodeAtEditorPoint(node.rect, editor, viewport_index, point)) |index| {
        return packCanvasHitId(.node, editor.nodes[index].id);
    }
    if (node_editor.groupAtEditorPoint(node.rect, editor, viewport_index, point)) |index| {
        return packCanvasHitId(.group, editor.groups[index].id);
    }
    if (node_editor.connectionAtEditorPoint(node.rect, editor, viewport_index, point)) |connection| {
        return packCanvasHitId(.connection, connectionHash(connection));
    }
    return null;
}

const InteractionSnapshot = struct {
    pan: [2]f32 = .{ 0.0, 0.0 },
    zoom: f32 = 1.0,
    structural_drag: bool = false,

    fn capture(state: *const node_editor.State) InteractionSnapshot {
        return .{
            .pan = state.pan,
            .zoom = state.zoom,
            .structural_drag = state.dragging_node_id != null or
                state.dragging_group_id != null or
                state.resizing_group_id != null or
                state.resizing_group_edges.any() or
                state.dragging_connection_from_id != null or
                state.reconnecting_connection != null or
                state.box_selecting,
        };
    }

    fn transformChanged(self: InteractionSnapshot, state: *const node_editor.State) bool {
        return @abs(self.pan[0] - state.pan[0]) > 0.001 or
            @abs(self.pan[1] - state.pan[1]) > 0.001 or
            @abs(self.zoom - state.zoom) > 0.0001;
    }
};

fn markCanvasInvalidation(binding: *Binding, rect: Rect, event: ElementEvent, before: InteractionSnapshot, changed: bool) void {
    if (!changed) return;
    const geometry_changed = before.structural_drag or binding.state.dragging_node_id != null or binding.state.dragging_group_id != null or binding.state.resizing_group_id != null or binding.state.reconnecting_connection != null;
    if (geometry_changed) {
        if (binding.viewport_index) |viewport_index| viewport_index.invalidateGeometry();
    }
    const canvas_state = binding.canvas_state orelse return;
    if (before.transformChanged(binding.state)) {
        canvas_state.invalidate(.viewport_transform, null);
        return;
    }

    var kinds = (zui.CanvasInvalidationSet{}).with(.paint);
    switch (event) {
        .mouse_move, .mouse_leave => kinds = kinds.with(.overlay),
        .mouse_down, .mouse_up => kinds = kinds.with(.hit_test),
        else => {},
    }
    if (geometry_changed) {
        kinds = kinds.with(.data).with(.hit_test);
    }

    canvas_state.invalidateSet(kinds, rect);
    if (binding.canvas_layers) |layers| {
        _ = layers.invalidateForDirtySummary(canvas_state.dirtySummary());
    }
}

fn connectionHash(connection: node_editor.Connection) u32 {
    return connection.from_id *% 16_777_619 ^ connection.to_id *% 2_654_435_761 ^ @as(u32, connection.from_port) << 8 ^ @as(u32, connection.to_port);
}

test "node editor view builds on zui custom paint primitives" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "Output", .pos = .{ 160, 80 } },
    };
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 320, .h = 180 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 320, .h = 180 } }, .user = null };
    const node = try nodeEditorView(&ctx, .{ .tag = 9401, .state = &state, .nodes = &nodes, .style = .{ .width = .{ .px = 300 }, .height = .{ .px = 160 } } });
    node.rect = .{ .x = 0, .y = 0, .w = 300, .h = 160 };
    try std.testing.expectEqual(@as(u32, 9401), node.id);
    try std.testing.expect(node.focusable);
    const node_rect = node_editor.nodeRectFromState(.{ .x = 0, .y = 0, .w = 300, .h = 160 }, state, nodes[0]);
    const click = [2]f32{ node_rect.x + node_rect.w * 0.5, node_rect.y + node_rect.h * 0.5 };
    var event = ElementEvent{ .mouse_down = .{ .button = .left, .x = click[0], .y = click[1] } };
    try std.testing.expect(nodeEditorViewEvent(node, &event, node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
}

test "node editor view drags mutable nodes" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "Output", .pos = .{ 180, 80 } },
    };
    var connections: [2]node_editor.Connection = .{node_editor.Connection{ .from_id = 0, .to_id = 0 }} ** 2;
    var node_len: usize = nodes.len;
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9402, .state = &state, .nodes = &nodes, .mutable_nodes = &nodes, .mutable_connections = &connections, .mutable_connection_len = &connection_len, .history = &history, .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } } });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };
    const before = nodes[1].pos;
    const node_rect = node_editor.nodeRectFromState(.{ .x = 0, .y = 0, .w = 340, .h = 200 }, state, nodes[1]);
    const start = [2]f32{ node_rect.x + node_rect.w * 0.5, node_rect.y + node_rect.h * 0.5 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = start[0] + 24, .y = start[1] + 12, .dx = 24, .dy = 12 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = start[0] + 24, .y = start[1] + 12 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
    try std.testing.expect(nodes[1].pos[0] > before[0]);
    try std.testing.expect(nodes[1].pos[1] > before[1]);
    try std.testing.expect(state.dragging_node_id == null);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expectEqual(before, nodes[1].pos);
}

test "node editor view drags multi-selection as one undo transaction" {
    var selected = [_]u32{ 1, 2, 0, 0 };
    var state = node_editor.State{
        .selected_node_ids = &selected,
        .selected_node_len = 2,
        .selected_node_id = 2,
        .zoom = 2,
    };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ -120, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "B", .pos = .{ 20, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 3, .title = "C", .pos = .{ 180, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    const before = nodes;
    var node_len: usize = nodes.len;
    var connections: [1]node_editor.Connection = .{.{ .from_id = 1, .to_id = 2 }};
    var connection_len: usize = connections.len;
    var history = node_editor.History{};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, connections.len){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 640, .h = 280 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 640, .h = 280 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9417,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .mutable_node_len = &node_len,
        .mutable_connections = &connections,
        .mutable_connection_len = &connection_len,
        .history = &history,
        .viewport_index = &viewport_index,
        .show_minimap = false,
        .style = .{ .width = .{ .px = 620 }, .height = .{ .px = 260 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 620, .h = 260 };
    const node_rect = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const start = [2]f32{ node_rect.x + node_rect.w * 0.5, node_rect.y + node_rect.h * 0.5 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    var move1 = ElementEvent{ .mouse_move = .{ .x = start[0] + 20, .y = start[1] + 10, .dx = 20, .dy = 10 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move1, editor_node.paint_user_data));
    var move2 = ElementEvent{ .mouse_move = .{ .x = start[0] + 28, .y = start[1] + 14, .dx = 8, .dy = 4 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move2, editor_node.paint_user_data));
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = start[0] + 28, .y = start[1] + 14 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expectEqual([2]f32{ before[0].pos[0] + 14, before[0].pos[1] + 7 }, nodes[0].pos);
    try std.testing.expectEqual([2]f32{ before[1].pos[0] + 14, before[1].pos[1] + 7 }, nodes[1].pos);
    try std.testing.expectEqual(before[2].pos, nodes[2].pos);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
    try std.testing.expect(!viewport_index.summary().valid);
    try std.testing.expectEqual(@as(u64, 1), viewport_index.summary().rebuild_count);
    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expectEqual(before[0].pos, nodes[0].pos);
    try std.testing.expectEqual(before[1].pos, nodes[1].pos);
    try std.testing.expectEqual(before[2].pos, nodes[2].pos);

    const third_rect = node_editor.nodeRectFromState(editor_node.rect, state, nodes[2]);
    const third_point = [2]f32{ third_rect.x + third_rect.w * 0.5, third_rect.y + third_rect.h * 0.5 };
    var third_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = third_point[0], .y = third_point[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &third_down, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 3), state.selected_node_id);
    try std.testing.expectEqual(@as(usize, 1), state.boundedSelectionLen());
}

test "node editor multi-drag is atomic when history capacity is insufficient" {
    const node_count = 17;
    var selected = [_]u32{ 1, 2, 0, 0 };
    var state = node_editor.State{
        .selected_node_ids = &selected,
        .selected_node_len = 2,
        .selected_node_id = 2,
    };
    var nodes: [node_count]node_editor.Node = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{
        .id = @intCast(index + 1),
        .title = "node",
        .pos = .{ @floatFromInt(index * 100), 0 },
        .size = .{ .w = 80, .h = 60 },
    };
    const before = nodes;
    var node_len: usize = nodes.len;
    var connections: [1]node_editor.Connection = undefined;
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 420, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 420, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9418,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .mutable_node_len = &node_len,
        .mutable_connections = &connections,
        .mutable_connection_len = &connection_len,
        .history = &history,
        .viewport_index = &viewport_index,
        .show_minimap = false,
        .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 220 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 220 };
    const node_rect = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const start = [2]f32{ node_rect.x + 20, node_rect.y + 20 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = start[0] + 20, .y = start[1] + 10, .dx = 20, .dy = 10 } };
    try std.testing.expect(!nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));
    try std.testing.expectEqual(before, nodes);
    try std.testing.expectEqual(@as(usize, 0), history.undo_len);
    try std.testing.expect(!state.interaction_history_pushed);
}

test "node editor view reports dirty canvas invalidation" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var canvas_state = zui.CanvasState{};
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "Output", .pos = .{ 180, 80 } },
    };
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9412, .canvas_state = &canvas_state, .viewport_index = &viewport_index, .geometry_revision = 1, .state = &state, .nodes = &nodes, .mutable_nodes = &nodes, .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } } });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };

    const node_rect = node_editor.nodeRectFromState(editor_node.rect, state, nodes[1]);
    const start = [2]f32{ node_rect.x + node_rect.w * 0.5, node_rect.y + node_rect.h * 0.5 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = start[0] + 24, .y = start[1] + 12, .dx = 24, .dy = 12 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));

    const summary = canvas_state.dirtySummary();
    try std.testing.expect(summary.needsPaint());
    try std.testing.expect(summary.invalidation.contains(.paint));
    try std.testing.expect(summary.invalidation.contains(.data));
    try std.testing.expect(summary.invalidation.contains(.hit_test));
    try std.testing.expectEqual(@as(?Rect, editor_node.rect), summary.dirty_bounds);
    try std.testing.expect(!viewport_index.summary().valid);
}

test "node editor view invalidates shared canvas layer cache" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var canvas_state = zui.CanvasState{};
    var canvas_layers = zui.CanvasLayerCache{};
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "Output", .pos = .{ 180, 80 } },
    };
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9414, .canvas_state = &canvas_state, .canvas_layers = &canvas_layers, .state = &state, .nodes = &nodes, .mutable_nodes = &nodes, .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } } });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };
    _ = canvas_layers.ensure(1, editor_node.rect);

    const node_rect = node_editor.nodeRectFromState(editor_node.rect, state, nodes[1]);
    const start = [2]f32{ node_rect.x + node_rect.w * 0.5, node_rect.y + node_rect.h * 0.5 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = start[0] + 24, .y = start[1] + 12, .dx = 24, .dy = 12 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));

    const summary = canvas_layers.summary();
    try std.testing.expectEqual(@as(usize, 0), summary.valid_count);
    try std.testing.expectEqual(@as(usize, 1), summary.invalid_count);
    try std.testing.expect(canvas_layers.entries[0].invalidation.contains(.paint));
}

test "node editor canvas hit test feeds generic canvas hover" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var canvas_state = zui.CanvasState{};
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "Output", .pos = .{ 180, 80 } },
    };
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9413, .canvas_state = &canvas_state, .state = &state, .nodes = &nodes, .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } } });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };

    const node_rect = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    var move = ElementEvent{ .mouse_move = .{ .x = node_rect.x + 4, .y = node_rect.y + 4, .dx = 0, .dy = 0 } };
    _ = editor_node.on_event.?(editor_node, &move);
    try std.testing.expectEqual(@as(?u64, packCanvasHitId(.node, 1)), canvas_state.hovered_id);
    try std.testing.expect(zui.summarizeCanvas(editor_node).has_hit_test_handler);
}

test "node editor canvas hit test reuses viewport candidates" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var canvas_state = zui.CanvasState{};
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "visible", .pos = .{ -40, -30 } },
        .{ .id = 2, .title = "culled", .pos = .{ 4000, 3000 } },
    };
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9415,
        .canvas_state = &canvas_state,
        .viewport_index = &viewport_index,
        .geometry_revision = 1,
        .state = &state,
        .nodes = &nodes,
        .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };

    const node_rect = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const point = [2]f32{ node_rect.x + 20, node_rect.y + 20 };
    try std.testing.expectEqual(packCanvasHitId(.node, 1), nodeEditorCanvasHitTest(editor_node, point, editor_node.paint_user_data).?);
    try std.testing.expectEqual(packCanvasHitId(.node, 1), nodeEditorCanvasHitTest(editor_node, point, editor_node.paint_user_data).?);
    const summary = viewport_index.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.visible_node_count);
    try std.testing.expectEqual(@as(u64, 1), summary.rebuild_count);
    try std.testing.expectEqual(@as(u64, 1), summary.viewport_reuse_count);
}

test "node editor view creates connections from output to input ports" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ 0, 0 }, .output_types = &.{.image} },
        .{ .id = 2, .title = "Output", .pos = .{ 180, 80 }, .input_types = &.{.image} },
    };
    var connections: [4]node_editor.Connection = .{node_editor.Connection{ .from_id = 0, .to_id = 0 }} ** 4;
    var connection_len: usize = 0;
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9403, .state = &state, .nodes = &nodes, .mutable_connections = &connections, .mutable_connection_len = &connection_len, .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } } });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };
    const out = node_editor.outputPortPosition(editor_node.rect, state, nodes[0]);
    const in = node_editor.inputPortPosition(editor_node.rect, state, nodes[1]);
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = out[0], .y = out[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = in[0], .y = in[1], .dx = in[0] - out[0], .dy = in[1] - out[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = in[0], .y = in[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 1), connection_len);
    try std.testing.expectEqual(node_editor.Connection{ .from_id = 1, .to_id = 2 }, connections[0]);
    try std.testing.expectEqual(@as(?node_editor.Connection, connections[0]), state.selected_connection);
}

test "node editor view retains borrowed connection commands across rebuilds" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ -120, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "Output", .pos = .{ 80, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    const connections = [_]node_editor.Connection{.{ .from_id = 1, .to_id = 2 }};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, connections.len){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var draw_storage = node_editor.StaticConnectionDrawWorkspace(connections.len){};
    var draw_workspace = draw_storage.workspace();
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9416,
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .viewport_index = &viewport_index,
        .connection_draw_workspace = &draw_workspace,
        .show_minimap = false,
        .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };

    var first = std.ArrayList(DrawCmd).empty;
    defer first.deinit(std.testing.allocator);
    try paintNodeEditor(std.testing.allocator, &first, editor_node.rect, 0, editor_node.paint_user_data);
    const first_stroke = for (first.items) |command| {
        if (command == .stroke_path) break command.stroke_path;
    } else return error.MissingConnectionStroke;
    try std.testing.expect(!first_stroke.owns_commands);
    const first_start = first_stroke.commands[0].move_to;
    for (first.items) |command| zui.ui_draw_cmd.freePayload(std.testing.allocator, command);

    nodes[0].pos[0] += 40;
    viewport_index.invalidate();
    var second = std.ArrayList(DrawCmd).empty;
    defer second.deinit(std.testing.allocator);
    try paintNodeEditor(std.testing.allocator, &second, editor_node.rect, 0, editor_node.paint_user_data);
    const second_command = for (second.items) |command| {
        if (command == .stroke_path) break command;
    } else return error.MissingConnectionStroke;
    const second_stroke = second_command.stroke_path;
    try std.testing.expect(!second_stroke.owns_commands);
    try std.testing.expect(second_stroke.commands.ptr == first_stroke.commands.ptr);
    try std.testing.expect(second_stroke.commands[0].move_to[0] > first_start[0]);
    const render_stroke = zui.ui_draw_cmd.toRenderCmd(second_command).stroke_path;
    try std.testing.expectEqualSlices(zui.RenderPathCommand, second_stroke.commands, render_stroke.path.commands);
    for (second.items) |command| zui.ui_draw_cmd.freePayload(std.testing.allocator, command);
}

test "node editor view rejects strict dataflow cycle gestures" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Source", .pos = .{ -160, 0 } },
        .{ .id = 2, .title = "Middle", .pos = .{ 20, 0 } },
        .{ .id = 3, .title = "Output", .pos = .{ 200, 0 } },
    };
    var connections: [4]node_editor.Connection = .{node_editor.Connection{ .from_id = 0, .to_id = 0 }} ** 4;
    connections[0] = .{ .from_id = 1, .to_id = 2 };
    connections[1] = .{ .from_id = 2, .to_id = 3 };
    var connection_len: usize = 2;
    var history = node_editor.History{};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 600, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 600, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9406,
        .state = &state,
        .nodes = &nodes,
        .mutable_connections = &connections,
        .mutable_connection_len = &connection_len,
        .history = &history,
        .connection_policy = .strict_dataflow,
        .style = .{ .width = .{ .px = 580 }, .height = .{ .px = 220 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 580, .h = 220 };

    const out = node_editor.outputPortPosition(editor_node.rect, state, nodes[2]);
    const in = node_editor.inputPortPosition(editor_node.rect, state, nodes[0]);
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = out[0], .y = out[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = in[0], .y = in[1], .dx = in[0] - out[0], .dy = in[1] - out[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));
    try std.testing.expect(!state.connection_preview_valid);
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = in[0], .y = in[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 2), connection_len);
    try std.testing.expectEqual(@as(usize, 0), history.undo_len);
    try std.testing.expect(state.pending_connection == null);
}

test "node editor view handles minimap panning and shift box selection" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ -220, -80 } },
        .{ .id = 2, .title = "Process", .pos = .{ 60, 40 } },
    };
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 420, .h = 260 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 420, .h = 260 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9404, .state = &state, .nodes = &nodes, .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 240 } } });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 240 };

    const snapshot = node_editor.minimapSnapshot(editor_node.rect, state, &nodes, &.{}, .{ .w = 120, .h = 72 });
    try std.testing.expect(snapshot.visible);
    const minimap_point = [2]f32{ snapshot.minimap_rect.x + snapshot.minimap_rect.w * 0.98, snapshot.minimap_rect.y + snapshot.minimap_rect.h * 0.95 };
    const pan_before = state.pan;
    var minimap_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = minimap_point[0], .y = minimap_point[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &minimap_down, editor_node.paint_user_data));
    var minimap_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = minimap_point[0], .y = minimap_point[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &minimap_up, editor_node.paint_user_data));
    try std.testing.expect(@abs(state.pan[0] - pan_before[0]) > 0.001 or @abs(state.pan[1] - pan_before[1]) > 0.001);

    state.pan = .{ 0, 0 };
    state.zoom = 1;
    editor_node.input_shift_down = true;
    const n0 = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const n1 = node_editor.nodeRectFromState(editor_node.rect, state, nodes[1]);
    var box_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = n0.x - 8, .y = n0.y - 8 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &box_down, editor_node.paint_user_data));
    var box_move = ElementEvent{ .mouse_move = .{ .x = n1.x + n1.w + 8, .y = n1.y + n1.h + 8, .dx = n1.x - n0.x, .dy = n1.y - n0.y } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &box_move, editor_node.paint_user_data));
    var box_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = n1.x + n1.w + 8, .y = n1.y + n1.h + 8 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &box_up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    try std.testing.expect(state.isNodeSelected(1));
    try std.testing.expect(state.isNodeSelected(2));
}

test "node editor view handles groups and reconnect gestures through shared event adapter" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ -150, 0 }, .output_types = &.{.image} },
        .{ .id = 2, .title = "Process", .pos = .{ 20, 0 }, .input_types = &.{.image}, .output_types = &.{.image} },
        .{ .id = 3, .title = "Output", .pos = .{ 190, 0 }, .input_types = &.{.image} },
    };
    var groups = [_]node_editor.Group{.{ .id = 8, .title = "Group", .rect = .{ .x = -175, .y = -25, .w = 140, .h = 100 } }};
    var connections: [4]node_editor.Connection = .{node_editor.Connection{ .from_id = 0, .to_id = 0 }} ** 4;
    connections[0] = .{ .from_id = 1, .to_id = 2 };
    var connection_len: usize = 1;
    var history = node_editor.History{};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 520, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 520, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9405, .state = &state, .nodes = &nodes, .groups = &groups, .mutable_groups = &groups, .mutable_connections = &connections, .mutable_connection_len = &connection_len, .history = &history, .style = .{ .width = .{ .px = 500 }, .height = .{ .px = 220 } } });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 500, .h = 220 };

    const group_rect = node_editor.groupRect(editor_node.rect, state, groups[0]);
    const group_start = [2]f32{ group_rect.x + 12.0, group_rect.y + 12.0 };
    var group_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = group_start[0], .y = group_start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &group_down, editor_node.paint_user_data));
    var group_move = ElementEvent{ .mouse_move = .{ .x = group_start[0] + 18, .y = group_start[1] + 9, .dx = 18, .dy = 9 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &group_move, editor_node.paint_user_data));
    var group_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = group_start[0] + 18, .y = group_start[1] + 9 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &group_up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 8), state.selected_group_id);
    try std.testing.expect(groups[0].rect.x > -175);
    try std.testing.expect(history.undo_len > 0);

    try std.testing.expect(state.setConnectionSelection(connections[0]));
    const input2 = node_editor.inputPortPosition(editor_node.rect, state, nodes[1]);
    const input3 = node_editor.inputPortPosition(editor_node.rect, state, nodes[2]);
    var reconnect_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = input2[0], .y = input2[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &reconnect_down, editor_node.paint_user_data));
    var reconnect_move = ElementEvent{ .mouse_move = .{ .x = input3[0], .y = input3[1], .dx = input3[0] - input2[0], .dy = input3[1] - input2[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &reconnect_move, editor_node.paint_user_data));
    var reconnect_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = input3[0], .y = input3[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &reconnect_up, editor_node.paint_user_data));
    try std.testing.expectEqual(node_editor.Connection{ .from_id = 1, .to_id = 3 }, connections[0]);
    try std.testing.expectEqual(@as(?node_editor.Connection, connections[0]), state.selected_connection);
}
