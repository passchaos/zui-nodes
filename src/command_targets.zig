//! Zui CommandRouter adapters for the zui-nodes command surface.
//!
//! The generic command router, keymap and menu validation types belong to Zui
//! core.  The node-editor command behavior belongs here.  This module is the
//! boundary glue that lets applications route node commands through Zui's app
//! shell without depending on Zui core's legacy NodeEditor-specific adapters.

const std = @import("std");
const zui = @import("zui");
const commands = @import("commands.zig");
const command_dispatch = @import("command_dispatch.zig");
const command_surface = @import("command_surface.zig");
const node_editor = @import("node_editor.zig");

pub const CommandId = commands.CommandId;
pub const SelectionCommand = commands.SelectionCommand;
pub const NodeEditorCommand = commands.NodeEditorCommand;
pub const HistoryCommand = commands.HistoryCommand;
pub const CommandContext = command_dispatch.CommandContext;
pub const CommandRouteStep = zui.CommandRouteStep;
pub const CommandTargetHandler = zui.CommandTargetHandler;
pub const CommandTargetScope = zui.CommandTargetScope;

pub fn nodeEditorRoutedCommandPredicate(command_id: CommandId, step: CommandRouteStep, user_data: ?*anyopaque) bool {
    _ = step;
    const context = contextFromUserData(user_data) orelse return false;
    return canDispatchRoutedCommand(context, command_id);
}

pub fn nodeEditorRoutedCommandHandler(command_id: CommandId, step: CommandRouteStep, user_data: ?*anyopaque) void {
    _ = step;
    const context = contextFromUserData(user_data) orelse return;
    _ = dispatchRoutedCommand(context, command_id);
}

pub fn nodeEditorRoutedCommandDisabledReason(command_id: CommandId, step: CommandRouteStep, user_data: ?*anyopaque) []const u8 {
    _ = step;
    const context = contextFromUserData(user_data) orelse return "node editor unavailable";
    if (command_dispatch.selectionCommandFromId(command_id)) |command| return selectionDisabledReason(context, command);
    if (command_dispatch.commandFromId(command_id)) |command| return nodeEditorDisabledReason(context, command);
    if (command_dispatch.historyCommandFromId(command_id)) |command| return historyDisabledReason(context, command);
    return "node editor command unavailable";
}

pub fn nodeEditorRoutedCommandTargetHandler(command_id: CommandId, context: *CommandContext, scope: CommandTargetScope) CommandTargetHandler {
    return .{
        .command_id = command_id,
        .scope = scope,
        .predicate = nodeEditorRoutedCommandPredicate,
        .callback = nodeEditorRoutedCommandHandler,
        .disabled_reason = nodeEditorRoutedCommandDisabledReason,
        .user_data = context,
    };
}

pub fn nodeEditorSelectionCommandTargetHandler(command: SelectionCommand, context: *CommandContext, scope: CommandTargetScope) CommandTargetHandler {
    return nodeEditorRoutedCommandTargetHandler(command.commandId(), context, scope);
}

pub fn nodeEditorCommandTargetHandler(command: NodeEditorCommand, context: *CommandContext, scope: CommandTargetScope) CommandTargetHandler {
    return nodeEditorRoutedCommandTargetHandler(command.commandId(), context, scope);
}

pub fn nodeEditorHistoryCommandTargetHandler(command: HistoryCommand, context: *CommandContext, scope: CommandTargetScope) CommandTargetHandler {
    return nodeEditorRoutedCommandTargetHandler(command.commandId(), context, scope);
}

pub fn nodeEditorSelectionCommandTargetHandlers(context: *CommandContext, scope: CommandTargetScope) [command_surface.node_editor_selection_command_count]CommandTargetHandler {
    var handlers: [command_surface.node_editor_selection_command_count]CommandTargetHandler = undefined;
    for (command_surface.node_editor_selection_commands, 0..) |command, index| {
        handlers[index] = nodeEditorRoutedCommandTargetHandler(command.id, context, scope);
    }
    return handlers;
}

pub fn nodeEditorCommandTargetHandlers(context: *CommandContext, scope: CommandTargetScope) [command_surface.node_editor_command_count]CommandTargetHandler {
    var handlers: [command_surface.node_editor_command_count]CommandTargetHandler = undefined;
    for (command_surface.node_editor_commands, 0..) |command, index| {
        handlers[index] = nodeEditorRoutedCommandTargetHandler(command.id, context, scope);
    }
    return handlers;
}

pub fn nodeEditorHistoryCommandTargetHandlers(context: *CommandContext, scope: CommandTargetScope) [command_surface.node_editor_history_command_count]CommandTargetHandler {
    var handlers: [command_surface.node_editor_history_command_count]CommandTargetHandler = undefined;
    for (command_surface.node_editor_history_commands, 0..) |command, index| {
        handlers[index] = nodeEditorRoutedCommandTargetHandler(command.id, context, scope);
    }
    return handlers;
}

pub fn nodeEditorAllCommandTargetHandlers(context: *CommandContext, scope: CommandTargetScope) [command_surface.node_editor_all_command_count]CommandTargetHandler {
    var handlers: [command_surface.node_editor_all_command_count]CommandTargetHandler = undefined;
    for (command_surface.node_editor_all_commands, 0..) |command, index| {
        handlers[index] = nodeEditorRoutedCommandTargetHandler(command.id, context, scope);
    }
    return handlers;
}

pub fn canDispatchRoutedCommand(context: *const CommandContext, command_id: CommandId) bool {
    if (command_dispatch.selectionCommandFromId(command_id)) |command| return command_dispatch.canDispatchSelection(context, command);
    if (command_dispatch.commandFromId(command_id)) |command| return command_dispatch.canDispatch(context, command);
    if (command_dispatch.historyCommandFromId(command_id)) |command| return command_dispatch.canDispatchHistory(context, command);
    return false;
}

pub fn dispatchRoutedCommand(context: *CommandContext, command_id: CommandId) bool {
    if (command_dispatch.selectionCommandFromId(command_id)) |command| return command_dispatch.dispatchSelection(context, command);
    if (command_dispatch.commandFromId(command_id)) |command| return command_dispatch.dispatch(context, command);
    if (command_dispatch.historyCommandFromId(command_id)) |command| return command_dispatch.dispatchHistory(context, command);
    return false;
}

fn contextFromUserData(user_data: ?*anyopaque) ?*CommandContext {
    return if (user_data) |ptr| @ptrCast(@alignCast(ptr)) else null;
}

fn selectionDisabledReason(context: *const CommandContext, command: SelectionCommand) []const u8 {
    if (command_dispatch.canDispatchSelection(context, command)) return "enabled";
    const node_count = @min(context.node_len.*, context.nodes.len);
    const selected_count = context.state.selectedNodeStorageCount(context.nodes, node_count);
    return switch (command) {
        .rename, .focus => if (selected_count == 0) "selection unavailable" else "node unavailable",
        .delete => if (selected_count == 0 and context.state.selected_connection == null) "nothing selected" else "delete unavailable",
        .duplicate => if (selected_count == 0) "selection unavailable" else "node capacity full",
    };
}

fn nodeEditorDisabledReason(context: *const CommandContext, command: NodeEditorCommand) []const u8 {
    if (command_dispatch.canDispatch(context, command)) return "enabled";
    const node_count = @min(context.node_len.*, context.nodes.len);
    return switch (command) {
        .clear_selection => "nothing selected",
        .select_all, .focus_selection, .frame_all => if (node_count == 0) "node graph empty" else "selection unavailable",
        .copy_selection => if (context.clipboard == null) "clipboard unavailable" else "nothing selected",
        .paste_clipboard => if (context.clipboard == null) "clipboard unavailable" else "clipboard empty or node capacity full",
        .insert_image_input, .insert_processing_node, .insert_output_node => "node capacity full",
        .insert_processing_chain => if (context.connection_len == null) "connection storage unavailable" else "chain unavailable",
        .align_left, .align_center_x, .align_right, .align_top, .align_center_y, .align_bottom => "selection unavailable",
        .distribute_horizontal, .distribute_vertical => "needs at least three selected nodes",
        .group_selected_nodes => if (context.group_len == null) "group storage unavailable" else "selection unavailable",
        .ungroup_selected, .select_group_contents, .fit_group_to_selection => "group unavailable",
        .disconnect_selected_link, .disconnect_selected_inputs, .disconnect_selected_outputs, .disconnect_selected_links => "link unavailable",
        .select_upstream_nodes, .select_downstream_nodes => "connected nodes unavailable",
        .open_context_menu => "context menu unavailable",
        .close_context_menu => "context menu closed",
        .disconnect_context_port_links, .select_context_port_peers => "context port unavailable",
        .reconnect_to_previous, .reconnect_to_next => "reconnect unavailable",
    };
}

fn historyDisabledReason(context: *const CommandContext, command: HistoryCommand) []const u8 {
    if (command_dispatch.canDispatchHistory(context, command)) return "enabled";
    if (context.history == null) return "history unavailable";
    return switch (command) {
        .undo => "undo unavailable",
        .redo => "redo unavailable",
    };
}

test "zui-nodes command target handlers route selection, editor, and history commands" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var selection_state = commands.SelectionCommandState{};
    var nodes: [8]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 8;
    nodes[0] = .{ .id = 1, .title = "A", .pos = .{ 0, 0 } };
    nodes[1] = .{ .id = 2, .title = "B", .pos = .{ 120, 0 } };
    var node_len: usize = 2;
    var connections: [8]node_editor.Connection = .{node_editor.Connection{ .from_id = 0, .to_id = 0 }} ** 8;
    connections[0] = .{ .from_id = 1, .to_id = 2 };
    var connection_len: usize = 1;
    var groups: [2]node_editor.Group = .{node_editor.Group{ .id = 0, .title = "", .rect = .zero }} ** 2;
    var group_len: usize = 0;
    var history = node_editor.History{};
    var context = CommandContext{
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
    var command_storage = command_surface.node_editor_all_commands;
    var registry = command_surface.nodeEditorAllCommandRegistryForContext(&context, &command_storage);
    var handlers = nodeEditorAllCommandTargetHandlers(&context, .app);
    var router = zui.CommandRouter{};
    var validation = zui.CommandValidation{ .router = &router, .handlers = &handlers };

    try std.testing.expect(validation.dispatch(registry, NodeEditorCommand.select_all.commandId()) != null);
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());

    registry = command_surface.nodeEditorAllCommandRegistryForContext(&context, &command_storage);
    try std.testing.expect(validation.dispatch(registry, SelectionCommand.duplicate.commandId()) != null);
    try std.testing.expectEqual(@as(usize, 4), node_len);
    try std.testing.expect(selection_state.last_duplicated_id != null);

    registry = command_surface.nodeEditorAllCommandRegistryForContext(&context, &command_storage);
    try std.testing.expect(validation.dispatch(registry, HistoryCommand.undo.commandId()) != null);
    try std.testing.expectEqual(@as(usize, 2), node_len);

    _ = state.setConnectionSelection(connections[0]);
    registry = command_surface.nodeEditorAllCommandRegistryForContext(&context, &command_storage);
    try std.testing.expect(validation.dispatch(registry, SelectionCommand.delete.commandId()) != null);
    try std.testing.expectEqual(@as(usize, 0), connection_len);
}
