//! Devtools summaries and lightweight panel for zui-nodes.
//!
//! The node editor model/view live in this extension, so diagnostics for node
//! counts, selection, hover/drag state and minimap status should live here too
//! rather than in Zui core.

const std = @import("std");
const zui = @import("zui");
const node_editor = @import("node_editor.zig");

pub const Node = node_editor.Node;
pub const Connection = node_editor.Connection;
pub const Group = node_editor.Group;
pub const State = node_editor.State;
pub const MinimapSnapshot = node_editor.MinimapSnapshot;
pub const Rect = zui.Rect;
pub const ElementNode = zui.ElementNode;
pub const ViewContext = zui.ViewContext;
pub const Style = zui.Style;

pub const SummaryOptions = struct {
    state: *const State,
    nodes: []const Node = &.{},
    connections: []const Connection = &.{},
    groups: []const Group = &.{},
    viewport: Rect = .zero,
    minimap_size: zui.ui_base.Size = .{ .w = 150, .h = 96 },
    connection_path_cache: ?*const node_editor.ConnectionPathCache = null,
};

pub const Summary = struct {
    node_count: usize = 0,
    connection_count: usize = 0,
    group_count: usize = 0,
    selected_node_count: usize = 0,
    selected_node_id: ?u32 = null,
    selected_group_id: ?u32 = null,
    has_selected_connection: bool = false,
    hover_node_id: ?u32 = null,
    hover_group_id: ?u32 = null,
    dragging: bool = false,
    dragging_minimap: bool = false,
    zoom: f32 = 1.0,
    pan: [2]f32 = .{ 0, 0 },
    minimap: MinimapSnapshot = .{},
    connection_path_cache: node_editor.ConnectionPathCacheSummary = .{},

    pub fn hasSelection(self: Summary) bool {
        return self.selected_node_count > 0 or self.selected_group_id != null or self.has_selected_connection;
    }

    pub fn statusText(self: Summary) []const u8 {
        if (self.dragging) return "dragging";
        if (self.hasSelection()) return "selected";
        if (self.node_count == 0) return "empty";
        return "active";
    }
};

pub const PanelOptions = struct {
    summary: Summary,
    title: []const u8 = "Node Devtools",
    width: f32 = 280,
    row_height: f32 = 18,
    style: Style = .{},
};

pub fn summarize(options: SummaryOptions) Summary {
    const state = options.state;
    const minimap = node_editor.minimapSnapshot(options.viewport, state.*, options.nodes, options.groups, options.minimap_size);
    return .{
        .node_count = options.nodes.len,
        .connection_count = options.connections.len,
        .group_count = options.groups.len,
        .selected_node_count = state.boundedSelectionLen(),
        .selected_node_id = state.selected_node_id,
        .selected_group_id = state.selected_group_id,
        .has_selected_connection = state.selected_connection != null,
        .hover_node_id = state.hover_node_id,
        .hover_group_id = state.hover_group_id,
        .dragging = state.dragging_canvas or state.dragging_node_id != null or state.dragging_group_id != null or state.dragging_connection_from_id != null or state.resizing_group_id != null or state.box_selecting or state.dragging_minimap,
        .dragging_minimap = state.dragging_minimap,
        .zoom = state.zoom,
        .pan = state.pan,
        .minimap = minimap,
        .connection_path_cache = if (options.connection_path_cache) |cache| cache.summary() else .{},
    };
}

pub fn panel(ctx: *ViewContext, options: PanelOptions) !*ElementNode {
    const root = try ctx.panelSurface(.{
        .gap = 5,
        .padding = zui.Edges.all(8),
        .background = ctx.theme().surface_alt,
        .border_color = ctx.theme().border,
        .border_width = 0.75,
        .border_radius = 8,
        .style = panelStyle(options.style, options.width),
    });
    const title = try ctx.label(options.title, .{
        .font_size = 12,
        .font_weight = 700,
        .color = ctx.theme().text,
        .height = .{ .px = options.row_height },
        .line_height = options.row_height,
    });
    const counts = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "nodes={d} links={d} groups={d} status={s}", .{
        options.summary.node_count,
        options.summary.connection_count,
        options.summary.group_count,
        options.summary.statusText(),
    }), .{ .font_size = 10, .color = ctx.theme().text_muted, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const selection = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "selection={d} node={?d} group={?d} conn={}", .{
        options.summary.selected_node_count,
        options.summary.selected_node_id,
        options.summary.selected_group_id,
        options.summary.has_selected_connection,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const viewport = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "zoom={d:.2} pan={d:.1},{d:.1} minimap={}", .{
        options.summary.zoom,
        options.summary.pan[0],
        options.summary.pan[1],
        options.summary.minimap.visible,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const path_cache = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "paths={d} hits={d} misses={d} rebuilds={d}", .{
        options.summary.connection_path_cache.entry_count,
        options.summary.connection_path_cache.hit_count,
        options.summary.connection_path_cache.miss_count,
        options.summary.connection_path_cache.rebuild_count,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    try ctx.children(root, .{ title, counts, selection, viewport, path_cache });
    return root;
}

fn panelStyle(base: Style, width: f32) Style {
    var style = base;
    style.direction = .column;
    style.width = .{ .px = width };
    return style;
}

test "zui-nodes devtools summarize node editor state" {
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected, .zoom = 1.25, .pan = .{ 12, -4 } };
    const nodes = [_]Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 160, 64 } },
    };
    const connections = [_]Connection{.{ .from_id = 1, .to_id = 2 }};
    var path_cache = node_editor.ConnectionPathCache{};
    _ = path_cache.pathFor(.{ 0, 0 }, .{ 100, 20 });
    _ = path_cache.pathFor(.{ 0, 0 }, .{ 100, 20 });
    try std.testing.expect(state.setSingleSelection(2));
    const summary = summarize(.{
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .viewport = .{ .x = 0, .y = 0, .w = 360, .h = 220 },
        .connection_path_cache = &path_cache,
    });
    try std.testing.expectEqual(@as(usize, 2), summary.node_count);
    try std.testing.expectEqual(@as(usize, 1), summary.connection_count);
    try std.testing.expect(summary.hasSelection());
    try std.testing.expect(summary.minimap.visible);
    try std.testing.expectEqual(@as(u64, 1), summary.connection_path_cache.hit_count);
    try std.testing.expectEqualStrings("selected", summary.statusText());
}
