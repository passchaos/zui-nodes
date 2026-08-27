//! Devtools summaries and lightweight panel for zui-nodes.
//!
//! The node editor model/view live in this extension, so diagnostics for node
//! counts, selection, hover/drag state and minimap status should live here too
//! rather than in Zui core.

const std = @import("std");
const zui = @import("zui");
const graph_topology = @import("graph_topology.zig");
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
    connection_draw_workspace: ?*const node_editor.ConnectionDrawWorkspace = null,
    topology_index: ?*graph_topology.Index = null,
    viewport_index: ?*node_editor.ViewportIndex = null,
    geometry_revision: ?u64 = null,
    semantic_zoom: node_editor.SemanticZoomOptions = .{},
    drag_auto_pan: node_editor.DragAutoPanOptions = .{},
    drag_snap: node_editor.DragSnapOptions = .{},
    alignment_snap: node_editor.AlignmentSnapOptions = .{},
    distribution_snap: node_editor.DistributionSnapOptions = .{},
    history: ?*const node_editor.History = null,
    connection_policy: node_editor.ConnectionPolicy = .default,
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
    detail_level: node_editor.DetailLevel = .full,
    drag_auto_pan_enabled: bool = false,
    drag_auto_pan_active: bool = false,
    drag_snap_enabled: bool = false,
    drag_snap_active: bool = false,
    alignment_snap_enabled: bool = false,
    alignment_snap_active: bool = false,
    distribution_snap_enabled: bool = false,
    distribution_snap_active: bool = false,
    snap_guide_x: ?f32 = null,
    snap_guide_y: ?f32 = null,
    pan: [2]f32 = .{ 0, 0 },
    minimap: MinimapSnapshot = .{},
    connection_path_cache: node_editor.ConnectionPathCacheSummary = .{},
    connection_draw: node_editor.ConnectionDrawSummary = .{},
    topology: graph_topology.Summary = .{},
    viewport_index: node_editor.ViewportSummary = .{},
    history: node_editor.HistorySummary = .{},
    graph_validation: node_editor.GraphValidationReport = .{},
    graph_valid: bool = true,
    graph_issue_count: usize = 0,

    pub fn hasSelection(self: Summary) bool {
        return self.selected_node_count > 0 or self.selected_group_id != null or self.has_selected_connection;
    }

    pub fn statusText(self: Summary) []const u8 {
        if (!self.graph_valid) return "invalid";
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
    const graph_report = node_editor.validateGraph(options.nodes, options.connections, options.connection_policy);
    if (options.topology_index) |topology| _ = topology.ensure(options.nodes, options.connections);
    if (options.viewport_index) |viewport_index| {
        _ = if (options.geometry_revision) |revision|
            viewport_index.prepareVersioned(options.nodes, options.groups, options.connections, options.viewport, state.pan, state.zoom, revision)
        else
            viewport_index.prepare(options.nodes, options.groups, options.connections, options.viewport, state.pan, state.zoom);
    }
    const minimap = if (options.viewport_index) |viewport_index|
        if (viewport_index.graphBounds()) |bounds|
            node_editor.minimapSnapshotFromGraphBounds(options.viewport, state.*, node_editor.paddedBounds(bounds, 0.12), options.minimap_size)
        else
            node_editor.minimapSnapshot(options.viewport, state.*, options.nodes, options.groups, options.minimap_size)
    else
        node_editor.minimapSnapshot(options.viewport, state.*, options.nodes, options.groups, options.minimap_size);
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
        .detail_level = node_editor.semanticDetailLevel(state.*, options.semantic_zoom),
        .drag_auto_pan_enabled = options.drag_auto_pan.enabled,
        .drag_auto_pan_active = state.dragging_node_id != null or state.dragging_group_id != null or state.resizing_group_id != null or state.dragging_connection_from_id != null or state.reconnecting_connection != null or state.box_selecting,
        .drag_snap_enabled = options.drag_snap.enabled,
        .drag_snap_active = state.dragging_node_id != null and
            ((state.snap_guide_x != null and state.snap_guide_x_span == null) or
                (state.snap_guide_y != null and state.snap_guide_y_span == null)),
        .alignment_snap_enabled = options.alignment_snap.enabled,
        .alignment_snap_active = state.dragging_node_id != null and (state.snap_guide_x_span != null or state.snap_guide_y_span != null),
        .distribution_snap_enabled = options.distribution_snap.enabled,
        .distribution_snap_active = state.dragging_node_id != null and (state.spacing_guide_x != null or state.spacing_guide_y != null),
        .snap_guide_x = state.snap_guide_x,
        .snap_guide_y = state.snap_guide_y,
        .pan = state.pan,
        .minimap = minimap,
        .connection_path_cache = if (options.connection_path_cache) |cache| cache.summary() else .{},
        .connection_draw = if (options.connection_draw_workspace) |workspace| workspace.summary() else .{},
        .topology = if (options.topology_index) |topology| topology.summary() else .{},
        .viewport_index = if (options.viewport_index) |viewport_index| viewport_index.summary() else .{},
        .history = if (options.history) |history| history.summary() else .{},
        .graph_validation = graph_report,
        .graph_valid = graph_report.validFor(options.connection_policy),
        .graph_issue_count = graph_report.issueCountFor(options.connection_policy),
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
    const viewport = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "zoom={d:.2} detail={s} pan={d:.1},{d:.1} minimap={}", .{
        options.summary.zoom,
        @tagName(options.summary.detail_level),
        options.summary.pan[0],
        options.summary.pan[1],
        options.summary.minimap.visible,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const auto_pan = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "auto-pan enabled={} active={}", .{
        options.summary.drag_auto_pan_enabled,
        options.summary.drag_auto_pan_active,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const drag_snap = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "snap grid={} align={} distribute={} active={}/{}/{} guides={?d:.1},{?d:.1}", .{
        options.summary.drag_snap_enabled,
        options.summary.alignment_snap_enabled,
        options.summary.distribution_snap_enabled,
        options.summary.drag_snap_active,
        options.summary.alignment_snap_active,
        options.summary.distribution_snap_active,
        options.summary.snap_guide_x,
        options.summary.snap_guide_y,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const path_cache = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "paths={d} hits={d} misses={d} rebuilds={d}", .{
        options.summary.connection_path_cache.entry_count,
        options.summary.connection_path_cache.hit_count,
        options.summary.connection_path_cache.miss_count,
        options.summary.connection_path_cache.rebuild_count,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const connection_draw = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "connection draw capacity={d} borrowed={d} fallback={d} frames={d}", .{
        options.summary.connection_draw.capacity,
        options.summary.connection_draw.borrowed_connection_count,
        options.summary.connection_draw.fallback_connection_count,
        options.summary.connection_draw.frame_count,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const graph = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "graph valid={} issues={d} dup={d} fanin={d} orphan={d} port={d} type={d} cycle={d}", .{
        options.summary.graph_valid,
        options.summary.graph_issue_count,
        options.summary.graph_validation.duplicate_connection_count,
        options.summary.graph_validation.input_fan_in_count,
        options.summary.graph_validation.orphan_connection_count,
        options.summary.graph_validation.invalid_port_count,
        options.summary.graph_validation.incompatible_port_type_count,
        options.summary.graph_validation.cycle_count,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const topology = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "topology indexed={d}/{d} rebuilds={d} hits={d} valid={}", .{
        options.summary.topology.indexed_connection_count,
        options.summary.topology.connection_count,
        options.summary.topology.rebuild_count,
        options.summary.topology.cache_hit_count,
        options.summary.topology.valid,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const viewport_index = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "viewport nodes={d}/{d} groups={d}/{d} links={d}/{d} rebuilds={d} queries={d} geometry_reuse={d} viewport_reuse={d} valid={}", .{
        options.summary.viewport_index.visible_node_count,
        options.summary.viewport_index.node_count,
        options.summary.viewport_index.visible_group_count,
        options.summary.viewport_index.group_count,
        options.summary.viewport_index.visible_connection_count,
        options.summary.viewport_index.connection_count,
        options.summary.viewport_index.rebuild_count,
        options.summary.viewport_index.query_count,
        options.summary.viewport_index.geometry_reuse_count,
        options.summary.viewport_index.viewport_reuse_count,
        options.summary.viewport_index.valid,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    const history = try ctx.label(try std.fmt.allocPrint(ctx.allocator, "history bound={} undo={d} redo={d} nodes={d} links={d} rejected={d} dropped={d}", .{
        options.summary.history.available,
        options.summary.history.undo_len,
        options.summary.history.redo_len,
        options.summary.history.node_capacity,
        options.summary.history.connection_capacity,
        options.summary.history.rejected_snapshot_count,
        options.summary.history.dropped_snapshot_count,
    }), .{ .font_size = 10, .color = ctx.theme().text_subtle, .height = .{ .px = options.row_height }, .line_height = options.row_height, .text_overflow = .ellipsis });
    try ctx.children(root, .{ title, counts, selection, viewport, auto_pan, drag_snap, path_cache, connection_draw, topology, viewport_index, history, graph });
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
    try std.testing.expectEqual(node_editor.DetailLevel.full, summary.detail_level);
    try std.testing.expectEqualStrings("selected", summary.statusText());
}

test "zui-nodes devtools exposes active drag snap guides" {
    var selected = [_]u32{ 1, 0, 0, 0 };
    var state = State{
        .selected_node_ids = &selected,
        .selected_node_len = 1,
        .selected_node_id = 1,
        .dragging_node_id = 1,
        .snap_guide_x = 32,
        .snap_guide_x_span = .{ 0, 80 },
        .snap_guide_y = 16,
    };
    const summary = summarize(.{
        .state = &state,
        .nodes = &.{.{ .id = 1, .title = "A", .pos = .{ 0, 0 } }},
        .drag_snap = .{ .enabled = true, .spacing = .{ 16, 16 }, .threshold_pixels = 5 },
        .alignment_snap = .{ .enabled = true },
        .distribution_snap = .{ .enabled = true },
    });
    try std.testing.expect(summary.drag_snap_enabled);
    try std.testing.expect(summary.drag_snap_active);
    try std.testing.expect(summary.alignment_snap_enabled);
    try std.testing.expect(summary.alignment_snap_active);
    try std.testing.expect(summary.distribution_snap_enabled);
    try std.testing.expectEqual(@as(?f32, 32), summary.snap_guide_x);
    try std.testing.expectEqual(@as(?f32, 16), summary.snap_guide_y);
}

test "zui-nodes devtools reports strict graph validation issues" {
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 120, 0 } },
    };
    const connections = [_]Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 1 },
    };
    const summary = summarize(.{
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .connection_policy = .strict_dataflow,
    });
    try std.testing.expectEqual(@as(usize, 2), summary.graph_validation.cycle_count);
    try std.testing.expect(!summary.graph_validation.validFor(.strict_dataflow));
    try std.testing.expectEqualStrings("invalid", summary.statusText());
}

test "zui-nodes devtools exposes topology index reuse" {
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 120, 0 } },
    };
    const connections = [_]Connection{.{ .from_id = 1, .to_id = 2 }};
    var topology_storage = graph_topology.StaticWorkspace(4, 4){};
    var topology = graph_topology.Index.init(topology_storage.workspace());
    var history = node_editor.History{};
    try std.testing.expect(topology.ensure(&nodes, &connections).complete());
    try std.testing.expect(topology.ensure(&nodes, &connections).cache_hit);

    const summary = summarize(.{
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .topology_index = &topology,
        .history = &history,
    });
    try std.testing.expect(summary.topology.valid);
    try std.testing.expectEqual(@as(usize, 1), summary.topology.indexed_connection_count);
    try std.testing.expectEqual(@as(u64, 1), summary.topology.rebuild_count);
    try std.testing.expectEqual(@as(u64, 2), summary.topology.cache_hit_count);
    try std.testing.expect(summary.history.available);
    try std.testing.expectEqual(@as(usize, 16), summary.history.node_capacity);
}

test "zui-nodes devtools exposes viewport culling and reuse" {
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "visible", .pos = .{ -40, -20 } },
        .{ .id = 2, .title = "culled", .pos = .{ 1000, 0 } },
    };
    const connections = [_]Connection{.{ .from_id = 1, .to_id = 2 }};
    var viewport_storage = node_editor.StaticViewportWorkspace(nodes.len, 0, connections.len){};
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var draw_storage = node_editor.StaticConnectionDrawWorkspace(connections.len){};
    var draw_workspace = draw_storage.workspace();
    const viewport = Rect{ .x = 0, .y = 0, .w = 320, .h = 180 };

    _ = summarize(.{
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .viewport = viewport,
        .viewport_index = &viewport_index,
        .connection_draw_workspace = &draw_workspace,
        .geometry_revision = 4,
    });
    const summary = summarize(.{
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .viewport = viewport,
        .viewport_index = &viewport_index,
        .connection_draw_workspace = &draw_workspace,
        .geometry_revision = 4,
    });
    try std.testing.expect(summary.viewport_index.valid);
    try std.testing.expectEqual(@as(usize, 1), summary.viewport_index.visible_node_count);
    try std.testing.expectEqual(@as(usize, 2), summary.viewport_index.node_count);
    try std.testing.expectEqual(@as(u64, 1), summary.viewport_index.rebuild_count);
    try std.testing.expectEqual(@as(u64, 1), summary.viewport_index.viewport_reuse_count);
    try std.testing.expectEqual(connections.len, summary.connection_draw.capacity);
    try std.testing.expect(summary.connection_draw.allocationFree());
}
