const std = @import("std");
const zui = @import("zui");
const draw_cmd = zui.ui_draw_cmd;
const paint_primitives = zui.ui_paint_primitives;
const ui_base = zui.ui_base;
const command_search = zui.ui_command_search;
const commands_mod = @import("commands.zig");
const menu_mod = zui.ui_menu;
const graph_validation = @import("graph_validation.zig");
const graph_topology = @import("graph_topology.zig");
const viewport_types = @import("node_viewport.zig").Types(Node, Group, Connection, Rect);

const render = struct {
    pub const PathCommand = zui.RenderPathCommand;
};

const Color = ui_base.Color;
const Rect = ui_base.Rect;
const Size = ui_base.Size;
const DrawCmd = draw_cmd.DrawCmd;

pub const GroupResizeEdges = packed struct {
    left: bool = false,
    right: bool = false,
    top: bool = false,
    bottom: bool = false,

    pub fn any(self: GroupResizeEdges) bool {
        return self.left or self.right or self.top or self.bottom;
    }

    pub fn horizontal(self: GroupResizeEdges) bool {
        return self.left or self.right;
    }
};

pub const ContextTarget = enum {
    canvas,
    node,
    group,
    connection,
    input_port,
    output_port,
};

pub const Connection = struct {
    from_id: u32,
    to_id: u32,
    from_port: u8 = 0,
    to_port: u8 = 0,
    color: Color = Color.rgba8(59, 130, 246, 190),
};

pub const ConnectionPolicy = graph_validation.ConnectionPolicy;
pub const ConnectionValidation = graph_validation.ConnectionValidation;
pub const ConnectionValidationOptions = graph_validation.ConnectionValidationOptions;
pub const GraphValidationReport = graph_validation.GraphValidationReport;
pub const ViewportWorkspace = viewport_types.Workspace;
pub const ViewportStorage = viewport_types.Storage;
pub const StaticViewportWorkspace = viewport_types.StaticWorkspace;
pub const ViewportPrepareResult = viewport_types.PrepareResult;
pub const ViewportSummary = viewport_types.Summary;
pub const ViewportIndex = viewport_types.Index;

pub const ConnectedSelectionResult = struct {
    traversal: graph_topology.TraversalResult = .{},
    changed: bool = false,

    pub fn complete(self: ConnectedSelectionResult) bool {
        return self.traversal.complete();
    }
};

pub const DetailLevel = enum(u8) {
    overview,
    compact,
    full,
};

pub const SemanticZoomMode = enum(u8) {
    adaptive,
    full,
};

pub const SemanticZoomOptions = struct {
    mode: SemanticZoomMode = .adaptive,
    compact_min_zoom: f32 = 0.4,
    full_min_zoom: f32 = 0.75,

    pub fn detailLevel(self: SemanticZoomOptions, zoom_value: f32) DetailLevel {
        if (self.mode == .full) return .full;
        const compact_min = @max(0.0, self.compact_min_zoom);
        const full_min = @max(compact_min, self.full_min_zoom);
        const zoom = @max(0.0, zoom_value);
        if (zoom < compact_min) return .overview;
        if (zoom < full_min) return .compact;
        return .full;
    }
};

pub fn semanticDetailLevel(state: anytype, options: SemanticZoomOptions) DetailLevel {
    const detail = options.detailLevel(state.zoom);
    if (detail == .overview and (state.dragging_connection_from_id != null or state.reconnecting_connection != null)) return .compact;
    return detail;
}

pub const ConnectionEnd = enum {
    from,
    to,
};

pub const ContextMenuState = struct {
    open: bool = false,
    target: ContextTarget = .canvas,
    node_id: ?u32 = null,
    group_id: ?u32 = null,
    connection: ?Connection = null,
    port_index: u8 = 0,
    screen_pos: [2]f32 = .{ 0.0, 0.0 },

    pub fn openAt(self: *ContextMenuState, target: ContextTarget, screen_pos: [2]f32) void {
        self.open = true;
        self.target = target;
        self.screen_pos = screen_pos;
    }

    pub fn close(self: *ContextMenuState) bool {
        if (!self.open) return false;
        self.open = false;
        self.node_id = null;
        self.group_id = null;
        self.connection = null;
        self.port_index = 0;
        return true;
    }

    pub fn anchor(self: ContextMenuState) Rect {
        return .{ .x = self.screen_pos[0], .y = self.screen_pos[1], .w = 1.0, .h = 1.0 };
    }
};

pub const Clipboard = struct {
    nodes: [32]Node = undefined,
    node_len: usize = 0,
    connections: [64]Connection = undefined,
    connection_len: usize = 0,
    source_ids: [32]u32 = .{0} ** 32,
    copied_bounds: Rect = .zero,
    paste_count: u32 = 0,

    pub fn clear(self: *Clipboard) void {
        self.node_len = 0;
        self.connection_len = 0;
        self.source_ids = .{0} ** self.source_ids.len;
        self.copied_bounds = .zero;
        self.paste_count = 0;
    }

    pub fn hasNodes(self: Clipboard) bool {
        return self.node_len > 0;
    }
};

pub const InspectorSnapshot = struct {
    selected_node_count: usize = 0,
    selected_group_id: ?u32 = null,
    selected_connection: ?Connection = null,
    title: []const u8 = "Canvas",
    bounds: ?Rect = null,
    input_count: usize = 0,
    output_count: usize = 0,
    incoming_links: usize = 0,
    outgoing_links: usize = 0,

    pub fn hasSelection(self: InspectorSnapshot) bool {
        return self.selected_node_count > 0 or self.selected_group_id != null or self.selected_connection != null;
    }
};

pub const InspectorDraft = struct {
    node_id: ?u32 = null,
    title: []const u8 = "",
    pos: [2]f32 = .{ 0.0, 0.0 },
    size: Size = .{ .w = 0.0, .h = 0.0 },
    input_count: u8 = 0,
    output_count: u8 = 0,

    pub fn hasNode(self: InspectorDraft) bool {
        return self.node_id != null;
    }
};

pub const MinimapSnapshot = struct {
    visible: bool = false,
    minimap_rect: Rect = .zero,
    graph_bounds: Rect = .zero,
    viewport_rect: Rect = .zero,

    pub fn contains(self: MinimapSnapshot, point: [2]f32) bool {
        return self.visible and self.minimap_rect.contains(point);
    }
};

pub const BoxSelectMode = enum {
    replace,
    add,
    subtract,
    toggle,
};

pub const Node = struct {
    id: u32,
    title: []const u8,
    pos: [2]f32,
    size: Size = .{ .w = 160.0, .h = 84.0 },
    color: Color = Color.rgb8(51, 65, 85),
    input_count: u8 = 1,
    output_count: u8 = 1,
    input_labels: []const []const u8 = &.{},
    output_labels: []const []const u8 = &.{},
    input_types: []const PortType = &.{},
    output_types: []const PortType = &.{},
};

pub const NodeTemplate = struct {
    title: []const u8,
    size: Size = .{ .w = 144.0, .h = 78.0 },
    color: Color = Color.rgb8(51, 65, 85),
    input_count: u8 = 1,
    output_count: u8 = 1,
    input_labels: []const []const u8 = &.{},
    output_labels: []const []const u8 = &.{},
    input_types: []const PortType = &.{},
    output_types: []const PortType = &.{},
};

pub const ChainTemplate = struct {
    nodes: []const NodeTemplate,
    connections: []const Connection = &.{},
    start_pos: [2]f32 = .{ 0.0, 0.0 },
    node_gap: [2]f32 = .{ 190.0, 0.0 },
};

pub const TemplatePaletteKind = enum {
    node,
    chain,
};

pub const TemplatePaletteItem = struct {
    label: []const u8,
    description: []const u8 = "",
    command: commands_mod.NodeEditorCommand,
    kind: TemplatePaletteKind = .node,
    aliases: []const []const u8 = &.{},
};

pub const TemplatePaletteState = struct {
    open: bool = false,
    query: []const u8 = "",
    selected_index: usize = 0,
    last_submitted: ?commands_mod.NodeEditorCommand = null,

    pub fn openPalette(self: *TemplatePaletteState) void {
        self.open = true;
    }

    pub fn close(self: *TemplatePaletteState) void {
        self.open = false;
        self.selected_index = 0;
    }

    pub fn toggle(self: *TemplatePaletteState) void {
        if (self.open) self.close() else self.openPalette();
    }

    pub fn setQuery(self: *TemplatePaletteState, query: []const u8) void {
        self.query = query;
        self.selected_index = 0;
    }

    pub fn matchCount(self: TemplatePaletteState, items: []const TemplatePaletteItem) usize {
        var count: usize = 0;
        for (items) |item| {
            if (self.matches(item)) count += 1;
        }
        return count;
    }

    pub fn itemAt(self: TemplatePaletteState, items: []const TemplatePaletteItem, match_index: usize) ?TemplatePaletteItem {
        var current: usize = 0;
        for (items) |item| {
            if (!self.matches(item)) continue;
            if (current == match_index) return item;
            current += 1;
        }
        return null;
    }

    pub fn selectedItem(self: TemplatePaletteState, items: []const TemplatePaletteItem) ?TemplatePaletteItem {
        const count = self.matchCount(items);
        if (count == 0) return null;
        return self.itemAt(items, @min(self.selected_index, count - 1));
    }

    pub fn moveSelection(self: *TemplatePaletteState, items: []const TemplatePaletteItem, delta: isize) void {
        const count = self.matchCount(items);
        if (count == 0) {
            self.selected_index = 0;
            return;
        }
        const current = @min(self.selected_index, count - 1);
        const next = if (delta < 0)
            current -| @as(usize, @intCast(-delta))
        else
            @min(count - 1, current + @as(usize, @intCast(delta)));
        self.selected_index = next;
    }

    pub fn submitSelected(self: *TemplatePaletteState, items: []const TemplatePaletteItem) ?commands_mod.NodeEditorCommand {
        const item = self.selectedItem(items) orelse return null;
        self.last_submitted = item.command;
        self.close();
        return item.command;
    }

    pub fn matches(self: TemplatePaletteState, item: TemplatePaletteItem) bool {
        if (self.query.len == 0) return true;
        if (containsIgnoreCase(item.label, self.query)) return true;
        if (containsIgnoreCase(item.description, self.query)) return true;
        if (fuzzyContainsIgnoreCase(item.label, self.query)) return true;
        for (item.aliases) |alias| {
            if (containsIgnoreCase(alias, self.query) or fuzzyContainsIgnoreCase(alias, self.query)) return true;
        }
        return false;
    }
};

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return command_search.substringRangeFolded(haystack, needle) != null;
}

fn fuzzyContainsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return command_search.fuzzyRangeFolded(haystack, needle) != null;
}

pub const Group = struct {
    id: u32 = 0,
    title: []const u8,
    rect: Rect,
    color: Color = Color.rgba8(59, 130, 246, 34),
    border_color: Color = Color.rgba8(96, 165, 250, 110),
    text_color: Color = Color.rgb8(226, 232, 240),
    title_height: f32 = 24.0,
    radius: f32 = 10.0,
};

const history_types = @import("node_history.zig").Types(Node, Group, Connection);
pub const HistorySnapshot = history_types.HistorySnapshot;
pub const HistoryWorkspace = history_types.HistoryWorkspace;
pub const HistoryStorage = history_types.HistoryStorage;
pub const StaticHistoryWorkspace = history_types.StaticHistoryWorkspace;
pub const HistorySummary = history_types.HistorySummary;
pub const History = history_types.History;

pub fn Options(comptime StateType: type) type {
    return struct {
        tag: u32 = 0,
        state: *StateType,
        nodes: []const Node,
        groups: []const Group = &.{},
        connections: []const Connection = &.{},
        mutable_connections: ?[]Connection = null,
        mutable_connection_len: ?*usize = null,
        history: ?*History = null,
        mutable_groups: ?[]Group = null,
        mutable_group_len: ?*usize = null,
        move_group_contents: bool = true,
        group_resize_margin: f32 = 8.0,
        group_min_size: Size = .{ .w = 72.0, .h = 48.0 },
        mutable_node_len: ?*usize = null,
        background: Color = Color.rgb8(15, 23, 42),
        grid_color: Color = Color.rgba8(148, 163, 184, 40),
        node_text_color: Color = Color.rgb8(248, 250, 252),
        selected_color: Color = Color.rgb8(96, 165, 250),
        port_color: Color = Color.rgb8(226, 232, 240),
        font_size: f32 = 12.0,
        grid_spacing: f32 = 32.0,
        mutable_nodes: ?[]Node = null,
        show_minimap: bool = true,
        minimap_size: Size = .{ .w = 150.0, .h = 96.0 },
        minimap_max_node_marks: usize = 512,
        minimap_max_group_marks: usize = 128,
        semantic_zoom: SemanticZoomOptions = .{},
        clipboard: ?*Clipboard = null,
        connection_path_cache: ?*ConnectionPathCache = null,
        connection_draw_workspace: ?*ConnectionDrawWorkspace = null,
        viewport_index: ?*ViewportIndex = null,
        geometry_revision: ?u64 = null,
        connection_policy: ConnectionPolicy = .default,
    };
}

pub const PortType = enum {
    any,
    flow,
    float,
    vector,
    color,
    image,
    mask,
    geometry,

    pub fn compatible(output_type: PortType, input_type: PortType) bool {
        if (output_type == .any or input_type == .any) return true;
        if (output_type == input_type) return true;
        return switch (output_type) {
            .color => input_type == .vector or input_type == .image,
            .image => input_type == .color or input_type == .mask,
            .mask => input_type == .float or input_type == .image,
            .float => input_type == .mask,
            else => false,
        };
    }
};

pub const PortHit = struct {
    node_index: usize,
    port_index: u8,
};

pub const GroupResizeHit = struct {
    group_index: usize,
    edges: GroupResizeEdges,
};

/// Convert a graph-space point into screen space using the editor viewport
/// transform. The state is intentionally accepted as `anytype`: core owns the
/// mutable interaction state for now, while this module owns the transform
/// invariant shared by hit testing, minimap planning, painting, and tests.
pub fn graphToScreen(rect: Rect, state: anytype, point: [2]f32) [2]f32 {
    return .{
        rect.x + rect.w * 0.5 + state.pan[0] + point[0] * state.zoom,
        rect.y + rect.h * 0.5 + state.pan[1] + point[1] * state.zoom,
    };
}

pub fn screenToGraph(rect: Rect, state: anytype, point: [2]f32) [2]f32 {
    const zoom = @max(0.0001, state.zoom);
    return .{
        (point[0] - rect.x - rect.w * 0.5 - state.pan[0]) / zoom,
        (point[1] - rect.y - rect.h * 0.5 - state.pan[1]) / zoom,
    };
}

pub fn nodeGraphRect(node: Node) Rect {
    return .{ .x = node.pos[0], .y = node.pos[1], .w = node.size.w, .h = node.size.h };
}

pub fn defaultInsertPosition(nodes: []const Node) [2]f32 {
    if (nodes.len == 0) return .{ -80.0, -40.0 };
    const bounds = graphBounds(nodes, &.{});
    return .{ bounds.x + bounds.w + 80.0, bounds.y + @max(20.0, bounds.h * 0.35) };
}

pub fn includeBounds(bounds: *?Rect, rect: Rect) void {
    if (bounds.* == null) {
        bounds.* = rect;
        return;
    }
    const existing = bounds.*.?;
    const min_x = @min(existing.x, rect.x);
    const min_y = @min(existing.y, rect.y);
    const max_x = @max(existing.x + existing.w, rect.x + rect.w);
    const max_y = @max(existing.y + existing.h, rect.y + rect.h);
    bounds.* = .{ .x = min_x, .y = min_y, .w = @max(1.0, max_x - min_x), .h = @max(1.0, max_y - min_y) };
}

pub fn graphBounds(nodes: []const Node, groups: []const Group) Rect {
    if (nodes.len == 0 and groups.len == 0) return .zero;
    var bounds: ?Rect = null;
    for (groups) |group| includeBounds(&bounds, group.rect);
    for (nodes) |node| includeBounds(&bounds, nodeGraphRect(node));
    return bounds orelse .zero;
}

pub fn paddedBounds(bounds: Rect, frac: f32) Rect {
    const pad_x = bounds.w * frac;
    const pad_y = bounds.h * frac;
    return .{ .x = bounds.x - pad_x, .y = bounds.y - pad_y, .w = bounds.w + pad_x * 2.0, .h = bounds.h + pad_y * 2.0 };
}

pub fn minimapPoint(minimap: Rect, bounds: Rect, point: [2]f32) [2]f32 {
    const sx = if (bounds.w > 0.0) (point[0] - bounds.x) / bounds.w else 0.0;
    const sy = if (bounds.h > 0.0) (point[1] - bounds.y) / bounds.h else 0.0;
    return .{ minimap.x + sx * minimap.w, minimap.y + sy * minimap.h };
}

pub fn graphPointFromMinimap(minimap: Rect, bounds: Rect, point: [2]f32) [2]f32 {
    const sx = if (minimap.w > 0.0) std.math.clamp((point[0] - minimap.x) / minimap.w, 0.0, 1.0) else 0.0;
    const sy = if (minimap.h > 0.0) std.math.clamp((point[1] - minimap.y) / minimap.h, 0.0, 1.0) else 0.0;
    return .{ bounds.x + sx * bounds.w, bounds.y + sy * bounds.h };
}

pub fn minimapNodeRect(minimap: Rect, bounds: Rect, node: Node) Rect {
    const p0 = minimapPoint(minimap, bounds, node.pos);
    const p1 = minimapPoint(minimap, bounds, .{ node.pos[0] + node.size.w, node.pos[1] + node.size.h });
    return .{ .x = p0[0], .y = p0[1], .w = @max(1.5, p1[0] - p0[0]), .h = @max(1.5, p1[1] - p0[1]) };
}

pub fn minimapGroupRect(minimap: Rect, bounds: Rect, group: Group) Rect {
    const p0 = minimapPoint(minimap, bounds, .{ group.rect.x, group.rect.y });
    const p1 = minimapPoint(minimap, bounds, .{ group.rect.x + group.rect.w, group.rect.y + group.rect.h });
    return .{ .x = p0[0], .y = p0[1], .w = @max(2.0, p1[0] - p0[0]), .h = @max(2.0, p1[1] - p0[1]) };
}

pub fn minimapViewportRect(minimap: Rect, bounds: Rect, viewport: Rect, state: anytype) Rect {
    const top_left = screenToGraph(viewport, state, .{ viewport.x, viewport.y });
    const bottom_right = screenToGraph(viewport, state, .{ viewport.x + viewport.w, viewport.y + viewport.h });
    const p0 = minimapPoint(minimap, bounds, top_left);
    const p1 = minimapPoint(minimap, bounds, bottom_right);
    return .{
        .x = std.math.clamp(@min(p0[0], p1[0]), minimap.x, minimap.x + minimap.w),
        .y = std.math.clamp(@min(p0[1], p1[1]), minimap.y, minimap.y + minimap.h),
        .w = @max(1.0, @min(@abs(p1[0] - p0[0]), minimap.w)),
        .h = @max(1.0, @min(@abs(p1[1] - p0[1]), minimap.h)),
    };
}

pub fn minimapSnapshot(viewport: Rect, state: anytype, nodes: []const Node, groups: []const Group, minimap_size: Size) MinimapSnapshot {
    if (viewport.w <= 0.0 or viewport.h <= 0.0 or nodes.len == 0 or minimap_size.w <= 0.0 or minimap_size.h <= 0.0) return .{};
    return minimapSnapshotFromGraphBounds(viewport, state, paddedBounds(graphBounds(nodes, groups), 0.12), minimap_size);
}

pub fn minimapSnapshotFromGraphBounds(viewport: Rect, state: anytype, bounds: Rect, minimap_size: Size) MinimapSnapshot {
    if (viewport.w <= 0.0 or viewport.h <= 0.0 or minimap_size.w <= 0.0 or minimap_size.h <= 0.0) return .{};
    if (bounds.w <= 0.0 or bounds.h <= 0.0) return .{};
    const minimap = Rect{
        .x = viewport.x + viewport.w - minimap_size.w - 10.0,
        .y = viewport.y + 10.0,
        .w = @min(minimap_size.w, @max(0.0, viewport.w - 20.0)),
        .h = @min(minimap_size.h, @max(0.0, viewport.h - 20.0)),
    };
    if (minimap.w <= 0.0 or minimap.h <= 0.0) return .{};
    return .{
        .visible = true,
        .minimap_rect = minimap,
        .graph_bounds = bounds,
        .viewport_rect = minimapViewportRect(minimap, bounds, viewport, state),
    };
}

fn minimapSnapshotPrepared(viewport: Rect, editor: anytype, viewport_index: ?*ViewportIndex) MinimapSnapshot {
    if (editor.nodes.len == 0) return .{};
    if (viewport_index) |index| {
        if (index.graphBounds()) |bounds| return minimapSnapshotFromGraphBounds(viewport, editor.state.*, paddedBounds(bounds, 0.12), editor.minimap_size);
    }
    return minimapSnapshot(viewport, editor.state.*, editor.nodes, editor.groups, editor.minimap_size);
}

pub fn rectIntersects(a: Rect, b: Rect) bool {
    return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y;
}

pub fn resizeGroupRect(origin: Rect, edges: GroupResizeEdges, delta: [2]f32, min_size: Size) Rect {
    var out = origin;
    const min_w = @max(8.0, min_size.w);
    const min_h = @max(8.0, min_size.h);
    if (edges.left and !edges.right) {
        const right = origin.x + origin.w;
        out.x = @min(origin.x + delta[0], right - min_w);
        out.w = right - out.x;
    } else if (edges.right) {
        out.w = @max(min_w, origin.w + delta[0]);
    }
    if (edges.top and !edges.bottom) {
        const bottom = origin.y + origin.h;
        out.y = @min(origin.y + delta[1], bottom - min_h);
        out.h = bottom - out.y;
    } else if (edges.bottom) {
        out.h = @max(min_h, origin.h + delta[1]);
    }
    return out;
}

pub fn nodeRectFromState(rect: Rect, state: anytype, node: Node) Rect {
    const top_left = graphToScreen(rect, state, node.pos);
    return .{
        .x = top_left[0],
        .y = top_left[1],
        .w = node.size.w * state.zoom,
        .h = node.size.h * state.zoom,
    };
}

pub fn groupRect(rect: Rect, state: anytype, group: Group) Rect {
    const top_left = graphToScreen(rect, state, .{ group.rect.x, group.rect.y });
    return .{
        .x = top_left[0],
        .y = top_left[1],
        .w = group.rect.w * state.zoom,
        .h = group.rect.h * state.zoom,
    };
}

pub fn inputPortPosition(rect: Rect, state: anytype, node: Node) [2]f32 {
    return inputPortPositionAt(rect, state, node, 0);
}

pub fn inputPortPositionAt(rect: Rect, state: anytype, node: Node, port_index: u8) [2]f32 {
    const node_rect = nodeRectFromState(rect, state, node);
    return .{ node_rect.x, portY(node_rect, inputPortCount(node), port_index) };
}

pub fn outputPortPosition(rect: Rect, state: anytype, node: Node) [2]f32 {
    return outputPortPositionAt(rect, state, node, 0);
}

pub fn outputPortPositionAt(rect: Rect, state: anytype, node: Node, port_index: u8) [2]f32 {
    const node_rect = nodeRectFromState(rect, state, node);
    return .{ node_rect.x + node_rect.w, portY(node_rect, outputPortCount(node), port_index) };
}

pub fn inputPortCount(node: Node) u8 {
    return @max(@as(u8, 1), node.input_count);
}

pub fn outputPortCount(node: Node) u8 {
    return @max(@as(u8, 1), node.output_count);
}

pub fn inputPortLabel(node: Node, port_index: u8) ?[]const u8 {
    if (port_index >= node.input_labels.len) return null;
    return if (node.input_labels[port_index].len > 0) node.input_labels[port_index] else null;
}

pub fn outputPortLabel(node: Node, port_index: u8) ?[]const u8 {
    if (port_index >= node.output_labels.len) return null;
    return if (node.output_labels[port_index].len > 0) node.output_labels[port_index] else null;
}

pub fn inputPortType(node: Node, port_index: u8) PortType {
    if (port_index >= node.input_types.len) return .any;
    return node.input_types[port_index];
}

pub fn outputPortType(node: Node, port_index: u8) PortType {
    if (port_index >= node.output_types.len) return .any;
    return node.output_types[port_index];
}

pub fn connectionPortsCompatible(nodes: []const Node, connection: Connection) bool {
    if (nodes.len == 0) return true;
    const from = nodeById(nodes, connection.from_id) orelse return false;
    const to = nodeById(nodes, connection.to_id) orelse return false;
    if (connection.from_port >= outputPortCount(from) or connection.to_port >= inputPortCount(to)) return false;
    return PortType.compatible(outputPortType(from, connection.from_port), inputPortType(to, connection.to_port));
}

pub fn validateConnection(nodes: []const Node, connections: []const Connection, connection: Connection, policy: ConnectionPolicy, options: ConnectionValidationOptions) ConnectionValidation {
    var validation_options = options;
    if (nodes.len == 0) validation_options.nodes_are_authoritative = false;
    return graph_validation.validateConnection(nodes, connections, connection, policy, validation_options);
}

pub fn connectionAllowed(nodes: []const Node, connections: []const Connection, connection: Connection, policy: ConnectionPolicy, options: ConnectionValidationOptions) bool {
    return validateConnection(nodes, connections, connection, policy, options).validFor(policy);
}

pub fn validateGraph(nodes: []const Node, connections: []const Connection, policy: ConnectionPolicy) GraphValidationReport {
    return graph_validation.validateGraph(nodes, connections, policy);
}

fn chainConnectionsAllowed(chain: ChainTemplate, policy: ConnectionPolicy) bool {
    for (chain.connections, 0..) |connection, index| {
        if (connection.from_id >= chain.nodes.len or connection.to_id >= chain.nodes.len) continue;
        if (!policy.allow_self_links and connection.from_id == connection.to_id) return false;
        const from_template = chain.nodes[@as(usize, @intCast(connection.from_id))];
        const to_template = chain.nodes[@as(usize, @intCast(connection.to_id))];
        if (policy.enforce_port_ranges and (connection.from_port >= outputPortCountForTemplate(from_template) or connection.to_port >= inputPortCountForTemplate(to_template))) return false;
        if (policy.enforce_port_types and
            connection.from_port < from_template.output_types.len and
            connection.to_port < to_template.input_types.len and
            !PortType.compatible(from_template.output_types[connection.from_port], to_template.input_types[connection.to_port]))
        {
            return false;
        }
        if (!policy.allow_duplicate_links) {
            var later = index + 1;
            while (later < chain.connections.len) : (later += 1) {
                const other = chain.connections[later];
                if (other.from_id >= chain.nodes.len or other.to_id >= chain.nodes.len) continue;
                if (connectionEndpointsEqual(connection, other)) return false;
            }
        }
        if (!policy.allow_cycles and chainPathExists(chain.connections, connection.to_id, connection.from_id, connection)) return false;
    }
    return true;
}

fn inputPortCountForTemplate(template: NodeTemplate) u8 {
    return @max(@as(u8, 1), template.input_count);
}

fn outputPortCountForTemplate(template: NodeTemplate) u8 {
    return @max(@as(u8, 1), template.output_count);
}

fn chainPathExists(connections: []const Connection, start_id: u32, target_id: u32, ignore: Connection) bool {
    if (start_id == target_id) return true;
    var visited: [64]u32 = .{0} ** 64;
    var visited_len: usize = 0;
    var stack: [64]u32 = .{0} ** 64;
    var stack_len: usize = 1;
    stack[0] = start_id;

    while (stack_len > 0) {
        stack_len -= 1;
        const current = stack[stack_len];
        if (current == target_id) return true;
        if (idInSlice(visited[0..visited_len], current)) continue;
        if (visited_len >= visited.len) return false;
        visited[visited_len] = current;
        visited_len += 1;

        for (connections) |connection| {
            if (connectionEndpointsEqual(connection, ignore)) continue;
            if (connection.from_id != current) continue;
            if (connection.to_id == target_id) return true;
            if (idInSlice(visited[0..visited_len], connection.to_id)) continue;
            if (stack_len >= stack.len) return false;
            stack[stack_len] = connection.to_id;
            stack_len += 1;
        }
    }
    return false;
}

fn idInSlice(ids: []const u32, id: u32) bool {
    for (ids) |value| {
        if (value == id) return true;
    }
    return false;
}

fn editorConnectionPolicy(editor: anytype) ConnectionPolicy {
    const Editor = @TypeOf(editor);
    if (@hasField(Editor, "connection_policy")) return editor.connection_policy;
    return .default;
}

fn editorActiveConnections(editor: anytype) []const Connection {
    const Editor = @TypeOf(editor);
    if (@hasField(Editor, "mutable_connections")) {
        if (editor.mutable_connections) |connections| {
            const len = if (editor.mutable_connection_len) |value| @min(value.*, connections.len) else connections.len;
            return connections[0..len];
        }
    }
    if (@hasField(Editor, "connections")) return editor.connections;
    return &.{};
}

pub fn nodeIndexById(nodes: []const Node, id: u32) ?usize {
    for (nodes, 0..) |node, index| {
        if (node.id == id) return index;
    }
    return null;
}

pub fn nodeFromTemplate(template: NodeTemplate, id: u32, pos: [2]f32) Node {
    return .{
        .id = id,
        .title = template.title,
        .pos = pos,
        .size = template.size,
        .color = template.color,
        .input_count = template.input_count,
        .output_count = template.output_count,
        .input_labels = template.input_labels,
        .output_labels = template.output_labels,
        .input_types = template.input_types,
        .output_types = template.output_types,
    };
}

pub fn groupIndexById(groups: []const Group, id: u32) ?usize {
    for (groups, 0..) |group, index| {
        if (group.id == id) return index;
    }
    return null;
}

pub fn uniqueGroupId(groups: []const Group, base: u32) u32 {
    var candidate = base;
    var guard: usize = 0;
    while (groupIndexById(groups, candidate) != null and guard < groups.len + 1024) : (guard += 1) {
        candidate +%= 1;
    }
    return candidate;
}

pub const AdjacentNodeDirection = enum { previous, next };

pub fn adjacentNodeId(nodes: []const Node, anchor_id: u32, avoid_id: u32, direction: AdjacentNodeDirection) ?u32 {
    if (nodes.len == 0) return null;
    const anchor_index = nodeIndexById(nodes, anchor_id) orelse return null;
    var step: usize = 1;
    while (step < nodes.len) : (step += 1) {
        const index = switch (direction) {
            .previous => if (anchor_index >= step) anchor_index - step else nodes.len + anchor_index - step,
            .next => (anchor_index + step) % nodes.len,
        };
        const id = nodes[index].id;
        if (id != anchor_id and id != avoid_id) return id;
    }
    return null;
}

pub fn portY(node_rect: Rect, port_count: u8, port_index: u8) f32 {
    const count = @max(@as(u8, 1), port_count);
    const clamped_index = @min(port_index, count - 1);
    if (count == 1) return node_rect.y + node_rect.h * 0.5;
    const usable_h = @max(1.0, node_rect.h - 24.0);
    const top = node_rect.y + 16.0;
    return top + usable_h * (@as(f32, @floatFromInt(clamped_index)) + 0.5) / @as(f32, @floatFromInt(count));
}

pub fn portHit(pos: [2]f32, point: [2]f32) bool {
    return @abs(point[0] - pos[0]) <= 8.0 and @abs(point[1] - pos[1]) <= 8.0;
}

pub fn inputPortAtPoint(rect: Rect, state: anytype, nodes: []const Node, point: [2]f32) ?PortHit {
    for (nodes, 0..) |node, index| {
        var port_index: u8 = 0;
        while (port_index < inputPortCount(node)) : (port_index += 1) {
            if (portHit(inputPortPositionAt(rect, state, node, port_index), point)) return .{ .node_index = index, .port_index = port_index };
        }
    }
    return null;
}

pub fn outputPortAtPoint(rect: Rect, state: anytype, nodes: []const Node, point: [2]f32) ?PortHit {
    for (nodes, 0..) |node, index| {
        var port_index: u8 = 0;
        while (port_index < outputPortCount(node)) : (port_index += 1) {
            if (portHit(outputPortPositionAt(rect, state, node, port_index), point)) return .{ .node_index = index, .port_index = port_index };
        }
    }
    return null;
}

pub fn connectionAtPoint(
    rect: Rect,
    state: anytype,
    nodes: []const Node,
    mutable_connections: ?[]const Connection,
    mutable_connection_len: ?usize,
    connections: []const Connection,
    point: [2]f32,
) ?Connection {
    if (mutable_connections) |mutable| {
        const len = if (mutable_connection_len) |value| @min(value, mutable.len) else mutable.len;
        var i = len;
        while (i > 0) {
            i -= 1;
            const connection = mutable[i];
            if (connectionHit(rect, state, nodes, connection, point)) return connection;
        }
    }
    var i = connections.len;
    while (i > 0) {
        i -= 1;
        const connection = connections[i];
        if (connectionHit(rect, state, nodes, connection, point)) return connection;
    }
    return null;
}

pub fn connectionHit(rect: Rect, state: anytype, nodes: []const Node, connection: Connection, point: [2]f32) bool {
    const from = nodeById(nodes, connection.from_id) orelse return false;
    const to = nodeById(nodes, connection.to_id) orelse return false;
    const a = outputPortPositionAt(rect, state, from, connection.from_port);
    const b = inputPortPositionAt(rect, state, to, connection.to_port);
    return cubicDistanceToPoint(a, .{ a[0] + @max(40.0, @abs(b[0] - a[0]) * 0.5), a[1] }, .{ b[0] - @max(40.0, @abs(b[0] - a[0]) * 0.5), b[1] }, b, point) <= 7.0;
}

pub fn optionalConnectionEqual(a: ?Connection, b: ?Connection) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return connectionEndpointsEqual(a.?, b.?);
}

pub fn connectionEndpointsEqual(a: Connection, b: Connection) bool {
    return a.from_id == b.from_id and a.to_id == b.to_id and a.from_port == b.from_port and a.to_port == b.to_port;
}

pub fn nodeById(nodes: []const Node, id: u32) ?Node {
    for (nodes) |node| if (node.id == id) return node;
    return null;
}

pub fn nodeAtPoint(rect: Rect, state: anytype, nodes: []const Node, point: [2]f32) ?usize {
    var i = nodes.len;
    while (i > 0) {
        i -= 1;
        if (nodeRectFromState(rect, state, nodes[i]).contains(point)) return i;
    }
    return null;
}

pub fn groupAtPoint(rect: Rect, state: anytype, groups: []const Group, point: [2]f32) ?usize {
    var i = groups.len;
    while (i > 0) {
        i -= 1;
        if (groupRect(rect, state, groups[i]).contains(point)) return i;
    }
    return null;
}

pub fn groupResizeAtPoint(rect: Rect, state: anytype, groups: []const Group, margin_value: f32, point: [2]f32) ?GroupResizeHit {
    const margin = @max(0.0, margin_value);
    if (margin <= 0.0) return null;
    var i = groups.len;
    while (i > 0) {
        i -= 1;
        const screen_rect = groupRect(rect, state, groups[i]);
        if (!screen_rect.contains(point)) continue;
        const edges = GroupResizeEdges{
            .left = point[0] <= screen_rect.x + margin,
            .right = point[0] >= screen_rect.x + screen_rect.w - margin,
            .top = point[1] <= screen_rect.y + margin,
            .bottom = point[1] >= screen_rect.y + screen_rect.h - margin,
        };
        if (edges.any()) return .{ .group_index = i, .edges = edges };
    }
    return null;
}

pub fn nodeInsideGraphRect(node: Node, rect: Rect) bool {
    return node.pos[0] >= rect.x and node.pos[1] >= rect.y and
        node.pos[0] + node.size.w <= rect.x + rect.w and
        node.pos[1] + node.size.h <= rect.y + rect.h;
}

pub const ConnectionPath = struct {
    start: [2]f32 = .{ 0.0, 0.0 },
    c0: [2]f32 = .{ 0.0, 0.0 },
    c1: [2]f32 = .{ 0.0, 0.0 },
    end: [2]f32 = .{ 0.0, 0.0 },
};

pub fn connectionPathForPoints(a: [2]f32, b: [2]f32) ConnectionPath {
    const dx = @max(40.0, @abs(b[0] - a[0]) * 0.5);
    return .{
        .start = a,
        .c0 = .{ a[0] + dx, a[1] },
        .c1 = .{ b[0] - dx, b[1] },
        .end = b,
    };
}

pub const ConnectionPathCacheCapacity: usize = 128;

pub const ConnectionPathCacheEntry = struct {
    a: [2]f32 = .{ 0.0, 0.0 },
    b: [2]f32 = .{ 0.0, 0.0 },
    path: ConnectionPath = .{},
    valid: bool = false,
    last_used_generation: u64 = 0,
};

pub const ConnectionPathCacheSummary = struct {
    entry_count: usize = 0,
    valid_count: usize = 0,
    hit_count: u64 = 0,
    miss_count: u64 = 0,
    rebuild_count: u64 = 0,
    eviction_count: u64 = 0,
    generation: u64 = 0,
};

pub const ConnectionPathCache = struct {
    entries: [ConnectionPathCacheCapacity]ConnectionPathCacheEntry = [_]ConnectionPathCacheEntry{.{}} ** ConnectionPathCacheCapacity,
    entry_count: usize = 0,
    generation: u64 = 0,
    hit_count: u64 = 0,
    miss_count: u64 = 0,
    rebuild_count: u64 = 0,
    eviction_count: u64 = 0,

    pub fn reset(self: *ConnectionPathCache) void {
        self.* = .{};
    }

    pub fn pathFor(self: *ConnectionPathCache, a: [2]f32, b: [2]f32) ConnectionPath {
        self.generation +%= 1;
        if (self.findIndex(a, b)) |index| {
            var entry = &self.entries[index];
            entry.last_used_generation = self.generation;
            self.hit_count +%= 1;
            return entry.path;
        }
        self.miss_count +%= 1;
        self.rebuild_count +%= 1;
        const index = self.allocateIndex();
        const path = connectionPathForPoints(a, b);
        self.entries[index] = .{ .a = a, .b = b, .path = path, .valid = true, .last_used_generation = self.generation };
        return path;
    }

    pub fn summary(self: *const ConnectionPathCache) ConnectionPathCacheSummary {
        var valid_count: usize = 0;
        for (self.entries[0..self.entry_count]) |entry| {
            if (entry.valid) valid_count += 1;
        }
        return .{
            .entry_count = self.entry_count,
            .valid_count = valid_count,
            .hit_count = self.hit_count,
            .miss_count = self.miss_count,
            .rebuild_count = self.rebuild_count,
            .eviction_count = self.eviction_count,
            .generation = self.generation,
        };
    }

    fn findIndex(self: *const ConnectionPathCache, a: [2]f32, b: [2]f32) ?usize {
        var i: usize = 0;
        while (i < self.entry_count) : (i += 1) {
            const entry = self.entries[i];
            if (entry.valid and pointsEqual(entry.a, a) and pointsEqual(entry.b, b)) return i;
        }
        return null;
    }

    fn allocateIndex(self: *ConnectionPathCache) usize {
        if (self.entry_count < ConnectionPathCacheCapacity) {
            const index = self.entry_count;
            self.entry_count += 1;
            return index;
        }
        var oldest_index: usize = 0;
        var oldest_generation = self.entries[0].last_used_generation;
        for (self.entries[1..], 1..) |entry, index| {
            if (entry.last_used_generation < oldest_generation) {
                oldest_generation = entry.last_used_generation;
                oldest_index = index;
            }
        }
        self.eviction_count +%= 1;
        return oldest_index;
    }
};

/// Persistent command slots for allocation-free connection painting. The
/// workspace must outlive every retained draw list that borrows from it.
pub const ConnectionDrawWorkspace = struct {
    path_commands: [][2]render.PathCommand,
    frame_count: u64 = 0,
    borrowed_connection_count: usize = 0,
    fallback_connection_count: usize = 0,

    pub fn capacity(self: ConnectionDrawWorkspace) usize {
        return self.path_commands.len;
    }

    pub fn summary(self: ConnectionDrawWorkspace) ConnectionDrawSummary {
        return .{
            .capacity = self.path_commands.len,
            .frame_count = self.frame_count,
            .borrowed_connection_count = self.borrowed_connection_count,
            .fallback_connection_count = self.fallback_connection_count,
        };
    }

    fn beginPaint(self: *ConnectionDrawWorkspace) void {
        self.frame_count +%= 1;
        self.borrowed_connection_count = 0;
        self.fallback_connection_count = 0;
    }
};

pub const ConnectionDrawSummary = struct {
    capacity: usize = 0,
    frame_count: u64 = 0,
    borrowed_connection_count: usize = 0,
    fallback_connection_count: usize = 0,

    pub fn allocationFree(self: ConnectionDrawSummary) bool {
        return self.fallback_connection_count == 0;
    }
};

pub const ConnectionDrawStorage = struct {
    allocator: std.mem.Allocator,
    path_commands: [][2]render.PathCommand,

    pub fn init(allocator: std.mem.Allocator, connection_capacity: usize) !ConnectionDrawStorage {
        return .{
            .allocator = allocator,
            .path_commands = try allocator.alloc([2]render.PathCommand, connection_capacity),
        };
    }

    pub fn deinit(self: *ConnectionDrawStorage) void {
        self.allocator.free(self.path_commands);
        self.* = undefined;
    }

    pub fn workspace(self: *ConnectionDrawStorage) ConnectionDrawWorkspace {
        return .{ .path_commands = self.path_commands };
    }
};

pub fn StaticConnectionDrawWorkspace(comptime connection_capacity: usize) type {
    return struct {
        path_commands: [connection_capacity][2]render.PathCommand = undefined,

        pub fn workspace(self: *@This()) ConnectionDrawWorkspace {
            return .{ .path_commands = &self.path_commands };
        }
    };
}

fn pointsEqual(a: [2]f32, b: [2]f32) bool {
    return a[0] == b[0] and a[1] == b[1];
}

const SelectionCommand = commands_mod.SelectionCommand;
const SelectionCommandResult = commands_mod.SelectionCommandResult;
const SelectionCommandState = commands_mod.SelectionCommandState;
const NodeEditorCommand = commands_mod.NodeEditorCommand;
const MenuItem = menu_mod.MenuItem;
const MenuModel = menu_mod.MenuModel;

const DistributeSortContext = struct {
    nodes: []const Node,
    horizontal: bool,
};

fn distributeLessThan(context: DistributeSortContext, a_index: usize, b_index: usize) bool {
    const a = context.nodes[a_index];
    const b = context.nodes[b_index];
    const a_center = if (context.horizontal) a.pos[0] + a.size.w * 0.5 else a.pos[1] + a.size.h * 0.5;
    const b_center = if (context.horizontal) b.pos[0] + b.size.w * 0.5 else b.pos[1] + b.size.h * 0.5;
    if (@abs(a_center - b_center) > 0.001) return a_center < b_center;
    return a.id < b.id;
}

fn reconnectCandidateValid(active_connections: []const Connection, selected: Connection, replacement: Connection, nodes: []const Node, policy: ConnectionPolicy) bool {
    if (connectionEndpointsEqual(selected, replacement)) return false;
    return connectionAllowed(nodes, active_connections, replacement, policy, .{
        .ignore_connection = graph_validation.ConnectionKey.from(selected),
    });
}

/// Mutable node-editor model used by core.zig widgets and by headless tests.
/// Keeping this state machine in the node_editor module makes command, selection,
/// grouping, clipboard, and reconnect behavior reusable without depending on the
/// large View/ViewContext implementation in core.zig.
pub const State = struct {
    pan: [2]f32 = .{ 0.0, 0.0 },
    zoom: f32 = 1.0,
    min_zoom: f32 = 0.2,
    max_zoom: f32 = 4.0,
    dragging_canvas: bool = false,
    dragging_node_id: ?u32 = null,
    dragging_connection_from_id: ?u32 = null,
    dragging_connection_from_port: u8 = 0,
    reconnecting_connection: ?Connection = null,
    reconnecting_connection_end: ConnectionEnd = .to,
    connection_preview: [2]f32 = .{ 0.0, 0.0 },
    connection_preview_valid: bool = true,
    pending_connection: ?Connection = null,
    dragging_group_id: ?u32 = null,
    resizing_group_id: ?u32 = null,
    resizing_group_edges: GroupResizeEdges = .{},
    interaction_history_pushed: bool = false,
    selected_node_id: ?u32 = null,
    selected_node_ids: []u32 = &.{},
    selected_node_len: usize = 0,
    selected_group_id: ?u32 = null,
    selected_connection: ?Connection = null,
    hover_node_id: ?u32 = null,
    hover_group_id: ?u32 = null,
    hover_input_node_id: ?u32 = null,
    hover_output_node_id: ?u32 = null,
    hover_connection: ?Connection = null,
    box_selecting: bool = false,
    box_select_start: [2]f32 = .{ 0.0, 0.0 },
    box_select_end: [2]f32 = .{ 0.0, 0.0 },
    box_select_mode: BoxSelectMode = .replace,
    dragging_minimap: bool = false,
    minimap_drag_offset: [2]f32 = .{ 0.0, 0.0 },
    context_menu: ContextMenuState = .{},

    pub fn clamp(self: *State) void {
        self.min_zoom = @max(0.001, self.min_zoom);
        self.max_zoom = @max(self.min_zoom, self.max_zoom);
        self.zoom = std.math.clamp(self.zoom, self.min_zoom, self.max_zoom);
    }

    pub fn panBy(self: *State, delta: [2]f32) bool {
        const before = self.pan;
        self.pan[0] += delta[0];
        self.pan[1] += delta[1];
        return @abs(before[0] - self.pan[0]) > 0.001 or @abs(before[1] - self.pan[1]) > 0.001;
    }

    pub fn zoomAt(self: *State, viewport: Rect, anchor: [2]f32, factor: f32) bool {
        if (factor <= 0.0 or viewport.w <= 0.0 or viewport.h <= 0.0) return false;
        self.clamp();
        const before_zoom = self.zoom;
        const graph_before = screenToGraph(viewport, self.*, anchor);
        self.zoom = std.math.clamp(self.zoom * factor, self.min_zoom, self.max_zoom);
        self.pan = .{
            anchor[0] - (viewport.x + viewport.w * 0.5) - graph_before[0] * self.zoom,
            anchor[1] - (viewport.y + viewport.h * 0.5) - graph_before[1] * self.zoom,
        };
        return @abs(self.zoom - before_zoom) > 0.0001;
    }

    pub fn centerViewportOnGraphPoint(self: *State, viewport: Rect, graph_point: [2]f32) bool {
        if (viewport.w <= 0.0 or viewport.h <= 0.0) return false;
        self.clamp();
        const before = self.pan;
        self.pan = .{ -graph_point[0] * self.zoom, -graph_point[1] * self.zoom };
        return @abs(before[0] - self.pan[0]) > 0.001 or @abs(before[1] - self.pan[1]) > 0.001;
    }

    pub fn panToMinimapPoint(self: *State, viewport: Rect, snapshot: MinimapSnapshot, point: [2]f32) bool {
        if (!snapshot.contains(point) or viewport.w <= 0.0 or viewport.h <= 0.0) return false;
        const graph_point = graphPointFromMinimap(snapshot.minimap_rect, snapshot.graph_bounds, point);
        return self.centerViewportOnGraphPoint(viewport, graph_point);
    }

    pub fn beginMinimapDrag(self: *State, viewport: Rect, snapshot: MinimapSnapshot, point: [2]f32) bool {
        if (!snapshot.contains(point)) return false;
        self.dragging_minimap = true;
        self.minimap_drag_offset = if (snapshot.viewport_rect.contains(point))
            .{ point[0] - (snapshot.viewport_rect.x + snapshot.viewport_rect.w * 0.5), point[1] - (snapshot.viewport_rect.y + snapshot.viewport_rect.h * 0.5) }
        else
            .{ 0.0, 0.0 };
        return self.updateMinimapDrag(viewport, snapshot, point) or true;
    }

    pub fn updateMinimapDrag(self: *State, viewport: Rect, snapshot: MinimapSnapshot, point: [2]f32) bool {
        if (!self.dragging_minimap or !snapshot.visible or viewport.w <= 0.0 or viewport.h <= 0.0) return false;
        const adjusted = [2]f32{ point[0] - self.minimap_drag_offset[0], point[1] - self.minimap_drag_offset[1] };
        const clamped = [2]f32{
            std.math.clamp(adjusted[0], snapshot.minimap_rect.x, snapshot.minimap_rect.x + snapshot.minimap_rect.w),
            std.math.clamp(adjusted[1], snapshot.minimap_rect.y, snapshot.minimap_rect.y + snapshot.minimap_rect.h),
        };
        const graph_point = graphPointFromMinimap(snapshot.minimap_rect, snapshot.graph_bounds, clamped);
        return self.centerViewportOnGraphPoint(viewport, graph_point);
    }

    pub fn beginNodeDrag(self: *State, id: u32) bool {
        const preserve_multi_selection = self.boundedSelectionLen() > 1 and self.isNodeSelected(id);
        const changed = self.dragging_node_id == null or self.dragging_node_id.? != id or
            self.selected_node_id == null or self.selected_node_id.? != id or
            self.selected_group_id != null or self.selected_connection != null or
            (!preserve_multi_selection and (self.boundedSelectionLen() != 1 or !self.isNodeSelected(id)));
        self.dragging_node_id = id;
        self.dragging_group_id = null;
        self.interaction_history_pushed = false;
        self.dragging_canvas = false;
        self.box_selecting = false;
        if (preserve_multi_selection) {
            self.selected_node_id = id;
            self.selected_group_id = null;
            self.selected_connection = null;
        } else {
            _ = self.setSingleSelection(id);
        }
        return changed;
    }

    pub fn endDrag(self: *State) bool {
        const changed = self.dragging_canvas or self.dragging_node_id != null or self.dragging_group_id != null or self.resizing_group_id != null or self.resizing_group_edges.any() or self.dragging_connection_from_id != null or self.box_selecting or self.dragging_minimap;
        self.dragging_canvas = false;
        self.dragging_node_id = null;
        self.dragging_group_id = null;
        self.resizing_group_id = null;
        self.resizing_group_edges = .{};
        self.interaction_history_pushed = false;
        self.dragging_connection_from_id = null;
        self.dragging_connection_from_port = 0;
        self.connection_preview_valid = true;
        self.reconnecting_connection = null;
        self.box_selecting = false;
        self.dragging_minimap = false;
        self.minimap_drag_offset = .{ 0.0, 0.0 };
        self.hover_group_id = null;
        return changed;
    }

    pub fn setSingleSelection(self: *State, id: u32) bool {
        const bounded_len = self.boundedSelectionLen();
        const changed = self.selected_node_id == null or self.selected_node_id.? != id or
            (self.selected_node_ids.len > 0 and (bounded_len != 1 or self.selected_node_ids[0] != id)) or
            (self.selected_node_ids.len == 0 and self.selected_node_len != 0);
        self.selected_node_id = id;
        if (self.selected_node_ids.len > 0) {
            self.selected_node_ids[0] = id;
            self.selected_node_len = 1;
        } else {
            self.selected_node_len = 0;
        }
        self.selected_group_id = null;
        self.selected_connection = null;
        return changed;
    }

    pub fn beginGroupDrag(self: *State, id: u32) bool {
        const changed = self.dragging_group_id == null or self.dragging_group_id.? != id or self.selected_group_id == null or self.selected_group_id.? != id;
        self.dragging_group_id = id;
        self.resizing_group_id = null;
        self.resizing_group_edges = .{};
        self.interaction_history_pushed = false;
        self.dragging_node_id = null;
        self.dragging_connection_from_id = null;
        self.dragging_connection_from_port = 0;
        self.connection_preview_valid = true;
        self.dragging_canvas = false;
        self.box_selecting = false;
        return self.setGroupSelection(id) or changed;
    }

    pub fn beginGroupResize(self: *State, id: u32, edges: GroupResizeEdges) bool {
        if (!edges.any()) return false;
        const changed = self.resizing_group_id == null or self.resizing_group_id.? != id or !std.meta.eql(self.resizing_group_edges, edges);
        self.resizing_group_id = id;
        self.resizing_group_edges = edges;
        self.dragging_group_id = null;
        self.interaction_history_pushed = false;
        self.dragging_node_id = null;
        self.dragging_connection_from_id = null;
        self.dragging_connection_from_port = 0;
        self.connection_preview_valid = true;
        self.dragging_canvas = false;
        self.box_selecting = false;
        return self.setGroupSelection(id) or changed;
    }

    pub fn isGroupSelected(self: *const State, id: u32) bool {
        return self.selected_group_id != null and self.selected_group_id.? == id;
    }

    pub fn setGroupSelection(self: *State, id: u32) bool {
        const changed = self.selected_group_id == null or self.selected_group_id.? != id or
            self.selected_node_id != null or self.selected_node_len != 0 or self.selected_connection != null;
        _ = self.clearNodeSelection();
        self.selected_group_id = id;
        self.selected_connection = null;
        return changed;
    }

    pub fn clearGroupSelection(self: *State) bool {
        if (self.selected_group_id == null) return false;
        self.selected_group_id = null;
        return true;
    }

    pub fn boundedSelectionLen(self: *const State) usize {
        return @min(self.selected_node_len, self.selected_node_ids.len);
    }

    pub fn lastSelectedNodeId(self: *const State) ?u32 {
        if (self.selected_node_id) |id| return id;
        const len = self.boundedSelectionLen();
        if (len == 0) return null;
        return self.selected_node_ids[len - 1];
    }

    pub fn isNodeSelected(self: *const State, id: u32) bool {
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |selected| {
            if (selected == id) return true;
        }
        return self.selected_node_id != null and self.selected_node_id.? == id;
    }

    pub fn toggleNodeSelection(self: *State, id: u32) bool {
        const was_selected = self.isNodeSelected(id);
        if (was_selected) {
            self.removeNodeFromSelection(id);
        } else {
            self.addNodeToSelection(id);
        }
        self.selected_group_id = null;
        self.selected_connection = null;
        return self.isNodeSelected(id) != was_selected;
    }

    pub fn clearSelection(self: *State) bool {
        const changed = self.selected_node_id != null or self.selected_node_len != 0 or self.selected_group_id != null or self.selected_connection != null;
        self.selected_node_id = null;
        self.selected_node_len = 0;
        self.selected_group_id = null;
        self.selected_connection = null;
        return changed;
    }

    pub fn clearNodeSelection(self: *State) bool {
        const changed = self.selected_node_id != null or self.selected_node_len != 0;
        self.selected_node_id = null;
        self.selected_node_len = 0;
        return changed;
    }

    pub fn hasSelection(self: *const State) bool {
        return self.selected_node_id != null or self.boundedSelectionLen() != 0 or self.selected_group_id != null or self.selected_connection != null;
    }

    pub fn selectAllNodes(self: *State, nodes: []const Node, node_len: usize) bool {
        const count = @min(node_len, nodes.len);
        if (count == 0) return false;
        const before_id = self.selected_node_id;
        const before_len = self.selected_node_len;
        const before_group = self.selected_group_id;
        const before_connection = self.selected_connection;
        var before_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| before_hash = before_hash *% 16777619 +% id;

        self.selected_node_len = 0;
        for (nodes[0..count]) |node| {
            if (self.selected_node_len >= self.selected_node_ids.len) break;
            self.selected_node_ids[self.selected_node_len] = node.id;
            self.selected_node_len += 1;
        }
        self.selected_node_id = if (self.selected_node_len > 0) self.selected_node_ids[self.selected_node_len - 1] else nodes[count - 1].id;
        self.selected_group_id = null;
        self.selected_connection = null;
        self.box_selecting = false;

        var after_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| after_hash = after_hash *% 16777619 +% id;
        return before_id != self.selected_node_id or before_len != self.selected_node_len or before_group != self.selected_group_id or
            !optionalConnectionEqual(before_connection, self.selected_connection) or before_hash != after_hash;
    }

    pub fn isConnectionSelected(self: *const State, connection: Connection) bool {
        const selected = self.selected_connection orelse return false;
        return State.connectionEndpointsEqual(selected, connection);
    }

    pub fn isConnectionHovered(self: *const State, connection: Connection) bool {
        const hovered = self.hover_connection orelse return false;
        return State.connectionEndpointsEqual(hovered, connection);
    }

    pub fn setConnectionSelection(self: *State, connection: Connection) bool {
        const changed = self.selected_connection == null or !State.connectionEndpointsEqual(self.selected_connection.?, connection) or
            self.selected_node_id != null or self.selected_node_len != 0 or self.selected_group_id != null;
        _ = self.clearNodeSelection();
        self.selected_group_id = null;
        self.selected_connection = connection;
        return changed;
    }

    pub fn clearConnectionSelection(self: *State) bool {
        if (self.selected_connection == null) return false;
        self.selected_connection = null;
        return true;
    }

    pub fn canHandleSelectionCommand(self: State, command: SelectionCommand) bool {
        _ = command;
        return self.lastSelectedNodeId() != null;
    }

    pub fn handleSelectionCommand(self: *State, command: SelectionCommand, selection: *SelectionCommandState) SelectionCommandResult {
        selection.selected_id = self.lastSelectedNodeId();
        const result = selection.handle(command);
        if (command == .delete and result.handled) _ = self.clearSelection();
        return result;
    }

    pub fn selectedNodeStorageCount(self: *const State, nodes: []const Node, node_len: usize) usize {
        const count = @min(node_len, nodes.len);
        var selected_count: usize = 0;
        for (nodes[0..count]) |node| {
            if (self.isNodeSelected(node.id)) selected_count += 1;
        }
        return selected_count;
    }

    pub fn lastSelectedStoredNodeId(self: *const State, nodes: []const Node, node_len: usize) ?u32 {
        const count = @min(node_len, nodes.len);
        var id: ?u32 = null;
        for (nodes[0..count]) |node| {
            if (self.isNodeSelected(node.id)) id = node.id;
        }
        return id;
    }

    pub fn canArrangeSelectedNodes(self: *const State, nodes: []const Node, node_len: usize, command: NodeEditorCommand) bool {
        const selected_count = self.selectedNodeStorageCount(nodes, node_len);
        return switch (command) {
            .align_left,
            .align_center_x,
            .align_right,
            .align_top,
            .align_center_y,
            .align_bottom,
            => selected_count >= 1,
            .distribute_horizontal,
            .distribute_vertical,
            => selected_count >= 3,
            else => false,
        };
    }

    pub fn arrangeSelectedNodes(self: *State, nodes: []Node, node_len: usize, command: NodeEditorCommand) bool {
        const count = @min(node_len, nodes.len);
        if (!self.canArrangeSelectedNodes(nodes, count, command)) return false;
        return switch (command) {
            .align_left,
            .align_center_x,
            .align_right,
            .align_top,
            .align_center_y,
            .align_bottom,
            => self.alignSelectedNodes(nodes[0..count], command),
            .distribute_horizontal,
            .distribute_vertical,
            => self.distributeSelectedNodes(nodes[0..count], command),
            else => false,
        };
    }

    pub fn canInsertNodeTemplate(_: *const State, nodes: []const Node, node_len: usize) bool {
        return @min(node_len, nodes.len) < nodes.len;
    }

    pub fn canInsertNodeChain(self: *const State, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize, chain: ChainTemplate) bool {
        return self.canInsertNodeChainWithPolicy(nodes, node_len, connections, connection_len, chain, .default);
    }

    pub fn canInsertNodeChainWithPolicy(_: *const State, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize, chain: ChainTemplate, policy: ConnectionPolicy) bool {
        const active_node_len = @min(node_len, nodes.len);
        const active_connection_len = @min(connection_len, connections.len);
        if (chain.nodes.len == 0 or active_node_len + chain.nodes.len > nodes.len or active_connection_len + chain.connections.len > connections.len) return false;
        return chainConnectionsAllowed(chain, policy);
    }

    pub fn insertNodeTemplate(self: *State, nodes: []Node, node_len: *usize, template: NodeTemplate, pos: [2]f32) bool {
        const count = @min(node_len.*, nodes.len);
        node_len.* = count;
        if (count >= nodes.len) return false;
        const id = uniqueDuplicateNodeId(nodes[0..count], @as(u32, @intCast(count + 1)), 1000);
        nodes[count] = nodeFromTemplate(template, id, pos);
        node_len.* = count + 1;
        _ = self.setSingleSelection(id);
        return true;
    }

    pub fn insertNodeChain(self: *State, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize, chain: ChainTemplate) bool {
        return self.insertNodeChainWithPolicy(nodes, node_len, connections, connection_len, chain, .default);
    }

    pub fn insertNodeChainWithPolicy(self: *State, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize, chain: ChainTemplate, policy: ConnectionPolicy) bool {
        const active_node_len = @min(node_len.*, nodes.len);
        const active_connection_len = @min(connection_len.*, connections.len);
        node_len.* = active_node_len;
        connection_len.* = active_connection_len;
        if (!self.canInsertNodeChainWithPolicy(nodes, active_node_len, connections, active_connection_len, chain, policy)) return false;
        var insert_index = active_node_len;
        for (chain.nodes, 0..) |template, i| {
            const id = uniqueDuplicateNodeId(nodes[0..insert_index], @as(u32, @intCast(insert_index + 1)), 1000);
            nodes[insert_index] = nodeFromTemplate(template, id, .{
                chain.start_pos[0] + chain.node_gap[0] * @as(f32, @floatFromInt(i)),
                chain.start_pos[1] + chain.node_gap[1] * @as(f32, @floatFromInt(i)),
            });
            insert_index += 1;
        }
        var connection_index = active_connection_len;
        for (chain.connections) |connection| {
            if (connection.from_id >= chain.nodes.len or connection.to_id >= chain.nodes.len) continue;
            var mapped = connection;
            mapped.from_id = nodes[active_node_len + @as(usize, @intCast(connection.from_id))].id;
            mapped.to_id = nodes[active_node_len + @as(usize, @intCast(connection.to_id))].id;
            if (connectionAllowed(nodes[0..insert_index], connections[0..connection_index], mapped, policy, .{})) {
                connections[connection_index] = mapped;
                connection_index += 1;
            }
        }
        node_len.* = insert_index;
        connection_len.* = connection_index;
        self.selected_node_len = 0;
        self.selected_node_id = null;
        self.selected_group_id = null;
        self.selected_connection = null;
        for (nodes[active_node_len..insert_index]) |node| {
            if (self.selected_node_len < self.selected_node_ids.len) {
                self.selected_node_ids[self.selected_node_len] = node.id;
                self.selected_node_len += 1;
            }
            self.selected_node_id = node.id;
        }
        return true;
    }

    pub fn canMutateSelectedNodes(self: *const State, command: SelectionCommand, nodes: []const Node, node_len: usize) bool {
        const count = @min(node_len, nodes.len);
        const selected_count = self.selectedNodeStorageCount(nodes, count);
        return switch (command) {
            .delete => selected_count > 0,
            .duplicate => selected_count > 0 and count + selected_count <= nodes.len,
            .rename, .focus => selected_count > 0,
        };
    }

    pub fn deleteSelectedNodes(self: *State, nodes: []Node, node_len: *usize) bool {
        const count = @min(node_len.*, nodes.len);
        node_len.* = count;
        if (count == 0 or !self.canMutateSelectedNodes(.delete, nodes, count)) return false;
        var write: usize = 0;
        var changed = false;
        var read: usize = 0;
        while (read < count) : (read += 1) {
            if (self.isNodeSelected(nodes[read].id)) {
                changed = true;
                continue;
            }
            if (write != read) nodes[write] = nodes[read];
            write += 1;
        }
        if (changed) _ = self.clearSelection();
        node_len.* = write;
        return changed;
    }

    pub fn deleteSelectedNodesAndConnections(self: *State, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize) bool {
        const removed_ids = self.selectedNodeIdsInStorage(nodes, node_len.*);
        const selected_connection_before = self.selected_connection;
        const nodes_changed = self.deleteSelectedNodes(nodes, node_len);
        var connections_changed = removeConnectionsTouchingIds(connections, connection_len, removed_ids.ids[0..removed_ids.len]);
        if (selected_connection_before) |connection| {
            connections_changed = removeConnection(connections, connection_len, connection) or connections_changed;
        }
        if (connections_changed) {
            self.selected_connection = null;
            self.hover_connection = null;
        }
        return nodes_changed or connections_changed;
    }

    pub fn duplicateSelectedNodes(self: *State, nodes: []Node, node_len: *usize, id_offset: u32, offset: [2]f32) bool {
        const count = @min(node_len.*, nodes.len);
        node_len.* = count;
        const duplicate_count = self.selectedNodeStorageCount(nodes, count);
        if (count == 0 or duplicate_count == 0 or count + duplicate_count > nodes.len) return false;
        var append_index = count;
        for (nodes[0..count]) |node| {
            if (!self.isNodeSelected(node.id)) continue;
            var duplicate = node;
            duplicate.id = uniqueDuplicateNodeId(nodes[0..append_index], node.id, id_offset);
            duplicate.pos[0] += offset[0];
            duplicate.pos[1] += offset[1];
            nodes[append_index] = duplicate;
            append_index += 1;
        }
        self.selected_node_len = 0;
        self.selected_node_id = null;
        self.selected_connection = null;
        for (nodes[count..append_index]) |duplicate| {
            if (self.selected_node_len < self.selected_node_ids.len) {
                self.selected_node_ids[self.selected_node_len] = duplicate.id;
                self.selected_node_len += 1;
            }
            self.selected_node_id = duplicate.id;
        }
        node_len.* = append_index;
        return true;
    }

    pub fn duplicateSelectedNodesAndConnections(self: *State, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize, id_offset: u32, offset: [2]f32) bool {
        const selected_before = self.selectedNodeIdsInStorage(nodes, node_len.*);
        if (selected_before.len == 0) return false;
        const old_len = @min(node_len.*, nodes.len);
        const clamped_connection_len = @min(connection_len.*, connections.len);
        connection_len.* = clamped_connection_len;
        const internal_connection_count = countInternalConnectionsTouchingIds(connections, clamped_connection_len, selected_before.ids[0..selected_before.len]);
        if (clamped_connection_len + internal_connection_count > connections.len) return false;
        if (!self.duplicateSelectedNodes(nodes, node_len, id_offset, offset)) return false;

        var mapping = NodeEditorDuplicateMap{};
        const new_len = @min(node_len.*, nodes.len);
        var i: usize = 0;
        while (i < selected_before.len and old_len + i < new_len) : (i += 1) {
            mapping.add(selected_before.ids[i], nodes[old_len + i].id);
        }
        if (mapping.len == 0) return true;

        var append_index = clamped_connection_len;
        for (connections[0..clamped_connection_len]) |connection| {
            const from_id = mapping.mappedId(connection.from_id) orelse continue;
            const to_id = mapping.mappedId(connection.to_id) orelse continue;
            var duplicate = connection;
            duplicate.from_id = from_id;
            duplicate.to_id = to_id;
            if (!connectionExists(connections[0..append_index], duplicate)) {
                connections[append_index] = duplicate;
                append_index += 1;
            }
        }
        connection_len.* = append_index;
        return true;
    }

    pub fn canMutateSelectedNodeGraph(self: *const State, command: SelectionCommand, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize) bool {
        const count = @min(node_len, nodes.len);
        const selected_count = self.selectedNodeStorageCount(nodes, count);
        return switch (command) {
            .delete => selected_count > 0 or self.selectedConnectionExists(connections, connection_len),
            .duplicate => blk: {
                if (selected_count == 0 or count + selected_count > nodes.len) break :blk false;
                const selected_ids = self.selectedNodeIdsInStorage(nodes, count);
                const internal_connections = countInternalConnectionsTouchingIds(connections, connection_len, selected_ids.ids[0..selected_ids.len]);
                break :blk @min(connection_len, connections.len) + internal_connections <= connections.len;
            },
            .rename, .focus => selected_count > 0,
        };
    }

    pub fn selectedConnectionExists(self: *const State, connections: []const Connection, connection_len: usize) bool {
        const selected = self.selected_connection orelse return false;
        return connectionExists(connections[0..@min(connection_len, connections.len)], selected);
    }

    pub fn selectedGraphBounds(self: *const State, nodes: []const Node, node_len: usize, groups: []const Group) ?Rect {
        const count = @min(node_len, nodes.len);
        var bounds: ?Rect = null;
        for (nodes[0..count]) |node| {
            if (self.isNodeSelected(node.id)) includeBounds(&bounds, nodeGraphRect(node));
        }
        if (self.selected_group_id) |group_id| {
            for (groups) |group| {
                if (group.id == group_id) {
                    includeBounds(&bounds, group.rect);
                    break;
                }
            }
        }
        if (self.selected_connection) |selected| {
            for (nodes[0..count]) |node| {
                if (node.id == selected.from_id or node.id == selected.to_id) {
                    includeBounds(&bounds, nodeGraphRect(node));
                }
            }
        }
        return bounds;
    }

    pub fn focusSelectionInViewport(self: *State, viewport: Rect, nodes: []const Node, node_len: usize, groups: []const Group) bool {
        const bounds = self.selectedGraphBounds(nodes, node_len, groups) orelse return false;
        return self.frameGraphBoundsInViewport(viewport, bounds, 0.18);
    }

    pub fn frameAllInViewport(self: *State, viewport: Rect, nodes: []const Node, node_len: usize, groups: []const Group) bool {
        const count = @min(node_len, nodes.len);
        if (count == 0 and groups.len == 0) return false;
        return self.frameGraphBoundsInViewport(viewport, graphBounds(nodes[0..count], groups), 0.14);
    }

    pub fn canReconnectSelectedConnectionToPreviousNode(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize) bool {
        return self.canReconnectSelectedConnectionToPreviousNodeWithPolicy(connections, connection_len, nodes, node_len, .default);
    }

    pub fn canReconnectSelectedConnectionToPreviousNodeWithPolicy(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, policy: ConnectionPolicy) bool {
        return self.selectedAdjacentReconnectCandidate(connections, connection_len, nodes, node_len, .previous, policy) != null;
    }

    pub fn canReconnectSelectedConnectionToNextNode(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize) bool {
        return self.canReconnectSelectedConnectionToNextNodeWithPolicy(connections, connection_len, nodes, node_len, .default);
    }

    pub fn canReconnectSelectedConnectionToNextNodeWithPolicy(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, policy: ConnectionPolicy) bool {
        return self.selectedAdjacentReconnectCandidate(connections, connection_len, nodes, node_len, .next, policy) != null;
    }

    pub fn reconnectSelectedConnectionToPreviousNode(self: *State, connections: []Connection, connection_len: *usize, nodes: []const Node, node_len: usize) bool {
        return self.reconnectSelectedConnectionToPreviousNodeWithPolicy(connections, connection_len, nodes, node_len, .default);
    }

    pub fn reconnectSelectedConnectionToPreviousNodeWithPolicy(self: *State, connections: []Connection, connection_len: *usize, nodes: []const Node, node_len: usize, policy: ConnectionPolicy) bool {
        return self.reconnectSelectedConnectionToAdjacentNode(connections, connection_len, nodes, node_len, .previous, policy);
    }

    pub fn reconnectSelectedConnectionToNextNode(self: *State, connections: []Connection, connection_len: *usize, nodes: []const Node, node_len: usize) bool {
        return self.reconnectSelectedConnectionToNextNodeWithPolicy(connections, connection_len, nodes, node_len, .default);
    }

    pub fn reconnectSelectedConnectionToNextNodeWithPolicy(self: *State, connections: []Connection, connection_len: *usize, nodes: []const Node, node_len: usize, policy: ConnectionPolicy) bool {
        return self.reconnectSelectedConnectionToAdjacentNode(connections, connection_len, nodes, node_len, .next, policy);
    }

    pub fn canGroupSelectedNodes(self: *const State, nodes: []const Node, node_len: usize, groups: []const Group, group_len: usize) bool {
        return self.selectedNodeStorageCount(nodes, node_len) > 0 and @min(group_len, groups.len) < groups.len;
    }

    pub fn canUngroupSelected(self: *const State, groups: []const Group, group_len: usize) bool {
        const group_id = self.selected_group_id orelse return false;
        return groupIndexById(groups[0..@min(group_len, groups.len)], group_id) != null;
    }

    pub fn canSelectGroupContents(self: *const State, nodes: []const Node, node_len: usize, groups: []const Group, group_len: usize) bool {
        const group = self.selectedGroup(groups, group_len) orelse return false;
        for (nodes[0..@min(node_len, nodes.len)]) |node| {
            if (nodeInsideGraphRect(node, group.rect)) return true;
        }
        return false;
    }

    pub fn canFitGroupToSelection(self: *const State, nodes: []const Node, node_len: usize, groups: []const Group, group_len: usize) bool {
        return self.selectedGroup(groups, group_len) != null and self.selectedNodeStorageCount(nodes, node_len) > 0;
    }

    pub fn groupSelectedNodes(self: *State, nodes: []const Node, node_len: usize, groups: []Group, group_len: *usize, title: []const u8) bool {
        const count = @min(node_len, nodes.len);
        const clamped_group_len = @min(group_len.*, groups.len);
        group_len.* = clamped_group_len;
        if (clamped_group_len >= groups.len) return false;
        const bounds = self.selectedNodesBounds(nodes, count) orelse return false;
        const group_id = uniqueGroupId(groups[0..clamped_group_len], 1000);
        groups[clamped_group_len] = .{
            .id = group_id,
            .title = title,
            .rect = paddedBounds(bounds, 0.16),
        };
        group_len.* = clamped_group_len + 1;
        _ = self.setGroupSelection(group_id);
        return true;
    }

    pub fn ungroupSelected(self: *State, groups: []Group, group_len: *usize) bool {
        const group_id = self.selected_group_id orelse return false;
        const count = @min(group_len.*, groups.len);
        group_len.* = count;
        const remove_index = groupIndexById(groups[0..count], group_id) orelse return false;
        var index = remove_index;
        while (index + 1 < count) : (index += 1) groups[index] = groups[index + 1];
        group_len.* = count - 1;
        self.selected_group_id = null;
        return true;
    }

    pub fn selectGroupContents(self: *State, nodes: []const Node, node_len: usize, groups: []const Group, group_len: usize) bool {
        const group = self.selectedGroup(groups, group_len) orelse return false;
        const before_len = self.selected_node_len;
        const before_id = self.selected_node_id;
        var before_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| before_hash = before_hash *% 16777619 +% id;
        self.selected_node_len = 0;
        for (nodes[0..@min(node_len, nodes.len)]) |node| {
            if (!nodeInsideGraphRect(node, group.rect) or self.selected_node_len >= self.selected_node_ids.len) continue;
            self.selected_node_ids[self.selected_node_len] = node.id;
            self.selected_node_len += 1;
        }
        self.selected_node_id = if (self.selected_node_len > 0) self.selected_node_ids[self.selected_node_len - 1] else null;
        self.selected_group_id = null;
        self.selected_connection = null;
        var after_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| after_hash = after_hash *% 16777619 +% id;
        return before_len != self.selected_node_len or before_id != self.selected_node_id or before_hash != after_hash;
    }

    pub fn fitSelectedGroupToSelection(self: *State, nodes: []const Node, node_len: usize, groups: []Group, group_len: usize) bool {
        const group_id = self.selected_group_id orelse return false;
        const group_index = groupIndexById(groups[0..@min(group_len, groups.len)], group_id) orelse return false;
        const bounds = self.selectedNodesBounds(nodes, node_len) orelse return false;
        const next_rect = paddedBounds(bounds, 0.16);
        const before = groups[group_index].rect;
        groups[group_index].rect = next_rect;
        return @abs(before.x - next_rect.x) > 0.001 or @abs(before.y - next_rect.y) > 0.001 or
            @abs(before.w - next_rect.w) > 0.001 or @abs(before.h - next_rect.h) > 0.001;
    }

    pub fn canDisconnectSelectedLink(self: *const State, connections: []const Connection, connection_len: usize) bool {
        return self.selectedConnectionExists(connections, connection_len);
    }

    pub fn canDisconnectSelectedNodeLinks(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, command: NodeEditorCommand) bool {
        if (self.selectedNodeStorageCount(nodes, node_len) == 0) return false;
        return self.countSelectedNodeLinks(connections, connection_len, command) > 0;
    }

    pub fn disconnectSelectedLink(self: *State, connections: []Connection, connection_len: *usize) bool {
        const selected = self.selected_connection orelse return false;
        const changed = removeConnection(connections, connection_len, selected);
        if (changed) {
            self.selected_connection = null;
            self.hover_connection = null;
        }
        return changed;
    }

    pub fn disconnectSelectedNodeLinks(self: *State, connections: []Connection, connection_len: *usize, command: NodeEditorCommand) bool {
        const count = @min(connection_len.*, connections.len);
        connection_len.* = count;
        var write: usize = 0;
        var changed = false;
        var read: usize = 0;
        while (read < count) : (read += 1) {
            const connection = connections[read];
            const remove = switch (command) {
                .disconnect_selected_inputs => self.isNodeSelected(connection.to_id),
                .disconnect_selected_outputs => self.isNodeSelected(connection.from_id),
                .disconnect_selected_links => self.isNodeSelected(connection.from_id) or self.isNodeSelected(connection.to_id),
                else => false,
            };
            if (remove) {
                changed = true;
                continue;
            }
            if (write != read) connections[write] = connection;
            write += 1;
        }
        connection_len.* = write;
        if (changed) {
            self.selected_connection = null;
            self.hover_connection = null;
        }
        return changed;
    }

    pub fn canSelectConnectedNodes(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, command: NodeEditorCommand) bool {
        const related = self.connectedNodeSelection(connections, connection_len, nodes, node_len, command);
        if (related.len == 0) return false;
        if (self.selected_connection != null or self.selected_group_id != null) return true;
        if (related.len != self.selectedNodeStorageCount(nodes, node_len)) return true;
        for (related.ids[0..related.len]) |id| {
            if (!self.isNodeSelected(id)) return true;
        }
        return false;
    }

    /// Check an upstream/downstream selection against a reusable topology
    /// index. This path scales with the reachable subgraph instead of rescanning
    /// every connection for every visited node.
    pub fn canSelectConnectedNodesIndexed(self: *const State, topology: *graph_topology.Index, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, command: NodeEditorCommand) bool {
        const active_nodes = nodes[0..@min(node_len, nodes.len)];
        const active_connections = connections[0..@min(connection_len, connections.len)];
        const traversal = self.traverseConnectedNodes(topology, active_connections, active_nodes, command) orelse
            return self.canSelectConnectedNodes(active_connections, active_connections.len, active_nodes, active_nodes.len, command);
        if (traversal.visited_node_count == 0) return false;
        if (self.selected_connection != null or self.selected_group_id != null) return true;

        const target_len = @min(traversal.visited_node_count, self.selected_node_ids.len);
        if (self.boundedSelectionLen() != target_len) return true;
        var target_index: usize = 0;
        var last_reachable_id: ?u32 = null;
        for (active_nodes, 0..) |node, index| {
            if (!topology.nodeReachableAt(index)) continue;
            last_reachable_id = node.id;
            if (target_index < target_len) {
                if (self.selected_node_ids[target_index] != node.id) return true;
                target_index += 1;
            }
        }
        const target_selected_id = if (target_len > 0)
            reachableNodeIdAt(topology, active_nodes, target_len - 1)
        else
            last_reachable_id;
        return self.selected_node_id != target_selected_id;
    }

    pub fn selectConnectedNodes(self: *State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, command: NodeEditorCommand) bool {
        const related = self.connectedNodeSelection(connections, connection_len, nodes, node_len, command);
        if (related.len == 0) return false;
        const before_len = self.selected_node_len;
        const before_id = self.selected_node_id;
        var before_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| before_hash = before_hash *% 16777619 +% id;
        self.selected_node_len = 0;
        for (related.ids[0..related.len]) |id| {
            if (self.selected_node_len >= self.selected_node_ids.len) break;
            self.selected_node_ids[self.selected_node_len] = id;
            self.selected_node_len += 1;
        }
        self.selected_node_id = if (self.selected_node_len > 0) self.selected_node_ids[self.selected_node_len - 1] else null;
        self.selected_group_id = null;
        self.selected_connection = null;
        var after_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| after_hash = after_hash *% 16777619 +% id;
        return before_len != self.selected_node_len or before_id != self.selected_node_id or before_hash != after_hash;
    }

    pub fn selectConnectedNodesIndexed(self: *State, topology: *graph_topology.Index, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, command: NodeEditorCommand) bool {
        return self.selectConnectedNodesIndexedDetailed(topology, connections, connection_len, nodes, node_len, command).changed;
    }

    pub fn selectConnectedNodesIndexedDetailed(self: *State, topology: *graph_topology.Index, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, command: NodeEditorCommand) ConnectedSelectionResult {
        const active_nodes = nodes[0..@min(node_len, nodes.len)];
        const active_connections = connections[0..@min(connection_len, connections.len)];
        var traversal = self.traverseConnectedNodes(topology, active_connections, active_nodes, command) orelse return .{
            .changed = self.selectConnectedNodes(active_connections, active_connections.len, active_nodes, active_nodes.len, command),
            .traversal = .{ .topology_unavailable = true },
        };
        if (traversal.visited_node_count == 0) return .{ .traversal = traversal };

        const before_len = self.boundedSelectionLen();
        const before_id = self.selected_node_id;
        const before_group = self.selected_group_id;
        const before_connection = self.selected_connection;
        var before_hash: u64 = 0;
        for (self.selected_node_ids[0..before_len]) |id| before_hash = before_hash *% 16777619 +% id;

        topology.writeReachableNodeIds(self.selected_node_ids, &traversal);
        self.selected_node_len = traversal.output_count;
        self.selected_node_id = if (self.selected_node_len > 0)
            self.selected_node_ids[self.selected_node_len - 1]
        else
            lastReachableNodeId(topology, active_nodes);
        self.selected_group_id = null;
        self.selected_connection = null;

        var after_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| after_hash = after_hash *% 16777619 +% id;
        return .{
            .traversal = traversal,
            .changed = before_len != self.selected_node_len or before_id != self.selected_node_id or
                before_group != self.selected_group_id or !optionalConnectionEqual(before_connection, self.selected_connection) or
                before_hash != after_hash,
        };
    }

    pub fn canDisconnectContextPortLinks(self: *const State, connections: []const Connection, connection_len: usize) bool {
        return self.countContextPortLinks(connections, connection_len) > 0;
    }

    pub fn disconnectContextPortLinks(self: *State, connections: []Connection, connection_len: *usize) bool {
        const target = self.contextPortTarget() orelse return false;
        const count = @min(connection_len.*, connections.len);
        connection_len.* = count;
        var write: usize = 0;
        var changed = false;
        var read: usize = 0;
        while (read < count) : (read += 1) {
            const connection = connections[read];
            const remove = target.matches(connection);
            if (remove) {
                changed = true;
                continue;
            }
            if (write != read) connections[write] = connection;
            write += 1;
        }
        connection_len.* = write;
        if (changed) {
            self.selected_connection = null;
            self.hover_connection = null;
        }
        return changed;
    }

    pub fn canSelectContextPortPeers(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize) bool {
        return self.contextPortPeerSelection(connections, connection_len, nodes, node_len).len > 0;
    }

    pub fn selectContextPortPeers(self: *State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize) bool {
        const peers = self.contextPortPeerSelection(connections, connection_len, nodes, node_len);
        if (peers.len == 0) return false;
        const before_len = self.selected_node_len;
        const before_id = self.selected_node_id;
        var before_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| before_hash = before_hash *% 16777619 +% id;
        self.selected_node_len = 0;
        for (peers.ids[0..peers.len]) |id| {
            if (self.selected_node_len >= self.selected_node_ids.len) break;
            self.selected_node_ids[self.selected_node_len] = id;
            self.selected_node_len += 1;
        }
        self.selected_node_id = if (self.selected_node_len > 0) self.selected_node_ids[self.selected_node_len - 1] else null;
        self.selected_group_id = null;
        self.selected_connection = null;
        var after_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| after_hash = after_hash *% 16777619 +% id;
        return before_len != self.selected_node_len or before_id != self.selected_node_id or before_hash != after_hash;
    }

    pub fn copySelectionToClipboard(self: *const State, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize, clipboard: *Clipboard) bool {
        const count = @min(node_len, nodes.len);
        const selected_ids = self.selectedNodeIdsInStorage(nodes, count);
        if (selected_ids.len == 0) return false;

        clipboard.clear();
        var bounds: ?Rect = null;
        for (nodes[0..count]) |node| {
            if (!idInList(selected_ids.ids[0..selected_ids.len], node.id)) continue;
            if (clipboard.node_len >= clipboard.nodes.len) break;
            clipboard.nodes[clipboard.node_len] = node;
            clipboard.source_ids[clipboard.node_len] = node.id;
            clipboard.node_len += 1;
            includeBounds(&bounds, nodeGraphRect(node));
        }
        for (connections[0..@min(connection_len, connections.len)]) |connection| {
            if (clipboard.connection_len >= clipboard.connections.len) break;
            if (!idInList(selected_ids.ids[0..selected_ids.len], connection.from_id) or
                !idInList(selected_ids.ids[0..selected_ids.len], connection.to_id)) continue;
            clipboard.connections[clipboard.connection_len] = connection;
            clipboard.connection_len += 1;
        }
        clipboard.copied_bounds = bounds orelse .zero;
        return clipboard.node_len > 0;
    }

    pub fn canPasteClipboard(self: *const State, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize, clipboard: Clipboard) bool {
        return self.canPasteClipboardWithPolicy(nodes, node_len, connections, connection_len, clipboard, .default);
    }

    pub fn canPasteClipboardWithPolicy(self: *const State, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize, clipboard: Clipboard, policy: ConnectionPolicy) bool {
        _ = self;
        const active_node_len = @min(node_len, nodes.len);
        const active_connection_len = @min(connection_len, connections.len);
        if (clipboard.node_len == 0 or active_node_len + clipboard.node_len > nodes.len or active_connection_len + clipboard.connection_len > connections.len) return false;
        return validateGraph(clipboard.nodes[0..clipboard.node_len], clipboard.connections[0..clipboard.connection_len], policy).validFor(policy);
    }

    pub fn pasteClipboard(self: *State, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize, clipboard: *Clipboard, offset: [2]f32) bool {
        return self.pasteClipboardWithPolicy(nodes, node_len, connections, connection_len, clipboard, offset, .default);
    }

    pub fn pasteClipboardWithPolicy(self: *State, nodes: []Node, node_len: *usize, connections: []Connection, connection_len: *usize, clipboard: *Clipboard, offset: [2]f32, policy: ConnectionPolicy) bool {
        const active_node_len = @min(node_len.*, nodes.len);
        const active_connection_len = @min(connection_len.*, connections.len);
        node_len.* = active_node_len;
        connection_len.* = active_connection_len;
        if (!self.canPasteClipboardWithPolicy(nodes, active_node_len, connections, active_connection_len, clipboard.*, policy)) return false;

        const paste_index = clipboard.paste_count +% 1;
        const step = if (paste_index == 0) @as(f32, 1.0) else @as(f32, @floatFromInt(paste_index));
        const delta = .{ offset[0] * step, offset[1] * step };
        var mapping = NodeEditorDuplicateMap{};
        var append_node = active_node_len;
        for (clipboard.nodes[0..clipboard.node_len], 0..) |source, index| {
            const source_id = clipboard.source_ids[index];
            var pasted = source;
            pasted.id = uniqueDuplicateNodeId(nodes[0..append_node], source_id, 1000 + paste_index);
            pasted.pos[0] += delta[0];
            pasted.pos[1] += delta[1];
            nodes[append_node] = pasted;
            mapping.add(source_id, pasted.id);
            append_node += 1;
        }

        var append_connection = active_connection_len;
        for (clipboard.connections[0..clipboard.connection_len]) |connection| {
            const from_id = mapping.mappedId(connection.from_id) orelse continue;
            const to_id = mapping.mappedId(connection.to_id) orelse continue;
            var pasted = connection;
            pasted.from_id = from_id;
            pasted.to_id = to_id;
            if (connectionAllowed(nodes[0..append_node], connections[0..append_connection], pasted, policy, .{})) {
                connections[append_connection] = pasted;
                append_connection += 1;
            }
        }

        node_len.* = append_node;
        connection_len.* = append_connection;
        self.selected_node_id = null;
        self.selected_node_len = 0;
        self.selected_group_id = null;
        self.selected_connection = null;
        for (nodes[active_node_len..append_node]) |node| {
            if (self.selected_node_len < self.selected_node_ids.len) {
                self.selected_node_ids[self.selected_node_len] = node.id;
                self.selected_node_len += 1;
            }
            self.selected_node_id = node.id;
        }
        clipboard.paste_count = paste_index;
        return true;
    }

    pub fn openContextMenu(self: *State, target: ContextTarget, screen_pos: [2]f32) bool {
        self.context_menu.openAt(target, screen_pos);
        return true;
    }

    pub fn closeContextMenu(self: *State) bool {
        return self.context_menu.close();
    }

    pub fn contextMenuModel(self: *const State, allocator: std.mem.Allocator, nodes: []const Node, node_len: usize, connections: []const Connection, connection_len: usize, clipboard: ?*const Clipboard) !MenuModel {
        var items = std.ArrayList(MenuItem).empty;
        errdefer items.deinit(allocator);
        const can_copy = self.selectedNodeStorageCount(nodes, node_len) > 0;
        const can_paste = if (clipboard) |clip| self.canPasteClipboard(nodes, node_len, connections, connection_len, clip.*) else false;
        switch (self.context_menu.target) {
            .node, .canvas => {
                try items.append(allocator, .{ .command_id = NodeEditorCommand.copy_selection.commandId(), .enabled = can_copy });
                try items.append(allocator, .{ .command_id = NodeEditorCommand.paste_clipboard.commandId(), .enabled = can_paste });
                try items.append(allocator, MenuItem.separator());
                try items.append(allocator, .{ .command_id = NodeEditorCommand.select_all.commandId(), .enabled = @min(node_len, nodes.len) > 0 });
                try items.append(allocator, .{ .command_id = NodeEditorCommand.frame_all.commandId(), .enabled = @min(node_len, nodes.len) > 0 });
            },
            .connection, .input_port, .output_port => {
                try items.append(allocator, .{ .command_id = NodeEditorCommand.disconnect_selected_link.commandId(), .enabled = self.selectedConnectionExists(connections, connection_len) });
                try items.append(allocator, .{ .command_id = NodeEditorCommand.select_upstream_nodes.commandId(), .enabled = self.canSelectConnectedNodes(connections, connection_len, nodes, node_len, .select_upstream_nodes) });
                try items.append(allocator, .{ .command_id = NodeEditorCommand.select_downstream_nodes.commandId(), .enabled = self.canSelectConnectedNodes(connections, connection_len, nodes, node_len, .select_downstream_nodes) });
            },
            .group => {
                try items.append(allocator, .{ .command_id = NodeEditorCommand.select_group_contents.commandId() });
                try items.append(allocator, .{ .command_id = NodeEditorCommand.fit_group_to_selection.commandId() });
                try items.append(allocator, .{ .command_id = NodeEditorCommand.ungroup_selected.commandId() });
            },
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    pub fn inspectorSnapshot(self: *const State, nodes: []const Node, node_len: usize, groups: []const Group, group_len: usize, connections: []const Connection, connection_len: usize) InspectorSnapshot {
        const count = @min(node_len, nodes.len);
        var snapshot = InspectorSnapshot{
            .selected_node_count = self.selectedNodeStorageCount(nodes, count),
            .selected_group_id = self.selected_group_id,
            .selected_connection = self.selected_connection,
            .bounds = self.selectedGraphBounds(nodes, count, groups[0..@min(group_len, groups.len)]),
        };
        if (snapshot.selected_node_count == 1) {
            if (self.lastSelectedStoredNodeId(nodes, count)) |id| {
                if (nodeById(nodes[0..count], id)) |node| {
                    snapshot.title = node.title;
                    snapshot.input_count = inputPortCount(node);
                    snapshot.output_count = outputPortCount(node);
                }
            }
        } else if (snapshot.selected_node_count > 1) {
            snapshot.title = "Multiple Nodes";
        } else if (self.selected_group_id != null) {
            snapshot.title = "Group";
        } else if (self.selected_connection != null) {
            snapshot.title = "Connection";
        }
        for (connections[0..@min(connection_len, connections.len)]) |connection| {
            if (self.isNodeSelected(connection.to_id)) snapshot.incoming_links += 1;
            if (self.isNodeSelected(connection.from_id)) snapshot.outgoing_links += 1;
        }
        return snapshot;
    }

    pub fn inspectorDraft(self: *const State, nodes: []const Node, node_len: usize) InspectorDraft {
        const id = self.lastSelectedStoredNodeId(nodes, node_len) orelse return .{};
        const node = nodeById(nodes[0..@min(node_len, nodes.len)], id) orelse return .{};
        return .{
            .node_id = id,
            .title = node.title,
            .pos = node.pos,
            .size = node.size,
            .input_count = node.input_count,
            .output_count = node.output_count,
        };
    }

    pub fn applyInspectorDraft(self: *State, nodes: []Node, node_len: usize, draft: InspectorDraft) bool {
        const id = draft.node_id orelse return false;
        const count = @min(node_len, nodes.len);
        for (nodes[0..count]) |*node| {
            if (node.id != id) continue;
            const before_title = node.title;
            const before_pos = node.pos;
            const before_size = node.size;
            node.title = draft.title;
            node.pos = draft.pos;
            node.size = .{ .w = @max(16.0, draft.size.w), .h = @max(16.0, draft.size.h) };
            _ = self.setSingleSelection(id);
            return !std.mem.eql(u8, before_title, node.title) or
                @abs(before_pos[0] - node.pos[0]) > 0.001 or
                @abs(before_pos[1] - node.pos[1]) > 0.001 or
                @abs(before_size.w - node.size.w) > 0.001 or
                @abs(before_size.h - node.size.h) > 0.001;
        }
        return false;
    }

    const SelectedNodeIdList = struct {
        ids: [64]u32 = .{0} ** 64,
        len: usize = 0,
    };

    const ContextPortTarget = struct {
        node_id: u32,
        port_index: u8,
        input: bool,

        fn matches(self: ContextPortTarget, connection: Connection) bool {
            return if (self.input)
                connection.to_id == self.node_id and connection.to_port == self.port_index
            else
                connection.from_id == self.node_id and connection.from_port == self.port_index;
        }

        fn peerId(self: ContextPortTarget, connection: Connection) ?u32 {
            if (!self.matches(connection)) return null;
            return if (self.input) connection.from_id else connection.to_id;
        }
    };

    const NodeEditorDuplicateMap = struct {
        from_ids: [64]u32 = .{0} ** 64,
        to_ids: [64]u32 = .{0} ** 64,
        len: usize = 0,

        fn add(self: *NodeEditorDuplicateMap, from_id: u32, to_id: u32) void {
            if (self.len >= self.from_ids.len) return;
            self.from_ids[self.len] = from_id;
            self.to_ids[self.len] = to_id;
            self.len += 1;
        }

        fn mappedId(self: *const NodeEditorDuplicateMap, id: u32) ?u32 {
            for (self.from_ids[0..self.len], 0..) |from_id, index| {
                if (from_id == id) return self.to_ids[index];
            }
            return null;
        }
    };

    fn selectedNodeIdsInStorage(self: *const State, nodes: []const Node, node_len: usize) SelectedNodeIdList {
        const count = @min(node_len, nodes.len);
        var out = SelectedNodeIdList{};
        for (nodes[0..count]) |node| {
            if (!self.isNodeSelected(node.id) or out.len >= out.ids.len) continue;
            out.ids[out.len] = node.id;
            out.len += 1;
        }
        return out;
    }

    fn selectedNodesBounds(self: *const State, nodes: []const Node, node_len: usize) ?Rect {
        const count = @min(node_len, nodes.len);
        var bounds: ?Rect = null;
        for (nodes[0..count]) |node| {
            if (self.isNodeSelected(node.id)) includeBounds(&bounds, nodeGraphRect(node));
        }
        return bounds;
    }

    fn selectedGroup(self: *const State, groups: []const Group, group_len: usize) ?Group {
        const group_id = self.selected_group_id orelse return null;
        const count = @min(group_len, groups.len);
        if (groupIndexById(groups[0..count], group_id)) |index| return groups[index];
        return null;
    }

    fn countSelectedNodeLinks(self: *const State, connections: []const Connection, connection_len: usize, command: NodeEditorCommand) usize {
        var count: usize = 0;
        for (connections[0..@min(connection_len, connections.len)]) |connection| {
            const selected = switch (command) {
                .disconnect_selected_inputs => self.isNodeSelected(connection.to_id),
                .disconnect_selected_outputs => self.isNodeSelected(connection.from_id),
                .disconnect_selected_links => self.isNodeSelected(connection.from_id) or self.isNodeSelected(connection.to_id),
                else => false,
            };
            if (selected) count += 1;
        }
        return count;
    }

    fn connectedNodeSelection(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, command: NodeEditorCommand) SelectedNodeIdList {
        const active_nodes = nodes[0..@min(node_len, nodes.len)];
        var out = SelectedNodeIdList{};
        if (command != .select_upstream_nodes and command != .select_downstream_nodes) return out;

        if (self.selected_connection) |connection| {
            const seed_id = switch (command) {
                .select_upstream_nodes => connection.from_id,
                .select_downstream_nodes => connection.to_id,
                else => unreachable,
            };
            appendUniqueNodeId(&out, active_nodes, seed_id);
        }
        for (active_nodes) |node| {
            if (self.isNodeSelected(node.id)) appendUniqueNodeId(&out, active_nodes, node.id);
        }

        var scan: usize = 0;
        while (scan < out.len) : (scan += 1) {
            const anchor = out.ids[scan];
            for (connections[0..@min(connection_len, connections.len)]) |connection| {
                const maybe_id = switch (command) {
                    .select_upstream_nodes => if (connection.to_id == anchor) connection.from_id else null,
                    .select_downstream_nodes => if (connection.from_id == anchor) connection.to_id else null,
                    else => unreachable,
                };
                const id = maybe_id orelse continue;
                appendUniqueNodeId(&out, active_nodes, id);
            }
        }
        sortSelectedNodeIdsByStorageOrder(&out, active_nodes);
        return out;
    }

    fn traverseConnectedNodes(self: *const State, topology: *graph_topology.Index, connections: []const Connection, nodes: []const Node, command: NodeEditorCommand) ?graph_topology.TraversalResult {
        const direction: graph_topology.Direction = switch (command) {
            .select_upstream_nodes => .upstream,
            .select_downstream_nodes => .downstream,
            else => return null,
        };
        if (!topology.ensure(nodes, connections).usable()) return null;
        const connection_seed = if (self.selected_connection) |connection| switch (direction) {
            .upstream => connection.from_id,
            .downstream => connection.to_id,
        } else null;
        const primary_seed = connection_seed orelse if (self.boundedSelectionLen() == 0) self.selected_node_id else null;
        return topology.traverse(direction, primary_seed, self.selected_node_ids[0..self.boundedSelectionLen()]);
    }

    fn lastReachableNodeId(topology: *const graph_topology.Index, nodes: []const Node) ?u32 {
        var last: ?u32 = null;
        for (nodes, 0..) |node, index| {
            if (topology.nodeReachableAt(index)) last = node.id;
        }
        return last;
    }

    fn reachableNodeIdAt(topology: *const graph_topology.Index, nodes: []const Node, target_index: usize) ?u32 {
        var reachable_index: usize = 0;
        for (nodes, 0..) |node, index| {
            if (!topology.nodeReachableAt(index)) continue;
            if (reachable_index == target_index) return node.id;
            reachable_index += 1;
        }
        return null;
    }

    fn appendUniqueNodeId(out: *SelectedNodeIdList, nodes: []const Node, id: u32) void {
        if (!nodeIdExists(nodes, id) or idInList(out.ids[0..out.len], id) or out.len >= out.ids.len) return;
        out.ids[out.len] = id;
        out.len += 1;
    }

    fn sortSelectedNodeIdsByStorageOrder(out: *SelectedNodeIdList, nodes: []const Node) void {
        const discovered = out.*;
        var write: usize = 0;
        for (nodes) |node| {
            if (!idInList(discovered.ids[0..discovered.len], node.id)) continue;
            out.ids[write] = node.id;
            write += 1;
        }
        out.len = write;
    }

    fn contextPortTarget(self: *const State) ?ContextPortTarget {
        const node_id = self.context_menu.node_id orelse return null;
        return switch (self.context_menu.target) {
            .input_port => .{ .node_id = node_id, .port_index = self.context_menu.port_index, .input = true },
            .output_port => .{ .node_id = node_id, .port_index = self.context_menu.port_index, .input = false },
            else => null,
        };
    }

    fn countContextPortLinks(self: *const State, connections: []const Connection, connection_len: usize) usize {
        const target = self.contextPortTarget() orelse return 0;
        var count: usize = 0;
        for (connections[0..@min(connection_len, connections.len)]) |connection| {
            if (target.matches(connection)) count += 1;
        }
        return count;
    }

    fn contextPortPeerSelection(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize) SelectedNodeIdList {
        const target = self.contextPortTarget() orelse return .{};
        const active_nodes = nodes[0..@min(node_len, nodes.len)];
        var out = SelectedNodeIdList{};
        for (connections[0..@min(connection_len, connections.len)]) |connection| {
            const id = target.peerId(connection) orelse continue;
            if (!nodeIdExists(active_nodes, id) or idInList(out.ids[0..out.len], id)) continue;
            if (out.len >= out.ids.len) break;
            out.ids[out.len] = id;
            out.len += 1;
        }
        return out;
    }

    fn alignSelectedNodes(self: *State, nodes: []Node, command: NodeEditorCommand) bool {
        var initialized = false;
        var target: f32 = 0.0;
        for (nodes) |node| {
            if (!self.isNodeSelected(node.id)) continue;
            const value = switch (command) {
                .align_left => node.pos[0],
                .align_center_x => node.pos[0] + node.size.w * 0.5,
                .align_right => node.pos[0] + node.size.w,
                .align_top => node.pos[1],
                .align_center_y => node.pos[1] + node.size.h * 0.5,
                .align_bottom => node.pos[1] + node.size.h,
                else => return false,
            };
            if (!initialized) {
                target = value;
                initialized = true;
                continue;
            }
            target = switch (command) {
                .align_left, .align_top => @min(target, value),
                .align_right, .align_bottom => @max(target, value),
                .align_center_x, .align_center_y => target + value,
                else => target,
            };
        }
        if (!initialized) return false;
        if (command == .align_center_x or command == .align_center_y) {
            target /= @as(f32, @floatFromInt(@max(@as(usize, 1), self.selectedNodeStorageCount(nodes, nodes.len))));
        }
        var changed = false;
        for (nodes) |*node| {
            if (!self.isNodeSelected(node.id)) continue;
            const before = node.pos;
            switch (command) {
                .align_left => node.pos[0] = target,
                .align_center_x => node.pos[0] = target - node.size.w * 0.5,
                .align_right => node.pos[0] = target - node.size.w,
                .align_top => node.pos[1] = target,
                .align_center_y => node.pos[1] = target - node.size.h * 0.5,
                .align_bottom => node.pos[1] = target - node.size.h,
                else => return false,
            }
            changed = changed or @abs(before[0] - node.pos[0]) > 0.001 or @abs(before[1] - node.pos[1]) > 0.001;
        }
        return changed;
    }

    fn distributeSelectedNodes(self: *State, nodes: []Node, command: NodeEditorCommand) bool {
        var order = [_]usize{0} ** 64;
        var order_len: usize = 0;
        for (nodes, 0..) |node, index| {
            if (!self.isNodeSelected(node.id) or order_len >= order.len) continue;
            order[order_len] = index;
            order_len += 1;
        }
        if (order_len < 3) return false;
        const horizontal = switch (command) {
            .distribute_horizontal => true,
            .distribute_vertical => false,
            else => return false,
        };
        std.mem.sort(usize, order[0..order_len], DistributeSortContext{ .nodes = nodes, .horizontal = horizontal }, distributeLessThan);
        const first = nodes[order[0]];
        const last = nodes[order[order_len - 1]];
        const first_center = if (horizontal) first.pos[0] + first.size.w * 0.5 else first.pos[1] + first.size.h * 0.5;
        const last_center = if (horizontal) last.pos[0] + last.size.w * 0.5 else last.pos[1] + last.size.h * 0.5;
        const step = (last_center - first_center) / @as(f32, @floatFromInt(order_len - 1));
        var changed = false;
        for (order[0..order_len], 0..) |node_index, rank| {
            if (rank == 0 or rank + 1 == order_len) continue;
            const target_center = first_center + step * @as(f32, @floatFromInt(rank));
            const node = &nodes[node_index];
            const before = node.pos;
            if (horizontal) {
                node.pos[0] = target_center - node.size.w * 0.5;
            } else {
                node.pos[1] = target_center - node.size.h * 0.5;
            }
            changed = changed or @abs(before[0] - node.pos[0]) > 0.001 or @abs(before[1] - node.pos[1]) > 0.001;
        }
        return changed;
    }

    fn frameGraphBoundsInViewport(self: *State, viewport: Rect, bounds: Rect, padding_frac: f32) bool {
        if (viewport.w <= 1.0 or viewport.h <= 1.0 or bounds.w <= 0.0 or bounds.h <= 0.0) return false;
        self.clamp();
        const padded = paddedBounds(bounds, @max(0.0, padding_frac));
        const before_zoom = self.zoom;
        const before_pan = self.pan;
        const fit_zoom = @min(viewport.w / @max(1.0, padded.w), viewport.h / @max(1.0, padded.h));
        self.zoom = std.math.clamp(fit_zoom, self.min_zoom, self.max_zoom);
        const center = .{ padded.x + padded.w * 0.5, padded.y + padded.h * 0.5 };
        self.pan = .{ -center[0] * self.zoom, -center[1] * self.zoom };
        return @abs(before_zoom - self.zoom) > 0.0001 or @abs(before_pan[0] - self.pan[0]) > 0.001 or @abs(before_pan[1] - self.pan[1]) > 0.001;
    }

    fn reconnectSelectedConnectionToAdjacentNode(self: *State, connections: []Connection, connection_len: *usize, nodes: []const Node, node_len: usize, direction: AdjacentNodeDirection, policy: ConnectionPolicy) bool {
        const replacement = self.selectedAdjacentReconnectCandidate(connections, connection_len.*, nodes, node_len, direction, policy) orelse return false;
        const selected = self.selected_connection orelse return false;
        const count = @min(connection_len.*, connections.len);
        connection_len.* = count;
        for (connections[0..count]) |*connection| {
            if (!State.connectionEndpointsEqual(connection.*, selected)) continue;
            connection.* = replacement;
            self.selected_connection = replacement;
            self.hover_connection = replacement;
            return true;
        }
        return false;
    }

    fn selectedAdjacentReconnectCandidate(self: *const State, connections: []const Connection, connection_len: usize, nodes: []const Node, node_len: usize, direction: AdjacentNodeDirection, policy: ConnectionPolicy) ?Connection {
        const selected = self.selected_connection orelse return null;
        const active_connections = connections[0..@min(connection_len, connections.len)];
        if (!connectionExists(active_connections, selected)) return null;
        const active_nodes = nodes[0..@min(node_len, nodes.len)];
        if (adjacentNodeId(active_nodes, selected.to_id, selected.from_id, direction)) |to_id| {
            var replacement = selected;
            replacement.to_id = to_id;
            replacement.to_port = 0;
            if (reconnectCandidateValid(active_connections, selected, replacement, active_nodes, policy)) return replacement;
        }
        if (adjacentNodeId(active_nodes, selected.from_id, selected.to_id, direction)) |from_id| {
            var replacement = selected;
            replacement.from_id = from_id;
            replacement.from_port = 0;
            if (reconnectCandidateValid(active_connections, selected, replacement, active_nodes, policy)) return replacement;
        }
        return null;
    }

    fn idInList(ids: []const u32, id: u32) bool {
        for (ids) |value| {
            if (value == id) return true;
        }
        return false;
    }

    fn addNodeToSelection(self: *State, id: u32) void {
        if (self.isNodeSelected(id) or self.selected_node_ids.len == 0) return;
        if (self.selected_node_len >= self.selected_node_ids.len) return;
        self.selected_node_ids[self.selected_node_len] = id;
        self.selected_node_len += 1;
        self.selected_node_id = id;
        self.selected_group_id = null;
        self.selected_connection = null;
    }

    fn removeNodeFromSelection(self: *State, id: u32) void {
        const len = self.boundedSelectionLen();
        if (len == 0) {
            if (self.selected_node_id != null and self.selected_node_id.? == id) self.selected_node_id = null;
            return;
        }
        var write: usize = 0;
        var read: usize = 0;
        while (read < len) : (read += 1) {
            const selected = self.selected_node_ids[read];
            if (selected == id) continue;
            if (write != read) self.selected_node_ids[write] = selected;
            write += 1;
        }
        self.selected_node_len = write;
        self.selected_node_id = if (write > 0) self.selected_node_ids[write - 1] else null;
    }

    fn removeConnectionsTouchingIds(connections: []Connection, connection_len: *usize, ids: []const u32) bool {
        const count = @min(connection_len.*, connections.len);
        connection_len.* = count;
        if (ids.len == 0 or count == 0) return false;
        var write: usize = 0;
        var changed = false;
        var read: usize = 0;
        while (read < count) : (read += 1) {
            const connection = connections[read];
            if (idInList(ids, connection.from_id) or idInList(ids, connection.to_id)) {
                changed = true;
                continue;
            }
            if (write != read) connections[write] = connection;
            write += 1;
        }
        connection_len.* = write;
        return changed;
    }

    fn removeConnection(connections: []Connection, connection_len: *usize, target: Connection) bool {
        const count = @min(connection_len.*, connections.len);
        connection_len.* = count;
        var write: usize = 0;
        var changed = false;
        var read: usize = 0;
        while (read < count) : (read += 1) {
            const connection = connections[read];
            if (State.connectionEndpointsEqual(connection, target)) {
                changed = true;
                continue;
            }
            if (write != read) connections[write] = connection;
            write += 1;
        }
        connection_len.* = write;
        return changed;
    }

    fn countInternalConnectionsTouchingIds(connections: []const Connection, connection_len: usize, ids: []const u32) usize {
        const count = @min(connection_len, connections.len);
        var selected_connection_count: usize = 0;
        for (connections[0..count]) |connection| {
            if (idInList(ids, connection.from_id) and idInList(ids, connection.to_id)) selected_connection_count += 1;
        }
        return selected_connection_count;
    }

    pub fn connectionExists(connections: []const Connection, needle: Connection) bool {
        for (connections) |connection| {
            if (State.connectionEndpointsEqual(connection, needle)) return true;
        }
        return false;
    }

    pub fn connectionEndpointsEqual(a: Connection, b: Connection) bool {
        return a.from_id == b.from_id and a.to_id == b.to_id and a.from_port == b.from_port and a.to_port == b.to_port;
    }

    fn nodeIdExists(nodes: []const Node, id: u32) bool {
        for (nodes) |node| {
            if (node.id == id) return true;
        }
        return false;
    }

    fn uniqueDuplicateNodeId(nodes: []const Node, source_id: u32, id_offset: u32) u32 {
        const step = if (id_offset == 0) 1 else id_offset;
        var candidate = source_id +% step;
        var guard: usize = 0;
        while (nodeIdExists(nodes, candidate) and guard < nodes.len + 1024) : (guard += 1) {
            candidate +%= step;
        }
        return candidate;
    }

    pub fn beginBoxSelect(self: *State, point: [2]f32) bool {
        return self.beginBoxSelectMode(point, .replace);
    }

    pub fn beginBoxSelectMode(self: *State, point: [2]f32, mode: BoxSelectMode) bool {
        self.box_selecting = true;
        self.box_select_mode = mode;
        self.dragging_canvas = false;
        self.dragging_node_id = null;
        self.dragging_group_id = null;
        self.resizing_group_id = null;
        self.resizing_group_edges = .{};
        self.interaction_history_pushed = false;
        self.dragging_connection_from_id = null;
        self.dragging_connection_from_port = 0;
        self.connection_preview_valid = true;
        self.box_select_start = point;
        self.box_select_end = point;
        return true;
    }

    pub fn updateBoxSelect(self: *State, point: [2]f32) bool {
        if (!self.box_selecting) return false;
        const changed = @abs(self.box_select_end[0] - point[0]) > 0.001 or @abs(self.box_select_end[1] - point[1]) > 0.001;
        self.box_select_end = point;
        return changed;
    }

    pub fn boxSelectRect(self: State) Rect {
        const x0 = @min(self.box_select_start[0], self.box_select_end[0]);
        const y0 = @min(self.box_select_start[1], self.box_select_end[1]);
        const x1 = @max(self.box_select_start[0], self.box_select_end[0]);
        const y1 = @max(self.box_select_start[1], self.box_select_end[1]);
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    pub fn applyBoxSelection(self: *State, nodes: []const Node, rect: Rect, editor_rect: Rect, zoom: f32, pan: [2]f32) bool {
        return self.applyBoxSelectionIndexed(nodes, null, rect, editor_rect, zoom, pan);
    }

    pub fn applyBoxSelectionCandidates(self: *State, nodes: []const Node, node_indices: []const usize, rect: Rect, editor_rect: Rect, zoom: f32, pan: [2]f32) bool {
        return self.applyBoxSelectionIndexed(nodes, node_indices, rect, editor_rect, zoom, pan);
    }

    fn applyBoxSelectionIndexed(self: *State, nodes: []const Node, node_indices: ?[]const usize, rect: Rect, editor_rect: Rect, zoom: f32, pan: [2]f32) bool {
        const before_len = self.selected_node_len;
        const before_id = self.selected_node_id;
        var before_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| before_hash = before_hash *% 16777619 +% id;
        if (self.box_select_mode == .replace) self.selected_node_len = 0;
        var temp_state = self.*;
        temp_state.zoom = zoom;
        temp_state.pan = pan;
        if (node_indices) |indices| {
            for (indices) |node_index| {
                if (node_index >= nodes.len) continue;
                self.applyBoxSelectionNode(nodes[node_index], rect, editor_rect, temp_state);
            }
        } else {
            for (nodes) |node| self.applyBoxSelectionNode(node, rect, editor_rect, temp_state);
        }
        self.selected_node_id = if (self.selected_node_len > 0) self.selected_node_ids[self.selected_node_len - 1] else null;
        self.box_selecting = false;
        self.box_select_mode = .replace;
        var after_hash: u64 = 0;
        for (self.selected_node_ids[0..self.boundedSelectionLen()]) |id| after_hash = after_hash *% 16777619 +% id;
        return before_len != self.selected_node_len or before_id != self.selected_node_id or before_hash != after_hash;
    }

    fn applyBoxSelectionNode(self: *State, node: Node, rect: Rect, editor_rect: Rect, temp_state: State) void {
        const node_rect = nodeRectFromState(editor_rect, temp_state, node);
        if (!rectIntersects(node_rect, rect)) return;
        switch (self.box_select_mode) {
            .replace, .add => self.addNodeToSelection(node.id),
            .subtract => self.removeNodeFromSelection(node.id),
            .toggle => if (self.isNodeSelected(node.id))
                self.removeNodeFromSelection(node.id)
            else
                self.addNodeToSelection(node.id),
        }
    }

    pub fn takePendingConnection(self: *State) ?Connection {
        const pending = self.pending_connection;
        self.pending_connection = null;
        return pending;
    }

    pub fn appendConnection(self: *State, connections: []Connection, len: *usize, connection: Connection) bool {
        return self.appendConnectionChecked(connections, len, connection, &.{});
    }

    pub fn appendConnectionChecked(self: *State, connections: []Connection, len: *usize, connection: Connection, nodes: []const Node) bool {
        return self.appendConnectionWithPolicy(connections, len, connection, nodes, .default);
    }

    pub fn appendConnectionWithPolicy(self: *State, connections: []Connection, len: *usize, connection: Connection, nodes: []const Node, policy: ConnectionPolicy) bool {
        const clamped_len = @min(len.*, connections.len);
        len.* = clamped_len;
        if (!connectionAllowed(nodes, connections[0..clamped_len], connection, policy, .{})) {
            self.pending_connection = null;
            return false;
        }
        if (clamped_len >= connections.len) {
            self.pending_connection = connection;
            return false;
        }
        connections[clamped_len] = connection;
        len.* = clamped_len + 1;
        self.pending_connection = null;
        _ = self.setConnectionSelection(connection);
        return true;
    }

    pub fn beginReconnectConnection(self: *State, connection: Connection, endpoint: ConnectionEnd, preview: [2]f32) bool {
        const changed = self.reconnecting_connection == null or !State.connectionEndpointsEqual(self.reconnecting_connection.?, connection) or self.reconnecting_connection_end != endpoint;
        _ = self.setConnectionSelection(connection);
        self.reconnecting_connection = connection;
        self.reconnecting_connection_end = endpoint;
        self.dragging_connection_from_id = null;
        self.dragging_connection_from_port = 0;
        self.connection_preview_valid = true;
        self.dragging_canvas = false;
        self.dragging_node_id = null;
        self.box_selecting = false;
        self.connection_preview = preview;
        return changed;
    }

    pub fn updateReconnectPreview(self: *State, point: [2]f32) bool {
        if (self.reconnecting_connection == null) return false;
        const changed = @abs(self.connection_preview[0] - point[0]) > 0.001 or @abs(self.connection_preview[1] - point[1]) > 0.001;
        self.connection_preview = point;
        return changed;
    }

    pub fn reconnectSelectedConnection(self: *State, connections: []Connection, len: *usize, endpoint: ConnectionEnd, node_id: u32) bool {
        const selected = self.selected_connection orelse return false;
        return self.reconnectConnection(connections, len, selected, endpoint, node_id);
    }

    pub fn reconnectConnection(self: *State, connections: []Connection, len: *usize, target: Connection, endpoint: ConnectionEnd, node_id: u32) bool {
        return self.reconnectConnectionPort(connections, len, target, endpoint, node_id, 0);
    }

    pub fn reconnectConnectionPort(self: *State, connections: []Connection, len: *usize, target: Connection, endpoint: ConnectionEnd, node_id: u32, port: u8) bool {
        return self.reconnectConnectionPortChecked(connections, len, target, endpoint, node_id, port, &.{});
    }

    pub fn reconnectConnectionPortChecked(self: *State, connections: []Connection, len: *usize, target: Connection, endpoint: ConnectionEnd, node_id: u32, port: u8, nodes: []const Node) bool {
        return self.reconnectConnectionPortWithPolicy(connections, len, target, endpoint, node_id, port, nodes, .default);
    }

    pub fn reconnectConnectionPortWithPolicy(self: *State, connections: []Connection, len: *usize, target: Connection, endpoint: ConnectionEnd, node_id: u32, port: u8, nodes: []const Node, policy: ConnectionPolicy) bool {
        const clamped_len = @min(len.*, connections.len);
        len.* = clamped_len;
        var replacement = target;
        switch (endpoint) {
            .from => {
                replacement.from_id = node_id;
                replacement.from_port = port;
            },
            .to => {
                replacement.to_id = node_id;
                replacement.to_port = port;
            },
        }
        if (State.connectionEndpointsEqual(replacement, target)) {
            self.selected_connection = replacement;
            return false;
        }
        if (!connectionAllowed(nodes, connections[0..clamped_len], replacement, policy, .{
            .ignore_connection = graph_validation.ConnectionKey.from(target),
        })) return false;
        for (connections[0..clamped_len]) |*connection| {
            if (!State.connectionEndpointsEqual(connection.*, target)) continue;
            connection.* = replacement;
            self.selected_connection = replacement;
            self.hover_connection = replacement;
            return true;
        }
        return false;
    }
};

fn cubicDistanceToPoint(a: [2]f32, c0: [2]f32, c1: [2]f32, b: [2]f32, point: [2]f32) f32 {
    var best: f32 = std.math.floatMax(f32);
    var previous = a;
    var i: usize = 1;
    while (i <= 24) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 24.0;
        const current = cubicPoint(a, c0, c1, b, t);
        best = @min(best, segmentDistanceToPoint(previous, current, point));
        previous = current;
    }
    return best;
}

fn cubicPoint(a: [2]f32, c0: [2]f32, c1: [2]f32, b: [2]f32, t: f32) [2]f32 {
    const u = 1.0 - t;
    const uu = u * u;
    const tt = t * t;
    const uuu = uu * u;
    const ttt = tt * t;
    return .{
        a[0] * uuu + c0[0] * 3.0 * uu * t + c1[0] * 3.0 * u * tt + b[0] * ttt,
        a[1] * uuu + c0[1] * 3.0 * uu * t + c1[1] * 3.0 * u * tt + b[1] * ttt,
    };
}

fn segmentDistanceToPoint(a: [2]f32, b: [2]f32, point: [2]f32) f32 {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const len_sq = dx * dx + dy * dy;
    const t = if (len_sq <= 0.0001) 0.0 else std.math.clamp(((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / len_sq, 0.0, 1.0);
    const closest = [2]f32{ a[0] + dx * t, a[1] + dy * t };
    const px = point[0] - closest[0];
    const py = point[1] - closest[1];
    return @sqrt(px * px + py * py);
}

const TestState = struct {
    pan: [2]f32 = .{ 0.0, 0.0 },
    zoom: f32 = 1.0,
};

// -----------------------------------------------------------------------------
// Paint helpers
// -----------------------------------------------------------------------------

pub const DrawCommandRange = struct {
    start: usize = 0,
    end: usize = 0,
};

fn nodeRectFromElement(rect: Rect, editor: anytype, node: Node) Rect {
    return nodeRectFromState(rect, editor.state.*, node);
}

fn groupRectFromElement(rect: Rect, editor: anytype, group: Group) Rect {
    return groupRect(rect, editor.state.*, group);
}

fn editorConnectionPathCache(editor: anytype) ?*ConnectionPathCache {
    const Editor = @TypeOf(editor);
    if (@hasField(Editor, "connection_path_cache")) return editor.connection_path_cache;
    return null;
}

fn editorConnectionDrawWorkspace(editor: anytype) ?*ConnectionDrawWorkspace {
    const Editor = @TypeOf(editor);
    if (@hasField(Editor, "connection_draw_workspace")) return editor.connection_draw_workspace;
    return null;
}

fn editorDetailLevel(editor: anytype) DetailLevel {
    const Editor = @TypeOf(editor);
    const options: SemanticZoomOptions = if (@hasField(Editor, "semantic_zoom")) editor.semantic_zoom else .{};
    return semanticDetailLevel(editor.state.*, options);
}

fn editorViewportIndex(editor: anytype) ?*ViewportIndex {
    const Editor = @TypeOf(editor);
    if (@hasField(Editor, "viewport_index")) return editor.viewport_index;
    return null;
}

fn editorGeometryRevision(editor: anytype) ?u64 {
    const Editor = @TypeOf(editor);
    if (@hasField(Editor, "geometry_revision")) return editor.geometry_revision;
    return null;
}

pub fn prepareNodeEditorViewportIndex(rect: Rect, editor: anytype) ?*ViewportIndex {
    const viewport_index = editorViewportIndex(editor) orelse return null;
    const connections = editorActiveConnections(editor);
    const prepared = if (editorGeometryRevision(editor)) |revision|
        viewport_index.prepareVersioned(editor.nodes, editor.groups, connections, rect, editor.state.pan, editor.state.zoom, revision)
    else
        viewport_index.prepare(editor.nodes, editor.groups, connections, rect, editor.state.pan, editor.state.zoom);
    return if (prepared.ready) viewport_index else null;
}

pub fn appendNodeEditor(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, layer: i32) !DrawCommandRange {
    if (rect.w <= 0.0 or rect.h <= 0.0) return .{};
    editor.state.clamp();
    try paint_primitives.appendFillRect(allocator, out, rect, editor.background, 0.0, layer);
    try out.append(allocator, .{ .clip_begin = rect });
    const connection_path_cache = editorConnectionPathCache(editor);
    const connection_draw_workspace = editorConnectionDrawWorkspace(editor);
    if (connection_draw_workspace) |workspace| workspace.beginPaint();
    const viewport_index = prepareNodeEditorViewportIndex(rect, editor);
    const detail_level = editorDetailLevel(editor);
    try appendNodeEditorGrid(allocator, out, rect, editor, layer + 1);
    if (viewport_index) |index| {
        for (index.visibleGroupIndices()) |group_index| {
            try appendNodeEditorGroup(allocator, out, rect, editor, editor.groups[group_index], detail_level, layer + 2);
        }
    } else {
        for (editor.groups) |group| {
            try appendNodeEditorGroup(allocator, out, rect, editor, group, detail_level, layer + 2);
        }
    }
    const connections = editorActiveConnections(editor);
    if (viewport_index) |index| {
        for (index.visibleConnectionIndices()) |connection_index| {
            try appendNodeEditorConnectionItem(allocator, out, rect, editor, connection_path_cache, connection_draw_workspace, index, connection_index, connections[connection_index], layer + 3);
        }
    } else {
        for (connections, 0..) |connection, connection_index| {
            try appendNodeEditorConnectionItem(allocator, out, rect, editor, connection_path_cache, connection_draw_workspace, null, connection_index, connection, layer + 3);
        }
    }
    if (viewport_index) |index| {
        for (index.visibleNodeIndices()) |node_index| {
            try appendNodeEditorNode(allocator, out, rect, editor, editor.nodes[node_index], detail_level, layer);
        }
    } else {
        for (editor.nodes) |node_item| {
            try appendNodeEditorNode(allocator, out, rect, editor, node_item, detail_level, layer);
        }
    }
    const dynamic_start = out.items.len;
    try appendNodeEditorConnectionOverlayPrepared(allocator, out, rect, editor, viewport_index, layer);
    const dynamic_end = out.items.len;
    if (editor.state.box_selecting) {
        const box = editor.state.boxSelectRect();
        if (box.w > 0.0 and box.h > 0.0) {
            try paint_primitives.appendFillRect(allocator, out, box, editor.selected_color.withAlpha(0.16), 0.0, layer + 7);
            try paint_primitives.appendBorder(allocator, out, box, editor.selected_color.withAlpha(0.72), 1.0, 0.0, layer + 8);
        }
    }
    if (editor.show_minimap) try appendNodeEditorMinimap(allocator, out, rect, editor, viewport_index, layer + 9);
    try out.append(allocator, .{ .clip_end = {} });
    return .{ .start = dynamic_start, .end = dynamic_end };
}

fn appendNodeEditorConnectionItem(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, connection_path_cache: ?*ConnectionPathCache, connection_draw_workspace: ?*ConnectionDrawWorkspace, viewport_index: ?*ViewportIndex, connection_index: usize, connection: Connection, layer: i32) !void {
    const from = if (viewport_index) |index| editor.nodes[index.nodeIndexForId(connection.from_id) orelse return] else nodeById(editor.nodes, connection.from_id) orelse return;
    const to = if (viewport_index) |index| editor.nodes[index.nodeIndexForId(connection.to_id) orelse return] else nodeById(editor.nodes, connection.to_id) orelse return;
    const a = outputPortPositionAt(rect, editor.state.*, from, connection.from_port);
    const b = inputPortPositionAt(rect, editor.state.*, to, connection.to_port);
    const selected = editor.state.isConnectionSelected(connection);
    const hovered = editor.state.isConnectionHovered(connection);
    const color = if (selected) editor.selected_color else if (hovered) connection.color.lighten(0.12) else connection.color;
    const width: f32 = if (selected) 3.25 else if (hovered) 2.7 else 2.0;
    if (connection_draw_workspace) |workspace| {
        if (connection_index < workspace.path_commands.len) {
            workspace.borrowed_connection_count += 1;
            return appendNodeEditorConnectionBorrowed(allocator, out, connection_path_cache, &workspace.path_commands[connection_index], a, b, color, width, layer);
        }
        workspace.fallback_connection_count += 1;
    }
    try appendNodeEditorConnection(allocator, out, connection_path_cache, a, b, color, width, layer);
}

fn appendNodeEditorConnectionBorrowed(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), cache: ?*ConnectionPathCache, commands: *[2]render.PathCommand, a: [2]f32, b: [2]f32, color: Color, width: f32, layer: i32) !void {
    const path = if (cache) |connection_cache| connection_cache.pathFor(a, b) else connectionPathForPoints(a, b);
    commands[0] = .{ .move_to = path.start };
    commands[1] = .{ .cubic_to = .{ .c0 = path.c0, .c1 = path.c1, .end = path.end } };
    try out.append(allocator, .{ .stroke_path = .{
        .commands = commands,
        .style = .{ .width = width, .cap = .round, .join = .round },
        .color = color,
        .layer = layer,
        .owns_commands = false,
    } });
}

fn appendNodeEditorNode(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, node_item: Node, detail_level: DetailLevel, layer: i32) !void {
    const node_rect = nodeRectFromElement(rect, editor, node_item);
    if (!rectOverlapsOrTouches(node_rect, rect)) return;
    const selected = editor.state.isNodeSelected(node_item.id);
    const hovered = editor.state.hover_node_id != null and editor.state.hover_node_id.? == node_item.id;
    const bg = if (selected) node_item.color.lighten(0.08) else if (hovered) node_item.color.lighten(0.04) else node_item.color;
    try paint_primitives.appendFillRect(allocator, out, node_rect, bg, 7.0, layer + 3);
    try paint_primitives.appendBorder(allocator, out, node_rect, if (selected) editor.selected_color else editor.grid_color.withAlpha(0.8), if (selected) 2.0 else 1.0, 7.0, layer + 4);
    if (detail_level == .overview) return;
    try out.append(allocator, .{ .text = .{ .pos = .{ node_rect.x + 10.0, node_rect.y + 8.0 }, .size = editor.font_size, .color = editor.node_text_color, .text = node_item.title, .layer = layer + 5 } });
    var input_port_index: u8 = 0;
    while (input_port_index < inputPortCount(node_item)) : (input_port_index += 1) {
        const in_port = inputPortPositionAt(rect, editor.state.*, node_item, input_port_index);
        const input_hovered = editor.state.hover_input_node_id != null and editor.state.hover_input_node_id.? == node_item.id;
        try out.append(allocator, .{ .point = .{ .pos = in_port, .size = if (input_hovered) 7.0 else 5.0, .color = if (input_hovered) editor.selected_color else editor.port_color, .layer = layer + 6 } });
        if (detail_level == .full) {
            if (inputPortLabel(node_item, input_port_index)) |port_label| try out.append(allocator, .{ .text = .{ .pos = .{ in_port[0] + 8.0, in_port[1] - editor.font_size * 0.5 }, .size = @max(8.0, editor.font_size - 2.0), .color = editor.node_text_color.withAlpha(0.78), .text = port_label, .layer = layer + 6 } });
        }
    }
    var output_port_index: u8 = 0;
    while (output_port_index < outputPortCount(node_item)) : (output_port_index += 1) {
        const out_port = outputPortPositionAt(rect, editor.state.*, node_item, output_port_index);
        const output_hovered = editor.state.hover_output_node_id != null and editor.state.hover_output_node_id.? == node_item.id;
        const output_dragging = editor.state.dragging_connection_from_id != null and editor.state.dragging_connection_from_id.? == node_item.id;
        try out.append(allocator, .{ .point = .{ .pos = out_port, .size = if (output_hovered) 7.0 else 5.0, .color = if (output_hovered or output_dragging) editor.selected_color else editor.port_color, .layer = layer + 6 } });
        if (detail_level == .full) {
            if (outputPortLabel(node_item, output_port_index)) |port_label| {
                const label_w = @as(f32, @floatFromInt(port_label.len)) * @max(8.0, editor.font_size - 2.0) * 0.54;
                try out.append(allocator, .{ .text = .{ .pos = .{ out_port[0] - label_w - 8.0, out_port[1] - editor.font_size * 0.5 }, .size = @max(8.0, editor.font_size - 2.0), .color = editor.node_text_color.withAlpha(0.78), .text = port_label, .layer = layer + 6 } });
            }
        }
    }
}

fn appendNodeEditorGrid(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, layer: i32) !void {
    if (editor.grid_color.a <= 0.0) return;
    const spacing = @max(8.0, editor.grid_spacing * editor.state.zoom);
    var x = rect.x + @mod(editor.state.pan[0], spacing);
    while (x < rect.x + rect.w) : (x += spacing) {
        try out.append(allocator, .{ .line = .{ .a = .{ x, rect.y }, .b = .{ x, rect.y + rect.h }, .thickness = 1.0, .color = editor.grid_color, .layer = layer } });
    }
    var y = rect.y + @mod(editor.state.pan[1], spacing);
    while (y < rect.y + rect.h) : (y += spacing) {
        try out.append(allocator, .{ .line = .{ .a = .{ rect.x, y }, .b = .{ rect.x + rect.w, y }, .thickness = 1.0, .color = editor.grid_color, .layer = layer } });
    }
}

fn nodeEditorPreviewConnectionColor(editor: anytype) Color {
    return if (editor.state.connection_preview_valid)
        editor.selected_color.withAlpha(0.72)
    else
        Color.rgba8(248, 113, 113, 220);
}

pub fn appendNodeEditorConnectionOverlay(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, layer: i32) !void {
    return appendNodeEditorConnectionOverlayPrepared(allocator, out, rect, editor, prepareNodeEditorViewportIndex(rect, editor), layer);
}

fn appendNodeEditorConnectionOverlayPrepared(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, viewport_index: ?*ViewportIndex, layer: i32) !void {
    try appendNodeEditorConnectionPreviewOverlay(allocator, out, rect, editor, layer + 3);
    if (editorDetailLevel(editor) == .overview) return;
    if (viewport_index) |index| {
        for (index.visibleNodeIndices()) |node_index| try appendNodeEditorPortOverlay(allocator, out, rect, editor, editor.nodes[node_index], layer);
    } else {
        for (editor.nodes) |node_item| try appendNodeEditorPortOverlay(allocator, out, rect, editor, node_item, layer);
    }
}

fn appendNodeEditorPortOverlay(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, node_item: Node, layer: i32) !void {
    const node_rect = nodeRectFromElement(rect, editor, node_item);
    if (!rectOverlapsOrTouches(node_rect, rect)) return;
    var input_port_index: u8 = 0;
    while (input_port_index < inputPortCount(node_item)) : (input_port_index += 1) {
        const in_port = inputPortPositionAt(rect, editor.state.*, node_item, input_port_index);
        const input_hovered = editor.state.hover_input_node_id != null and editor.state.hover_input_node_id.? == node_item.id;
        const color = if (input_hovered) editor.selected_color else Color.transparent;
        try out.append(allocator, .{ .point = .{ .pos = in_port, .size = if (input_hovered) 7.0 else 5.0, .color = color, .layer = layer + 6 } });
    }
    var output_port_index: u8 = 0;
    while (output_port_index < outputPortCount(node_item)) : (output_port_index += 1) {
        const out_port = outputPortPositionAt(rect, editor.state.*, node_item, output_port_index);
        const output_hovered = editor.state.hover_output_node_id != null and editor.state.hover_output_node_id.? == node_item.id;
        const output_dragging = editor.state.dragging_connection_from_id != null and editor.state.dragging_connection_from_id.? == node_item.id;
        const active = output_hovered or output_dragging;
        try out.append(allocator, .{ .point = .{ .pos = out_port, .size = if (output_hovered) 7.0 else 5.0, .color = if (active) editor.selected_color else Color.transparent, .layer = layer + 6 } });
    }
}

fn appendNodeEditorConnectionPreviewOverlay(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, layer: i32) !void {
    if (editor.state.dragging_connection_from_id) |from_id| {
        if (nodeById(editor.nodes, from_id)) |from| {
            const preview_color = nodeEditorPreviewConnectionColor(editor);
            try appendNodeEditorConnection(allocator, out, editorConnectionPathCache(editor), outputPortPositionAt(rect, editor.state.*, from, editor.state.dragging_connection_from_port), editor.state.connection_preview, preview_color, if (editor.state.connection_preview_valid) 2.0 else 2.8, layer);
            return;
        }
    }
    if (editor.state.reconnecting_connection) |connection| {
        if (nodeById(editor.nodes, connection.from_id)) |from| {
            if (nodeById(editor.nodes, connection.to_id)) |to| {
                const a = outputPortPositionAt(rect, editor.state.*, from, connection.from_port);
                const b = inputPortPositionAt(rect, editor.state.*, to, connection.to_port);
                const start = if (editor.state.reconnecting_connection_end == .from) editor.state.connection_preview else a;
                const end = if (editor.state.reconnecting_connection_end == .to) editor.state.connection_preview else b;
                try appendNodeEditorConnection(allocator, out, editorConnectionPathCache(editor), start, end, nodeEditorPreviewConnectionColor(editor), if (editor.state.connection_preview_valid) 2.7 else 3.2, layer);
                return;
            }
        }
    }
    try out.append(allocator, .{ .line = .{
        .a = .{ rect.x, rect.y },
        .b = .{ rect.x + 0.001, rect.y },
        .thickness = 1.0,
        .color = Color.transparent,
        .layer = layer,
    } });
}

fn appendNodeEditorGroup(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, group: Group, detail_level: DetailLevel, layer: i32) !void {
    const group_rect = groupRectFromElement(rect, editor, group);
    if (group_rect.x + group_rect.w < rect.x or group_rect.x > rect.x + rect.w or group_rect.y + group_rect.h < rect.y or group_rect.y > rect.y + rect.h) return;
    const radius = @max(0.0, group.radius * editor.state.zoom);
    const selected = editor.state.isGroupSelected(group.id);
    const hovered = editor.state.hover_group_id != null and editor.state.hover_group_id.? == group.id;
    const fill_color = if (selected)
        group.color.lighten(0.06).withAlpha(@max(group.color.a, 0.18))
    else if (hovered)
        group.color.lighten(0.04).withAlpha(@max(group.color.a, 0.14))
    else
        group.color;
    const border_color = if (selected) editor.selected_color else if (hovered) group.border_color.lighten(0.08) else group.border_color;
    if (fill_color.a > 0.0) try paint_primitives.appendFillRect(allocator, out, group_rect, fill_color, radius, layer);
    const title_h = @max(0.0, group.title_height * editor.state.zoom);
    if (title_h > 0.0) {
        const title_rect = Rect{ .x = group_rect.x, .y = group_rect.y, .w = group_rect.w, .h = @min(group_rect.h, title_h) };
        try paint_primitives.appendFillRect(allocator, out, title_rect, border_color.withAlpha(@max(border_color.a * 0.24, 0.10)), radius, layer + 1);
    }
    if (border_color.a > 0.0) try paint_primitives.appendBorder(allocator, out, group_rect, border_color, if (selected) 1.8 else 1.0, radius, layer + 2);
    if (detail_level != .overview and group.title.len > 0 and group.text_color.a > 0.0) {
        try out.append(allocator, .{ .text = .{
            .pos = .{ group_rect.x + 10.0 * editor.state.zoom, group_rect.y + @max(5.0, 7.0 * editor.state.zoom) },
            .size = @max(8.0, editor.font_size * 0.92),
            .color = if (selected) editor.selected_color.lighten(0.08) else group.text_color,
            .text = group.title,
            .layer = layer + 3,
        } });
    }
}

fn appendNodeEditorConnection(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), cache: ?*ConnectionPathCache, a: [2]f32, b: [2]f32, color: Color, width: f32, layer: i32) !void {
    const path = if (cache) |connection_cache| connection_cache.pathFor(a, b) else connectionPathForPoints(a, b);
    const commands = try allocator.alloc(render.PathCommand, 2);
    errdefer allocator.free(commands);
    commands[0] = .{ .move_to = path.start };
    commands[1] = .{ .cubic_to = .{
        .c0 = path.c0,
        .c1 = path.c1,
        .end = path.end,
    } };
    try out.append(allocator, .{ .stroke_path = .{
        .commands = commands,
        .style = .{ .width = width, .cap = .round, .join = .round },
        .color = color,
        .layer = layer,
    } });
}

fn appendNodeEditorMinimap(allocator: std.mem.Allocator, out: *std.ArrayList(DrawCmd), rect: Rect, editor: anytype, viewport_index: ?*ViewportIndex, layer: i32) !void {
    const snapshot = minimapSnapshotPrepared(rect, editor, viewport_index);
    if (!snapshot.visible) return;
    const minimap = snapshot.minimap_rect;
    const bounds = snapshot.graph_bounds;
    try paint_primitives.appendFillRect(allocator, out, minimap, editor.background.lighten(0.08).withAlpha(0.84), 5.0, layer);
    try paint_primitives.appendBorder(allocator, out, minimap, editor.grid_color.withAlpha(0.9), 1.0, 5.0, layer + 1);
    const group_mark_count = @min(editor.groups.len, editor.minimap_max_group_marks);
    for (0..group_mark_count) |mark_index| {
        const group = editor.groups[sampledIndex(mark_index, group_mark_count, editor.groups.len)];
        const group_rect = minimapGroupRect(minimap, bounds, group);
        try paint_primitives.appendFillRect(allocator, out, group_rect, group.color.withAlpha(@max(group.color.a, 0.18)), 1.5, layer + 2);
        try paint_primitives.appendBorder(allocator, out, group_rect, group.border_color.withAlpha(@max(group.border_color.a, 0.36)), 0.75, 1.5, layer + 3);
    }
    const node_mark_count = @min(editor.nodes.len, editor.minimap_max_node_marks);
    for (0..node_mark_count) |mark_index| {
        const node_item = editor.nodes[sampledIndex(mark_index, node_mark_count, editor.nodes.len)];
        const node_rect = minimapNodeRect(minimap, bounds, node_item);
        const selected = editor.state.isNodeSelected(node_item.id);
        try paint_primitives.appendFillRect(allocator, out, node_rect, if (selected) editor.selected_color else node_item.color.lighten(0.08), 1.5, layer + 4);
    }
    try paint_primitives.appendBorder(allocator, out, snapshot.viewport_rect, editor.selected_color.withAlpha(0.88), 1.0, 2.0, layer + 5);
}

fn sampledIndex(mark_index: usize, mark_count: usize, item_count: usize) usize {
    if (mark_count >= item_count) return mark_index;
    return mark_index * item_count / mark_count;
}

fn rectOverlapsOrTouches(a: Rect, b: Rect) bool {
    return a.x <= b.x + b.w and a.x + a.w >= b.x and a.y <= b.y + b.h and a.y + a.h >= b.y;
}

fn dragNodeBy(editor: anytype, id: u32, delta_screen: [2]f32) bool {
    const nodes = editor.mutable_nodes orelse return false;
    const zoom = @max(0.0001, editor.state.zoom);
    const delta_graph = [2]f32{ delta_screen[0] / zoom, delta_screen[1] / zoom };
    if (@abs(delta_graph[0]) <= 0.001 and @abs(delta_graph[1]) <= 0.001) return false;
    const active_len = if (editor.mutable_node_len) |len| @min(len.*, nodes.len) else @min(editor.nodes.len, nodes.len);
    const move_selection = editor.state.boundedSelectionLen() > 1 and editor.state.isNodeSelected(id);
    if (move_selection) {
        if (editorViewportIndex(editor)) |viewport_index| {
            if (viewport_index.nodeIndexForId(id) != null) {
                var moved = false;
                for (editor.state.selected_node_ids[0..editor.state.boundedSelectionLen()]) |selected_id| {
                    const node_index = viewport_index.nodeIndexForId(selected_id) orelse continue;
                    if (node_index >= active_len or nodes[node_index].id != selected_id) continue;
                    nodes[node_index].pos[0] += delta_graph[0];
                    nodes[node_index].pos[1] += delta_graph[1];
                    moved = true;
                }
                if (moved) editor.state.selected_node_id = id;
                return moved;
            }
        }
        var moved = false;
        for (nodes[0..active_len]) |*node| {
            if (!editor.state.isNodeSelected(node.id)) continue;
            node.pos[0] += delta_graph[0];
            node.pos[1] += delta_graph[1];
            moved = true;
        }
        if (moved) editor.state.selected_node_id = id;
        return moved;
    }
    for (nodes[0..active_len]) |*node| {
        if (node.id != id) continue;
        node.pos[0] += delta_graph[0];
        node.pos[1] += delta_graph[1];
        editor.state.selected_node_id = id;
        return true;
    }
    return false;
}

const EditorHistoryMutation = struct {
    history: ?*History = null,
    snapshot: HistorySnapshot = .{},
};

fn beginEditorHistory(editor: anytype) ?EditorHistoryMutation {
    const history = editor.history orelse return .{};
    const groups = editor.mutable_groups orelse editor.groups;
    const group_len = if (editor.mutable_group_len) |len| @min(len.*, groups.len) else groups.len;
    const connections = editor.mutable_connections orelse &.{};
    const node_len = if (editor.mutable_node_len) |len| @min(len.*, editor.nodes.len) else editor.nodes.len;
    const connection_len = if (editor.mutable_connection_len) |len| @min(len.*, connections.len) else connections.len;
    if (!history.supportsGraphCapacity(node_len, group_len, connection_len, editor.state.boundedSelectionLen())) return null;
    const snapshot = history.captureWithGroups(editor.state.*, editor.nodes, node_len, groups[0..group_len], connections, connection_len);
    if (!snapshot.complete) return null;
    return .{ .history = history, .snapshot = snapshot };
}

fn invalidateEditorViewportGeometry(editor: anytype) void {
    if (editorViewportIndex(editor)) |viewport_index| viewport_index.invalidateGeometry();
}

fn finishEditorHistory(editor: anytype, mutation: EditorHistoryMutation, changed: bool) bool {
    if (!changed) return false;
    invalidateEditorViewportGeometry(editor);
    if (mutation.history) |history| {
        if (!history.commitBefore(mutation.snapshot)) return false;
    }
    return true;
}

fn beginInteractionHistoryIfNeeded(editor: anytype) ?EditorHistoryMutation {
    if (editor.state.interaction_history_pushed) return .{};
    return beginEditorHistory(editor);
}

fn finishInteractionHistory(editor: anytype, mutation: EditorHistoryMutation, changed: bool) bool {
    if (!changed) return false;
    if (!editor.state.interaction_history_pushed) {
        if (!finishEditorHistory(editor, mutation, true)) return false;
        editor.state.interaction_history_pushed = true;
    } else {
        invalidateEditorViewportGeometry(editor);
    }
    return true;
}

fn dragGroupBy(editor: anytype, id: u32, delta_screen: [2]f32) bool {
    const groups = editor.mutable_groups orelse return false;
    const zoom = @max(0.0001, editor.state.zoom);
    const delta_graph = [2]f32{ delta_screen[0] / zoom, delta_screen[1] / zoom };
    if (@abs(delta_graph[0]) <= 0.001 and @abs(delta_graph[1]) <= 0.001) return false;
    var group_rect: ?Rect = null;
    for (groups) |*group| {
        if (group.id != id) continue;
        group_rect = group.rect;
        group.rect.x += delta_graph[0];
        group.rect.y += delta_graph[1];
        editor.state.selected_group_id = id;
        break;
    }
    const before_rect = group_rect orelse return false;
    if (editor.move_group_contents) {
        if (editor.mutable_nodes) |nodes| {
            for (nodes) |*node| {
                if (!nodeInsideGraphRect(node.*, before_rect)) continue;
                node.pos[0] += delta_graph[0];
                node.pos[1] += delta_graph[1];
            }
        }
    }
    return true;
}

fn resizeGroupBy(editor: anytype, id: u32, edges: GroupResizeEdges, delta_screen: [2]f32) bool {
    if (!edges.any()) return false;
    const groups = editor.mutable_groups orelse return false;
    const zoom = @max(0.0001, editor.state.zoom);
    const delta_graph = [2]f32{ delta_screen[0] / zoom, delta_screen[1] / zoom };
    var changed = false;
    for (groups) |*group| {
        if (group.id != id) continue;
        const resized = resizeGroupRect(group.rect, edges, delta_graph, editor.group_min_size);
        changed = @abs(group.rect.x - resized.x) > 0.001 or @abs(group.rect.y - resized.y) > 0.001 or
            @abs(group.rect.w - resized.w) > 0.001 or @abs(group.rect.h - resized.h) > 0.001;
        group.rect = resized;
        editor.state.selected_group_id = id;
        break;
    }
    return changed;
}

fn dragPreviewCompatible(editor: anytype, input_hover: ?PortHit) bool {
    const from_id = editor.state.dragging_connection_from_id orelse return true;
    const hit = input_hover orelse return true;
    const to_id = editor.nodes[hit.node_index].id;
    const connection = Connection{
        .from_id = from_id,
        .from_port = editor.state.dragging_connection_from_port,
        .to_id = to_id,
        .to_port = hit.port_index,
    };
    return connectionAllowed(editor.nodes, editorActiveConnections(editor), connection, editorConnectionPolicy(editor), .{});
}

fn reconnectPreviewCompatible(editor: anytype, input_hover: ?PortHit, output_hover: ?PortHit) bool {
    const connection = editor.state.reconnecting_connection orelse return true;
    var replacement = connection;
    switch (editor.state.reconnecting_connection_end) {
        .from => {
            const hit = output_hover orelse return true;
            replacement.from_id = editor.nodes[hit.node_index].id;
            replacement.from_port = hit.port_index;
        },
        .to => {
            const hit = input_hover orelse return true;
            replacement.to_id = editor.nodes[hit.node_index].id;
            replacement.to_port = hit.port_index;
        },
    }
    return connectionAllowed(editor.nodes, editorActiveConnections(editor), replacement, editorConnectionPolicy(editor), .{
        .ignore_connection = graph_validation.ConnectionKey.from(connection),
    });
}

pub fn inputPortAtEditorPoint(rect: Rect, editor: anytype, viewport_index: ?*ViewportIndex, point: [2]f32) ?PortHit {
    if (editorDetailLevel(editor) == .overview) return null;
    if (viewport_index) |index| {
        // Port rows keep up to 17 px of screen-space inset even when a node is
        // tiny, so widen the broad phase while retaining exact portHit checks.
        for (index.nodeIndicesNearPoint(rect, editor.state.pan, editor.state.zoom, point, 25.0)) |node_index| {
            const node = editor.nodes[node_index];
            var port_index: u8 = 0;
            while (port_index < inputPortCount(node)) : (port_index += 1) {
                if (portHit(inputPortPositionAt(rect, editor.state.*, node, port_index), point)) return .{ .node_index = node_index, .port_index = port_index };
            }
        }
        return null;
    }
    return inputPortAtPoint(rect, editor.state.*, editor.nodes, point);
}

pub fn outputPortAtEditorPoint(rect: Rect, editor: anytype, viewport_index: ?*ViewportIndex, point: [2]f32) ?PortHit {
    if (editorDetailLevel(editor) == .overview) return null;
    if (viewport_index) |index| {
        for (index.nodeIndicesNearPoint(rect, editor.state.pan, editor.state.zoom, point, 25.0)) |node_index| {
            const node = editor.nodes[node_index];
            var port_index: u8 = 0;
            while (port_index < outputPortCount(node)) : (port_index += 1) {
                if (portHit(outputPortPositionAt(rect, editor.state.*, node, port_index), point)) return .{ .node_index = node_index, .port_index = port_index };
            }
        }
        return null;
    }
    return outputPortAtPoint(rect, editor.state.*, editor.nodes, point);
}

pub fn connectionAtEditorPoint(rect: Rect, editor: anytype, viewport_index: ?*ViewportIndex, point: [2]f32) ?Connection {
    const connections = editorActiveConnections(editor);
    if (viewport_index) |index| {
        const candidates = index.connectionIndicesNearPoint(rect, editor.state.pan, editor.state.zoom, point, 7.0);
        var i = candidates.len;
        while (i > 0) {
            i -= 1;
            const connection = connections[candidates[i]];
            const from_index = index.nodeIndexForId(connection.from_id) orelse continue;
            const to_index = index.nodeIndexForId(connection.to_id) orelse continue;
            const from = editor.nodes[from_index];
            const to = editor.nodes[to_index];
            const a = outputPortPositionAt(rect, editor.state.*, from, connection.from_port);
            const b = inputPortPositionAt(rect, editor.state.*, to, connection.to_port);
            const path = connectionPathForPoints(a, b);
            if (cubicDistanceToPoint(path.start, path.c0, path.c1, path.end, point) <= 7.0) return connection;
        }
        return null;
    }
    return connectionAtPoint(rect, editor.state.*, editor.nodes, null, null, connections, point);
}

pub fn nodeAtEditorPoint(rect: Rect, editor: anytype, viewport_index: ?*ViewportIndex, point: [2]f32) ?usize {
    if (viewport_index) |index| {
        const candidates = index.nodeIndicesNearPoint(rect, editor.state.pan, editor.state.zoom, point, 0.0);
        var i = candidates.len;
        while (i > 0) {
            i -= 1;
            const node_index = candidates[i];
            if (nodeRectFromState(rect, editor.state.*, editor.nodes[node_index]).contains(point)) return node_index;
        }
        return null;
    }
    return nodeAtPoint(rect, editor.state.*, editor.nodes, point);
}

pub fn groupAtEditorPoint(rect: Rect, editor: anytype, viewport_index: ?*ViewportIndex, point: [2]f32) ?usize {
    if (viewport_index) |index| {
        const candidates = index.groupIndicesNearPoint(rect, editor.state.pan, editor.state.zoom, point, 0.0);
        var i = candidates.len;
        while (i > 0) {
            i -= 1;
            const group_index = candidates[i];
            if (groupRect(rect, editor.state.*, editor.groups[group_index]).contains(point)) return group_index;
        }
        return null;
    }
    return groupAtPoint(rect, editor.state.*, editor.groups, point);
}

pub fn groupResizeAtEditorPoint(rect: Rect, editor: anytype, viewport_index: ?*ViewportIndex, point: [2]f32) ?GroupResizeHit {
    if (viewport_index) |index| {
        const candidates = index.groupIndicesNearPoint(rect, editor.state.pan, editor.state.zoom, point, editor.group_resize_margin);
        var i = candidates.len;
        while (i > 0) {
            i -= 1;
            const group_index = candidates[i];
            const screen_rect = groupRect(rect, editor.state.*, editor.groups[group_index]);
            if (!screen_rect.contains(point)) continue;
            const margin = @max(0.0, editor.group_resize_margin);
            const edges = GroupResizeEdges{
                .left = point[0] <= screen_rect.x + margin,
                .right = point[0] >= screen_rect.x + screen_rect.w - margin,
                .top = point[1] <= screen_rect.y + margin,
                .bottom = point[1] >= screen_rect.y + screen_rect.h - margin,
            };
            if (edges.any()) return .{ .group_index = group_index, .edges = edges };
        }
        return null;
    }
    return groupResizeAtPoint(rect, editor.state.*, editor.groups, editor.group_resize_margin, point);
}

pub const EventInputModifiers = struct {
    shift_down: bool = false,
    control_down: bool = false,
    super_down: bool = false,
    alt_down: bool = false,
};

pub fn handleEditorEvent(rect: Rect, input: EventInputModifiers, editor: anytype, event: anytype) bool {
    const geometry_drag_active = editor.state.dragging_node_id != null or editor.state.dragging_group_id != null or editor.state.resizing_group_id != null;
    const skip_prepare = switch (event.*) {
        .mouse_move => geometry_drag_active or editor.state.dragging_canvas or editor.state.dragging_minimap or editor.state.box_selecting,
        .mouse_up => geometry_drag_active or editor.state.dragging_canvas or editor.state.dragging_minimap,
        else => false,
    };
    const viewport_index = if (skip_prepare) editorViewportIndex(editor) else prepareNodeEditorViewportIndex(rect, editor);
    switch (event.*) {
        .mouse_move => |m| {
            if (editor.state.dragging_minimap) {
                const snapshot = minimapSnapshotPrepared(rect, editor, viewport_index);
                return editor.state.updateMinimapDrag(rect, snapshot, .{ m.x, m.y });
            }
            if (editor.state.box_selecting) return editor.state.updateBoxSelect(.{ m.x, m.y });
            if (editor.state.reconnecting_connection != null) {
                const changed = editor.state.updateReconnectPreview(.{ m.x, m.y });
                const input_hover = inputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y });
                const output_hover = outputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y });
                editor.state.hover_input_node_id = if (input_hover) |hit| editor.nodes[hit.node_index].id else null;
                editor.state.hover_output_node_id = if (output_hover) |hit| editor.nodes[hit.node_index].id else null;
                const valid = reconnectPreviewCompatible(editor, input_hover, output_hover);
                const valid_changed = editor.state.connection_preview_valid != valid;
                editor.state.connection_preview_valid = valid;
                return changed or valid_changed or input_hover != null or output_hover != null;
            }
            if (editor.state.dragging_connection_from_id != null) {
                editor.state.connection_preview = .{ m.x, m.y };
                const input_hover = inputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y });
                const input_id = if (input_hover) |hit| editor.nodes[hit.node_index].id else null;
                editor.state.hover_input_node_id = input_id;
                const valid = dragPreviewCompatible(editor, input_hover);
                const valid_changed = editor.state.connection_preview_valid != valid;
                editor.state.connection_preview_valid = valid;
                return valid_changed or true;
            }
            if (editor.state.dragging_node_id) |id| {
                if (@abs(m.dx) <= 0.001 and @abs(m.dy) <= 0.001) return false;
                const history_mutation = beginInteractionHistoryIfNeeded(editor) orelse return false;
                return finishInteractionHistory(editor, history_mutation, dragNodeBy(editor, id, .{ m.dx, m.dy }));
            }
            if (editor.state.resizing_group_id) |id| {
                if (@abs(m.dx) <= 0.001 and @abs(m.dy) <= 0.001) return false;
                const history_mutation = beginInteractionHistoryIfNeeded(editor) orelse return false;
                return finishInteractionHistory(editor, history_mutation, resizeGroupBy(editor, id, editor.state.resizing_group_edges, .{ m.dx, m.dy }));
            }
            if (editor.state.dragging_group_id) |id| {
                if (@abs(m.dx) <= 0.001 and @abs(m.dy) <= 0.001) return false;
                const history_mutation = beginInteractionHistoryIfNeeded(editor) orelse return false;
                return finishInteractionHistory(editor, history_mutation, dragGroupBy(editor, id, .{ m.dx, m.dy }));
            }
            if (editor.state.dragging_canvas) return editor.state.panBy(.{ m.dx, m.dy });
            const input_hover = inputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y });
            const output_hover = outputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y });
            const input_id = if (input_hover) |hit| editor.nodes[hit.node_index].id else null;
            const output_id = if (output_hover) |hit| editor.nodes[hit.node_index].id else null;
            const hit = nodeAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y });
            const hover_id = if (hit) |index| editor.nodes[index].id else null;
            const group_hit = if (hit == null and input_hover == null and output_hover == null) groupAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y }) else null;
            const group_hover_id = if (group_hit) |index| editor.groups[index].id else null;
            const hover_connection = if (hit == null and group_hit == null and input_hover == null and output_hover == null) connectionAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y }) else null;
            const changed = editor.state.hover_node_id != hover_id or
                editor.state.hover_group_id != group_hover_id or
                editor.state.hover_input_node_id != input_id or
                editor.state.hover_output_node_id != output_id or !optionalConnectionEqual(editor.state.hover_connection, hover_connection);
            editor.state.hover_node_id = hover_id;
            editor.state.hover_group_id = group_hover_id;
            editor.state.hover_input_node_id = input_id;
            editor.state.hover_output_node_id = output_id;
            editor.state.hover_connection = hover_connection;
            return changed;
        },
        .mouse_leave => {
            if (editor.state.hover_node_id == null and editor.state.hover_group_id == null and editor.state.hover_input_node_id == null and editor.state.hover_output_node_id == null and editor.state.hover_connection == null) return false;
            editor.state.hover_node_id = null;
            editor.state.hover_group_id = null;
            editor.state.hover_input_node_id = null;
            editor.state.hover_output_node_id = null;
            editor.state.hover_connection = null;
            return true;
        },
        .mouse_down => |m| {
            if (m.button == .right) {
                const point = [2]f32{ m.x, m.y };
                if (inputPortAtEditorPoint(rect, editor, viewport_index, point)) |hit| {
                    editor.state.context_menu.node_id = editor.nodes[hit.node_index].id;
                    editor.state.context_menu.port_index = hit.port_index;
                    editor.state.context_menu.group_id = null;
                    editor.state.context_menu.connection = null;
                    return editor.state.openContextMenu(.input_port, point);
                }
                if (outputPortAtEditorPoint(rect, editor, viewport_index, point)) |hit| {
                    editor.state.context_menu.node_id = editor.nodes[hit.node_index].id;
                    editor.state.context_menu.port_index = hit.port_index;
                    editor.state.context_menu.group_id = null;
                    editor.state.context_menu.connection = null;
                    return editor.state.openContextMenu(.output_port, point);
                }
                if (nodeAtEditorPoint(rect, editor, viewport_index, point)) |index| {
                    const id = editor.nodes[index].id;
                    if (!editor.state.isNodeSelected(id)) _ = editor.state.setSingleSelection(id);
                    editor.state.context_menu.node_id = id;
                    editor.state.context_menu.group_id = null;
                    editor.state.context_menu.connection = null;
                    return editor.state.openContextMenu(.node, point);
                }
                if (connectionAtEditorPoint(rect, editor, viewport_index, point)) |connection| {
                    _ = editor.state.setConnectionSelection(connection);
                    editor.state.context_menu.connection = connection;
                    editor.state.context_menu.node_id = null;
                    editor.state.context_menu.group_id = null;
                    return editor.state.openContextMenu(.connection, point);
                }
                if (groupAtEditorPoint(rect, editor, viewport_index, point)) |index| {
                    const id = editor.groups[index].id;
                    _ = editor.state.setGroupSelection(id);
                    editor.state.context_menu.group_id = id;
                    editor.state.context_menu.node_id = null;
                    editor.state.context_menu.connection = null;
                    return editor.state.openContextMenu(.group, point);
                }
                editor.state.context_menu.node_id = null;
                editor.state.context_menu.group_id = null;
                editor.state.context_menu.connection = null;
                return editor.state.openContextMenu(.canvas, point);
            }
            if (m.button != .left) return false;
            if (editor.show_minimap) {
                const point = [2]f32{ m.x, m.y };
                const snapshot = minimapSnapshotPrepared(rect, editor, viewport_index);
                if (snapshot.contains(point)) {
                    _ = editor.state.closeContextMenu();
                    return editor.state.beginMinimapDrag(rect, snapshot, point);
                }
            }
            if (editor.state.selected_connection) |selected_connection| {
                if (outputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |hit| {
                    if (editor.nodes[hit.node_index].id == selected_connection.from_id and hit.port_index == selected_connection.from_port) {
                        return editor.state.beginReconnectConnection(selected_connection, .from, .{ m.x, m.y });
                    }
                }
                if (inputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |hit| {
                    if (editor.nodes[hit.node_index].id == selected_connection.to_id and hit.port_index == selected_connection.to_port) {
                        return editor.state.beginReconnectConnection(selected_connection, .to, .{ m.x, m.y });
                    }
                }
            }
            if (outputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |hit| {
                editor.state.dragging_connection_from_id = editor.nodes[hit.node_index].id;
                editor.state.dragging_connection_from_port = hit.port_index;
                editor.state.connection_preview = .{ m.x, m.y };
                editor.state.connection_preview_valid = true;
                editor.state.pending_connection = null;
                return true;
            }
            if (nodeAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |index| {
                const id = editor.nodes[index].id;
                if (input.shift_down) {
                    return editor.state.toggleNodeSelection(id);
                } else {
                    return editor.state.beginNodeDrag(id);
                }
            }
            if (groupResizeAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |hit| {
                return editor.state.beginGroupResize(editor.groups[hit.group_index].id, hit.edges);
            }
            if (connectionAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |connection| {
                return editor.state.setConnectionSelection(connection);
            }
            if (groupAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |index| {
                return editor.state.beginGroupDrag(editor.groups[index].id);
            }
            if (input.shift_down) {
                const mode: BoxSelectMode = if ((input.control_down or input.super_down) and input.alt_down)
                    .toggle
                else if (input.alt_down)
                    .subtract
                else if (input.control_down or input.super_down)
                    .add
                else
                    .replace;
                return editor.state.beginBoxSelectMode(.{ m.x, m.y }, mode);
            }
            _ = editor.state.clearSelection();
            editor.state.dragging_canvas = true;
            return true;
        },
        .mouse_up => |m| {
            if (m.button != .left) return false;
            if (editor.state.dragging_minimap) {
                editor.state.dragging_minimap = false;
                editor.state.minimap_drag_offset = .{ 0.0, 0.0 };
                return true;
            }
            if (editor.state.box_selecting) {
                editor.state.box_select_end = .{ m.x, m.y };
                const box = editor.state.boxSelectRect();
                if (viewport_index) |index| {
                    const candidates = index.nodeIndicesInScreenRect(rect, editor.state.pan, editor.state.zoom, box);
                    return editor.state.applyBoxSelectionCandidates(editor.nodes, candidates, box, rect, editor.state.zoom, editor.state.pan);
                }
                return editor.state.applyBoxSelection(editor.nodes, box, rect, editor.state.zoom, editor.state.pan);
            }
            if (editor.state.reconnecting_connection) |connection| {
                const endpoint = editor.state.reconnecting_connection_end;
                var changed = false;
                if (editor.mutable_connections) |connections| {
                    if (editor.mutable_connection_len) |len| {
                        const target_id = switch (endpoint) {
                            .from => if (outputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |hit| editor.nodes[hit.node_index].id else null,
                            .to => if (inputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |hit| editor.nodes[hit.node_index].id else null,
                        };
                        const target_port = switch (endpoint) {
                            .from => if (outputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |hit| hit.port_index else 0,
                            .to => if (inputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |hit| hit.port_index else 0,
                        };
                        if (target_id) |id| {
                            var replacement = connection;
                            switch (endpoint) {
                                .from => {
                                    replacement.from_id = id;
                                    replacement.from_port = target_port;
                                },
                                .to => {
                                    replacement.to_id = id;
                                    replacement.to_port = target_port;
                                },
                            }
                            if (connectionAllowed(editor.nodes, connections[0..@min(len.*, connections.len)], replacement, editorConnectionPolicy(editor), .{
                                .ignore_connection = graph_validation.ConnectionKey.from(connection),
                            })) {
                                if (beginEditorHistory(editor)) |history_mutation| {
                                    changed = editor.state.reconnectConnectionPortWithPolicy(connections, len, connection, endpoint, id, target_port, editor.nodes, editorConnectionPolicy(editor));
                                    _ = finishEditorHistory(editor, history_mutation, changed);
                                }
                            }
                        }
                    }
                }
                editor.state.reconnecting_connection = null;
                editor.state.connection_preview_valid = true;
                editor.state.hover_input_node_id = null;
                editor.state.hover_output_node_id = null;
                return changed;
            }
            if (editor.state.dragging_connection_from_id) |from_id| {
                if (inputPortAtEditorPoint(rect, editor, viewport_index, .{ m.x, m.y })) |to_hit| {
                    const to_id = editor.nodes[to_hit.node_index].id;
                    if (from_id != to_id) {
                        const connection = Connection{ .from_id = from_id, .from_port = editor.state.dragging_connection_from_port, .to_id = to_id, .to_port = to_hit.port_index };
                        if (editor.mutable_connections) |connections| {
                            if (editor.mutable_connection_len) |len| {
                                const before_len = len.*;
                                const active_connections = connections[0..@min(before_len, connections.len)];
                                const can_append = before_len < connections.len and connectionAllowed(editor.nodes, active_connections, connection, editorConnectionPolicy(editor), .{});
                                if (can_append) {
                                    const history_capacity_ok = if (editor.history) |history|
                                        history.supportsGraphCapacity(if (editor.mutable_node_len) |node_len| @min(node_len.*, editor.nodes.len) else editor.nodes.len, if (editor.mutable_group_len) |group_len| @min(group_len.*, editor.groups.len) else editor.groups.len, before_len + 1, 1)
                                    else
                                        true;
                                    if (history_capacity_ok) {
                                        if (beginEditorHistory(editor)) |history_mutation| {
                                            const changed = editor.state.appendConnectionWithPolicy(connections, len, connection, editor.nodes, editorConnectionPolicy(editor));
                                            _ = finishEditorHistory(editor, history_mutation, changed);
                                        }
                                    }
                                } else {
                                    editor.state.pending_connection = null;
                                }
                            } else {
                                editor.state.pending_connection = connection;
                            }
                        } else {
                            editor.state.pending_connection = connection;
                        }
                    }
                }
                editor.state.dragging_connection_from_id = null;
                editor.state.dragging_connection_from_port = 0;
                editor.state.connection_preview_valid = true;
                return true;
            }
            return editor.state.endDrag();
        },
        .mouse_wheel => |w| {
            if (!rect.contains(.{ w.x, w.y })) return false;
            return editor.state.panBy(.{ @floatCast(w.delta_x), @floatCast(w.delta_y) });
        },
        .mouse_pinch => |p| {
            if (!rect.contains(.{ p.x, p.y })) return false;
            return editor.state.zoomAt(rect, .{ p.x, p.y }, @floatCast(p.scale_delta));
        },
        .key_down => |key| switch (key) {
            .home => {
                const before_pan = editor.state.pan;
                const before_zoom = editor.state.zoom;
                editor.state.pan = .{ 0.0, 0.0 };
                editor.state.zoom = 1.0;
                return @abs(before_pan[0]) > 0.001 or @abs(before_pan[1]) > 0.001 or @abs(before_zoom - 1.0) > 0.001;
            },
            else => return false,
        },
        else => return false,
    }
}

pub fn handleElementEvent(node: anytype, event: anytype) bool {
    if (node.element != .node_editor) return false;
    return handleEditorEvent(node.rect, .{
        .shift_down = node.input_shift_down,
        .control_down = node.input_control_down,
        .super_down = node.input_super_down,
        .alt_down = node.input_alt_down,
    }, node.element.node_editor, event);
}

test "NodeEditor geometry transforms hit nodes ports and groups" {
    const viewport = Rect{ .x = 10, .y = 20, .w = 400, .h = 240 };
    const state = TestState{ .pan = .{ 12, -6 }, .zoom = 2.0 };
    const node = Node{ .id = 1, .title = "A", .pos = .{ -20, 10 }, .size = .{ .w = 80, .h = 50 }, .input_count = 2, .output_count = 2 };
    const group = Group{ .id = 9, .title = "G", .rect = .{ .x = -30, .y = 0, .w = 120, .h = 70 } };
    const screen = graphToScreen(viewport, state, node.pos);
    try std.testing.expectEqual([2]f32{ 182, 154 }, screen);
    try std.testing.expectApproxEqAbs(@as(f32, node.pos[0]), screenToGraph(viewport, state, screen)[0], 0.001);
    const node_rect = nodeRectFromState(viewport, state, node);
    try std.testing.expectEqual(Rect{ .x = 182, .y = 154, .w = 160, .h = 100 }, node_rect);
    try std.testing.expectEqual(@as(?usize, 0), nodeAtPoint(viewport, state, &.{node}, .{ 190, 160 }));
    const out1 = outputPortPositionAt(viewport, state, node, 1);
    try std.testing.expectEqual(@as(?PortHit, .{ .node_index = 0, .port_index = 1 }), outputPortAtPoint(viewport, state, &.{node}, out1));
    const group_rect = groupRect(viewport, state, group);
    try std.testing.expectEqual(Rect{ .x = 162, .y = 134, .w = 240, .h = 140 }, group_rect);
    const resize = groupResizeAtPoint(viewport, state, &.{group}, 8.0, .{ group_rect.x + 2.0, group_rect.y + group_rect.h - 2.0 }) orelse return error.MissingResizeHit;
    try std.testing.expect(resize.edges.left and resize.edges.bottom);
}

test "NodeEditor node drag preserves an existing multi-selection" {
    var selected = [_]u32{ 1, 2, 0, 0 };
    var state = State{
        .selected_node_ids = &selected,
        .selected_node_len = 2,
        .selected_node_id = 2,
    };
    try std.testing.expect(state.beginNodeDrag(1));
    try std.testing.expectEqual(@as(?u32, 1), state.dragging_node_id);
    try std.testing.expectEqual(@as(?u32, 1), state.selected_node_id);
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    try std.testing.expectEqualSlices(u32, &.{ 1, 2 }, state.selected_node_ids[0..state.boundedSelectionLen()]);
    _ = state.endDrag();

    try std.testing.expect(state.beginNodeDrag(3));
    try std.testing.expectEqual(@as(?u32, 3), state.selected_node_id);
    try std.testing.expectEqual(@as(usize, 1), state.boundedSelectionLen());
    try std.testing.expectEqualSlices(u32, &.{3}, state.selected_node_ids[0..state.boundedSelectionLen()]);
}

test "NodeEditor bounds minimap and group resize helpers" {
    const nodes = [_]Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 }, .size = .{ .w = 100, .h = 50 } },
        .{ .id = 2, .title = "B", .pos = .{ 200, 80 }, .size = .{ .w = 60, .h = 60 } },
    };
    const groups = [_]Group{.{ .id = 10, .title = "Group", .rect = .{ .x = -40, .y = -20, .w = 120, .h = 90 } }};
    const bounds = graphBounds(&nodes, &groups);
    try std.testing.expectEqual(Rect{ .x = -40, .y = -20, .w = 300, .h = 160 }, bounds);
    try std.testing.expectEqual([2]f32{ 340, 49 }, defaultInsertPosition(&nodes));
    const resized = resizeGroupRect(groups[0].rect, .{ .left = true, .top = true }, .{ 200, 200 }, .{ .w = 48, .h = 40 });
    try std.testing.expectEqual(Rect{ .x = 32, .y = 30, .w = 48, .h = 40 }, resized);
    const snapshot = minimapSnapshot(.{ .x = 0, .y = 0, .w = 420, .h = 240 }, TestState{ .zoom = 1.0 }, &nodes, &groups, .{ .w = 120, .h = 72 });
    try std.testing.expect(snapshot.visible);
    try std.testing.expect(snapshot.contains(.{ snapshot.minimap_rect.x + 1, snapshot.minimap_rect.y + 1 }));
    const roundtrip = graphPointFromMinimap(snapshot.minimap_rect, snapshot.graph_bounds, minimapPoint(snapshot.minimap_rect, snapshot.graph_bounds, .{ 50, 40 }));
    try std.testing.expectApproxEqAbs(@as(f32, 50), roundtrip[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), roundtrip[1], 0.001);
}

test "NodeEditor connection hit testing and port compatibility" {
    const viewport = Rect{ .x = 0, .y = 0, .w = 320, .h = 160 };
    const state = TestState{};
    const nodes = [_]Node{
        .{ .id = 1, .title = "Source", .pos = .{ -120, -30 }, .size = .{ .w = 80, .h = 60 }, .output_count = 2, .output_types = &.{ .float, .image }, .output_labels = &.{ "value", "image" } },
        .{ .id = 2, .title = "Sink", .pos = .{ 80, -30 }, .size = .{ .w = 80, .h = 60 }, .input_count = 2, .input_types = &.{ .float, .mask }, .input_labels = &.{ "amount", "mask" } },
    };
    try std.testing.expect(connectionPortsCompatible(&nodes, .{ .from_id = 1, .from_port = 0, .to_id = 2, .to_port = 0 }));
    try std.testing.expect(connectionPortsCompatible(&nodes, .{ .from_id = 1, .from_port = 1, .to_id = 2, .to_port = 1 }));
    try std.testing.expect(!connectionPortsCompatible(&nodes, .{ .from_id = 1, .from_port = 2, .to_id = 2, .to_port = 0 }));
    try std.testing.expectEqualStrings("image", outputPortLabel(nodes[0], 1).?);
    const connection = Connection{ .from_id = 1, .from_port = 1, .to_id = 2, .to_port = 1 };
    const out = outputPortPositionAt(viewport, state, nodes[0], 1);
    const in = inputPortPositionAt(viewport, state, nodes[1], 1);
    const mid = [2]f32{ (out[0] + in[0]) * 0.5, (out[1] + in[1]) * 0.5 };
    try std.testing.expect(connectionHit(viewport, state, &nodes, connection, mid));
    try std.testing.expectEqual(connection, connectionAtPoint(viewport, state, &nodes, null, null, &.{connection}, mid).?);
}

test "NodeEditor viewport index preserves full scan hit ordering across transforms" {
    const viewport = Rect{ .x = 20, .y = 30, .w = 420, .h = 260 };
    var selected: [8]u32 = .{0} ** 8;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "source back", .pos = .{ -140, -30 }, .size = .{ .w = 80, .h = 60 }, .input_count = 2, .output_count = 2 },
        .{ .id = 2, .title = "source front", .pos = .{ -140, -30 }, .size = .{ .w = 80, .h = 60 }, .input_count = 2, .output_count = 2 },
        .{ .id = 3, .title = "sink back", .pos = .{ 80, -30 }, .size = .{ .w = 80, .h = 60 }, .input_count = 2, .output_count = 2 },
        .{ .id = 4, .title = "sink front", .pos = .{ 80, -30 }, .size = .{ .w = 80, .h = 60 }, .input_count = 2, .output_count = 2 },
    };
    const groups = [_]Group{
        .{ .id = 10, .title = "group back", .rect = .{ .x = -170, .y = -55, .w = 120, .h = 110 } },
        .{ .id = 11, .title = "group front", .rect = .{ .x = -170, .y = -55, .w = 120, .h = 110 } },
    };
    const connections = [_]Connection{
        .{ .from_id = 1, .from_port = 0, .to_id = 3, .to_port = 0, .color = Color.rgb8(255, 0, 0) },
        .{ .from_id = 2, .from_port = 0, .to_id = 4, .to_port = 0, .color = Color.rgb8(0, 255, 0) },
        .{ .from_id = 999, .to_id = 4 },
    };
    var storage = StaticViewportWorkspace(nodes.len, groups.len, connections.len){};
    var viewport_index = ViewportIndex.init(storage.workspace());
    const editor = Options(State){
        .state = &state,
        .nodes = &nodes,
        .groups = &groups,
        .connections = &connections,
        .viewport_index = &viewport_index,
        .show_minimap = false,
    };

    for ([_]struct { pan: [2]f32, zoom: f32 }{
        .{ .pan = .{ 0, 0 }, .zoom = 1 },
        .{ .pan = .{ 17, -9 }, .zoom = 1.75 },
        .{ .pan = .{ -22, 14 }, .zoom = 0.6 },
    }) |transform| {
        state.pan = transform.pan;
        state.zoom = transform.zoom;
        const prepared = prepareNodeEditorViewportIndex(viewport, editor) orelse return error.ViewportIndexUnavailable;
        const source_rect = nodeRectFromState(viewport, state, nodes[0]);
        const node_point = [2]f32{ source_rect.x + source_rect.w * 0.5, source_rect.y + source_rect.h * 0.5 };
        try std.testing.expectEqual(nodeAtPoint(viewport, state, &nodes, node_point), nodeAtEditorPoint(viewport, editor, prepared, node_point));
        try std.testing.expectEqual(groupAtPoint(viewport, state, &groups, node_point), groupAtEditorPoint(viewport, editor, prepared, node_point));

        const input_point = inputPortPositionAt(viewport, state, nodes[0], 1);
        const output_point = outputPortPositionAt(viewport, state, nodes[0], 1);
        try std.testing.expectEqual(inputPortAtPoint(viewport, state, &nodes, input_point), inputPortAtEditorPoint(viewport, editor, prepared, input_point));
        try std.testing.expectEqual(outputPortAtPoint(viewport, state, &nodes, output_point), outputPortAtEditorPoint(viewport, editor, prepared, output_point));

        const group_screen = groupRect(viewport, state, groups[0]);
        const resize_point = [2]f32{ group_screen.x + 2, group_screen.y + group_screen.h - 2 };
        try std.testing.expectEqual(groupResizeAtPoint(viewport, state, &groups, editor.group_resize_margin, resize_point), groupResizeAtEditorPoint(viewport, editor, prepared, resize_point));

        const a = outputPortPositionAt(viewport, state, nodes[0], 0);
        const b = inputPortPositionAt(viewport, state, nodes[2], 0);
        const connection_point = [2]f32{ (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5 };
        try std.testing.expectEqual(connectionAtPoint(viewport, state, &nodes, null, null, &connections, connection_point), connectionAtEditorPoint(viewport, editor, prepared, connection_point));
        try std.testing.expectEqual(@as(usize, 1), viewport_index.summary().orphan_connection_count);
    }
}

test "NodeEditor viewport index preserves tiny multi-port geometry at minimum zoom" {
    const viewport = Rect{ .x = 0, .y = 0, .w = 320, .h = 180 };
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected, .zoom = 0.2 };
    const nodes = [_]Node{
        .{ .id = 1, .title = "source", .pos = .{ -300, -100 }, .size = .{ .w = 80, .h = 8 }, .input_count = 8, .output_count = 8 },
        .{ .id = 2, .title = "sink", .pos = .{ 220, -100 }, .size = .{ .w = 80, .h = 8 }, .input_count = 8, .output_count = 8 },
    };
    const connections = [_]Connection{.{ .from_id = 1, .from_port = 7, .to_id = 2, .to_port = 7 }};
    var storage = StaticViewportWorkspace(nodes.len, 0, connections.len){};
    var viewport_index = ViewportIndex.init(storage.workspace());
    const editor = Options(State){ .state = &state, .nodes = &nodes, .connections = &connections, .viewport_index = &viewport_index, .semantic_zoom = .{ .mode = .full }, .show_minimap = false };
    const prepared = prepareNodeEditorViewportIndex(viewport, editor) orelse return error.ViewportIndexUnavailable;

    const output_point = outputPortPositionAt(viewport, state, nodes[0], 7);
    const input_point = inputPortPositionAt(viewport, state, nodes[1], 7);
    try std.testing.expectEqual(outputPortAtPoint(viewport, state, &nodes, output_point), outputPortAtEditorPoint(viewport, editor, prepared, output_point));
    try std.testing.expectEqual(inputPortAtPoint(viewport, state, &nodes, input_point), inputPortAtEditorPoint(viewport, editor, prepared, input_point));
    const midpoint = [2]f32{ (output_point[0] + input_point[0]) * 0.5, (output_point[1] + input_point[1]) * 0.5 };
    try std.testing.expectEqual(connectionAtPoint(viewport, state, &nodes, null, null, &connections, midpoint), connectionAtEditorPoint(viewport, editor, prepared, midpoint));
}

test "NodeEditor viewport index safe invalidation and undersized fallback stay correct" {
    const viewport = Rect{ .x = 0, .y = 0, .w = 320, .h = 180 };
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    var nodes = [_]Node{
        .{ .id = 1, .title = "moving", .pos = .{ 1000, 0 } },
        .{ .id = 2, .title = "fixed", .pos = .{ -40, -30 } },
    };
    var storage = StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = ViewportIndex.init(storage.workspace());
    const editor = Options(State){ .state = &state, .nodes = &nodes, .viewport_index = &viewport_index, .show_minimap = false };
    try std.testing.expect(prepareNodeEditorViewportIndex(viewport, editor) != null);
    try std.testing.expectEqualSlices(usize, &.{1}, viewport_index.visibleNodeIndices());

    nodes[0].pos = .{ -40, -30 };
    try std.testing.expect(prepareNodeEditorViewportIndex(viewport, editor) != null);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, viewport_index.visibleNodeIndices());
    try std.testing.expectEqual(@as(u64, 2), viewport_index.summary().rebuild_count);

    var tiny_storage = StaticViewportWorkspace(1, 0, 0){};
    var tiny_index = ViewportIndex.init(tiny_storage.workspace());
    const fallback_editor = Options(State){ .state = &state, .nodes = &nodes, .viewport_index = &tiny_index, .show_minimap = false };
    try std.testing.expect(prepareNodeEditorViewportIndex(viewport, fallback_editor) == null);
    const point = graphToScreen(viewport, state, .{ 0, 0 });
    try std.testing.expectEqual(nodeAtPoint(viewport, state, &nodes, point), nodeAtEditorPoint(viewport, fallback_editor, null, point));
}

test "NodeEditor mutable connections replace static connections in paint and hit paths" {
    const viewport = Rect{ .x = 0, .y = 0, .w = 320, .h = 180 };
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "source", .pos = .{ -120, -30 }, .size = .{ .w = 80, .h = 60 } },
        .{ .id = 2, .title = "sink", .pos = .{ 80, -30 }, .size = .{ .w = 80, .h = 60 } },
    };
    const static_connections = [_]Connection{.{ .from_id = 2, .to_id = 1, .color = Color.rgb8(255, 0, 0) }};
    var mutable_connections = [_]Connection{.{ .from_id = 1, .to_id = 2, .color = Color.rgb8(0, 255, 0) }};
    var mutable_len: usize = 1;
    var storage = StaticViewportWorkspace(nodes.len, 0, mutable_connections.len){};
    var viewport_index = ViewportIndex.init(storage.workspace());
    const editor = Options(State){
        .state = &state,
        .nodes = &nodes,
        .connections = &static_connections,
        .mutable_connections = &mutable_connections,
        .mutable_connection_len = &mutable_len,
        .viewport_index = &viewport_index,
        .show_minimap = false,
        .grid_color = Color.transparent,
    };
    const prepared = prepareNodeEditorViewportIndex(viewport, editor) orelse return error.ViewportIndexUnavailable;
    try std.testing.expectEqual(@as(usize, 1), prepared.visibleConnectionIndices().len);
    const a = outputPortPositionAt(viewport, state, nodes[0], 0);
    const b = inputPortPositionAt(viewport, state, nodes[1], 0);
    const midpoint = [2]f32{ (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5 };
    try std.testing.expectEqual(mutable_connections[0], connectionAtEditorPoint(viewport, editor, prepared, midpoint).?);

    var out = std.ArrayList(DrawCmd).empty;
    defer {
        for (out.items) |cmd| draw_cmd.freePayload(std.testing.allocator, cmd);
        out.deinit(std.testing.allocator);
    }
    _ = try appendNodeEditor(std.testing.allocator, &out, viewport, editor, 0);
    var stroke_count: usize = 0;
    for (out.items) |command| switch (command) {
        .stroke_path => stroke_count += 1,
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), stroke_count);
}

test "NodeEditor connection draw workspace eliminates path payload allocations" {
    const node_count = 64;
    const connection_count = node_count - 1;
    var nodes: [node_count]Node = undefined;
    var connections: [connection_count]Connection = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{
        .id = @intCast(index + 1),
        .title = "node",
        .pos = .{ @floatFromInt(index * 18), @floatFromInt((index % 4) * 12) },
        .size = .{ .w = 16, .h = 12 },
    };
    for (&connections, 0..) |*connection, index| connection.* = .{
        .from_id = nodes[index].id,
        .to_id = nodes[index + 1].id,
        .color = if (index & 1 == 0) Color.rgba8(59, 130, 246, 190) else Color.rgba8(16, 185, 129, 170),
    };
    var selected_ids: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected_ids };
    var viewport_storage = StaticViewportWorkspace(node_count, 0, connection_count){};
    var viewport_index = ViewportIndex.init(viewport_storage.workspace());
    var draw_storage = StaticConnectionDrawWorkspace(connection_count){};
    var draw_workspace = draw_storage.workspace();
    const viewport = Rect{ .x = 0, .y = 0, .w = 3000, .h = 400 };
    const editor = Options(State){
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .connection_draw_workspace = &draw_workspace,
        .viewport_index = &viewport_index,
        .show_minimap = false,
    };
    const prepared = prepareNodeEditorViewportIndex(viewport, editor) orelse return error.ViewportIndexUnavailable;
    const visible = prepared.visibleConnectionIndices();
    try std.testing.expectEqual(connection_count, visible.len);

    var out = try std.ArrayList(DrawCmd).initCapacity(std.testing.allocator, visible.len);
    defer out.deinit(std.testing.allocator);
    for (visible) |connection_index| {
        try appendNodeEditorConnectionItem(std.testing.failing_allocator, &out, viewport, editor, null, &draw_workspace, prepared, connection_index, connections[connection_index], 7);
    }
    try std.testing.expectEqual(visible.len, out.items.len);
    for (out.items, visible) |command, connection_index| {
        const stroke = command.stroke_path;
        try std.testing.expect(!stroke.owns_commands);
        try std.testing.expectEqual(connections[connection_index].color, stroke.color);
        try std.testing.expectEqual(@as(f32, 2.0), stroke.style.width);
        try std.testing.expectEqual(@as(i32, 7), stroke.layer);
        const expected = connectionPathForPoints(
            outputPortPositionAt(viewport, state, nodes[connection_index], 0),
            inputPortPositionAt(viewport, state, nodes[connection_index + 1], 0),
        );
        try std.testing.expectEqual(render.PathCommand{ .move_to = expected.start }, stroke.commands[0]);
        try std.testing.expectEqual(render.PathCommand{ .cubic_to = .{ .c0 = expected.c0, .c1 = expected.c1, .end = expected.end } }, stroke.commands[1]);
        const render_command = draw_cmd.toRenderCmd(command).stroke_path;
        try std.testing.expectEqualSlices(render.PathCommand, stroke.commands, render_command.path.commands);
        try std.testing.expectEqual(stroke.style, render_command.style);
        try std.testing.expectEqual(stroke.color.toArr4(), render_command.color);
        try std.testing.expectEqual(stroke.layer, render_command.layer);
        draw_cmd.freePayload(std.testing.failing_allocator, command);
    }
    const summary = draw_workspace.summary();
    try std.testing.expectEqual(@as(u64, 0), summary.frame_count);
    try std.testing.expectEqual(visible.len, summary.borrowed_connection_count);
    try std.testing.expect(summary.allocationFree());
}

test "NodeEditor borrowed connection payload clones into independent ownership" {
    var storage = StaticConnectionDrawWorkspace(1){};
    var workspace = storage.workspace();
    workspace.path_commands[0] = .{
        .{ .move_to = .{ 1, 2 } },
        .{ .cubic_to = .{ .c0 = .{ 3, 4 }, .c1 = .{ 5, 6 }, .end = .{ 7, 8 } } },
    };
    const borrowed = DrawCmd{ .stroke_path = .{
        .commands = &workspace.path_commands[0],
        .style = .{ .width = 2, .cap = .round, .join = .round },
        .color = Color.rgba8(59, 130, 246, 190),
        .layer = 7,
        .owns_commands = false,
    } };
    try std.testing.expect(!draw_cmd.ownsPayload(borrowed));
    draw_cmd.freePayload(std.testing.failing_allocator, borrowed);
    const cloned = try draw_cmd.clonePayload(std.testing.allocator, borrowed);
    defer draw_cmd.freePayload(std.testing.allocator, cloned);
    try std.testing.expect(draw_cmd.ownsPayload(cloned));
    try std.testing.expect(cloned.stroke_path.commands.ptr != borrowed.stroke_path.commands.ptr);
    try std.testing.expectEqualSlices(render.PathCommand, borrowed.stroke_path.commands, cloned.stroke_path.commands);
    const render_stroke = draw_cmd.toRenderCmd(borrowed).stroke_path;
    try std.testing.expectEqualSlices(render.PathCommand, borrowed.stroke_path.commands, render_stroke.path.commands);
    try std.testing.expectEqual(borrowed.stroke_path.style, render_stroke.style);
    try std.testing.expectEqual(borrowed.stroke_path.color.toArr4(), render_stroke.color);
}

test "NodeEditor connection draw storage supports runtime capacity" {
    var storage = try ConnectionDrawStorage.init(std.testing.allocator, 17);
    defer storage.deinit();
    var workspace = storage.workspace();
    try std.testing.expectEqual(@as(usize, 17), workspace.capacity());
}

test "NodeEditor connection draw workspace reports bounded fallback" {
    const viewport = Rect{ .x = 0, .y = 0, .w = 800, .h = 300 };
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "a", .pos = .{ -250, -30 } },
        .{ .id = 2, .title = "b", .pos = .{ 0, -30 } },
        .{ .id = 3, .title = "c", .pos = .{ 250, -30 } },
    };
    const connections = [_]Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
    };
    var draw_storage = StaticConnectionDrawWorkspace(1){};
    var draw_workspace = draw_storage.workspace();
    const editor = Options(State){ .state = &state, .nodes = &nodes, .connections = &connections, .connection_draw_workspace = &draw_workspace, .show_minimap = false };
    var out = std.ArrayList(DrawCmd).empty;
    defer {
        for (out.items) |command| draw_cmd.freePayload(std.testing.allocator, command);
        out.deinit(std.testing.allocator);
    }
    _ = try appendNodeEditor(std.testing.allocator, &out, viewport, editor, 0);
    const summary = draw_workspace.summary();
    try std.testing.expectEqual(@as(u64, 1), summary.frame_count);
    try std.testing.expectEqual(@as(usize, 1), summary.borrowed_connection_count);
    try std.testing.expectEqual(@as(usize, 1), summary.fallback_connection_count);
    try std.testing.expect(!summary.allocationFree());
    var borrowed_count: usize = 0;
    var owned_count: usize = 0;
    for (out.items) |command| switch (command) {
        .stroke_path => |stroke| if (stroke.owns_commands) {
            owned_count += 1;
        } else {
            borrowed_count += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), borrowed_count);
    try std.testing.expectEqual(@as(usize, 1), owned_count);
}

test "NodeEditor indexed minimap keeps large graph draw commands bounded" {
    const node_count = 600;
    const group_count = 20;
    const connection_count = node_count - 1;
    var nodes: [node_count]Node = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{
        .id = @intCast(index + 1),
        .title = "node",
        .pos = .{ @floatFromInt((index % 30) * 180), @floatFromInt((index / 30) * 110) },
    };
    var groups: [group_count]Group = undefined;
    for (&groups, 0..) |*group, index| group.* = .{
        .id = @intCast(index + 1),
        .title = "group",
        .rect = .{ .x = @floatFromInt(index * 900), .y = -80, .w = 820, .h = 220 },
    };
    var connections: [connection_count]Connection = undefined;
    for (&connections, 0..) |*connection, index| connection.* = .{ .from_id = nodes[index].id, .to_id = nodes[index + 1].id };
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    var storage = StaticViewportWorkspace(node_count, group_count, connection_count){};
    var viewport_index = ViewportIndex.init(storage.workspace());
    const viewport = Rect{ .x = 0, .y = 0, .w = 640, .h = 360 };
    const editor = Options(State){
        .state = &state,
        .nodes = &nodes,
        .groups = &groups,
        .connections = &connections,
        .viewport_index = &viewport_index,
        .minimap_max_node_marks = 32,
        .minimap_max_group_marks = 0,
    };
    const prepared = prepareNodeEditorViewportIndex(viewport, editor) orelse return error.ViewportIndexUnavailable;
    const indexed_bounds = prepared.graphBounds() orelse return error.MissingGraphBounds;
    try std.testing.expectEqual(graphBounds(&nodes, &groups), indexed_bounds);
    try std.testing.expect(prepared.visibleNodeIndices().len < node_count / 10);
    try std.testing.expect(prepared.visibleGroupIndices().len < group_count);
    try std.testing.expect(prepared.visibleConnectionIndices().len < connection_count / 10);

    var main_out = std.ArrayList(DrawCmd).empty;
    defer {
        for (main_out.items) |command| draw_cmd.freePayload(std.testing.allocator, command);
        main_out.deinit(std.testing.allocator);
    }
    var main_editor = editor;
    main_editor.show_minimap = false;
    _ = try appendNodeEditor(std.testing.allocator, &main_out, viewport, main_editor, 0);
    var title_count: usize = 0;
    var stroke_count: usize = 0;
    for (main_out.items) |command| switch (command) {
        .text => title_count += 1,
        .stroke_path => stroke_count += 1,
        else => {},
    };
    try std.testing.expectEqual(prepared.visibleNodeIndices().len + prepared.visibleGroupIndices().len, title_count);
    try std.testing.expectEqual(prepared.visibleConnectionIndices().len, stroke_count);

    var out = std.ArrayList(DrawCmd).empty;
    defer {
        for (out.items) |command| draw_cmd.freePayload(std.testing.allocator, command);
        out.deinit(std.testing.allocator);
    }
    try appendNodeEditorMinimap(std.testing.allocator, &out, viewport, editor, prepared, 0);
    var fill_count: usize = 0;
    for (out.items) |command| switch (command) {
        .rect, .paint_quad => fill_count += 1,
        else => {},
    };
    // Background fill + border, one mark per sample, and viewport border.
    try std.testing.expectEqual(@as(usize, 35), fill_count);
}

test "NodeEditor indexed box selection matches full scan in every mode" {
    const viewport = Rect{ .x = 0, .y = 0, .w = 420, .h = 240 };
    const nodes = [_]Node{
        .{ .id = 1, .title = "outside left", .pos = .{ -600, -30 } },
        .{ .id = 2, .title = "inside back", .pos = .{ -120, -30 } },
        .{ .id = 3, .title = "inside front", .pos = .{ 60, -30 } },
        .{ .id = 4, .title = "outside right", .pos = .{ 700, -30 } },
    };
    const groups = [_]Group{};
    const connections = [_]Connection{};
    var viewport_storage = StaticViewportWorkspace(nodes.len, 0, 0){};
    var viewport_index = ViewportIndex.init(viewport_storage.workspace());
    const box = Rect{ .x = 80, .y = 70, .w = 340, .h = 130 };
    try std.testing.expect(viewport_index.prepare(&nodes, &groups, &connections, viewport, .{ 0, 0 }, 1).ready);
    const candidates = viewport_index.nodeIndicesInScreenRect(viewport, .{ 0, 0 }, 1, box);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, candidates);

    for ([_]BoxSelectMode{ .replace, .add, .subtract, .toggle }) |mode| {
        var full_ids: [8]u32 = .{0} ** 8;
        var indexed_ids: [8]u32 = .{0} ** 8;
        var full = State{ .selected_node_ids = &full_ids };
        var indexed = State{ .selected_node_ids = &indexed_ids };
        _ = full.setSingleSelection(1);
        _ = indexed.setSingleSelection(1);
        full.box_selecting = true;
        indexed.box_selecting = true;
        full.box_select_mode = mode;
        indexed.box_select_mode = mode;

        const full_changed = full.applyBoxSelection(&nodes, box, viewport, 1, .{ 0, 0 });
        const indexed_changed = indexed.applyBoxSelectionCandidates(&nodes, candidates, box, viewport, 1, .{ 0, 0 });
        try std.testing.expectEqual(full_changed, indexed_changed);
        try std.testing.expectEqual(full.selected_node_id, indexed.selected_node_id);
        try std.testing.expectEqual(full.boundedSelectionLen(), indexed.boundedSelectionLen());
        try std.testing.expectEqualSlices(u32, full.selected_node_ids[0..full.boundedSelectionLen()], indexed.selected_node_ids[0..indexed.boundedSelectionLen()]);
    }
}

test "NodeEditor semantic zoom keeps paint and port hit detail aligned" {
    const viewport = Rect{ .x = 0, .y = 0, .w = 420, .h = 240 };
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    const labels = [_][]const u8{ "in", "mask" };
    const nodes = [_]Node{.{
        .id = 1,
        .title = "Node",
        .pos = .{ -80, -40 },
        .size = .{ .w = 160, .h = 84 },
        .input_count = 2,
        .output_count = 2,
        .input_labels = &labels,
        .output_labels = &labels,
    }};
    const groups = [_]Group{.{ .id = 9, .title = "Group", .rect = .{ .x = -110, .y = -65, .w = 220, .h = 140 } }};
    var viewport_storage = StaticViewportWorkspace(nodes.len, groups.len, 0){};
    var viewport_index = ViewportIndex.init(viewport_storage.workspace());

    const cases = [_]struct { zoom: f32, expected: DetailLevel, text_count: usize, point_count: usize, ports_hit: bool }{
        .{ .zoom = 0.25, .expected = .overview, .text_count = 0, .point_count = 0, .ports_hit = false },
        .{ .zoom = 0.5, .expected = .compact, .text_count = 2, .point_count = 8, .ports_hit = true },
        .{ .zoom = 1.0, .expected = .full, .text_count = 6, .point_count = 8, .ports_hit = true },
    };
    for (cases) |case| {
        state.zoom = case.zoom;
        var out = std.ArrayList(DrawCmd).empty;
        defer {
            for (out.items) |command| draw_cmd.freePayload(std.testing.allocator, command);
            out.deinit(std.testing.allocator);
        }
        const editor = Options(State){ .state = &state, .nodes = &nodes, .groups = &groups, .viewport_index = &viewport_index, .show_minimap = false, .grid_color = Color.transparent };
        try std.testing.expectEqual(case.expected, editor.semantic_zoom.detailLevel(state.zoom));
        _ = try appendNodeEditor(std.testing.allocator, &out, viewport, editor, 0);
        var text_count: usize = 0;
        var point_count: usize = 0;
        for (out.items) |command| switch (command) {
            .text => text_count += 1,
            .point => point_count += 1,
            else => {},
        };
        try std.testing.expectEqual(case.text_count, text_count);
        try std.testing.expectEqual(case.point_count, point_count);
        const prepared = prepareNodeEditorViewportIndex(viewport, editor) orelse return error.ViewportIndexUnavailable;
        const input_point = inputPortPositionAt(viewport, state, nodes[0], 0);
        try std.testing.expectEqual(case.ports_hit, inputPortAtEditorPoint(viewport, editor, prepared, input_point) != null);
    }

    state.zoom = 0.25;
    var full_out = std.ArrayList(DrawCmd).empty;
    defer {
        for (full_out.items) |command| draw_cmd.freePayload(std.testing.allocator, command);
        full_out.deinit(std.testing.allocator);
    }
    const full_editor = Options(State){ .state = &state, .nodes = &nodes, .groups = &groups, .viewport_index = &viewport_index, .semantic_zoom = .{ .mode = .full }, .show_minimap = false, .grid_color = Color.transparent };
    _ = try appendNodeEditor(std.testing.allocator, &full_out, viewport, full_editor, 0);
    var full_text_count: usize = 0;
    for (full_out.items) |command| if (command == .text) {
        full_text_count += 1;
    };
    try std.testing.expectEqual(@as(usize, 6), full_text_count);
    const prepared = prepareNodeEditorViewportIndex(viewport, full_editor) orelse return error.ViewportIndexUnavailable;
    try std.testing.expect(inputPortAtEditorPoint(viewport, full_editor, prepared, inputPortPositionAt(viewport, state, nodes[0], 0)) != null);

    state.dragging_connection_from_id = nodes[0].id;
    const active_editor = Options(State){ .state = &state, .nodes = &nodes, .groups = &groups, .viewport_index = &viewport_index, .show_minimap = false, .grid_color = Color.transparent };
    try std.testing.expectEqual(DetailLevel.compact, editorDetailLevel(active_editor));
    try std.testing.expect(inputPortAtEditorPoint(viewport, active_editor, prepared, inputPortPositionAt(viewport, state, nodes[0], 0)) != null);

    state.dragging_connection_from_id = null;
    state.zoom = 1.0;
    var adaptive_near = std.ArrayList(DrawCmd).empty;
    defer {
        for (adaptive_near.items) |command| draw_cmd.freePayload(std.testing.allocator, command);
        adaptive_near.deinit(std.testing.allocator);
    }
    var full_near = std.ArrayList(DrawCmd).empty;
    defer {
        for (full_near.items) |command| draw_cmd.freePayload(std.testing.allocator, command);
        full_near.deinit(std.testing.allocator);
    }
    const adaptive_near_editor = Options(State){ .state = &state, .nodes = &nodes, .groups = &groups, .viewport_index = &viewport_index, .show_minimap = false, .grid_color = Color.transparent };
    const full_near_editor = Options(State){ .state = &state, .nodes = &nodes, .groups = &groups, .viewport_index = &viewport_index, .semantic_zoom = .{ .mode = .full }, .show_minimap = false, .grid_color = Color.transparent };
    _ = try appendNodeEditor(std.testing.allocator, &adaptive_near, viewport, adaptive_near_editor, 0);
    _ = try appendNodeEditor(std.testing.allocator, &full_near, viewport, full_near_editor, 0);
    try std.testing.expectEqual(adaptive_near.items.len, full_near.items.len);
    for (adaptive_near.items, full_near.items) |adaptive_command, full_command| {
        try std.testing.expect(std.meta.eql(adaptive_command, full_command));
    }
}

test "NodeEditor strict dataflow policy rejects cyclic link mutation" {
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 160, 0 } },
        .{ .id = 3, .title = "C", .pos = .{ 320, 0 } },
    };
    var connections: [4]Connection = .{Connection{ .from_id = 0, .to_id = 0 }} ** 4;
    connections[0] = .{ .from_id = 1, .to_id = 2 };
    connections[1] = .{ .from_id = 2, .to_id = 3 };
    var connection_len: usize = 2;
    const cycle = Connection{ .from_id = 3, .to_id = 1 };
    const validation = validateConnection(&nodes, connections[0..connection_len], cycle, .strict_dataflow, .{});
    try std.testing.expect(validation.creates_cycle);
    try std.testing.expectEqualStrings("cycle", validation.firstIssue(.strict_dataflow));
    try std.testing.expect(!state.appendConnectionWithPolicy(&connections, &connection_len, cycle, &nodes, .strict_dataflow));
    try std.testing.expectEqual(@as(usize, 2), connection_len);
    try std.testing.expect(state.pending_connection == null);
    try std.testing.expect(state.appendConnectionWithPolicy(&connections, &connection_len, cycle, &nodes, .default));
    try std.testing.expectEqual(@as(usize, 3), connection_len);
    const graph_report = validateGraph(&nodes, connections[0..connection_len], .strict_dataflow);
    try std.testing.expect(graph_report.cycle_count > 0);
    try std.testing.expect(!graph_report.validFor(.strict_dataflow));
}

test "NodeEditor connected selection follows full upstream and downstream chains" {
    var selected: [8]u32 = .{0} ** 8;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "Input", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "Normalize", .pos = .{ 160, 0 } },
        .{ .id = 3, .title = "Grade", .pos = .{ 320, 0 } },
        .{ .id = 4, .title = "Composite", .pos = .{ 480, 0 } },
        .{ .id = 5, .title = "Viewer", .pos = .{ 640, 0 } },
    };
    const connections = [_]Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
        .{ .from_id = 3, .to_id = 4 },
        .{ .from_id = 2, .to_id = 5 },
    };

    _ = state.setSingleSelection(4);
    try std.testing.expect(state.selectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_upstream_nodes));
    try std.testing.expectEqual(@as(usize, 4), state.boundedSelectionLen());
    try std.testing.expect(state.isNodeSelected(1));
    try std.testing.expect(state.isNodeSelected(2));
    try std.testing.expect(state.isNodeSelected(3));
    try std.testing.expect(state.isNodeSelected(4));
    try std.testing.expectEqual(@as(?u32, 4), state.selected_node_id);

    _ = state.setSingleSelection(1);
    try std.testing.expect(state.selectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_downstream_nodes));
    try std.testing.expectEqual(@as(usize, 5), state.boundedSelectionLen());
    try std.testing.expect(state.isNodeSelected(5));
    try std.testing.expectEqual(@as(?u32, 5), state.selected_node_id);
}

test "NodeEditor connected selection can start from a selected connection" {
    var selected: [8]u32 = .{0} ** 8;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 120, 0 } },
        .{ .id = 3, .title = "C", .pos = .{ 240, 0 } },
        .{ .id = 4, .title = "D", .pos = .{ 360, 0 } },
    };
    const connections = [_]Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
        .{ .from_id = 3, .to_id = 4 },
    };

    _ = state.setConnectionSelection(connections[1]);
    try std.testing.expect(state.selectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_upstream_nodes));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    try std.testing.expect(state.isNodeSelected(1));
    try std.testing.expect(state.isNodeSelected(2));
    try std.testing.expectEqual(@as(?u32, 2), state.selected_node_id);

    _ = state.setConnectionSelection(connections[1]);
    try std.testing.expect(state.selectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_downstream_nodes));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    try std.testing.expect(state.isNodeSelected(3));
    try std.testing.expect(state.isNodeSelected(4));
    try std.testing.expectEqual(@as(?u32, 4), state.selected_node_id);
}

test "NodeEditor connected selection handles cycles branches and no-op capabilities" {
    var selected: [8]u32 = .{0} ** 8;
    var state = State{ .selected_node_ids = &selected };
    const nodes = [_]Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 120, 0 } },
        .{ .id = 3, .title = "C", .pos = .{ 240, 0 } },
        .{ .id = 4, .title = "Branch", .pos = .{ 240, 120 } },
        .{ .id = 5, .title = "Isolated", .pos = .{ 480, 0 } },
    };
    const connections = [_]Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
        .{ .from_id = 3, .to_id = 1 },
        .{ .from_id = 2, .to_id = 4 },
    };

    _ = state.setSingleSelection(1);
    try std.testing.expect(state.canSelectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_downstream_nodes));
    try std.testing.expect(state.selectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_downstream_nodes));
    try std.testing.expectEqual(@as(usize, 4), state.boundedSelectionLen());
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3, 4 }, state.selected_node_ids[0..state.boundedSelectionLen()]);
    try std.testing.expect(!state.canSelectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_downstream_nodes));
    try std.testing.expect(!state.selectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_downstream_nodes));

    _ = state.setSingleSelection(5);
    try std.testing.expect(!state.canSelectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_upstream_nodes));
    try std.testing.expect(!state.selectConnectedNodes(&connections, connections.len, &nodes, nodes.len, .select_upstream_nodes));
}

test "NodeEditor indexed connected selection scales past inline traversal capacity" {
    const node_count = 192;
    var selected: [node_count]u32 = .{0} ** node_count;
    var state = State{ .selected_node_ids = &selected };
    var nodes: [node_count]Node = undefined;
    var connections: [node_count - 1]Connection = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{
        .id = @intCast(index + 1),
        .title = "Node",
        .pos = .{ @floatFromInt(index), 0 },
    };
    for (&connections, 0..) |*connection, index| connection.* = .{
        .from_id = nodes[index].id,
        .to_id = nodes[index + 1].id,
    };
    var topology_storage = graph_topology.StaticWorkspace(node_count, connections.len){};
    var topology = graph_topology.Index.init(topology_storage.workspace());

    _ = state.setSingleSelection(nodes[node_count - 1].id);
    const result = state.selectConnectedNodesIndexedDetailed(&topology, &connections, connections.len, &nodes, nodes.len, .select_upstream_nodes);
    try std.testing.expect(result.complete());
    try std.testing.expect(result.changed);
    try std.testing.expectEqual(node_count, state.boundedSelectionLen());
    try std.testing.expectEqual(node_count, result.traversal.visited_node_count);
    try std.testing.expectEqual(connections.len, result.traversal.edge_visit_count);
    try std.testing.expectEqual(@as(?u32, nodes[node_count - 1].id), state.selected_node_id);

    _ = state.setSingleSelection(nodes[0].id);
    try std.testing.expect(state.selectConnectedNodesIndexed(&topology, &connections, connections.len, &nodes, nodes.len, .select_downstream_nodes));
    try std.testing.expectEqual(node_count, state.boundedSelectionLen());
    try std.testing.expectEqual(@as(u64, 1), topology.summary().rebuild_count);
    try std.testing.expectEqual(@as(u64, 1), topology.summary().cache_hit_count);
}

test "NodeEditor inline history rejects oversized snapshots without truncation" {
    var selected: [24]u32 = .{0} ** 24;
    const state = State{ .selected_node_ids = &selected };
    var nodes: [24]Node = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{
        .id = @intCast(index + 1),
        .title = "Node",
        .pos = .{ @floatFromInt(index), 0 },
    };
    var history = History{};
    try std.testing.expect(!history.pushBefore(state, &nodes, nodes.len, &.{}, 0));
    try std.testing.expectEqual(@as(usize, 0), history.undo_len);
    try std.testing.expectEqual(@as(u64, 1), history.summary().rejected_snapshot_count);
}

test "NodeEditor connection path cache reuses cubic controls" {
    var cache = ConnectionPathCache{};
    const a = [2]f32{ 10, 20 };
    const b = [2]f32{ 140, 80 };
    const first = cache.pathFor(a, b);
    const second = cache.pathFor(a, b);
    try std.testing.expectEqual(first, second);
    var summary = cache.summary();
    try std.testing.expectEqual(@as(u64, 1), summary.miss_count);
    try std.testing.expectEqual(@as(u64, 1), summary.hit_count);
    try std.testing.expectEqual(@as(u64, 1), summary.rebuild_count);
    try std.testing.expectEqual(@as(usize, 1), summary.valid_count);

    _ = cache.pathFor(.{ 12, 20 }, b);
    summary = cache.summary();
    try std.testing.expectEqual(@as(usize, 2), summary.entry_count);
    try std.testing.expectEqual(@as(u64, 2), summary.rebuild_count);
}

test "NodeEditor paint reuses connection path cache payload" {
    var selected: [4]u32 = .{0} ** 4;
    var state = State{ .selected_node_ids = &selected };
    var path_cache = ConnectionPathCache{};
    const nodes = [_]Node{
        .{ .id = 1, .title = "Source", .pos = .{ -120, -30 }, .size = .{ .w = 80, .h = 60 }, .output_count = 1 },
        .{ .id = 2, .title = "Sink", .pos = .{ 80, -30 }, .size = .{ .w = 80, .h = 60 }, .input_count = 1 },
    };
    const connections = [_]Connection{.{ .from_id = 1, .to_id = 2 }};
    var out = std.ArrayList(DrawCmd).empty;
    defer {
        for (out.items) |cmd| draw_cmd.freePayload(std.testing.allocator, cmd);
        out.deinit(std.testing.allocator);
    }
    const editor = Options(State){
        .state = &state,
        .nodes = &nodes,
        .connections = &connections,
        .connection_path_cache = &path_cache,
    };
    _ = try appendNodeEditor(std.testing.allocator, &out, .{ .x = 0, .y = 0, .w = 320, .h = 160 }, editor, 0);
    _ = try appendNodeEditor(std.testing.allocator, &out, .{ .x = 0, .y = 0, .w = 320, .h = 160 }, editor, 0);
    const summary = path_cache.summary();
    try std.testing.expect(summary.rebuild_count > 0);
    try std.testing.expect(summary.hit_count > 0);
}
