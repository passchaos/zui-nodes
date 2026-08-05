//! Command dispatch for the zui-nodes extension.
//!
//! This module replaces the old Zui-core NodeEditor command adapters for the
//! extension package. It owns only UI/editor intent over caller-owned node graph
//! arrays; graph evaluation/runtime remains outside both zui and zui-nodes.

const std = @import("std");
const commands = @import("commands.zig");
const node_editor = @import("node_editor.zig");

pub const NodeEditorCommand = commands.NodeEditorCommand;
pub const SelectionCommand = commands.SelectionCommand;
pub const HistoryCommand = commands.HistoryCommand;
pub const CommandId = commands.CommandId;

pub const CommandContext = struct {
    state: *node_editor.State,
    selection_state: ?*commands.SelectionCommandState = null,
    nodes: []node_editor.Node,
    node_len: *usize,
    connections: []node_editor.Connection = &.{},
    connection_len: ?*usize = null,
    groups: []node_editor.Group = &.{},
    group_len: ?*usize = null,
    history: ?*node_editor.History = null,
    clipboard: ?*node_editor.Clipboard = null,
    insert_image_input: node_editor.NodeTemplate = .{ .title = "Image Input" },
    insert_processing_node: node_editor.NodeTemplate = .{ .title = "Process" },
    insert_output_node: node_editor.NodeTemplate = .{ .title = "Output" },
    insert_chain: node_editor.ChainTemplate = .{ .nodes = &.{} },
    duplicate_id_offset: u32 = 1000,
    duplicate_offset: [2]f32 = .{ 32.0, 24.0 },
};

pub fn commandFromId(command_id: CommandId) ?NodeEditorCommand {
    if (command_id < commands.node_editor_command_id_base) return null;
    const raw = command_id - commands.node_editor_command_id_base;
    if (raw > @intFromEnum(NodeEditorCommand.select_context_port_peers)) return null;
    return @enumFromInt(raw);
}

pub fn selectionCommandFromId(command_id: CommandId) ?SelectionCommand {
    if (command_id < commands.selection_command_id_base) return null;
    const raw = command_id - commands.selection_command_id_base;
    if (raw > @intFromEnum(SelectionCommand.focus)) return null;
    return @enumFromInt(raw);
}

pub fn canDispatchSelection(context: *const CommandContext, command: SelectionCommand) bool {
    const node_count = activeNodeCount(context);
    const connection_count = activeConnectionCount(context);
    return switch (command) {
        .delete, .duplicate => if (context.connection_len != null)
            context.state.canMutateSelectedNodeGraph(command, context.nodes, node_count, context.connections, connection_count)
        else
            context.state.canMutateSelectedNodes(command, context.nodes, node_count),
        .rename, .focus => context.state.canMutateSelectedNodes(command, context.nodes, node_count),
    };
}

pub fn dispatchSelection(context: *CommandContext, command: SelectionCommand) bool {
    if (!canDispatchSelection(context, command)) return false;
    return switch (command) {
        .delete, .duplicate => dispatchSelectionMutation(context, command),
        .rename, .focus => dispatchSelectionStateOnly(context, command),
    };
}

pub fn dispatchSelectionId(context: *CommandContext, command_id: CommandId) bool {
    const command = selectionCommandFromId(command_id) orelse return false;
    return dispatchSelection(context, command);
}

pub fn canDispatch(context: *const CommandContext, command: NodeEditorCommand) bool {
    const node_count = activeNodeCount(context);
    const connection_count = activeConnectionCount(context);
    return switch (command) {
        .clear_selection => context.state.hasSelection(),
        .select_all => node_count > 0,
        .focus_selection, .frame_all => node_count > 0,
        .copy_selection => if (context.clipboard) |_| context.state.selectedNodeStorageCount(context.nodes, node_count) > 0 else false,
        .paste_clipboard => if (context.clipboard) |clipboard| clipboard.hasNodes() and node_count + clipboard.node_len <= context.nodes.len else false,
        .insert_image_input, .insert_processing_node, .insert_output_node => node_count < context.nodes.len,
        .insert_processing_chain => context.insert_chain.nodes.len > 0 and context.connection_len != null and context.state.canInsertNodeChain(context.nodes, node_count, context.connections, connection_count, context.insert_chain),
        .align_left, .align_center_x, .align_right, .align_top, .align_center_y, .align_bottom => context.state.canArrangeSelectedNodes(context.nodes, node_count, command),
        .distribute_horizontal, .distribute_vertical => context.state.canArrangeSelectedNodes(context.nodes, node_count, command),
        .disconnect_selected_link => context.state.canDisconnectSelectedLink(context.connections, connection_count),
        .disconnect_selected_inputs, .disconnect_selected_outputs, .disconnect_selected_links => context.connection_len != null and context.state.canDisconnectSelectedNodeLinks(context.connections, connection_count, context.nodes, node_count, command),
        .select_upstream_nodes, .select_downstream_nodes => context.state.canSelectConnectedNodes(context.connections, connection_count, context.nodes, node_count, command),
        .group_selected_nodes => context.group_len != null and context.state.canGroupSelectedNodes(context.nodes, node_count, context.groups, activeGroupCount(context)),
        .ungroup_selected => context.group_len != null and context.state.canUngroupSelected(context.groups, activeGroupCount(context)),
        .select_group_contents => context.state.canSelectGroupContents(context.nodes, node_count, context.groups, activeGroupCount(context)),
        .fit_group_to_selection => context.group_len != null and context.state.canFitGroupToSelection(context.nodes, node_count, context.groups, activeGroupCount(context)),
        .open_context_menu => true,
        .close_context_menu => context.state.context_menu.open,
        .disconnect_context_port_links => context.connection_len != null and context.state.canDisconnectContextPortLinks(context.connections, connection_count),
        .select_context_port_peers => context.state.canSelectContextPortPeers(context.connections, connection_count, context.nodes, node_count),
        .reconnect_to_previous => context.connection_len != null and context.state.canReconnectSelectedConnectionToPreviousNode(context.connections, connection_count, context.nodes, node_count),
        .reconnect_to_next => context.connection_len != null and context.state.canReconnectSelectedConnectionToNextNode(context.connections, connection_count, context.nodes, node_count),
    };
}

pub fn dispatch(context: *CommandContext, command: NodeEditorCommand) bool {
    if (!canDispatch(context, command)) return false;
    const node_count = activeNodeCount(context);
    return switch (command) {
        .clear_selection => context.state.clearSelection(),
        .select_all => context.state.selectAllNodes(context.nodes, node_count),
        .focus_selection => context.state.lastSelectedNodeId() != null,
        .frame_all => context.state.centerViewportOnGraphPoint(.{ .x = 0, .y = 0, .w = 640, .h = 360 }, .{ 0, 0 }),
        .copy_selection => copySelection(context),
        .paste_clipboard => pasteSelection(context),
        .insert_image_input => insertTemplate(context, context.insert_image_input),
        .insert_processing_node => insertTemplate(context, context.insert_processing_node),
        .insert_output_node => insertTemplate(context, context.insert_output_node),
        .insert_processing_chain => insertChain(context),
        .align_left, .align_center_x, .align_right, .align_top, .align_center_y, .align_bottom, .distribute_horizontal, .distribute_vertical => arrange(context, command),
        .disconnect_selected_link => disconnectSelectedLink(context),
        .disconnect_selected_inputs, .disconnect_selected_outputs, .disconnect_selected_links => disconnectSelectedNodeLinks(context, command),
        .select_upstream_nodes, .select_downstream_nodes => context.state.selectConnectedNodes(context.connections, activeConnectionCount(context), context.nodes, node_count, command),
        .group_selected_nodes => groupSelected(context),
        .ungroup_selected => ungroupSelected(context),
        .select_group_contents => context.state.selectGroupContents(context.nodes, node_count, context.groups, activeGroupCount(context)),
        .fit_group_to_selection => fitGroupToSelection(context),
        .open_context_menu => context.state.openContextMenu(.canvas, .{ 0, 0 }),
        .close_context_menu => context.state.closeContextMenu(),
        .disconnect_context_port_links => disconnectContextPortLinks(context),
        .select_context_port_peers => context.state.selectContextPortPeers(context.connections, activeConnectionCount(context), context.nodes, node_count),
        .reconnect_to_previous => reconnectPrevious(context),
        .reconnect_to_next => reconnectNext(context),
    };
}

pub fn historyCommandFromId(command_id: CommandId) ?HistoryCommand {
    if (command_id < commands.history_command_id_base) return null;
    const raw = command_id - commands.history_command_id_base;
    if (raw > @intFromEnum(HistoryCommand.redo)) return null;
    return @enumFromInt(raw);
}

pub fn canDispatchHistory(context: *const CommandContext, command: HistoryCommand) bool {
    const history = context.history orelse return false;
    return switch (command) {
        .undo => history.canUndo(),
        .redo => history.canRedo(),
    };
}

pub fn dispatchHistory(context: *CommandContext, command: HistoryCommand) bool {
    if (!canDispatchHistory(context, command)) return false;
    const history = context.history orelse return false;
    const connection_len = context.connection_len orelse return false;
    return switch (command) {
        .undo => history.undoWithGroups(context.state, context.nodes, context.node_len, context.groups, context.group_len, context.connections, connection_len),
        .redo => history.redoWithGroups(context.state, context.nodes, context.node_len, context.groups, context.group_len, context.connections, connection_len),
    };
}

pub fn dispatchHistoryId(context: *CommandContext, command_id: CommandId) bool {
    const command = historyCommandFromId(command_id) orelse return false;
    return dispatchHistory(context, command);
}

pub fn dispatchId(context: *CommandContext, command_id: CommandId) bool {
    const command = commandFromId(command_id) orelse return false;
    return dispatch(context, command);
}

fn activeNodeCount(context: *const CommandContext) usize {
    const count = @min(context.node_len.*, context.nodes.len);
    context.node_len.* = count;
    return count;
}

fn activeConnectionCount(context: *const CommandContext) usize {
    const len_ptr = context.connection_len orelse return @min(context.connections.len, context.connections.len);
    const count = @min(len_ptr.*, context.connections.len);
    len_ptr.* = count;
    return count;
}

fn activeGroupCount(context: *const CommandContext) usize {
    const len_ptr = context.group_len orelse return @min(context.groups.len, context.groups.len);
    const count = @min(len_ptr.*, context.groups.len);
    len_ptr.* = count;
    return count;
}

fn pushHistory(context: *CommandContext) void {
    const history = context.history orelse return;
    history.pushBeforeWithGroups(context.state.*, context.nodes, activeNodeCount(context), context.groups[0..activeGroupCount(context)], context.connections, activeConnectionCount(context));
}

fn dispatchSelectionStateOnly(context: *CommandContext, command: SelectionCommand) bool {
    var local_selection = commands.SelectionCommandState{};
    const selection = context.selection_state orelse &local_selection;
    const result = context.state.handleSelectionCommand(command, selection);
    return result.handled;
}

fn dispatchSelectionMutation(context: *CommandContext, command: SelectionCommand) bool {
    const node_count = activeNodeCount(context);
    const selected_before = switch (command) {
        .delete => context.state.lastSelectedStoredNodeId(context.nodes, node_count) orelse context.state.lastSelectedNodeId(),
        else => context.state.lastSelectedNodeId(),
    };
    pushHistory(context);
    const changed = if (context.connection_len) |connection_len|
        switch (command) {
            .delete => context.state.deleteSelectedNodesAndConnections(context.nodes, context.node_len, context.connections, connection_len),
            .duplicate => context.state.duplicateSelectedNodesAndConnections(context.nodes, context.node_len, context.connections, connection_len, context.duplicate_id_offset, context.duplicate_offset),
            .rename, .focus => false,
        }
    else switch (command) {
        .delete => context.state.deleteSelectedNodes(context.nodes, context.node_len),
        .duplicate => context.state.duplicateSelectedNodes(context.nodes, context.node_len, context.duplicate_id_offset, context.duplicate_offset),
        .rename, .focus => false,
    };
    if (!changed) return false;
    if (context.selection_state) |selection| {
        selection.selected_id = context.state.selected_node_id;
        switch (command) {
            .delete => selection.last_deleted_id = selected_before,
            .duplicate => {
                selection.last_duplicated_id = selection.selected_id;
                selection.duplicate_count +%= 1;
            },
            .rename, .focus => {},
        }
    }
    return true;
}

fn copySelection(context: *CommandContext) bool {
    const clipboard = context.clipboard orelse return false;
    return context.state.copySelectionToClipboard(context.nodes, activeNodeCount(context), context.connections, activeConnectionCount(context), clipboard);
}

fn pasteSelection(context: *CommandContext) bool {
    const clipboard = context.clipboard orelse return false;
    pushHistory(context);
    return context.state.pasteClipboard(context.nodes, context.node_len, context.connections, context.connection_len orelse return false, clipboard, .{ 24, 24 });
}

fn insertTemplate(context: *CommandContext, template: node_editor.NodeTemplate) bool {
    pushHistory(context);
    return context.state.insertNodeTemplate(context.nodes, context.node_len, template, node_editor.defaultInsertPosition(context.nodes[0..activeNodeCount(context)]));
}

fn insertChain(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    _ = connection_len;
    pushHistory(context);
    return context.state.insertNodeChain(context.nodes, context.node_len, context.connections, context.connection_len.?, context.insert_chain);
}

fn arrange(context: *CommandContext, command: NodeEditorCommand) bool {
    pushHistory(context);
    return context.state.arrangeSelectedNodes(context.nodes, activeNodeCount(context), command);
}

fn disconnectSelectedLink(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    pushHistory(context);
    return context.state.disconnectSelectedLink(context.connections, connection_len);
}

fn disconnectSelectedNodeLinks(context: *CommandContext, command: NodeEditorCommand) bool {
    const connection_len = context.connection_len orelse return false;
    pushHistory(context);
    return context.state.disconnectSelectedNodeLinks(context.connections, connection_len, command);
}

fn groupSelected(context: *CommandContext) bool {
    const group_len = context.group_len orelse return false;
    pushHistory(context);
    return context.state.groupSelectedNodes(context.nodes, activeNodeCount(context), context.groups, group_len, "Group");
}

fn ungroupSelected(context: *CommandContext) bool {
    const group_len = context.group_len orelse return false;
    pushHistory(context);
    return context.state.ungroupSelected(context.groups, group_len);
}

fn fitGroupToSelection(context: *CommandContext) bool {
    pushHistory(context);
    return context.state.fitSelectedGroupToSelection(context.nodes, activeNodeCount(context), context.groups, activeGroupCount(context));
}

fn reconnectPrevious(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    pushHistory(context);
    return context.state.reconnectSelectedConnectionToPreviousNode(context.connections, connection_len, context.nodes, activeNodeCount(context));
}

fn reconnectNext(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    pushHistory(context);
    return context.state.reconnectSelectedConnectionToNextNode(context.connections, connection_len, context.nodes, activeNodeCount(context));
}

fn disconnectContextPortLinks(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    pushHistory(context);
    return context.state.disconnectContextPortLinks(context.connections, connection_len);
}

test "zui-nodes command dispatch handles selection mutation and insertion" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [8]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 8;
    nodes[0] = .{ .id = 1, .title = "A", .pos = .{ 0, 0 } };
    nodes[1] = .{ .id = 2, .title = "B", .pos = .{ 100, 0 } };
    var node_len: usize = 2;
    var ctx = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len };
    try std.testing.expect(dispatch(&ctx, .select_all));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    try std.testing.expect(dispatch(&ctx, .insert_processing_node));
    try std.testing.expectEqual(@as(usize, 3), node_len);
    try std.testing.expect(state.lastSelectedNodeId() != null);
}

test "zui-nodes command dispatch copies and deletes selected nodes" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [8]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 8;
    nodes[0] = .{ .id = 1, .title = "A", .pos = .{ 0, 0 } };
    nodes[1] = .{ .id = 2, .title = "B", .pos = .{ 100, 0 } };
    var node_len: usize = 2;
    var clipboard = node_editor.Clipboard{};
    var ctx = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .clipboard = &clipboard };
    _ = state.setSingleSelection(1);
    try std.testing.expect(dispatch(&ctx, .copy_selection));
    try std.testing.expect(clipboard.hasNodes());
    try std.testing.expect(dispatch(&ctx, .clear_selection));
    try std.testing.expect(dispatchId(&ctx, NodeEditorCommand.clear_selection.commandId()) == false);
}

test "zui-nodes command dispatch handles group lifecycle" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [8]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 8;
    nodes[0] = .{ .id = 1, .title = "A", .pos = .{ 0, 0 } };
    nodes[1] = .{ .id = 2, .title = "B", .pos = .{ 100, 0 } };
    var node_len: usize = 2;
    var groups: [4]node_editor.Group = .{node_editor.Group{ .id = 0, .title = "", .rect = .zero }} ** 4;
    var group_len: usize = 0;
    var ctx = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .groups = &groups, .group_len = &group_len };
    try std.testing.expect(dispatch(&ctx, .select_all));
    try std.testing.expect(dispatch(&ctx, .group_selected_nodes));
    try std.testing.expectEqual(@as(usize, 1), group_len);
    try std.testing.expectEqual(@as(?u32, groups[0].id), state.selected_group_id);
    try std.testing.expect(dispatch(&ctx, .select_group_contents));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
    _ = state.selectAllNodes(&nodes, node_len);
    state.selected_group_id = groups[0].id;
    groups[0].rect = .{ .x = 0, .y = 0, .w = 20, .h = 20 };
    const before = groups[0].rect;
    try std.testing.expect(dispatch(&ctx, .fit_group_to_selection));
    try std.testing.expect(groups[0].rect.w >= before.w * 0.5);
    try std.testing.expect(dispatch(&ctx, .ungroup_selected));
    try std.testing.expectEqual(@as(usize, 0), group_len);
}

test "zui-nodes command dispatch reconnects selected connection and supports history" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [8]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 8;
    nodes[0] = .{ .id = 1, .title = "A", .pos = .{ 0, 0 } };
    nodes[1] = .{ .id = 2, .title = "B", .pos = .{ 100, 0 } };
    nodes[2] = .{ .id = 3, .title = "C", .pos = .{ 200, 0 } };
    var node_len: usize = 3;
    var connections: [4]node_editor.Connection = .{node_editor.Connection{ .from_id = 0, .to_id = 0 }} ** 4;
    connections[0] = .{ .from_id = 1, .to_id = 2 };
    var connection_len: usize = 1;
    var groups: [2]node_editor.Group = .{node_editor.Group{ .id = 0, .title = "", .rect = .zero }} ** 2;
    var group_len: usize = 0;
    var history = node_editor.History{};
    _ = state.setConnectionSelection(connections[0]);
    var ctx = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .connections = &connections, .connection_len = &connection_len, .groups = &groups, .group_len = &group_len, .history = &history };
    try std.testing.expect(dispatch(&ctx, .reconnect_to_next));
    try std.testing.expectEqual(@as(u32, 3), connections[0].to_id);
    try std.testing.expect(dispatchHistory(&ctx, .undo));
    try std.testing.expectEqual(@as(u32, 2), connections[0].to_id);
    try std.testing.expect(dispatchHistoryId(&ctx, HistoryCommand.redo.commandId()));
    try std.testing.expectEqual(@as(u32, 3), connections[0].to_id);
}

test "zui-nodes selection dispatch duplicates, deletes, and records history" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var selection_state = commands.SelectionCommandState{};
    var nodes: [8]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 8;
    nodes[0] = .{ .id = 1, .title = "A", .pos = .{ 0, 0 } };
    nodes[1] = .{ .id = 2, .title = "B", .pos = .{ 100, 0 } };
    var node_len: usize = 2;
    var connections: [8]node_editor.Connection = .{node_editor.Connection{ .from_id = 0, .to_id = 0 }} ** 8;
    connections[0] = .{ .from_id = 1, .to_id = 2 };
    var connection_len: usize = 1;
    var groups: [2]node_editor.Group = .{node_editor.Group{ .id = 0, .title = "", .rect = .zero }} ** 2;
    var group_len: usize = 0;
    var history = node_editor.History{};
    var ctx = CommandContext{
        .state = &state,
        .selection_state = &selection_state,
        .nodes = &nodes,
        .node_len = &node_len,
        .connections = &connections,
        .connection_len = &connection_len,
        .groups = &groups,
        .group_len = &group_len,
        .history = &history,
    };

    try std.testing.expect(selectionCommandFromId(SelectionCommand.duplicate.commandId()) == .duplicate);
    try std.testing.expect(dispatch(&ctx, .select_all));
    try std.testing.expect(canDispatchSelection(&ctx, .duplicate));
    try std.testing.expect(dispatchSelection(&ctx, .duplicate));
    try std.testing.expectEqual(@as(usize, 4), node_len);
    try std.testing.expectEqual(@as(usize, 2), connection_len);
    try std.testing.expectEqual(@as(u32, 1), selection_state.duplicate_count);
    try std.testing.expect(selection_state.last_duplicated_id != null);

    try std.testing.expect(dispatchHistory(&ctx, .undo));
    try std.testing.expectEqual(@as(usize, 2), node_len);
    try std.testing.expectEqual(@as(usize, 1), connection_len);

    _ = state.setConnectionSelection(connections[0]);
    try std.testing.expect(dispatchSelectionId(&ctx, SelectionCommand.delete.commandId()));
    try std.testing.expectEqual(@as(usize, 2), node_len);
    try std.testing.expectEqual(@as(usize, 0), connection_len);
}
