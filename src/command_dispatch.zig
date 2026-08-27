//! Command dispatch for the zui-nodes extension.
//!
//! This module replaces the old Zui-core NodeEditor command adapters for the
//! extension package. It owns only UI/editor intent over caller-owned node graph
//! arrays; graph evaluation/runtime remains outside both zui and zui-nodes.

const std = @import("std");
const zui = @import("zui");
const commands = @import("commands.zig");
const graph_layout = @import("graph_layout.zig");
const graph_topology = @import("graph_topology.zig");
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
    viewport: ?zui.Rect = null,
    duplicate_id_offset: u32 = 1000,
    duplicate_offset: [2]f32 = .{ 32.0, 24.0 },
    connection_policy: node_editor.ConnectionPolicy = .default,
    topology_index: ?*graph_topology.Index = null,
    layout_workspace: ?graph_layout.LayeredLayoutWorkspace = null,
    layout_options: graph_layout.LayeredLayoutOptions = .{},
};

pub fn commandFromId(command_id: CommandId) ?NodeEditorCommand {
    if (command_id < commands.node_editor_command_id_base) return null;
    const raw = command_id - commands.node_editor_command_id_base;
    if (raw > @intFromEnum(NodeEditorCommand.auto_layout_layered)) return null;
    return @enumFromInt(raw);
}

pub fn selectionCommandFromId(command_id: CommandId) ?SelectionCommand {
    if (command_id < commands.selection_command_id_base) return null;
    const raw = command_id - commands.selection_command_id_base;
    if (raw > @intFromEnum(SelectionCommand.focus)) return null;
    return @enumFromInt(raw);
}

pub fn canDispatchSelection(context: *const CommandContext, command: SelectionCommand) bool {
    if (!canRecordSelectionCommand(context, command)) return false;
    const node_count = activeNodeCount(context);
    const connection_count = activeConnectionCount(context);
    return switch (command) {
        .delete => if (context.connection_len != null)
            context.state.canMutateSelectedNodeGraph(command, context.nodes, node_count, context.connections, connection_count)
        else
            context.state.canMutateSelectedNodes(command, context.nodes, node_count),
        .duplicate => if (context.connection_len != null)
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
    if (!canRecordNodeEditorCommand(context, command)) return false;
    const node_count = activeNodeCount(context);
    const connection_count = activeConnectionCount(context);
    return switch (command) {
        .clear_selection => context.state.hasSelection(),
        .select_all => node_count > 0,
        .focus_selection, .frame_all => node_count > 0,
        .copy_selection => if (context.clipboard) |_| context.state.selectedNodeStorageCount(context.nodes, node_count) > 0 else false,
        .paste_clipboard => if (context.clipboard) |clipboard| context.connection_len != null and context.state.canPasteClipboardWithPolicy(context.nodes, node_count, context.connections, connection_count, clipboard.*, context.connection_policy) else false,
        .insert_image_input, .insert_processing_node, .insert_output_node => node_count < context.nodes.len,
        .insert_processing_chain => context.insert_chain.nodes.len > 0 and context.connection_len != null and context.state.canInsertNodeChainWithPolicy(context.nodes, node_count, context.connections, connection_count, context.insert_chain, context.connection_policy),
        .align_left, .align_center_x, .align_right, .align_top, .align_center_y, .align_bottom => context.state.canArrangeSelectedNodes(context.nodes, node_count, command),
        .distribute_horizontal, .distribute_vertical => context.state.canArrangeSelectedNodes(context.nodes, node_count, command),
        .disconnect_selected_link => context.state.canDisconnectSelectedLink(context.connections, connection_count),
        .disconnect_selected_inputs, .disconnect_selected_outputs, .disconnect_selected_links => context.connection_len != null and context.state.canDisconnectSelectedNodeLinks(context.connections, connection_count, context.nodes, node_count, command),
        .select_upstream_nodes, .select_downstream_nodes => if (context.topology_index) |topology|
            context.state.canSelectConnectedNodesIndexed(topology, context.connections, connection_count, context.nodes, node_count, command)
        else
            context.state.canSelectConnectedNodes(context.connections, connection_count, context.nodes, node_count, command),
        .group_selected_nodes => context.group_len != null and context.state.canGroupSelectedNodes(context.nodes, node_count, context.groups, activeGroupCount(context)),
        .ungroup_selected => context.group_len != null and context.state.canUngroupSelected(context.groups, activeGroupCount(context)),
        .select_group_contents => context.state.canSelectGroupContents(context.nodes, node_count, context.groups, activeGroupCount(context)),
        .fit_group_to_selection => context.group_len != null and context.state.canFitGroupToSelection(context.nodes, node_count, context.groups, activeGroupCount(context)),
        .open_context_menu => true,
        .close_context_menu => context.state.context_menu.open,
        .disconnect_context_port_links => context.connection_len != null and context.state.canDisconnectContextPortLinks(context.connections, connection_count),
        .select_context_port_peers => context.state.canSelectContextPortPeers(context.connections, connection_count, context.nodes, node_count),
        .reconnect_to_previous => context.connection_len != null and context.state.canReconnectSelectedConnectionToPreviousNodeWithPolicy(context.connections, connection_count, context.nodes, node_count, context.connection_policy),
        .reconnect_to_next => context.connection_len != null and context.state.canReconnectSelectedConnectionToNextNodeWithPolicy(context.connections, connection_count, context.nodes, node_count, context.connection_policy),
        .auto_layout_layered => context.layout_workspace != null and graph_layout.canLayoutLayered(context.nodes, node_count, context.connections[0..connection_count], context.layout_workspace.?, layoutOptions(context)),
    };
}

pub fn dispatch(context: *CommandContext, command: NodeEditorCommand) bool {
    if (!canDispatch(context, command)) return false;
    const node_count = activeNodeCount(context);
    return switch (command) {
        .clear_selection => context.state.clearSelection(),
        .select_all => context.state.selectAllNodes(context.nodes, node_count),
        .focus_selection => if (context.viewport) |viewport|
            context.state.focusSelectionInViewport(viewport, context.nodes, node_count, context.groups[0..activeGroupCount(context)])
        else
            context.state.lastSelectedNodeId() != null,
        .frame_all => if (context.viewport) |viewport|
            context.state.frameAllInViewport(viewport, context.nodes, node_count, context.groups[0..activeGroupCount(context)])
        else
            context.state.centerViewportOnGraphPoint(.{ .x = 0, .y = 0, .w = 640, .h = 360 }, .{ 0, 0 }),
        .copy_selection => copySelection(context),
        .paste_clipboard => pasteSelection(context),
        .insert_image_input => insertTemplate(context, context.insert_image_input),
        .insert_processing_node => insertTemplate(context, context.insert_processing_node),
        .insert_output_node => insertTemplate(context, context.insert_output_node),
        .insert_processing_chain => insertChain(context),
        .align_left, .align_center_x, .align_right, .align_top, .align_center_y, .align_bottom, .distribute_horizontal, .distribute_vertical => arrange(context, command),
        .disconnect_selected_link => disconnectSelectedLink(context),
        .disconnect_selected_inputs, .disconnect_selected_outputs, .disconnect_selected_links => disconnectSelectedNodeLinks(context, command),
        .select_upstream_nodes, .select_downstream_nodes => if (context.topology_index) |topology|
            context.state.selectConnectedNodesIndexed(topology, context.connections, activeConnectionCount(context), context.nodes, node_count, command)
        else
            context.state.selectConnectedNodes(context.connections, activeConnectionCount(context), context.nodes, node_count, command),
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
        .auto_layout_layered => autoLayoutLayered(context),
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
    if (!canRecordHistory(context)) return false;
    return switch (command) {
        .undo => history.canUndoForSelections(context.nodes.len, context.groups.len, context.connections.len, context.state.selected_node_ids.len, if (context.state.selected_connections.len > 0) context.state.selected_connections.len else 1),
        .redo => history.canRedoForSelections(context.nodes.len, context.groups.len, context.connections.len, context.state.selected_node_ids.len, if (context.state.selected_connections.len > 0) context.state.selected_connections.len else 1),
    };
}

pub fn dispatchHistory(context: *CommandContext, command: HistoryCommand) bool {
    if (!canDispatchHistory(context, command)) return false;
    const history = context.history orelse return false;
    const connection_len = context.connection_len orelse return false;
    const changed = switch (command) {
        .undo => history.undoWithGroups(context.state, context.nodes, context.node_len, context.groups, context.group_len, context.connections, connection_len),
        .redo => history.redoWithGroups(context.state, context.nodes, context.node_len, context.groups, context.group_len, context.connections, connection_len),
    };
    if (changed) {
        if (context.topology_index) |topology| topology.invalidate();
    }
    return changed;
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

const HistoryMutation = struct {
    history: ?*node_editor.History = null,
    snapshot: node_editor.HistorySnapshot = .{},
};

fn beginHistoryMutation(context: *CommandContext) ?HistoryMutation {
    const history = context.history orelse return .{};
    const snapshot = history.captureWithGroups(context.state.*, context.nodes, activeNodeCount(context), context.groups[0..activeGroupCount(context)], context.connections, activeConnectionCount(context));
    if (!snapshot.complete) return null;
    return .{ .history = history, .snapshot = snapshot };
}

pub fn canRecordHistory(context: *const CommandContext) bool {
    const history = context.history orelse return true;
    return history.supportsGraphCapacityWithSelections(activeNodeCount(context), activeGroupCount(context), activeConnectionCount(context), context.state.boundedSelectionLen(), context.state.boundedConnectionSelectionLen());
}

pub fn canRecordSelectionCommand(context: *const CommandContext, command: SelectionCommand) bool {
    const node_count = activeNodeCount(context);
    const connection_count = activeConnectionCount(context);
    return switch (command) {
        .delete => canRecordHistory(context),
        .duplicate => historyCanRecordDuplicate(context, node_count, connection_count),
        .rename, .focus => true,
    };
}

pub fn canRecordNodeEditorCommand(context: *const CommandContext, command: NodeEditorCommand) bool {
    const node_count = activeNodeCount(context);
    const group_count = activeGroupCount(context);
    const connection_count = activeConnectionCount(context);
    return switch (command) {
        .paste_clipboard => if (context.clipboard) |clipboard|
            historyCanRecordProjected(context, node_count + clipboard.node_len, group_count, connection_count + clipboard.connection_len, @min(clipboard.node_len, context.state.selected_node_ids.len))
        else
            true,
        .insert_image_input, .insert_processing_node, .insert_output_node => historyCanRecordProjected(context, node_count + 1, group_count, connection_count, @min(@as(usize, 1), context.state.selected_node_ids.len)),
        .insert_processing_chain => historyCanRecordProjected(context, node_count + context.insert_chain.nodes.len, group_count, connection_count + context.insert_chain.connections.len, @min(context.insert_chain.nodes.len, context.state.selected_node_ids.len)),
        .group_selected_nodes => historyCanRecordProjected(context, node_count, group_count + 1, connection_count, context.state.boundedSelectionLen()),
        .align_left,
        .align_center_x,
        .align_right,
        .align_top,
        .align_center_y,
        .align_bottom,
        .distribute_horizontal,
        .distribute_vertical,
        .ungroup_selected,
        .fit_group_to_selection,
        .disconnect_selected_link,
        .disconnect_selected_inputs,
        .disconnect_selected_outputs,
        .disconnect_selected_links,
        .disconnect_context_port_links,
        .reconnect_to_previous,
        .reconnect_to_next,
        .auto_layout_layered,
        => canRecordHistory(context),
        else => true,
    };
}

fn historyCanRecordProjected(context: *const CommandContext, node_count: usize, group_count: usize, connection_count: usize, selection_count: usize) bool {
    const history = context.history orelse return true;
    return canRecordHistory(context) and history.supportsGraphCapacityWithSelections(node_count, group_count, connection_count, selection_count, context.state.boundedConnectionSelectionLen());
}

fn historyCanRecordDuplicate(context: *const CommandContext, node_count: usize, connection_count: usize) bool {
    const selected_count = context.state.selectedNodeStorageCount(context.nodes, node_count);
    var internal_connection_count: usize = 0;
    for (context.connections[0..connection_count]) |connection| {
        if (context.state.isNodeSelected(connection.from_id) and context.state.isNodeSelected(connection.to_id)) internal_connection_count += 1;
    }
    const projected_connection_count = if (context.connection_len != null) connection_count + internal_connection_count else connection_count;
    return historyCanRecordProjected(context, node_count + selected_count, activeGroupCount(context), projected_connection_count, @min(selected_count, context.state.selected_node_ids.len));
}

fn layoutOptions(context: *const CommandContext) graph_layout.LayeredLayoutOptions {
    var options = context.layout_options;
    options.connection_policy = context.connection_policy;
    return options;
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
    const history_mutation = beginHistoryMutation(context) orelse return false;
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
    if (!finishTopologyHistoryMutation(context, history_mutation, changed)) return false;
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
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishTopologyHistoryMutation(context, history_mutation, context.state.pasteClipboardWithPolicy(context.nodes, context.node_len, context.connections, context.connection_len orelse return false, clipboard, .{ 24, 24 }, context.connection_policy));
}

fn insertTemplate(context: *CommandContext, template: node_editor.NodeTemplate) bool {
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishTopologyHistoryMutation(context, history_mutation, context.state.insertNodeTemplate(context.nodes, context.node_len, template, node_editor.defaultInsertPosition(context.nodes[0..activeNodeCount(context)])));
}

fn insertChain(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    _ = connection_len;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    var chain = context.insert_chain;
    chain.start_pos = node_editor.defaultInsertPosition(context.nodes[0..activeNodeCount(context)]);
    return finishTopologyHistoryMutation(context, history_mutation, context.state.insertNodeChainWithPolicy(context.nodes, context.node_len, context.connections, context.connection_len.?, chain, context.connection_policy));
}

fn arrange(context: *CommandContext, command: NodeEditorCommand) bool {
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishHistoryMutation(history_mutation, context.state.arrangeSelectedNodes(context.nodes, activeNodeCount(context), command));
}

fn disconnectSelectedLink(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishTopologyHistoryMutation(context, history_mutation, context.state.disconnectSelectedLink(context.connections, connection_len));
}

fn disconnectSelectedNodeLinks(context: *CommandContext, command: NodeEditorCommand) bool {
    const connection_len = context.connection_len orelse return false;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishTopologyHistoryMutation(context, history_mutation, context.state.disconnectSelectedNodeLinks(context.connections, connection_len, command));
}

fn groupSelected(context: *CommandContext) bool {
    const group_len = context.group_len orelse return false;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishHistoryMutation(history_mutation, context.state.groupSelectedNodes(context.nodes, activeNodeCount(context), context.groups, group_len, "Group"));
}

fn ungroupSelected(context: *CommandContext) bool {
    const group_len = context.group_len orelse return false;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishHistoryMutation(history_mutation, context.state.ungroupSelected(context.groups, group_len));
}

fn fitGroupToSelection(context: *CommandContext) bool {
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishHistoryMutation(history_mutation, context.state.fitSelectedGroupToSelection(context.nodes, activeNodeCount(context), context.groups, activeGroupCount(context)));
}

fn reconnectPrevious(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishTopologyHistoryMutation(context, history_mutation, context.state.reconnectSelectedConnectionToPreviousNodeWithPolicy(context.connections, connection_len, context.nodes, activeNodeCount(context), context.connection_policy));
}

fn reconnectNext(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishTopologyHistoryMutation(context, history_mutation, context.state.reconnectSelectedConnectionToNextNodeWithPolicy(context.connections, connection_len, context.nodes, activeNodeCount(context), context.connection_policy));
}

fn disconnectContextPortLinks(context: *CommandContext) bool {
    const connection_len = context.connection_len orelse return false;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    return finishTopologyHistoryMutation(context, history_mutation, context.state.disconnectContextPortLinks(context.connections, connection_len));
}

fn autoLayoutLayered(context: *CommandContext) bool {
    const workspace = context.layout_workspace orelse return false;
    const history_mutation = beginHistoryMutation(context) orelse return false;
    const result = graph_layout.layoutLayered(context.nodes, activeNodeCount(context), context.connections[0..activeConnectionCount(context)], workspace, layoutOptions(context));
    return finishHistoryMutation(history_mutation, result.changed());
}

fn finishHistoryMutation(mutation: HistoryMutation, changed: bool) bool {
    if (!changed) return false;
    if (mutation.history) |history| return history.commitBefore(mutation.snapshot);
    return true;
}

fn finishTopologyHistoryMutation(context: *CommandContext, mutation: HistoryMutation, changed: bool) bool {
    if (!changed) return false;
    if (context.topology_index) |topology| topology.invalidate();
    return finishHistoryMutation(mutation, true);
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

test "zui-nodes command dispatch auto layouts a strict dataflow graph" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [6]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 6;
    nodes[0] = .{ .id = 10, .title = "Source", .pos = .{ 50, 30 } };
    nodes[1] = .{ .id = 20, .title = "Grade", .pos = .{ 25, 90 } };
    nodes[2] = .{ .id = 30, .title = "Output", .pos = .{ -10, 120 } };
    var node_len: usize = 3;
    var connections = [_]node_editor.Connection{
        .{ .from_id = 10, .to_id = 20 },
        .{ .from_id = 20, .to_id = 30 },
    };
    var workspace_storage = graph_layout.StaticLayeredLayoutWorkspace(8, 8){};
    var ctx = CommandContext{
        .state = &state,
        .nodes = &nodes,
        .node_len = &node_len,
        .connections = &connections,
        .layout_workspace = workspace_storage.workspace(),
        .layout_options = .{ .origin = .{ -40, -20 }, .layer_gap = 180, .node_gap = 30 },
        .connection_policy = .strict_dataflow,
    };
    try std.testing.expect(canDispatch(&ctx, .auto_layout_layered));
    try std.testing.expect(dispatch(&ctx, .auto_layout_layered));
    try std.testing.expectEqual(@as(f32, -40), nodes[0].pos[0]);
    try std.testing.expectEqual(@as(f32, 140), nodes[1].pos[0]);
    try std.testing.expectEqual(@as(f32, 320), nodes[2].pos[0]);
}

test "zui-nodes command dispatch uses indexed traversal for large dependency chains" {
    const node_count = 96;
    var selected: [node_count]u32 = .{0} ** node_count;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [node_count]node_editor.Node = undefined;
    var connections: [node_count - 1]node_editor.Connection = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{
        .id = @intCast(index + 1),
        .title = "Node",
        .pos = .{ @floatFromInt(index), 0 },
    };
    for (&connections, 0..) |*connection, index| connection.* = .{
        .from_id = nodes[index].id,
        .to_id = nodes[index + 1].id,
    };
    var node_len: usize = nodes.len;
    var connection_len: usize = connections.len;
    var topology_storage = graph_topology.StaticWorkspace(node_count, connections.len){};
    var topology = graph_topology.Index.init(topology_storage.workspace());
    var context = CommandContext{
        .state = &state,
        .nodes = &nodes,
        .node_len = &node_len,
        .connections = &connections,
        .connection_len = &connection_len,
        .topology_index = &topology,
    };

    _ = state.setSingleSelection(nodes[node_count - 1].id);
    try std.testing.expect(canDispatch(&context, .select_upstream_nodes));
    try std.testing.expect(dispatch(&context, .select_upstream_nodes));
    try std.testing.expectEqual(node_count, state.boundedSelectionLen());
    try std.testing.expectEqual(@as(u64, 1), topology.summary().rebuild_count);
    try std.testing.expect(topology.summary().cache_hit_count >= 1);
}

test "zui-nodes scalable history preserves large graph undo and rejects unsafe inline history" {
    const node_count = 40;
    const group_count = 20;
    var selected: [node_count]u32 = .{0} ** node_count;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [node_count]node_editor.Node = undefined;
    var connections: [node_count - 1]node_editor.Connection = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{
        .id = @intCast(index + 1),
        .title = "Node",
        .pos = .{ @floatFromInt(index * 10), @floatFromInt(index % 5) },
    };
    for (&connections, 0..) |*connection, index| connection.* = .{
        .from_id = nodes[index].id,
        .to_id = nodes[index + 1].id,
    };
    var groups: [group_count]node_editor.Group = undefined;
    for (&groups, 0..) |*group, index| group.* = .{ .id = @intCast(index + 1), .title = "Group", .rect = .{ .x = @floatFromInt(index * 5), .y = 0, .w = 100, .h = 80 } };
    const original_nodes = nodes;
    const original_groups = groups;
    var node_len: usize = nodes.len;
    var group_len: usize = groups.len;
    var connection_len: usize = connections.len;
    var history = node_editor.History{};
    var layout_storage = graph_layout.StaticLayeredLayoutWorkspace(node_count, node_count){};
    var context = CommandContext{
        .state = &state,
        .nodes = &nodes,
        .node_len = &node_len,
        .connections = &connections,
        .connection_len = &connection_len,
        .groups = &groups,
        .group_len = &group_len,
        .history = &history,
        .layout_workspace = layout_storage.workspace(),
        .connection_policy = .strict_dataflow,
    };

    try std.testing.expect(!canDispatch(&context, .auto_layout_layered));
    try std.testing.expect(!dispatch(&context, .auto_layout_layered));
    try std.testing.expectEqual(@as(usize, 0), history.undo_len);
    try std.testing.expectEqual(original_nodes, nodes);

    var history_storage = try node_editor.HistoryStorage.init(std.testing.allocator, node_count, group_count, connections.len, node_count);
    defer history_storage.deinit();
    try std.testing.expect(history.bindWorkspace(history_storage.workspace()));
    _ = state.selectAllNodes(&nodes, node_len);
    try std.testing.expect(canDispatch(&context, .auto_layout_layered));
    try std.testing.expect(dispatch(&context, .auto_layout_layered));
    groups[group_count - 1].rect.x += 17;
    const laid_out_nodes = nodes;
    const laid_out_groups = groups;
    try std.testing.expect(!std.meta.eql(original_nodes, laid_out_nodes));
    try std.testing.expect(dispatchHistory(&context, .undo));
    try std.testing.expectEqual(original_nodes, nodes);
    try std.testing.expectEqual(original_groups, groups);
    try std.testing.expectEqual(node_count, node_len);
    try std.testing.expectEqual(group_count, group_len);
    try std.testing.expectEqual(connections.len, connection_len);
    try std.testing.expectEqual(node_count, state.boundedSelectionLen());
    try std.testing.expect(dispatchHistory(&context, .redo));
    try std.testing.expectEqual(laid_out_nodes, nodes);
    try std.testing.expectEqual(laid_out_groups, groups);
    try std.testing.expect(history.summary().external_workspace);
    try std.testing.expectEqual(node_count, history.summary().node_capacity);
    try std.testing.expectEqual(@as(u64, 0), history.summary().rejected_snapshot_count);
}

test "zui-nodes scalable history rotates full stacks without aliasing snapshots" {
    const node_count = 24;
    var selected: [node_count]u32 = .{0} ** node_count;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [node_count]node_editor.Node = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{ .id = @intCast(index + 1), .title = "Node", .pos = .{ @floatFromInt(index), 0 } };
    var node_len: usize = nodes.len;
    var connections: [1]node_editor.Connection = undefined;
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var history_workspace = node_editor.StaticHistoryWorkspace(node_count, 1, 1, node_count){};
    try std.testing.expect(history.bindWorkspace(history_workspace.workspace()));

    var step: usize = 0;
    while (step < node_editor.History.stack_capacity + 4) : (step += 1) {
        try std.testing.expect(history.pushBefore(state, &nodes, node_len, &connections, connection_len));
        nodes[0].pos[0] += 1;
    }
    try std.testing.expectEqual(node_editor.History.stack_capacity, history.undo_len);
    try std.testing.expectEqual(@as(u64, 4), history.summary().dropped_snapshot_count);
    const final_x = nodes[0].pos[0];
    for (0..node_editor.History.stack_capacity) |undo_index| {
        try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
        try std.testing.expectEqual(final_x - @as(f32, @floatFromInt(undo_index + 1)), nodes[0].pos[0]);
    }
    try std.testing.expect(!history.canUndo());
    for (0..node_editor.History.stack_capacity) |redo_index| {
        try std.testing.expect(history.redo(&state, &nodes, &node_len, &connections, &connection_len));
        try std.testing.expectEqual(final_x - @as(f32, @floatFromInt(node_editor.History.stack_capacity - redo_index - 1)), nodes[0].pos[0]);
    }
    try std.testing.expectEqual(final_x, nodes[0].pos[0]);
    try std.testing.expect(!history.canRedo());
    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expectEqual(@as(usize, 1), history.redo_len);
    try std.testing.expect(history.pushBefore(state, &nodes, node_len, &connections, connection_len));
    nodes[0].pos[0] += 7;
    try std.testing.expectEqual(@as(usize, 0), history.redo_len);
    try std.testing.expect(!history.canRedo());
    try std.testing.expect(history.undo(&state, &nodes, &node_len, &connections, &connection_len));
    try std.testing.expectEqual(final_x - 1, nodes[0].pos[0]);
}

test "zui-nodes no-op mutation preserves redo branch" {
    var selected: [4]u32 = .{0} ** 4;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 0, 0 } },
    };
    var node_len: usize = nodes.len;
    var connections: [1]node_editor.Connection = undefined;
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var context = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .connections = &connections, .connection_len = &connection_len, .history = &history };

    _ = state.setSingleSelection(1);
    try std.testing.expect(history.pushBefore(state, &nodes, node_len, &connections, connection_len));
    nodes[0].pos[0] = 20;
    try std.testing.expect(dispatchHistory(&context, .undo));
    try std.testing.expect(history.canRedo());

    _ = state.selectAllNodes(&nodes, node_len);
    try std.testing.expect(canDispatch(&context, .align_left));
    // The nodes are already aligned, so the started transaction is a no-op and
    // must not erase the redo entry captured above.
    try std.testing.expect(!dispatch(&context, .align_left));
    try std.testing.expect(history.canRedo());
    try std.testing.expect(dispatchHistory(&context, .redo));
    try std.testing.expectEqual(@as(f32, 20), nodes[0].pos[0]);
}

test "zui-nodes command capacity includes projected insertion state" {
    var selected: [24]u32 = .{0} ** 24;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [24]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 24;
    for (nodes[0..16], 0..) |*node, index| node.* = .{ .id = @intCast(index + 1), .title = "Node", .pos = .{ @floatFromInt(index), 0 } };
    var node_len: usize = 16;
    var connections: [1]node_editor.Connection = undefined;
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var context = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .connections = &connections, .connection_len = &connection_len, .history = &history };

    try std.testing.expect(canRecordHistory(&context));
    try std.testing.expect(!canRecordNodeEditorCommand(&context, .insert_processing_node));
    try std.testing.expect(!canDispatch(&context, .insert_processing_node));

    var storage = node_editor.StaticHistoryWorkspace(nodes.len, 1, 1, selected.len){};
    try std.testing.expect(history.bindWorkspace(storage.workspace()));
    try std.testing.expect(canRecordNodeEditorCommand(&context, .insert_processing_node));
    try std.testing.expect(dispatch(&context, .insert_processing_node));
    try std.testing.expectEqual(@as(usize, 17), node_len);
    try std.testing.expect(dispatchHistory(&context, .undo));
    try std.testing.expectEqual(@as(usize, 16), node_len);
    try std.testing.expect(dispatchHistory(&context, .redo));
    try std.testing.expectEqual(@as(usize, 17), node_len);
}

test "zui-nodes scalable history rejects undo into undersized target storage" {
    var selected: [24]u32 = .{0} ** 24;
    const state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [24]node_editor.Node = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{ .id = @intCast(index + 1), .title = "Node", .pos = .{ @floatFromInt(index), 0 } };
    const node_len: usize = nodes.len;
    var connections: [1]node_editor.Connection = undefined;
    var connection_len: usize = 0;
    var history = node_editor.History{};
    var storage = node_editor.StaticHistoryWorkspace(nodes.len, 1, 1, selected.len){};
    try std.testing.expect(history.bindWorkspace(storage.workspace()));
    try std.testing.expect(history.pushBefore(state, &nodes, node_len, &connections, connection_len));
    nodes[0].pos[0] = 99;

    var small_nodes: [8]node_editor.Node = undefined;
    var small_node_len: usize = small_nodes.len;
    var small_selected: [8]u32 = .{0} ** 8;
    var small_state = node_editor.State{ .selected_node_ids = &small_selected };
    try std.testing.expect(!history.canUndoFor(small_nodes.len, 0, connections.len, small_selected.len));
    try std.testing.expect(!history.undo(&small_state, &small_nodes, &small_node_len, &connections, &connection_len));
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
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

test "zui-nodes command dispatch deletes multi-selected connections as one undo" {
    var selected_nodes: [4]u32 = .{0} ** 4;
    var selected_connections: [4]node_editor.Connection = undefined;
    var state = node_editor.State{ .selected_node_ids = &selected_nodes, .selected_connections = &selected_connections };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 100, 0 } },
        .{ .id = 3, .title = "C", .pos = .{ 200, 0 } },
        .{ .id = 4, .title = "D", .pos = .{ 300, 0 } },
    };
    var node_len: usize = nodes.len;
    var connections = [_]node_editor.Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
        .{ .from_id = 3, .to_id = 4 },
    };
    const before = connections;
    var connection_len: usize = connections.len;
    var history = node_editor.History{};
    var history_storage = node_editor.StaticHistoryWorkspace(nodes.len, 0, connections.len, selected_connections.len){};
    try std.testing.expect(history.bindWorkspace(history_storage.workspace()));
    _ = state.setConnectionSelection(connections[0]);
    try std.testing.expect(state.toggleConnectionSelection(connections[2]));
    var context = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .connections = &connections, .connection_len = &connection_len, .history = &history };

    try std.testing.expect(canDispatchSelection(&context, .delete));
    try std.testing.expect(dispatchSelection(&context, .delete));
    try std.testing.expectEqual(@as(usize, 1), connection_len);
    try std.testing.expectEqual(node_editor.Connection{ .from_id = 2, .to_id = 3 }, connections[0]);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
    try std.testing.expect(dispatchHistory(&context, .undo));
    try std.testing.expectEqual(@as(usize, 3), connection_len);
    try std.testing.expectEqual(before, connections);
    try std.testing.expectEqual(@as(usize, 2), state.boundedConnectionSelectionLen());
    try std.testing.expect(state.isConnectionSelected(before[0]));
    try std.testing.expect(state.isConnectionSelected(before[2]));
    try std.testing.expect(dispatchHistory(&context, .redo));
    try std.testing.expectEqual(@as(usize, 1), connection_len);
    try std.testing.expectEqual(@as(usize, 0), state.boundedConnectionSelectionLen());
}

test "zui-nodes graph mutations invalidate the shared topology index" {
    var selected_nodes: [2]u32 = .{0} ** 2;
    var state = node_editor.State{ .selected_node_ids = &selected_nodes };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 100, 0 } },
    };
    var node_len: usize = nodes.len;
    var connections = [_]node_editor.Connection{.{ .from_id = 1, .to_id = 2 }};
    var connection_len: usize = connections.len;
    var history = node_editor.History{};
    var history_storage = node_editor.StaticHistoryWorkspace(nodes.len, 0, connections.len, selected_nodes.len){};
    try std.testing.expect(history.bindWorkspace(history_storage.workspace()));
    var topology_storage = graph_topology.StaticWorkspace(nodes.len, connections.len){};
    var topology = graph_topology.Index.init(topology_storage.workspace());
    try std.testing.expect(topology.ensureVersioned(&nodes, &connections, 4).complete());
    _ = state.setConnectionSelection(connections[0]);
    var context = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .connections = &connections, .connection_len = &connection_len, .history = &history, .topology_index = &topology };

    try std.testing.expect(dispatch(&context, .disconnect_selected_link));
    try std.testing.expect(!topology.summary().valid);
    try std.testing.expect(topology.ensureVersioned(&nodes, connections[0..connection_len], 4).complete());
    try std.testing.expect(dispatchHistory(&context, .undo));
    try std.testing.expect(!topology.summary().valid);
    try std.testing.expect(topology.ensureVersioned(&nodes, connections[0..connection_len], 4).complete());
    try std.testing.expect(dispatchHistory(&context, .redo));
    try std.testing.expect(!topology.summary().valid);
}

test "zui-nodes command dispatch deletes mixed node and connection selection as one undo" {
    var selected_nodes = [_]u32{ 2, 0, 0, 0 };
    var selected_connections = [_]node_editor.Connection{.{ .from_id = 3, .to_id = 4 }} ** 4;
    var state = node_editor.State{
        .selected_node_ids = &selected_nodes,
        .selected_node_len = 1,
        .selected_node_id = 2,
        .selected_connections = &selected_connections,
        .selected_connection_len = 1,
        .selected_connection = selected_connections[0],
    };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 100, 0 } },
        .{ .id = 3, .title = "C", .pos = .{ 200, 0 } },
        .{ .id = 4, .title = "D", .pos = .{ 300, 0 } },
    };
    const before_nodes = nodes;
    var node_len: usize = nodes.len;
    var connections = [_]node_editor.Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
        .{ .from_id = 3, .to_id = 4 },
    };
    const before_connections = connections;
    var connection_len: usize = connections.len;
    var history = node_editor.History{};
    var history_storage = node_editor.StaticHistoryWorkspace(nodes.len, 0, connections.len, selected_connections.len){};
    try std.testing.expect(history.bindWorkspace(history_storage.workspace()));
    var context = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .connections = &connections, .connection_len = &connection_len, .history = &history };

    try std.testing.expect(dispatchSelection(&context, .delete));
    try std.testing.expectEqual(@as(usize, 3), node_len);
    try std.testing.expectEqual(@as(usize, 0), connection_len);
    try std.testing.expectEqual(@as(usize, 1), history.undo_len);
    try std.testing.expectEqual(@as(usize, 0), state.boundedSelectionLen());
    try std.testing.expectEqual(@as(usize, 0), state.boundedConnectionSelectionLen());

    try std.testing.expect(dispatchHistory(&context, .undo));
    try std.testing.expectEqual(@as(usize, 4), node_len);
    try std.testing.expectEqual(@as(usize, 3), connection_len);
    try std.testing.expectEqual(before_nodes, nodes);
    try std.testing.expectEqual(before_connections, connections);
    try std.testing.expectEqual(@as(usize, 1), state.boundedSelectionLen());
    try std.testing.expect(state.isNodeSelected(2));
    try std.testing.expectEqual(@as(usize, 1), state.boundedConnectionSelectionLen());
    try std.testing.expect(state.isConnectionSelected(before_connections[2]));
}

test "zui-nodes multi-connection delete rejects undersized history atomically" {
    var selected_nodes: [2]u32 = .{0} ** 2;
    var selected_connections: [2]node_editor.Connection = undefined;
    var state = node_editor.State{ .selected_node_ids = &selected_nodes, .selected_connections = &selected_connections };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 100, 0 } },
        .{ .id = 3, .title = "C", .pos = .{ 200, 0 } },
    };
    var node_len: usize = nodes.len;
    var connections = [_]node_editor.Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
    };
    const before = connections;
    var connection_len: usize = connections.len;
    var history = node_editor.History{};
    var history_storage = node_editor.StaticHistoryWorkspace(nodes.len, 0, connections.len, 1){};
    try std.testing.expect(history.bindWorkspace(history_storage.workspace()));
    _ = state.setConnectionSelection(connections[0]);
    try std.testing.expect(state.toggleConnectionSelection(connections[1]));
    var context = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len, .connections = &connections, .connection_len = &connection_len, .history = &history };

    try std.testing.expect(!canRecordHistory(&context));
    try std.testing.expect(!canDispatchSelection(&context, .delete));
    try std.testing.expect(!dispatchSelection(&context, .delete));
    try std.testing.expectEqual(@as(usize, 2), connection_len);
    try std.testing.expectEqual(before, connections);
    try std.testing.expectEqual(@as(usize, 2), state.boundedConnectionSelectionLen());
    try std.testing.expectEqual(@as(usize, 0), history.undo_len);
}

test "zui-nodes reconnect preserves non-primary selected connections" {
    var selected_nodes: [4]u32 = .{0} ** 4;
    var selected_connections: [4]node_editor.Connection = undefined;
    var state = node_editor.State{ .selected_node_ids = &selected_nodes, .selected_connections = &selected_connections };
    var nodes = [_]node_editor.Node{
        .{ .id = 1, .title = "A", .pos = .{ 0, 0 } },
        .{ .id = 2, .title = "B", .pos = .{ 100, 0 } },
        .{ .id = 3, .title = "C", .pos = .{ 200, 0 } },
        .{ .id = 4, .title = "D", .pos = .{ 300, 0 } },
    };
    var connections = [_]node_editor.Connection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
    };
    var connection_len: usize = connections.len;
    _ = state.setConnectionSelection(connections[0]);
    try std.testing.expect(state.toggleConnectionSelection(connections[1]));
    const previous_primary = connections[1];
    try std.testing.expect(state.reconnectConnectionPortWithPolicy(&connections, &connection_len, previous_primary, .to, 4, 0, &nodes, .default));
    try std.testing.expectEqual(@as(usize, 2), state.boundedConnectionSelectionLen());
    try std.testing.expect(state.isConnectionSelected(connections[0]));
    try std.testing.expect(state.isConnectionSelected(connections[1]));
    try std.testing.expectEqual(@as(?node_editor.Connection, connections[1]), state.selected_connection);
}

test "zui-nodes selection dispatch duplicates, deletes, and records history" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var selection_state = commands.SelectionCommandState{};
    var nodes: [40]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 40;
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
