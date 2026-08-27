const std = @import("std");
const zui = @import("zui");
const node_editor = @import("node_editor.zig");

const columns: usize = 100;
const rows: usize = 100;
const node_count: usize = columns * rows;
const horizontal_connection_count: usize = rows * (columns - 1);
const vertical_connection_count: usize = columns * (rows - 1);
const connection_count: usize = horizontal_connection_count + vertical_connection_count;
const default_iterations: usize = 1000;
const draw_command_capacity: usize = 16384;
const input_labels = [_][]const u8{ "input", "mask" };
const output_labels = [_][]const u8{ "value", "image" };

const Options = struct {
    iterations: usize = default_iterations,
    max_paint_ns: ?f64 = null,
    max_multi_drag_ns: ?f64 = null,
    max_box_connection_ns: ?f64 = null,
    max_navigation_ns: ?f64 = null,
};

const Report = struct {
    node_count: usize,
    connection_count: usize,
    iterations: usize,
    paint_ns_per_frame: f64,
    owning_paint_ns_per_frame: f64,
    paint_speedup: f64,
    multi_drag_ns_per_iteration: f64,
    multi_drag_selection_count: usize,
    alignment_snap_count: usize,
    distribution_snap_count: usize,
    distribution_snap_ns_per_iteration: f64,
    selected_connection_count: usize,
    selected_connection_paint_ns_per_frame: f64,
    selected_connection_delete_ns: f64,
    box_connection_ns_per_iteration: f64,
    max_box_connection_candidates: usize,
    box_connection_candidate_misses: usize,
    navigation_ns_per_iteration: f64,
    max_navigation_candidates: usize,
    max_visible_nodes: usize,
    max_visible_connections: usize,
    max_draw_commands: usize,
    overview_adaptive_commands: usize,
    overview_full_commands: usize,
    hot_path_allocations: usize,
    owned_payload_count: usize,
    owning_payload_count: usize,
    checksum: u64,
    quality_passed: bool,
    performance_passed: bool,
    passed: bool,
};

pub fn main(init: std.process.Init) !void {
    const options = try parseOptions(init);
    const report = try run(init, options);
    try printReport(init.io, report);
    if (!report.quality_passed) return error.EditorPaintBenchQualityFailed;
    if (!report.performance_passed) return error.EditorPaintBenchPerformanceFailed;
}

fn run(init: std.process.Init, options: Options) !Report {
    const allocator = init.gpa;
    const nodes = try allocator.alloc(node_editor.Node, node_count);
    defer allocator.free(nodes);
    const connections = try allocator.alloc(node_editor.Connection, connection_count);
    defer allocator.free(connections);
    for (nodes, 0..) |*node, index| {
        const column = index % columns;
        const row = index / columns;
        node.* = .{
            .id = @intCast(index + 1),
            .title = "node",
            .pos = .{
                (@as(f32, @floatFromInt(column)) - @as(f32, @floatFromInt(columns)) * 0.5) * 184.0,
                (@as(f32, @floatFromInt(row)) - @as(f32, @floatFromInt(rows)) * 0.5) * 112.0,
            },
            .size = .{ .w = 144, .h = 72 },
            .input_count = 2,
            .output_count = 2,
            .input_labels = &input_labels,
            .output_labels = &output_labels,
        };
    }
    var connection_index: usize = 0;
    for (0..rows) |row| {
        for (0..columns - 1) |column| {
            const from = row * columns + column;
            connections[connection_index] = .{ .from_id = nodes[from].id, .to_id = nodes[from + 1].id, .from_port = @intCast(column & 1), .to_port = @intCast(column & 1) };
            connection_index += 1;
        }
    }
    for (0..rows - 1) |row| {
        for (0..columns) |column| {
            const from = row * columns + column;
            connections[connection_index] = .{ .from_id = nodes[from].id, .to_id = nodes[from + columns].id, .from_port = @intCast(row & 1), .to_port = @intCast(row & 1) };
            connection_index += 1;
        }
    }

    var viewport_storage = try node_editor.ViewportStorage.init(allocator, node_count, 0, connection_count);
    defer viewport_storage.deinit();
    var viewport_index = node_editor.ViewportIndex.init(viewport_storage.workspace());
    var owning_viewport_storage = try node_editor.ViewportStorage.init(allocator, node_count, 0, connection_count);
    defer owning_viewport_storage.deinit();
    var owning_viewport_index = node_editor.ViewportIndex.init(owning_viewport_storage.workspace());
    var draw_storage = try node_editor.ConnectionDrawStorage.init(allocator, connection_count);
    defer draw_storage.deinit();
    var draw_workspace = draw_storage.workspace();
    var selected_ids: [64]u32 = .{0} ** 64;
    var selected_connections: [64]node_editor.Connection = undefined;
    var state = node_editor.State{ .selected_node_ids = &selected_ids, .selected_connections = &selected_connections };
    const viewport = zui.Rect{ .x = 0, .y = 0, .w = 1280, .h = 720 };
    var out = try std.ArrayList(zui.DrawCmd).initCapacity(allocator, draw_command_capacity);
    defer out.deinit(allocator);
    var no_memory: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_memory);
    const no_alloc = fixed.allocator();

    var checksum: u64 = 0xcbf2_9ce4_8422_2325;
    var max_visible_nodes: usize = 0;
    var max_visible_connections: usize = 0;
    var max_draw_commands: usize = 0;
    var owned_payload_count: usize = 0;
    var borrowed_elapsed_ns: u64 = 0;
    var owning_elapsed_ns: u64 = 0;
    var owning_out = try std.ArrayList(zui.DrawCmd).initCapacity(allocator, draw_command_capacity);
    defer owning_out.deinit(allocator);
    var owning_payload_count: usize = 0;
    for (0..options.iterations) |iteration| {
        const target_index = (iteration * 7919) % node_count;
        const target = nodes[target_index];
        state.zoom = switch (iteration % 3) {
            0 => 0.55,
            1 => 1.0,
            else => 1.75,
        };
        state.pan = .{ -target.pos[0] * state.zoom, -target.pos[1] * state.zoom };

        out.clearRetainingCapacity();
        const borrowed_started = std.Io.Clock.awake.now(init.io);
        _ = try node_editor.appendNodeEditor(no_alloc, &out, viewport, node_editor.Options(node_editor.State){
            .state = &state,
            .nodes = nodes,
            .connections = connections,
            .connection_draw_workspace = &draw_workspace,
            .viewport_index = &viewport_index,
            .geometry_revision = 1,
            .show_minimap = false,
            .grid_color = zui.Color.transparent,
        }, 0);
        borrowed_elapsed_ns += @intCast(borrowed_started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
        const summary = viewport_index.summary();
        max_visible_nodes = @max(max_visible_nodes, summary.visible_node_count);
        max_visible_connections = @max(max_visible_connections, summary.visible_connection_count);
        max_draw_commands = @max(max_draw_commands, out.items.len);
        var stroke_count: usize = 0;
        for (out.items) |command| {
            if (zui.ui_draw_cmd.ownsPayload(command)) owned_payload_count += 1;
            if (command == .stroke_path) stroke_count += 1;
        }
        checksum = (checksum ^ @as(u64, @intCast(out.items.len))) *% 0x0000_0100_0000_01b3;
        checksum = (checksum ^ @as(u64, @intCast(stroke_count))) *% 0x0000_0100_0000_01b3;
        if (stroke_count != summary.visible_connection_count) return error.EditorPaintConnectionCountMismatch;

        owning_out.clearRetainingCapacity();
        const owning_started = std.Io.Clock.awake.now(init.io);
        _ = try node_editor.appendNodeEditor(allocator, &owning_out, viewport, node_editor.Options(node_editor.State){
            .state = &state,
            .nodes = nodes,
            .connections = connections,
            .viewport_index = &owning_viewport_index,
            .geometry_revision = 1,
            .show_minimap = false,
            .grid_color = zui.Color.transparent,
        }, 0);
        owning_elapsed_ns += @intCast(owning_started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
        for (owning_out.items) |command| {
            if (zui.ui_draw_cmd.ownsPayload(command)) owning_payload_count += 1;
            zui.ui_draw_cmd.freePayload(allocator, command);
        }
    }
    const paint_ns_per_frame = @as(f64, @floatFromInt(borrowed_elapsed_ns)) / @as(f64, @floatFromInt(options.iterations));
    const owning_paint_ns_per_frame = @as(f64, @floatFromInt(owning_elapsed_ns)) / @as(f64, @floatFromInt(options.iterations));
    const paint_speedup = owning_paint_ns_per_frame / paint_ns_per_frame;

    const overview_target = nodes[node_count / 2];
    state.zoom = 0.25;
    state.pan = .{ -overview_target.pos[0] * state.zoom, -overview_target.pos[1] * state.zoom };
    out.clearRetainingCapacity();
    _ = try node_editor.appendNodeEditor(no_alloc, &out, viewport, node_editor.Options(node_editor.State){
        .state = &state,
        .nodes = nodes,
        .connections = connections,
        .connection_draw_workspace = &draw_workspace,
        .viewport_index = &viewport_index,
        .geometry_revision = 1,
        .show_minimap = false,
        .grid_color = zui.Color.transparent,
    }, 0);
    const overview_adaptive_commands = out.items.len;
    out.clearRetainingCapacity();
    _ = try node_editor.appendNodeEditor(no_alloc, &out, viewport, node_editor.Options(node_editor.State){
        .state = &state,
        .nodes = nodes,
        .connections = connections,
        .connection_draw_workspace = &draw_workspace,
        .viewport_index = &viewport_index,
        .geometry_revision = 1,
        .semantic_zoom = .{ .mode = .full },
        .show_minimap = false,
        .grid_color = zui.Color.transparent,
    }, 0);
    const overview_full_commands = out.items.len;
    const paint_summary = viewport_index.summary();

    const drag_selection_count = selected_ids.len;
    var drag_before: [selected_ids.len][2]f32 = undefined;
    for (&selected_ids, &drag_before, 0..) |*selected_id, *before, selection_index| {
        const node_index = selection_index * (node_count / drag_selection_count);
        selected_id.* = nodes[node_index].id;
        before.* = nodes[node_index].pos;
    }
    state.selected_node_len = drag_selection_count;
    state.selected_node_id = selected_ids[0];
    state.zoom = 1;
    state.pan = .{ 0, 0 };
    viewport_index.invalidate();
    const drag_revision: u64 = 2;
    if (!viewport_index.prepareVersioned(nodes, &.{}, connections, viewport, state.pan, state.zoom, drag_revision).ready) return error.EditorDragViewportUnavailable;
    const rebuilds_before_drag = viewport_index.summary().rebuild_count;
    _ = state.beginNodeDrag(selected_ids[0]);
    var drag_changed_count: usize = 0;
    var alignment_snap_count: usize = 0;
    const drag_started = std.Io.Clock.awake.now(init.io);
    for (0..options.iterations) |iteration| {
        var move = zui.ElementEvent{ .mouse_move = .{
            .x = @floatFromInt(iteration),
            .y = @floatFromInt(iteration),
            .dx = 1,
            .dy = 0.5,
        } };
        if (node_editor.handleEditorEvent(viewport, .{}, node_editor.Options(node_editor.State){
            .state = &state,
            .nodes = nodes,
            .mutable_nodes = nodes,
            .connections = connections,
            .viewport_index = &viewport_index,
            .geometry_revision = drag_revision,
            .drag_auto_pan = .{ .enabled = false },
            .drag_snap = .{ .enabled = true, .spacing = .{ 16, 16 }, .threshold_pixels = 6, .show_guides = false },
            .alignment_snap = .{ .enabled = true, .threshold_pixels = 6, .show_guides = false },
            .distribution_snap = .{ .enabled = true, .threshold_pixels = 6, .show_guides = false },
            .show_minimap = false,
        }, &move)) drag_changed_count += 1;
        if (state.snap_guide_x_span != null or state.snap_guide_y_span != null) alignment_snap_count += 1;
    }
    const drag_elapsed_ns: u64 = @intCast(drag_started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
    const multi_drag_ns_per_iteration = @as(f64, @floatFromInt(drag_elapsed_ns)) / @as(f64, @floatFromInt(options.iterations));
    _ = state.endDrag();
    const drag_summary = viewport_index.summary();
    const accumulated_drag = [2]f32{
        @floatFromInt(options.iterations),
        @as(f32, @floatFromInt(options.iterations)) * 0.5,
    };
    const actual_drag = [2]f32{ nodes[viewport_index.nodeIndexForId(selected_ids[0]).?].pos[0] - drag_before[0][0], nodes[viewport_index.nodeIndexForId(selected_ids[0]).?].pos[1] - drag_before[0][1] };
    var drag_correct = drag_changed_count > 0 and !drag_summary.valid and drag_summary.rebuild_count == rebuilds_before_drag;
    drag_correct = drag_correct and @abs(actual_drag[0] - accumulated_drag[0]) <= 6 and @abs(actual_drag[1] - accumulated_drag[1]) <= 6;
    for (selected_ids, drag_before) |selected_id, before| {
        const node_index = viewport_index.nodeIndexForId(selected_id) orelse {
            drag_correct = false;
            continue;
        };
        drag_correct = drag_correct and nodes[node_index].pos[0] == before[0] + actual_drag[0] and
            nodes[node_index].pos[1] == before[1] + actual_drag[1];
    }
    const unselected_before_x = (@as(f32, @floatFromInt(columns - 1)) - @as(f32, @floatFromInt(columns)) * 0.5) * 184.0;
    drag_correct = drag_correct and nodes[node_count - 1].pos[0] == unselected_before_x;

    const distribution_node_index = node_count / 2 + columns / 2;
    const distribution_before = nodes[distribution_node_index].pos;
    try std.testing.expect(state.setSingleSelection(nodes[distribution_node_index].id));
    state.pan = .{ -distribution_before[0], -distribution_before[1] };
    const distribution_revision: u64 = 3;
    if (!viewport_index.prepareVersioned(nodes, &.{}, connections, viewport, state.pan, state.zoom, distribution_revision).ready) return error.EditorDistributionViewportUnavailable;
    const distribution_rebuilds = viewport_index.summary().rebuild_count;
    _ = state.beginNodeDrag(nodes[distribution_node_index].id);
    var distribution_snap_count: usize = 0;
    const distribution_started = std.Io.Clock.awake.now(init.io);
    for (0..options.iterations) |_| {
        var move = zui.ElementEvent{ .mouse_move = .{ .x = viewport.w * 0.5, .y = viewport.h * 0.5, .dx = 0, .dy = 0 } };
        _ = node_editor.handleEditorEvent(viewport, .{}, node_editor.Options(node_editor.State){
            .state = &state,
            .nodes = nodes,
            .mutable_nodes = nodes,
            .connections = connections,
            .viewport_index = &viewport_index,
            .geometry_revision = distribution_revision,
            .drag_auto_pan = .{ .enabled = false },
            .distribution_snap = .{ .enabled = true, .threshold_pixels = 6, .show_guides = false },
            .show_minimap = false,
        }, &move);
        if (state.spacing_guide_x != null or state.spacing_guide_y != null) distribution_snap_count += 1;
    }
    const distribution_elapsed_ns: u64 = @intCast(distribution_started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
    const distribution_snap_ns_per_iteration = @as(f64, @floatFromInt(distribution_elapsed_ns)) / @as(f64, @floatFromInt(options.iterations));
    _ = state.endDrag();
    const distribution_correct = nodes[distribution_node_index].pos[0] == distribution_before[0] and
        nodes[distribution_node_index].pos[1] == distribution_before[1] and
        viewport_index.summary().rebuild_count == distribution_rebuilds and distribution_snap_count == options.iterations;

    _ = state.clearSelection();
    state.zoom = 1;
    const selected_target = nodes[columns / 2];
    state.pan = .{ -selected_target.pos[0], -selected_target.pos[1] };
    viewport_index.invalidate();
    if (!viewport_index.prepareVersioned(nodes, &.{}, connections, viewport, state.pan, state.zoom, 4).ready) return error.EditorSelectedConnectionViewportUnavailable;
    const visible_connections = viewport_index.visibleConnectionIndices();
    const selected_connection_count = @min(selected_connections.len, visible_connections.len);
    for (visible_connections[0..selected_connection_count], 0..) |connection_index_value, selection_index| {
        if (selection_index == 0) {
            _ = state.setConnectionSelection(connections[connection_index_value]);
        } else if (!state.toggleConnectionSelection(connections[connection_index_value])) {
            return error.EditorConnectionSelectionUnavailable;
        }
    }
    const selected_paint_started = std.Io.Clock.awake.now(init.io);
    for (0..options.iterations) |_| {
        out.clearRetainingCapacity();
        _ = try node_editor.appendNodeEditor(no_alloc, &out, viewport, node_editor.Options(node_editor.State){
            .state = &state,
            .nodes = nodes,
            .connections = connections,
            .connection_draw_workspace = &draw_workspace,
            .viewport_index = &viewport_index,
            .geometry_revision = 4,
            .show_minimap = false,
            .grid_color = zui.Color.transparent,
        }, 0);
    }
    const selected_paint_elapsed_ns: u64 = @intCast(selected_paint_started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
    const selected_connection_paint_ns_per_frame = @as(f64, @floatFromInt(selected_paint_elapsed_ns)) / @as(f64, @floatFromInt(options.iterations));
    var selected_stroke_count: usize = 0;
    for (out.items) |command| switch (command) {
        .stroke_path => |stroke| if (stroke.style.width == 3.25) {
            selected_stroke_count += 1;
        },
        else => {},
    };

    const delete_len = @min(connection_count, @as(usize, 4096));
    const delete_connections = try allocator.alloc(node_editor.Connection, delete_len);
    defer allocator.free(delete_connections);
    @memcpy(delete_connections, connections[0..delete_len]);
    var delete_connection_len: usize = delete_len;
    _ = state.clearSelection();
    for (0..selected_connection_count) |index| {
        if (index == 0) _ = state.setConnectionSelection(delete_connections[index]) else _ = state.toggleConnectionSelection(delete_connections[index]);
    }
    const delete_started = std.Io.Clock.awake.now(init.io);
    const delete_changed = state.disconnectSelectedLink(delete_connections, &delete_connection_len);
    const delete_elapsed_ns: u64 = @intCast(delete_started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
    const selected_connection_delete_ns: f64 = @floatFromInt(delete_elapsed_ns);
    const selected_connection_correct = selected_connection_count == selected_connections.len and selected_stroke_count == selected_connection_count and
        delete_changed and delete_connection_len == delete_len - selected_connection_count and state.boundedConnectionSelectionLen() == 0;
    const draw_summary = draw_workspace.summary();
    const selected_paint_visible_connection_count = viewport_index.summary().visible_connection_count;

    var indexed_box_nodes: [64]u32 = .{0} ** 64;
    var indexed_box_connections: [64]node_editor.Connection = undefined;
    var indexed_box_state = node_editor.State{ .selected_node_ids = &indexed_box_nodes, .selected_connections = &indexed_box_connections };
    var full_box_nodes: [64]u32 = .{0} ** 64;
    var full_box_connections: [64]node_editor.Connection = undefined;
    var full_box_state = node_editor.State{ .selected_node_ids = &full_box_nodes, .selected_connections = &full_box_connections };
    const box_rect = zui.Rect{ .x = 460, .y = 250, .w = 360, .h = 220 };
    const box_revision: u64 = 5;
    var box_elapsed_ns: u64 = 0;
    var max_box_connection_candidates: usize = 0;
    var box_connection_candidate_misses: usize = 0;
    var box_selection_correct = true;
    for (0..options.iterations) |iteration| {
        const row = (iteration * 37) % rows;
        const column = (iteration * 61) % columns;
        const target = nodes[row * columns + column];
        indexed_box_state.pan = .{ -target.pos[0], -target.pos[1] };
        const box_started = std.Io.Clock.awake.now(init.io);
        if (!viewport_index.prepareVersioned(nodes, &.{}, connections, viewport, indexed_box_state.pan, 1, box_revision).ready) return error.EditorBoxSelectionViewportUnavailable;
        const node_candidates = viewport_index.nodeIndicesInScreenRect(viewport, indexed_box_state.pan, 1, box_rect);
        const connection_candidates = viewport_index.connectionIndicesInScreenRect(viewport, indexed_box_state.pan, 1, box_rect);
        max_box_connection_candidates = @max(max_box_connection_candidates, connection_candidates.len);
        _ = indexed_box_state.beginBoxSelectModeWithScope(.{ box_rect.x + box_rect.w, box_rect.y }, .replace, .visible_only);
        _ = indexed_box_state.updateBoxSelect(.{ box_rect.x, box_rect.y + box_rect.h });
        _ = indexed_box_state.applyVisibleBoxSelectionIndexed(nodes, node_candidates, connections, connection_candidates, &viewport_index, box_rect, viewport, 1, indexed_box_state.pan);
        box_elapsed_ns += @intCast(box_started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());

        if (iteration % @max(@as(usize, 1), options.iterations / 8) == 0) {
            full_box_state.pan = indexed_box_state.pan;
            _ = full_box_state.beginBoxSelectModeWithScope(.{ box_rect.x + box_rect.w, box_rect.y }, .replace, .visible_only);
            _ = full_box_state.updateBoxSelect(.{ box_rect.x, box_rect.y + box_rect.h });
            _ = full_box_state.applyVisibleBoxSelection(nodes, null, connections, null, box_rect, viewport, 1, full_box_state.pan);
            box_selection_correct = box_selection_correct and
                full_box_state.boundedSelectionLen() == indexed_box_state.boundedSelectionLen() and
                full_box_state.boundedConnectionSelectionLen() == indexed_box_state.boundedConnectionSelectionLen();
            for (full_box_state.selected_node_ids[0..full_box_state.boundedSelectionLen()]) |node_id| {
                if (!indexed_box_state.isNodeSelected(node_id)) box_connection_candidate_misses += 1;
            }
            var full_connection_index: usize = 0;
            while (full_connection_index < full_box_state.boundedConnectionSelectionLen()) : (full_connection_index += 1) {
                if (!indexed_box_state.isConnectionSelected(full_box_state.connectionSelectionAt(full_connection_index).?)) box_connection_candidate_misses += 1;
            }
        }
    }
    const box_connection_ns_per_iteration = @as(f64, @floatFromInt(box_elapsed_ns)) / @as(f64, @floatFromInt(options.iterations));
    box_selection_correct = box_selection_correct and full_box_state.boundedSelectionLen() > 0 and full_box_state.boundedConnectionSelectionLen() > 0 and
        box_connection_candidate_misses == 0 and max_box_connection_candidates > 0 and max_box_connection_candidates < connection_count / 20;

    var navigation_selected: [64]u32 = .{0} ** 64;
    var navigation_state = node_editor.State{ .selected_node_ids = &navigation_selected };
    var navigation_elapsed_ns: u64 = 0;
    var max_navigation_candidates: usize = 0;
    var navigation_changed_count: usize = 0;
    for (0..options.iterations) |iteration| {
        const row = 1 + (iteration * 37) % (rows - 2);
        const column = 1 + (iteration * 61) % (columns - 2);
        const target = nodes[row * columns + column];
        navigation_state.pan = .{ -target.pos[0], -target.pos[1] };
        _ = navigation_state.setSingleSelection(target.id);
        const key: zui.KeyCode = switch (iteration % 4) {
            0 => .left,
            1 => .right,
            2 => .up,
            else => .down,
        };
        var event = zui.ElementEvent{ .key_down = key };
        const navigation_started = std.Io.Clock.awake.now(init.io);
        const handled = node_editor.handleEditorEvent(viewport, .{}, node_editor.Options(node_editor.State){
            .state = &navigation_state,
            .nodes = nodes,
            .connections = connections,
            .viewport_index = &viewport_index,
            .geometry_revision = 6,
            .spatial_navigation = .{ .enabled = true },
            .show_minimap = false,
        }, &event);
        navigation_elapsed_ns += @intCast(navigation_started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
        navigation_changed_count += @intFromBool(handled and navigation_state.selected_node_id != target.id);
        max_navigation_candidates = @max(max_navigation_candidates, navigation_state.navigation_candidate_count);
    }
    const navigation_ns_per_iteration = @as(f64, @floatFromInt(navigation_elapsed_ns)) / @as(f64, @floatFromInt(options.iterations));
    const navigation_correct = navigation_changed_count == options.iterations and max_navigation_candidates > 0 and max_navigation_candidates < node_count / 20;
    const quality_passed = connection_index == connection_count and paint_summary.valid and paint_summary.rebuild_count == 1 and
        max_visible_nodes > 0 and max_visible_nodes < node_count / 20 and
        max_visible_connections > 0 and max_visible_connections < connection_count / 10 and
        max_draw_commands < draw_command_capacity and owned_payload_count == 0 and fixed.end_index == 0 and
        draw_summary.frame_count == options.iterations * 2 + 2 and draw_summary.borrowed_connection_count == selected_paint_visible_connection_count and
        draw_summary.allocationFree() and owning_payload_count > 0 and paint_ns_per_frame <= owning_paint_ns_per_frame * 1.1 and
        overview_adaptive_commands * 3 < overview_full_commands and drag_correct and alignment_snap_count > 0 and distribution_correct and
        selected_connection_correct and box_selection_correct and navigation_correct and checksum != 0;
    const performance_passed = options.max_paint_ns == null or paint_ns_per_frame <= options.max_paint_ns.?;
    const drag_performance_passed = options.max_multi_drag_ns == null or
        (multi_drag_ns_per_iteration <= options.max_multi_drag_ns.? and distribution_snap_ns_per_iteration <= options.max_multi_drag_ns.? and
            selected_connection_paint_ns_per_frame <= options.max_multi_drag_ns.? and selected_connection_delete_ns <= options.max_multi_drag_ns.?);
    const box_performance_passed = options.max_box_connection_ns == null or box_connection_ns_per_iteration <= options.max_box_connection_ns.?;
    const navigation_performance_passed = options.max_navigation_ns == null or navigation_ns_per_iteration <= options.max_navigation_ns.?;
    return .{
        .node_count = node_count,
        .connection_count = connection_count,
        .iterations = options.iterations,
        .paint_ns_per_frame = paint_ns_per_frame,
        .owning_paint_ns_per_frame = owning_paint_ns_per_frame,
        .paint_speedup = paint_speedup,
        .multi_drag_ns_per_iteration = multi_drag_ns_per_iteration,
        .multi_drag_selection_count = drag_selection_count,
        .alignment_snap_count = alignment_snap_count,
        .distribution_snap_count = distribution_snap_count,
        .distribution_snap_ns_per_iteration = distribution_snap_ns_per_iteration,
        .selected_connection_count = selected_connection_count,
        .selected_connection_paint_ns_per_frame = selected_connection_paint_ns_per_frame,
        .selected_connection_delete_ns = selected_connection_delete_ns,
        .box_connection_ns_per_iteration = box_connection_ns_per_iteration,
        .max_box_connection_candidates = max_box_connection_candidates,
        .box_connection_candidate_misses = box_connection_candidate_misses,
        .navigation_ns_per_iteration = navigation_ns_per_iteration,
        .max_navigation_candidates = max_navigation_candidates,
        .max_visible_nodes = max_visible_nodes,
        .max_visible_connections = max_visible_connections,
        .max_draw_commands = max_draw_commands,
        .overview_adaptive_commands = overview_adaptive_commands,
        .overview_full_commands = overview_full_commands,
        .hot_path_allocations = 0,
        .owned_payload_count = owned_payload_count,
        .owning_payload_count = owning_payload_count,
        .checksum = checksum,
        .quality_passed = quality_passed,
        .performance_passed = performance_passed and drag_performance_passed and box_performance_passed and navigation_performance_passed,
        .passed = quality_passed and performance_passed and drag_performance_passed and box_performance_passed and navigation_performance_passed,
    };
}

fn parseOptions(init: std.process.Init) !Options {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    var options = Options{};
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--iterations="))
            options.iterations = try std.fmt.parseInt(usize, arg["--iterations=".len..], 10)
        else if (std.mem.startsWith(u8, arg, "--max-paint-ns="))
            options.max_paint_ns = try std.fmt.parseFloat(f64, arg["--max-paint-ns=".len..])
        else if (std.mem.startsWith(u8, arg, "--max-multi-drag-ns="))
            options.max_multi_drag_ns = try std.fmt.parseFloat(f64, arg["--max-multi-drag-ns=".len..])
        else if (std.mem.startsWith(u8, arg, "--max-box-connection-ns="))
            options.max_box_connection_ns = try std.fmt.parseFloat(f64, arg["--max-box-connection-ns=".len..])
        else if (std.mem.startsWith(u8, arg, "--max-navigation-ns="))
            options.max_navigation_ns = try std.fmt.parseFloat(f64, arg["--max-navigation-ns=".len..])
        else
            return error.InvalidArgument;
    }
    if (options.iterations == 0) return error.InvalidArgument;
    return options;
}

fn printReport(io: std.Io, report: Report) !void {
    var buffer: [1536]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    const stdout = &stdout_file_writer.interface;
    try stdout.print(
        "zui-nodes editor paint bench: nodes={d} connections={d} iterations={d} paint_ns_per_frame={d:.3} owning_paint_ns_per_frame={d:.3} speedup={d:.3}x multi_drag={d}@{d:.3}ns alignment_snaps={d} distribution_snap={d}@{d:.3}ns connection_select={d} paint={d:.3}ns delete={d:.3}ns box_connections={d:.3}ns candidates={d} misses={d} navigation={d:.3}ns candidates={d} max_visible_nodes={d} max_visible_connections={d} max_draw_commands={d} overview_commands={d}/{d} allocations={d} owned_payloads={d} owning_payloads={d} checksum={d} passed={}\n",
        .{ report.node_count, report.connection_count, report.iterations, report.paint_ns_per_frame, report.owning_paint_ns_per_frame, report.paint_speedup, report.multi_drag_selection_count, report.multi_drag_ns_per_iteration, report.alignment_snap_count, report.distribution_snap_count, report.distribution_snap_ns_per_iteration, report.selected_connection_count, report.selected_connection_paint_ns_per_frame, report.selected_connection_delete_ns, report.box_connection_ns_per_iteration, report.max_box_connection_candidates, report.box_connection_candidate_misses, report.navigation_ns_per_iteration, report.max_navigation_candidates, report.max_visible_nodes, report.max_visible_connections, report.max_draw_commands, report.overview_adaptive_commands, report.overview_full_commands, report.hot_path_allocations, report.owned_payload_count, report.owning_payload_count, report.checksum, report.passed },
    );
    try stdout.flush();
}

test "editor paint benchmark options compile" {
    _ = Options{};
}
