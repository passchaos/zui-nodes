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
    switch (event.*) {
        .mouse_move => |mouse| {
            const hit = node_editor.nodeAtPoint(node.rect, editor.state.*, editor.nodes, .{ mouse.x, mouse.y });
            const hover_id = if (hit) |index| editor.nodes[index].id else null;
            const changed = editor.state.hover_node_id != hover_id;
            editor.state.hover_node_id = hover_id;
            return changed;
        },
        .mouse_leave => {
            const changed = editor.state.hover_node_id != null;
            editor.state.hover_node_id = null;
            return changed;
        },
        .mouse_down => |mouse| {
            if (mouse.button == .right) {
                const point = [2]f32{ mouse.x, mouse.y };
                if (node_editor.nodeAtPoint(node.rect, editor.state.*, editor.nodes, point)) |index| {
                    const id = editor.nodes[index].id;
                    _ = editor.state.setSingleSelection(id);
                    editor.state.context_menu.node_id = id;
                    return editor.state.openContextMenu(.node, point);
                }
                return editor.state.openContextMenu(.canvas, point);
            }
            if (mouse.button != .left) return false;
            const point = [2]f32{ mouse.x, mouse.y };
            if (node_editor.nodeAtPoint(node.rect, editor.state.*, editor.nodes, point)) |index| {
                return editor.state.setSingleSelection(editor.nodes[index].id);
            }
            return editor.state.clearSelection();
        },
        else => return false,
    }
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
    try std.testing.expectEqual(@as(u32, 9401), node.id);
    try std.testing.expect(node.focusable);
    const node_rect = node_editor.nodeRectFromState(.{ .x = 0, .y = 0, .w = 300, .h = 160 }, state, nodes[0]);
    const click = [2]f32{ node_rect.x + node_rect.w * 0.5, node_rect.y + node_rect.h * 0.5 };
    var event = ElementEvent{ .mouse_down = .{ .button = .left, .x = click[0], .y = click[1] } };
    try std.testing.expect(nodeEditorViewEvent(node, &event));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);
}
