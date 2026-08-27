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
    /// Optional caller-owned topology index used by topology-first navigation.
    topology_index: ?*node_editor.GraphTopologyIndex = null,
    /// Optional application-owned geometry revision. When supplied, callers
    /// must increment it after external node/group/link geometry changes.
    geometry_revision: ?u64 = null,
    /// Optional application-owned revision for node ids and link endpoints.
    topology_revision: ?u64 = null,
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
    drag_auto_pan: node_editor.DragAutoPanOptions = .{},
    drag_snap: node_editor.DragSnapOptions = .{},
    alignment_snap: node_editor.AlignmentSnapOptions = .{},
    distribution_snap: node_editor.DistributionSnapOptions = .{},
    box_select_scope: node_editor.BoxSelectScope = .nodes_only,
    /// Opt-in arrow-key navigation. Shift extends the current node selection.
    spatial_navigation: node_editor.SpatialNavigationOptions = .{},
    /// Opt-in title double-click interaction and disclosure indicators.
    node_collapse: node_editor.NodeCollapseOptions = .{},
    /// Opt-in edge and corner resizing for the selected expanded node.
    node_resize: node_editor.NodeResizeOptions = .{},
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
    topology_index: ?*node_editor.GraphTopologyIndex = null,
    geometry_revision: ?u64 = null,
    topology_revision: ?u64 = null,
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
    drag_auto_pan: node_editor.DragAutoPanOptions = .{},
    drag_snap: node_editor.DragSnapOptions = .{},
    alignment_snap: node_editor.AlignmentSnapOptions = .{},
    distribution_snap: node_editor.DistributionSnapOptions = .{},
    box_select_scope: node_editor.BoxSelectScope = .nodes_only,
    spatial_navigation: node_editor.SpatialNavigationOptions = .{},
    node_collapse: node_editor.NodeCollapseOptions = .{},
    node_resize: node_editor.NodeResizeOptions = .{},
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
            .drag_auto_pan = self.drag_auto_pan,
            .drag_snap = self.drag_snap,
            .alignment_snap = self.alignment_snap,
            .distribution_snap = self.distribution_snap,
            .box_select_scope = self.box_select_scope,
            .spatial_navigation = self.spatial_navigation,
            .node_collapse = self.node_collapse,
            .node_resize = self.node_resize,
            .clipboard = self.clipboard,
            .connection_path_cache = self.connection_path_cache,
            .connection_draw_workspace = self.connection_draw_workspace,
            .viewport_index = self.viewport_index,
            .topology_index = self.topology_index,
            .geometry_revision = self.geometry_revision,
            .topology_revision = self.topology_revision,
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
        .topology_index = options.topology_index,
        .geometry_revision = options.geometry_revision,
        .topology_revision = options.topology_revision,
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
        .drag_auto_pan = options.drag_auto_pan,
        .drag_snap = options.drag_snap,
        .alignment_snap = options.alignment_snap,
        .distribution_snap = options.distribution_snap,
        .box_select_scope = options.box_select_scope,
        .spatial_navigation = options.spatial_navigation,
        .node_collapse = options.node_collapse,
        .node_resize = options.node_resize,
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
        .cursor = nodeEditorCanvasCursor,
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

fn nodeEditorCanvasCursor(node: *const ElementNode, point: [2]f32, user_data: ?*anyopaque) zui.CursorShape {
    const binding: *const Binding = if (user_data) |ptr| @ptrCast(@alignCast(ptr)) else return .default;
    if (binding.state.resizing_node_id != null) return node_editor.nodeResizeCursor(zui.CursorShape, binding.state.resizing_node_edges);
    if (binding.state.resizing_group_id != null) return node_editor.nodeResizeCursor(zui.CursorShape, binding.state.resizing_group_edges);
    if (binding.state.dragging_node_id != null or binding.state.dragging_group_id != null) return .grabbing;
    const editor = binding.editor();
    const viewport_index = node_editor.prepareNodeEditorViewportIndex(node.rect, editor);
    if (node_editor.inputPortAtEditorPoint(node.rect, editor, viewport_index, point) != null or
        node_editor.outputPortAtEditorPoint(node.rect, editor, viewport_index, point) != null) return .crosshair;
    if (node_editor.nodeResizeAtEditorPoint(node.rect, editor, viewport_index, point)) |hit| return node_editor.nodeResizeCursor(zui.CursorShape, hit.edges);
    if (node_editor.nodeAtEditorPoint(node.rect, editor, viewport_index, point) != null) return .grab;
    if (node_editor.groupResizeAtEditorPoint(node.rect, editor, viewport_index, point)) |hit| return node_editor.nodeResizeCursor(zui.CursorShape, hit.edges);
    if (node_editor.groupAtEditorPoint(node.rect, editor, viewport_index, point) != null) return .grab;
    return .default;
}

const InteractionSnapshot = struct {
    pan: [2]f32 = .{ 0.0, 0.0 },
    zoom: f32 = 1.0,
    node_drag_applied_delta: [2]f32 = .{ 0.0, 0.0 },
    node_collapse_mutation_count: u64 = 0,
    non_node_structural_drag: bool = false,

    fn capture(state: *const node_editor.State) InteractionSnapshot {
        return .{
            .pan = state.pan,
            .zoom = state.zoom,
            .node_drag_applied_delta = state.node_drag_applied_delta,
            .node_collapse_mutation_count = state.node_collapse_mutation_count,
            .non_node_structural_drag = state.dragging_group_id != null or
                state.resizing_group_id != null or
                state.resizing_node_id != null or
                state.resizing_group_edges.any() or
                state.dragging_connection_from_id != null or
                state.reconnecting_connection != null,
        };
    }

    fn transformChanged(self: InteractionSnapshot, state: *const node_editor.State) bool {
        return @abs(self.pan[0] - state.pan[0]) > 0.001 or
            @abs(self.pan[1] - state.pan[1]) > 0.001 or
            @abs(self.zoom - state.zoom) > 0.0001;
    }

    fn nodeGeometryChanged(self: InteractionSnapshot, state: *const node_editor.State) bool {
        return @abs(self.node_drag_applied_delta[0] - state.node_drag_applied_delta[0]) > 0.001 or
            @abs(self.node_drag_applied_delta[1] - state.node_drag_applied_delta[1]) > 0.001 or
            self.node_collapse_mutation_count != state.node_collapse_mutation_count;
    }
};

fn markCanvasInvalidation(binding: *Binding, rect: Rect, event: ElementEvent, before: InteractionSnapshot, changed: bool) void {
    if (!changed) return;
    const geometry_changed = before.nodeGeometryChanged(binding.state) or before.non_node_structural_drag or
        binding.state.dragging_group_id != null or binding.state.resizing_group_id != null or binding.state.resizing_node_id != null or binding.state.reconnecting_connection != null;
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

test "node editor view double-clicks titles to collapse with one undo" {
    var selected = [_]u32{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes = [_]node_editor.Node{.{ .id = 1, .title = "Fold me", .pos = .{ -60, -50 }, .size = .{ .w = 120, .h = 100 }, .input_count = 2, .output_count = 2 }};
    var node_len: usize = nodes.len;
    var connections: [1]node_editor.Connection = undefined;
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var canvas_state = zui.CanvasState{};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 320, .h = 200 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 320, .h = 200 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9432,
        .canvas_state = &canvas_state,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .mutable_node_len = &node_len,
        .mutable_connections = &connections,
        .mutable_connection_len = &connection_len,
        .history = &history,
        .viewport_index = &viewport_index,
        .node_collapse = .{ .enabled = true },
        .show_minimap = false,
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 320, .h = 200 };
    try std.testing.expect(node_editor.prepareNodeEditorViewportIndex(editor_node.rect, node_editor.Options(node_editor.State){ .state = &state, .nodes = &nodes, .viewport_index = &viewport_index, .show_minimap = false }) != null);
    const title = node_editor.nodeTitleRectFromState(editor_node.rect, state, nodes[0]);
    var double_click = ElementEvent{ .mouse_down = .{ .button = .left, .x = title.x + 20, .y = title.y + 12, .click_count = 2 } };

    try std.testing.expect(nodeEditorViewEvent(editor_node, &double_click, editor_node.paint_user_data));
    try std.testing.expect(nodes[0].collapsed);
    try std.testing.expectEqual(@as(?u32, null), state.dragging_node_id);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
    try std.testing.expect(!viewport_index.summary().valid);
    try std.testing.expect(canvas_state.dirtySummary().invalidation.contains(.data));

    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expect(!nodes[0].collapsed);
}

test "node editor view resizes a node as one zoom-correct undo transaction" {
    var selected = [_]u32{ 1, 0 };
    var state = node_editor.State{ .selected_node_ids = &selected, .selected_node_len = 1, .selected_node_id = 1, .zoom = 2 };
    var nodes = [_]node_editor.Node{.{ .id = 1, .title = "Resize", .pos = .{ -50, -40 }, .size = .{ .w = 100, .h = 80 } }};
    const before = nodes[0];
    var node_len: usize = nodes.len;
    var connections: [1]node_editor.Connection = undefined;
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 260 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 260 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9433,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .mutable_node_len = &node_len,
        .mutable_connections = &connections,
        .mutable_connection_len = &connection_len,
        .history = &history,
        .viewport_index = &viewport_index,
        .node_resize = .{ .enabled = true, .min_size = .{ .w = 72, .h = 48 } },
        .drag_auto_pan = .{ .enabled = false },
        .show_minimap = false,
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 260 };
    const node_rect = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = node_rect.x + node_rect.w - 2, .y = node_rect.y + node_rect.h - 2 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 1), state.resizing_node_id);
    try std.testing.expectEqual(zui.CursorShape.resize_south_east, nodeEditorCanvasCursor(editor_node, .{ node_rect.x + node_rect.w - 2, node_rect.y + node_rect.h - 2 }, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = node_rect.x + node_rect.w + 38, .y = node_rect.y + node_rect.h + 18, .dx = 40, .dy = 20 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(f32, 120), nodes[0].size.w);
    try std.testing.expectEqual(@as(f32, 90), nodes[0].size.h);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = move.mouse_move.x, .y = move.mouse_move.y } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, null), state.resizing_node_id);
    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expectEqual(before, nodes[0]);
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

test "node editor view shift-selects and drags multi-selection as one undo transaction" {
    var selected = [_]u32{ 2, 0, 0, 0 };
    var state = node_editor.State{
        .selected_node_ids = &selected,
        .selected_node_len = 1,
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
    editor_node.input_shift_down = true;
    var shift_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &shift_down, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    try std.testing.expectEqualSlices(u32, &.{ 2, 1 }, state.selected_node_ids[0..state.boundedSelectionLen()]);
    try std.testing.expectEqual(@as(?u32, null), state.dragging_node_id);

    editor_node.input_shift_down = false;
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

    _ = state.endDrag();
    editor_node.input_shift_down = true;
    var third_toggle = ElementEvent{ .mouse_down = .{ .button = .left, .x = third_point[0], .y = third_point[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &third_toggle, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 0), state.boundedSelectionLen());
    try std.testing.expectEqual(@as(?u32, null), state.dragging_node_id);
}

test "node editor view snaps multi-drag at zoom and Alt bypasses without splitting undo" {
    var selected = [_]u32{ 1, 2, 0, 0 };
    var state = node_editor.State{
        .selected_node_ids = &selected,
        .selected_node_len = 2,
        .selected_node_id = 1,
        .zoom = 2,
    };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ 1, 1 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "B", .pos = .{ 101, 51 }, .size = .{ .w = 80, .h = 60 } },
    };
    const before = nodes;
    const relative_before = [2]f32{ before[1].pos[0] - before[0].pos[0], before[1].pos[1] - before[0].pos[1] };
    var node_len: usize = nodes.len;
    var connections: [0]node_editor.Connection = .{};
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 500, .h = 260 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 500, .h = 260 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9420,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .mutable_node_len = &node_len,
        .history = &history,
        .viewport_index = &viewport_index,
        .drag_auto_pan = .{ .enabled = false },
        .drag_snap = .{ .enabled = true, .spacing = .{ 16, 16 }, .threshold_pixels = 6 },
        .show_minimap = false,
        .style = .{ .width = .{ .px = 500 }, .height = .{ .px = 260 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 500, .h = 260 };
    const anchor = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const start = [2]f32{ anchor.x + 20, anchor.y + 20 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));

    var snap_move = ElementEvent{ .mouse_move = .{ .x = start[0] + 4, .y = start[1] + 4, .dx = 4, .dy = 4 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &snap_move, editor_node.paint_user_data));
    try std.testing.expectEqual([2]f32{ 0, 0 }, nodes[0].pos);
    try std.testing.expectEqual([2]f32{ 100, 50 }, nodes[1].pos);
    try std.testing.expectEqual(@as(?f32, 0), state.snap_guide_x);
    try std.testing.expectEqual(@as(?f32, 0), state.snap_guide_y);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);

    editor_node.input_alt_down = true;
    var bypass = ElementEvent{ .mouse_move = .{ .x = start[0] + 4, .y = start[1] + 4, .dx = 0, .dy = 0 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &bypass, editor_node.paint_user_data));
    try std.testing.expectEqual([2]f32{ 3, 3 }, nodes[0].pos);
    try std.testing.expectEqual(@as(?f32, null), state.snap_guide_x);
    try std.testing.expectEqual(@as(?f32, null), state.snap_guide_y);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);

    editor_node.input_alt_down = false;
    var restore_snap = ElementEvent{ .mouse_move = .{ .x = start[0] + 4, .y = start[1] + 4, .dx = 0, .dy = 0 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &restore_snap, editor_node.paint_user_data));
    try std.testing.expectEqual([2]f32{ 0, 0 }, nodes[0].pos);
    try std.testing.expectEqual(relative_before, [2]f32{ nodes[1].pos[0] - nodes[0].pos[0], nodes[1].pos[1] - nodes[0].pos[1] });
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);

    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = start[0] + 4, .y = start[1] + 4 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?f32, null), state.snap_guide_x);
    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expectEqual(before, nodes);
}

test "node editor view aligns multi-drag to stationary nodes with one undo" {
    var selected = [_]u32{ 1, 2, 0, 0 };
    var state = node_editor.State{ .selected_node_ids = &selected, .selected_node_len = 2, .selected_node_id = 1 };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ -100, -40 }, .size = .{ .w = 40, .h = 20 } },
        .{ .id = 2, .title = "B", .pos = .{ -40, -40 }, .size = .{ .w = 40, .h = 20 } },
        .{ .id = 3, .title = "Target", .pos = .{ 40, -10 }, .size = .{ .w = 40, .h = 20 } },
    };
    const before = nodes;
    var node_len: usize = nodes.len;
    var connections: [0]node_editor.Connection = .{};
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9423,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .mutable_node_len = &node_len,
        .history = &history,
        .viewport_index = &viewport_index,
        .drag_auto_pan = .{ .enabled = false },
        .alignment_snap = .{ .enabled = true, .threshold_pixels = 6 },
        .show_minimap = false,
        .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 240 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 240 };
    const anchor = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const start = [2]f32{ anchor.x + 20, anchor.y + 10 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = start[0] + 38, .y = start[1], .dx = 38, .dy = 0 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));
    try std.testing.expectEqual([2]f32{ -60, -40 }, nodes[0].pos);
    try std.testing.expectEqual([2]f32{ 0, -40 }, nodes[1].pos);
    try std.testing.expectEqual(@as(?f32, 40), state.snap_guide_x);
    try std.testing.expectEqual(@as(?[2]f32, .{ -40, 10 }), state.snap_guide_x_span);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = start[0] + 38, .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expectEqual(before, nodes);
}

test "node editor snap guides repaint without invalidating geometry" {
    var selected = [_]u32{ 1, 0, 0, 0 };
    var state = node_editor.State{ .selected_node_ids = &selected, .selected_node_len = 1, .selected_node_id = 1 };
    var nodes = [_]node_editor.Node{.{ .id = 1, .title = "A", .pos = .{ 0, 0 } }};
    var history = node_editor.History{};
    var canvas_state = zui.CanvasState{};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9421,
        .canvas_state = &canvas_state,
        .viewport_index = &viewport_index,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .history = &history,
        .drag_auto_pan = .{ .enabled = false },
        .drag_snap = .{ .enabled = true, .spacing = .{ 16, 16 }, .threshold_pixels = 6 },
        .show_minimap = false,
        .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };
    const anchor = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const start = [2]f32{ anchor.x + 20, anchor.y + 20 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    try std.testing.expect(viewport_index.summary().valid);
    try std.testing.expectEqual(@as(usize, 0), history.undo_len);
    canvas_state.clearInvalidation();

    var guide_move = ElementEvent{ .mouse_move = .{ .x = start[0] + 2, .y = start[1] + 2, .dx = 2, .dy = 2 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &guide_move, editor_node.paint_user_data));
    try std.testing.expectEqual([2]f32{ 0, 0 }, nodes[0].pos);
    try std.testing.expectEqual(@as(?f32, 0), state.snap_guide_x);
    try std.testing.expect(viewport_index.summary().valid);
    const dirty = canvas_state.dirtySummary();
    try std.testing.expect(dirty.invalidation.contains(.paint));
    try std.testing.expect(dirty.invalidation.contains(.overlay));
    try std.testing.expect(!dirty.invalidation.contains(.data));
    try std.testing.expect(!dirty.invalidation.contains(.hit_test));
}

test "node editor snap composes with auto pan in one undo transaction" {
    var selected = [_]u32{ 1, 0, 0, 0 };
    var state = node_editor.State{ .selected_node_ids = &selected, .selected_node_len = 1, .selected_node_id = 1 };
    var nodes = [_]node_editor.Node{.{ .id = 1, .title = "A", .pos = .{ 17, 0 }, .size = .{ .w = 80, .h = 60 } }};
    const before = nodes;
    var node_len: usize = nodes.len;
    var connections: [0]node_editor.Connection = .{};
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9422,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .mutable_node_len = &node_len,
        .history = &history,
        .drag_auto_pan = .{ .edge_margin = 40, .max_step = 16 },
        .drag_snap = .{ .enabled = true, .spacing = .{ 16, 16 }, .threshold_pixels = 6 },
        .show_minimap = false,
        .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 240 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 240 };
    const anchor = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const start = [2]f32{ anchor.x + 20, anchor.y + 20 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var pan_move = ElementEvent{ .mouse_move = .{ .x = 399, .y = start[1], .dx = 0, .dy = 0 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &pan_move, editor_node.paint_user_data));
    try std.testing.expect(nodeEditorViewEvent(editor_node, &pan_move, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(f32, 48), nodes[0].pos[0]);
    try std.testing.expectEqual(@as(?f32, 48), state.snap_guide_x);
    try std.testing.expect(state.pan[0] < -30);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = 399, .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expectEqual(before, nodes);
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
    var move = ElementEvent{ .mouse_move = .{ .x = 399, .y = start[1] + 10, .dx = 20, .dy = 10 } };
    try std.testing.expect(!nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));
    try std.testing.expectEqual(before, nodes);
    try std.testing.expectEqual([2]f32{ 0, 0 }, state.pan);
    try std.testing.expectEqual(@as(usize, 0), history.undo_len);
    try std.testing.expect(!state.interaction_history_pushed);
}

test "node editor drag auto pan keeps selected nodes under the pointer" {
    var selected = [_]u32{ 1, 2, 0, 0 };
    var state = node_editor.State{
        .selected_node_ids = &selected,
        .selected_node_len = 2,
        .selected_node_id = 1,
    };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ 80, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "B", .pos = .{ -80, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    var history = node_editor.History{};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9419,
        .state = &state,
        .nodes = &nodes,
        .mutable_nodes = &nodes,
        .history = &history,
        .viewport_index = &viewport_index,
        .show_minimap = false,
        .drag_auto_pan = .{ .edge_margin = 40, .max_step = 20 },
        .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 240 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 240 };
    const before = nodes;
    const anchor_before = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const start = [2]f32{ anchor_before.x + anchor_before.w * 0.5, anchor_before.y + anchor_before.h * 0.5 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var move = ElementEvent{ .mouse_move = .{ .x = 399, .y = start[1], .dx = 12, .dy = 0 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move, editor_node.paint_user_data));
    try std.testing.expect(state.pan[0] < 0);
    const anchor_after = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 12), anchor_after.x - anchor_before.x, 0.001);
    try std.testing.expectApproxEqAbs(nodes[0].pos[0] - before[0].pos[0], nodes[1].pos[0] - before[1].pos[0], 0.001);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
}

test "node editor box auto pan preserves graph-space selection anchor" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    const nodes = [_]node_editor.Node{.{ .id = 1, .title = "A", .pos = .{ 0, 0 } }};
    const viewport = Rect{ .x = 0, .y = 0, .w = 400, .h = 240 };
    const editor = node_editor.Options(node_editor.State){
        .state = &state,
        .nodes = &nodes,
        .show_minimap = false,
        .drag_auto_pan = .{ .edge_margin = 40, .max_step = 20 },
    };
    try std.testing.expect(state.beginBoxSelectMode(.{ 200, 120 }, .replace));
    const anchor_graph_before = node_editor.screenToGraph(viewport, state, state.box_select_start);
    var move = ElementEvent{ .mouse_move = .{ .x = 399, .y = 120, .dx = 0, .dy = 0 } };
    try std.testing.expect(node_editor.handleEditorEvent(viewport, .{}, editor, &move));
    const anchor_graph_after = node_editor.screenToGraph(viewport, state, state.box_select_start);
    try std.testing.expectApproxEqAbs(anchor_graph_before[0], anchor_graph_after[0], 0.001);
    try std.testing.expectApproxEqAbs(anchor_graph_before[1], anchor_graph_after[1], 0.001);
    try std.testing.expect(state.pan[0] < 0);
    try std.testing.expectEqual([2]f32{ 399, 120 }, state.box_select_end);
}

test "node editor group drag and resize remain pointer aligned during auto pan" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var groups = [_]node_editor.Group{.{ .id = 1, .title = "Group", .rect = .{ .x = 60, .y = -40, .w = 120, .h = 100 } }};
    const viewport = Rect{ .x = 0, .y = 0, .w = 400, .h = 240 };
    const editor = node_editor.Options(node_editor.State){
        .state = &state,
        .nodes = &.{},
        .groups = &groups,
        .mutable_groups = &groups,
        .show_minimap = false,
        .drag_auto_pan = .{ .edge_margin = 40, .max_step = 20 },
    };
    const before_drag = node_editor.groupRect(viewport, state, groups[0]);
    try std.testing.expect(state.beginGroupDrag(1));
    var drag = ElementEvent{ .mouse_move = .{ .x = 399, .y = 120, .dx = 12, .dy = 0 } };
    try std.testing.expect(node_editor.handleEditorEvent(viewport, .{}, editor, &drag));
    const after_drag = node_editor.groupRect(viewport, state, groups[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 12), after_drag.x - before_drag.x, 0.001);
    _ = state.endDrag();

    state.pan = .{ 0, 0 };
    const before_resize = node_editor.groupRect(viewport, state, groups[0]);
    try std.testing.expect(state.beginGroupResize(1, .{ .right = true }));
    var resize = ElementEvent{ .mouse_move = .{ .x = 399, .y = 120, .dx = 10, .dy = 0 } };
    try std.testing.expect(node_editor.handleEditorEvent(viewport, .{}, editor, &resize));
    const after_resize = node_editor.groupRect(viewport, state, groups[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 10), (after_resize.x + after_resize.w) - (before_resize.x + before_resize.w), 0.001);
}

test "node editor connection auto pan pauses on valid targets" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Source", .pos = .{ -140, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "Target", .pos = .{ 110, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    const viewport = Rect{ .x = 0, .y = 0, .w = 400, .h = 240 };
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    const editor = node_editor.Options(node_editor.State){
        .state = &state,
        .nodes = &nodes,
        .viewport_index = &viewport_index,
        .show_minimap = false,
        .drag_auto_pan = .{ .edge_margin = 80, .max_step = 20 },
    };
    state.dragging_connection_from_id = 1;
    const target = node_editor.inputPortPosition(viewport, state, nodes[1]);
    const pan_before = state.pan;
    var target_move = ElementEvent{ .mouse_move = .{ .x = target[0], .y = target[1], .dx = 0, .dy = 0 } };
    try std.testing.expect(node_editor.handleEditorEvent(viewport, .{}, editor, &target_move));
    try std.testing.expectEqual(pan_before, state.pan);
    try std.testing.expectEqual(@as(?u32, 2), state.hover_input_node_id);

    var edge_move = ElementEvent{ .mouse_move = .{ .x = 399, .y = 20, .dx = 0, .dy = 0 } };
    try std.testing.expect(node_editor.handleEditorEvent(viewport, .{}, editor, &edge_move));
    try std.testing.expect(state.pan[0] < pan_before[0]);
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
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9412, .canvas_state = &canvas_state, .viewport_index = &viewport_index, .geometry_revision = 1, .state = &state, .nodes = &nodes, .mutable_nodes = &nodes, .drag_auto_pan = .{ .enabled = false }, .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } } });
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

test "node editor view shift-click toggles multiple connections and paints all selected" {
    var selected_nodes: [4]u32 = .{0} ** 4;
    var selected_connections: [4]node_editor.Connection = undefined;
    var state = node_editor.State{ .selected_node_ids = &selected_nodes, .selected_connections = &selected_connections };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ -180, -70 }, .size = .{ .w = 80, .h = 40 } },
        .{ .id = 2, .title = "B", .pos = .{ -180, 70 }, .size = .{ .w = 80, .h = 40 } },
        .{ .id = 3, .title = "C", .pos = .{ 100, -70 }, .size = .{ .w = 80, .h = 40 } },
        .{ .id = 4, .title = "D", .pos = .{ 100, 70 }, .size = .{ .w = 80, .h = 40 } },
    };
    const connections = [_]node_editor.Connection{
        .{ .from_id = 1, .to_id = 3 },
        .{ .from_id = 2, .to_id = 4 },
    };
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 520, .h = 300 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 520, .h = 300 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9424,
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .show_minimap = false,
        .grid_color = Color.transparent,
        .style = .{ .width = .{ .px = 500 }, .height = .{ .px = 280 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 500, .h = 280 };

    const first_path = node_editor.connectionPathForPoints(
        node_editor.outputPortPosition(editor_node.rect, state, nodes[0]),
        node_editor.inputPortPosition(editor_node.rect, state, nodes[2]),
    );
    const second_path = node_editor.connectionPathForPoints(
        node_editor.outputPortPosition(editor_node.rect, state, nodes[1]),
        node_editor.inputPortPosition(editor_node.rect, state, nodes[3]),
    );
    const first_point = [2]f32{ (first_path.start[0] + first_path.end[0]) * 0.5, (first_path.start[1] + first_path.end[1]) * 0.5 };
    const second_point = [2]f32{ (second_path.start[0] + second_path.end[0]) * 0.5, (second_path.start[1] + second_path.end[1]) * 0.5 };
    var first_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = first_point[0], .y = first_point[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &first_down, editor_node.paint_user_data));
    editor_node.input_shift_down = true;
    var second_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = second_point[0], .y = second_point[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &second_down, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 2), state.boundedConnectionSelectionLen());
    try std.testing.expect(state.isConnectionSelected(connections[0]));
    try std.testing.expect(state.isConnectionSelected(connections[1]));
    editor_node.input_shift_down = false;
    const first_output = node_editor.outputPortPosition(editor_node.rect, state, nodes[0]);
    var reconnect_first = ElementEvent{ .mouse_down = .{ .button = .left, .x = first_output[0], .y = first_output[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &reconnect_first, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?node_editor.Connection, connections[0]), state.reconnecting_connection);
    try std.testing.expectEqual(@as(?node_editor.Connection, connections[0]), state.selected_connection);
    try std.testing.expectEqual(@as(usize, 2), state.boundedConnectionSelectionLen());
    _ = state.endDrag();

    editor_node.input_shift_down = false;
    var first_right = ElementEvent{ .mouse_down = .{ .button = .right, .x = first_point[0], .y = first_point[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &first_right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 2), state.boundedConnectionSelectionLen());
    try std.testing.expectEqual(@as(?node_editor.Connection, connections[0]), state.selected_connection);

    var out = std.ArrayList(DrawCmd).empty;
    defer {
        for (out.items) |command| zui.ui_draw_cmd.freePayload(std.testing.allocator, command);
        out.deinit(std.testing.allocator);
    }
    _ = try node_editor.appendNodeEditor(std.testing.allocator, &out, editor_node.rect, @as(*Binding, @ptrCast(@alignCast(editor_node.paint_user_data.?))).editor(), 0);
    var selected_strokes: usize = 0;
    for (out.items) |command| switch (command) {
        .stroke_path => |stroke| if (stroke.style.width == 3.25) {
            selected_strokes += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 2), selected_strokes);

    editor_node.input_shift_down = true;
    try std.testing.expect(nodeEditorViewEvent(editor_node, &second_down, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 1), state.boundedConnectionSelectionLen());
    try std.testing.expect(state.isConnectionSelected(connections[0]));
    try std.testing.expect(!state.isConnectionSelected(connections[1]));
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

test "node editor view visible box selection supports contain crossing and modifiers" {
    var selected_nodes: [4]u32 = .{0} ** 4;
    var selected_connections: [4]node_editor.Connection = undefined;
    var state = node_editor.State{ .selected_node_ids = &selected_nodes, .selected_connections = &selected_connections };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ -140, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "B", .pos = .{ 60, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    const connections = [_]node_editor.Connection{.{ .from_id = 1, .to_id = 2 }};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, connections.len){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var draw_storage = node_editor.StaticConnectionDrawWorkspace(connections.len){};
    var draw_workspace = draw_storage.workspace();
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9424,
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .viewport_index = &viewport_index,
        .connection_draw_workspace = &draw_workspace,
        .box_select_scope = .visible_only,
        .drag_auto_pan = .{ .enabled = false },
        .show_minimap = false,
        .grid_color = Color.transparent,
        .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 240 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 240 };
    editor_node.input_shift_down = true;

    var contain_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = 50, .y = 70 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &contain_down, editor_node.paint_user_data));
    var contain_move = ElementEvent{ .mouse_move = .{ .x = 350, .y = 170, .dx = 300, .dy = 100 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &contain_move, editor_node.paint_user_data));
    try std.testing.expect(!state.box_select_crossing);
    var contain_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = 350, .y = 170 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &contain_up, editor_node.paint_user_data));
    try std.testing.expectEqualSlices(u32, &.{ 1, 2 }, state.selected_node_ids[0..state.boundedSelectionLen()]);
    try std.testing.expectEqual(@as(usize, 1), state.boundedConnectionSelectionLen());

    editor_node.input_alt_down = true;
    var subtract_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = 220, .y = 100 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &subtract_down, editor_node.paint_user_data));
    var subtract_move = ElementEvent{ .mouse_move = .{ .x = 180, .y = 140, .dx = -40, .dy = 40 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &subtract_move, editor_node.paint_user_data));
    try std.testing.expect(state.box_select_crossing);
    var subtract_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = 180, .y = 140 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &subtract_up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    try std.testing.expectEqual(@as(usize, 0), state.boundedConnectionSelectionLen());

    editor_node.input_alt_down = false;
    editor_node.input_control_down = true;
    var add_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = 220, .y = 100 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &add_down, editor_node.paint_user_data));
    var add_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = 180, .y = 140 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &add_up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 1), state.boundedConnectionSelectionLen());

    var out = std.ArrayList(DrawCmd).empty;
    defer out.deinit(std.testing.allocator);
    _ = try node_editor.appendNodeEditor(std.testing.allocator, &out, editor_node.rect, @as(*Binding, @ptrCast(@alignCast(editor_node.paint_user_data.?))).editor(), 0);
    var selected_strokes: usize = 0;
    for (out.items) |command| switch (command) {
        .stroke_path => |stroke| if (stroke.style.width == 3.25) {
            selected_strokes += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), selected_strokes);

    editor_node.input_alt_down = true;
    var toggle_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = 220, .y = 100 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &toggle_down, editor_node.paint_user_data));
    var toggle_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = 180, .y = 140 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &toggle_up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 0), state.boundedConnectionSelectionLen());
    try std.testing.expectEqual(node_editor.BoxSelectScope.nodes_only, state.box_select_scope);
    try std.testing.expect(!state.box_selecting);
}

test "node editor view visible box selection clips viewport and rejects overflow atomically" {
    var selected_nodes = [_]u32{ 4, 0, 0 };
    var selected_connections = [_]node_editor.Connection{.{ .from_id = 1, .to_id = 4 }};
    var state = node_editor.State{
        .selected_node_ids = &selected_nodes,
        .selected_node_len = 1,
        .selected_node_id = 4,
        .selected_connections = &selected_connections,
        .selected_connection_len = 1,
        .selected_connection = selected_connections[0],
    };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ -140, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "B", .pos = .{ -40, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 3, .title = "C", .pos = .{ 60, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 4, .title = "outside", .pos = .{ -300, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    const connections = [_]node_editor.Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
        .{ .from_id = 1, .to_id = 4 },
    };
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, connections.len){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9425,
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .viewport_index = &viewport_index,
        .box_select_scope = .visible_only,
        .drag_auto_pan = .{ .enabled = false },
        .show_minimap = false,
        .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 240 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 240 };
    editor_node.input_shift_down = true;

    var overflow_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = 50, .y = 70 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &overflow_down, editor_node.paint_user_data));
    var overflow_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = 350, .y = 170 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &overflow_up, editor_node.paint_user_data));
    try std.testing.expectEqualSlices(u32, &.{4}, state.selected_node_ids[0..state.boundedSelectionLen()]);
    try std.testing.expectEqual(@as(usize, 1), state.boundedConnectionSelectionLen());
    try std.testing.expect(state.isConnectionSelected(connections[2]));
    try std.testing.expect(viewport_index.summary().valid);

    _ = state.clearSelection();
    var clipped_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = 40, .y = 60 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &clipped_down, editor_node.paint_user_data));
    var clipped_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = -120, .y = 180 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &clipped_up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 0), state.boundedSelectionLen());
    try std.testing.expectEqual(@as(usize, 1), state.boundedConnectionSelectionLen());
    try std.testing.expect(state.isConnectionSelected(connections[2]));
    try std.testing.expect(!state.box_selecting);
}

test "node editor view arrow keys navigate visible nodes and shift extends selection" {
    var selected: [3]u32 = .{0} ** 3;
    var state = node_editor.State{ .selected_node_ids = &selected };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "left", .pos = .{ -140, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "right", .pos = .{ 60, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 3, .title = "offscreen", .pos = .{ 260, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var canvas_state = zui.CanvasState{};
    var history = node_editor.History{};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9426,
        .canvas_state = &canvas_state,
        .state = &state,
        .nodes = &nodes,
        .viewport_index = &viewport_index,
        .history = &history,
        .spatial_navigation = .{ .enabled = true },
        .show_minimap = false,
        .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 240 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 240 };

    var initial = ElementEvent{ .key_down = .right };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &initial, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
    try std.testing.expect(viewport_index.summary().valid);

    var right = ElementEvent{ .key_down = .right };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
    try std.testing.expectEqual(@as(usize, 1), state.boundedSelectionLen());
    try std.testing.expectEqual(@as(usize, 1), state.navigation_candidate_count);

    editor_node.input_shift_down = true;
    var left = ElementEvent{ .key_down = .left };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &left, editor_node.paint_user_data));
    try std.testing.expectEqualSlices(u32, &.{ 2, 1 }, state.selected_node_ids[0..state.boundedSelectionLen()]);
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
    try std.testing.expectEqual(@as(u64, 3), state.navigation_move_count);
    try std.testing.expect(canvas_state.dirtySummary().invalidation.contains(.paint));
    try std.testing.expectEqual(@as(usize, 0), history.undo_len);

    editor_node.input_shift_down = false;
    editor_node.input_alt_down = true;
    try std.testing.expect(!nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
    editor_node.input_alt_down = false;
    editor_node.input_control_down = true;
    try std.testing.expect(!nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
}

test "node editor view leaves arrow keys unhandled when spatial navigation is disabled" {
    var state = node_editor.State{};
    const nodes = [_]node_editor.Node{.{ .id = 1, .title = "A", .pos = .{ 0, 0 } }};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 240, .h = 160 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 240, .h = 160 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9427, .state = &state, .nodes = &nodes, .show_minimap = false });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 240, .h = 160 };
    var right = ElementEvent{ .key_down = .right };
    try std.testing.expect(!nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, null), state.selected_node_id);
}

test "node editor view consumes enabled arrow navigation at an exhausted edge" {
    var selected = [_]u32{1};
    var state = node_editor.State{ .selected_node_ids = &selected, .selected_node_len = 1, .selected_node_id = 1 };
    const nodes = [_]node_editor.Node{.{ .id = 1, .title = "A", .pos = .{ 0, 0 } }};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 240, .h = 160 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 240, .h = 160 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9429, .state = &state, .nodes = &nodes, .spatial_navigation = .{ .enabled = true }, .show_minimap = false });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 240, .h = 160 };
    var right = ElementEvent{ .key_down = .right };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
    try std.testing.expectEqual(@as(u64, 0), state.navigation_move_count);

    state.dragging_canvas = true;
    var left = ElementEvent{ .key_down = .left };
    try std.testing.expect(!nodeEditorViewEvent(editor_node, &left, editor_node.paint_user_data));
    state.dragging_canvas = false;
    state.context_menu.open = true;
    try std.testing.expect(!nodeEditorViewEvent(editor_node, &left, editor_node.paint_user_data));
}

test "node editor view can navigate the full graph and reveal an offscreen target" {
    var selected = [_]u32{ 1, 0 };
    var state = node_editor.State{ .selected_node_ids = &selected, .selected_node_len = 1, .selected_node_id = 1 };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "visible", .pos = .{ 60, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "offscreen", .pos = .{ 260, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var canvas_state = zui.CanvasState{};
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9428,
        .canvas_state = &canvas_state,
        .state = &state,
        .nodes = &nodes,
        .viewport_index = &viewport_index,
        .spatial_navigation = .{ .enabled = true, .visible_only = false, .ensure_visible = true, .viewport_padding = 12 },
        .show_minimap = false,
        .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 240 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 240 };

    var right = ElementEvent{ .key_down = .right };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
    try std.testing.expect(state.pan[0] < 0);
    const revealed = node_editor.nodeRectFromState(editor_node.rect, state, nodes[1]);
    try std.testing.expect(revealed.x >= 12);
    try std.testing.expect(revealed.x + revealed.w <= editor_node.rect.w - 12);
    try std.testing.expect(canvas_state.dirtySummary().invalidation.contains(.viewport_transform));

    const pan_after_reveal = state.pan;
    try std.testing.expect(nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(pan_after_reveal, state.pan);
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
}

test "node editor view prefers topology along the configured flow axis" {
    var selected = [_]u32{ 1, 0, 0, 0 };
    var state = node_editor.State{ .selected_node_ids = &selected, .selected_node_len = 1, .selected_node_id = 1 };
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "source", .pos = .{ -140, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "unlinked near", .pos = .{ -20, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 3, .title = "linked diagonal", .pos = .{ 100, 80 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 4, .title = "linked aligned", .pos = .{ 360, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    const connections = [_]node_editor.Connection{
        .{ .from_id = 1, .to_id = 3 },
        .{ .from_id = 1, .to_id = 4 },
    };
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, connections.len){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var topology_storage = node_editor.StaticGraphTopologyWorkspace(nodes.len, connections.len){};
    var topology_index = node_editor.GraphTopologyIndex.init(topology_storage.workspace());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 600, .h = 240 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 600, .h = 240 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9430,
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .viewport_index = &viewport_index,
        .topology_index = &topology_index,
        .topology_revision = 1,
        .spatial_navigation = .{ .enabled = true, .flow_direction = .left_to_right },
        .show_minimap = false,
        .style = .{ .width = .{ .px = 600 }, .height = .{ .px = 240 } },
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 600, .h = 240 };

    var right = ElementEvent{ .key_down = .right };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 4), state.selected_node_id);
    try std.testing.expect(state.pan[0] < 0);
    const revealed = node_editor.nodeRectFromState(editor_node.rect, state, nodes[3]);
    try std.testing.expect(revealed.x + revealed.w <= editor_node.rect.w - 16);
    try std.testing.expectEqual(@as(usize, 2), state.navigation_candidate_count);
    try std.testing.expectEqual(@as(u64, 1), state.navigation_topology_hit_count);
    try std.testing.expectEqual(@as(u64, 1), topology_index.summary().rebuild_count);

    var left = ElementEvent{ .key_down = .left };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &left, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
    try std.testing.expectEqual(@as(u64, 2), state.navigation_topology_hit_count);
    try std.testing.expectEqual(@as(u64, 1), topology_index.summary().rebuild_count);
    try std.testing.expect(topology_index.summary().cache_hit_count > 0);
    try std.testing.expectEqual(@as(u64, 2), topology_index.summary().direct_neighbor_query_count);

    _ = state.setSingleSelection(2);
    try std.testing.expect(nodeEditorViewEvent(editor_node, &right, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(?u32, 4), state.selected_node_id);
    try std.testing.expectEqual(@as(u64, 1), state.navigation_spatial_fallback_count);
}

test "node editor topology navigation follows reversed and vertical flow directions" {
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "source", .pos = .{ 100, 100 }, .size = .{ .w = 40, .h = 40 } },
        .{ .id = 2, .title = "target", .pos = .{ 0, 0 }, .size = .{ .w = 40, .h = 40 } },
    };
    const connections = [_]node_editor.Connection{.{ .from_id = 1, .to_id = 2 }};
    var selected = [_]u32{ 1, 0 };
    var state = node_editor.State{ .selected_node_ids = &selected, .selected_node_len = 1, .selected_node_id = 1 };
    var topology_storage = node_editor.StaticGraphTopologyWorkspace(nodes.len, connections.len){};
    var topology = node_editor.GraphTopologyIndex.init(topology_storage.workspace());
    try std.testing.expect(topology.ensure(&nodes, &connections).complete());

    try std.testing.expect(state.navigateNodeSelectionTopology(&nodes, &topology, .left, .right_to_left, false));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
    _ = state.setSingleSelection(1);
    try std.testing.expect(state.navigateNodeSelectionTopology(&nodes, &topology, .down, .top_to_bottom, false));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
    _ = state.setSingleSelection(2);
    try std.testing.expect(state.navigateNodeSelectionTopology(&nodes, &topology, .up, .top_to_bottom, false));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
    _ = state.setSingleSelection(1);
    try std.testing.expect(state.navigateNodeSelectionTopology(&nodes, &topology, .up, .bottom_to_top, false));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
    _ = state.setSingleSelection(2);
    try std.testing.expect(state.navigateNodeSelectionTopology(&nodes, &topology, .down, .bottom_to_top, false));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
}

test "node editor direct connection mutation invalidates topology navigation cache" {
    var state = node_editor.State{};
    const nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ -100, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 100, 0 } },
    };
    var connections = [_]node_editor.Connection{node_editor.Connection{ .from_id = 0, .to_id = 0 }};
    var connection_len: usize = 0;
    var topology_storage = node_editor.StaticGraphTopologyWorkspace(nodes.len, connections.len){};
    var topology = node_editor.GraphTopologyIndex.init(topology_storage.workspace());
    try std.testing.expect(topology.ensureVersioned(&nodes, connections[0..connection_len], 9).complete());
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 400, .h = 200 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 400, .h = 200 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{
        .tag = 9431,
        .state = &state,
        .nodes = &nodes,
        .mutable_connections = &connections,
        .mutable_connection_len = &connection_len,
        .topology_index = &topology,
        .topology_revision = 9,
        .show_minimap = false,
    });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 400, .h = 200 };
    const output = node_editor.outputPortPosition(editor_node.rect, state, nodes[0]);
    const input = node_editor.inputPortPosition(editor_node.rect, state, nodes[1]);
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = output[0], .y = output[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down, editor_node.paint_user_data));
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = input[0], .y = input[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up, editor_node.paint_user_data));
    try std.testing.expectEqual(@as(usize, 1), connection_len);
    try std.testing.expect(!topology.summary().valid);
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
