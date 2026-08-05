//! Zui view adapter for the zui-nodes extension.
//!
//! The extension owns node graph/editor UI.  Zui core only provides reusable
//! primitives such as custom paint, event bubbling and layout nodes.

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

pub const NodeEditorViewOptions = struct {
    tag: u32 = 0,
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
    clipboard: ?*node_editor.Clipboard = null,
    style: Style = .{},
};

const Binding = struct {
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
    clipboard: ?*node_editor.Clipboard = null,

    fn editor(self: *Binding) node_editor.Options(node_editor.State) {
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
            .clipboard = self.clipboard,
        };
    }
};

pub fn nodeEditorView(ctx: *ViewContext, options: NodeEditorViewOptions) !*ElementNode {
    const binding = try ctx.allocator.create(Binding);
    binding.* = .{
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
        .clipboard = options.clipboard,
    };
    var style = options.style;
    if (style.background.a == 0 and style.background_paint == .none) style.background = options.background;
    const node = try ctx.customPaint(paintNodeEditor, binding, style);
    node.id = options.tag;
    node.focusable = true;
    ctx.setEventHandler(node, nodeEditorViewEvent, binding);
    return node;
}

fn paintNodeEditor(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, layer: i32, user_data: ?*anyopaque) anyerror!void {
    const binding: *Binding = if (user_data) |ptr| @ptrCast(@alignCast(ptr)) else return;
    _ = try node_editor.appendNodeEditor(allocator, out, rect, binding.editor(), layer);
}

fn nodeEditorViewEvent(node: *ElementNode, event: *ElementEvent) bool {
    const binding: *Binding = if (node.user_data) |ptr| @ptrCast(@alignCast(ptr)) else return false;
    const editor = binding.editor();
    return node_editor.handleEditorEvent(node.rect, .{
        .shift_down = node.input_shift_down,
        .control_down = node.input_control_down,
        .super_down = node.input_super_down,
        .alt_down = node.input_alt_down,
    }, editor, event);
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
    try std.testing.expect(nodeEditorViewEvent(node, &event));
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
}

test "node editor view drags mutable nodes" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "Input", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "Output", .pos = .{ 180, 80 } },
    };
    var view = try zui.View.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 360, .h = 220 }, 0);
    defer view.deinit();
    var ctx = ViewContext{ .allocator = view.arena.allocator(), .view = &view, .constraints = .{ .min = .{ .w = 0, .h = 0 }, .max = .{ .w = 360, .h = 220 } }, .user = null };
    const editor_node = try nodeEditorView(&ctx, .{ .tag = 9402, .state = &state, .nodes = &nodes, .mutable_nodes = &nodes, .style = .{ .width = .{ .px = 340 }, .height = .{ .px = 200 } } });
    editor_node.rect = .{ .x = 0, .y = 0, .w = 340, .h = 200 };
    const before = nodes[1].pos;
    const node_rect = node_editor.nodeRectFromState(.{ .x = 0, .y = 0, .w = 340, .h = 200 }, state, nodes[1]);
    const start = [2]f32{ node_rect.x + node_rect.w * 0.5, node_rect.y + node_rect.h * 0.5 };
    var down = ElementEvent{ .mouse_down = .{ .button = .left, .x = start[0], .y = start[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down));
    var move = ElementEvent{ .mouse_move = .{ .x = start[0] + 24, .y = start[1] + 12, .dx = 24, .dy = 12 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move));
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = start[0] + 24, .y = start[1] + 12 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
    try std.testing.expect(nodes[1].pos[0] > before[0]);
    try std.testing.expect(nodes[1].pos[1] > before[1]);
    try std.testing.expect(state.dragging_node_id == null);
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
    try std.testing.expect(nodeEditorViewEvent(editor_node, &down));
    var move = ElementEvent{ .mouse_move = .{ .x = in[0], .y = in[1], .dx = in[0] - out[0], .dy = in[1] - out[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &move));
    var up = ElementEvent{ .mouse_up = .{ .button = .left, .x = in[0], .y = in[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &up));
    try std.testing.expectEqual(@as(usize, 1), connection_len);
    try std.testing.expectEqual(node_editor.Connection{ .from_id = 1, .to_id = 2 }, connections[0]);
    try std.testing.expectEqual(@as(?node_editor.Connection, connections[0]), state.selected_connection);
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
    try std.testing.expect(nodeEditorViewEvent(editor_node, &minimap_down));
    var minimap_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = minimap_point[0], .y = minimap_point[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &minimap_up));
    try std.testing.expect(@abs(state.pan[0] - pan_before[0]) > 0.001 or @abs(state.pan[1] - pan_before[1]) > 0.001);

    state.pan = .{ 0, 0 };
    state.zoom = 1;
    editor_node.input_shift_down = true;
    const n0 = node_editor.nodeRectFromState(editor_node.rect, state, nodes[0]);
    const n1 = node_editor.nodeRectFromState(editor_node.rect, state, nodes[1]);
    var box_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = n0.x - 8, .y = n0.y - 8 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &box_down));
    var box_move = ElementEvent{ .mouse_move = .{ .x = n1.x + n1.w + 8, .y = n1.y + n1.h + 8, .dx = n1.x - n0.x, .dy = n1.y - n0.y } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &box_move));
    var box_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = n1.x + n1.w + 8, .y = n1.y + n1.h + 8 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &box_up));
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
    try std.testing.expect(nodeEditorViewEvent(editor_node, &group_down));
    var group_move = ElementEvent{ .mouse_move = .{ .x = group_start[0] + 18, .y = group_start[1] + 9, .dx = 18, .dy = 9 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &group_move));
    var group_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = group_start[0] + 18, .y = group_start[1] + 9 } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &group_up));
    try std.testing.expectEqual(@as(?u32, 8), state.selected_group_id);
    try std.testing.expect(groups[0].rect.x > -175);
    try std.testing.expect(history.undo_len > 0);

    try std.testing.expect(state.setConnectionSelection(connections[0]));
    const input2 = node_editor.inputPortPosition(editor_node.rect, state, nodes[1]);
    const input3 = node_editor.inputPortPosition(editor_node.rect, state, nodes[2]);
    var reconnect_down = ElementEvent{ .mouse_down = .{ .button = .left, .x = input2[0], .y = input2[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &reconnect_down));
    var reconnect_move = ElementEvent{ .mouse_move = .{ .x = input3[0], .y = input3[1], .dx = input3[0] - input2[0], .dy = input3[1] - input2[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &reconnect_move));
    var reconnect_up = ElementEvent{ .mouse_up = .{ .button = .left, .x = input3[0], .y = input3[1] } };
    try std.testing.expect(nodeEditorViewEvent(editor_node, &reconnect_up));
    try std.testing.expectEqual(node_editor.Connection{ .from_id = 1, .to_id = 3 }, connections[0]);
    try std.testing.expectEqual(@as(?node_editor.Connection, connections[0]), state.selected_connection);
}
