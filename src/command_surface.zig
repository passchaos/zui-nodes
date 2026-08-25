//! Command/menu metadata for the zui-nodes extension.
//!
//! Zui core owns the generic command registry, menu model, keymap, palette and
//! routing primitives.  This package owns node-editor-specific command IDs,
//! enablement, labels and context-menu composition.  Keeping this layer here
//! lets demos and applications bind node-graph actions to Zui app-shell
//! facilities without moving the node graph itself back into the core UI
//! framework.

const std = @import("std");
const zui = @import("zui");
const commands = @import("commands.zig");
const command_dispatch = @import("command_dispatch.zig");
const node_editor = @import("node_editor.zig");

pub const Command = zui.Command;
pub const CommandId = commands.CommandId;
pub const CommandRegistry = zui.CommandRegistry;
pub const MenuItem = zui.MenuItem;
pub const MenuModel = zui.MenuModel;
pub const SelectionCommand = commands.SelectionCommand;
pub const NodeEditorCommand = commands.NodeEditorCommand;
pub const HistoryCommand = commands.HistoryCommand;
pub const CommandContext = command_dispatch.CommandContext;
pub const ContextTarget = node_editor.ContextTarget;

pub const node_editor_command_category = "node editor";
pub const node_editor_selection_category = "node editor selection";
pub const node_editor_history_category = "node editor history";
pub const node_editor_selection_command_count: usize = @intFromEnum(SelectionCommand.focus) + 1;
pub const node_editor_command_count: usize = @intFromEnum(NodeEditorCommand.auto_layout_layered) + 1;
pub const node_editor_history_command_count: usize = @intFromEnum(HistoryCommand.redo) + 1;
pub const node_editor_all_command_count: usize = node_editor_selection_command_count + node_editor_command_count + node_editor_history_command_count;
pub const node_editor_context_menu_capacity: usize = 40;

pub const node_editor_selection_commands = [_]Command{
    .{ .id = SelectionCommand.rename.commandId(), .title = "Rename Selected Node", .description = "Begin renaming the active node selection", .category = node_editor_selection_category, .panel_role = .viewport, .default_shortcut = "Enter" },
    .{ .id = SelectionCommand.delete.commandId(), .title = "Delete Selected Nodes", .description = "Delete selected nodes or the selected node link", .category = node_editor_selection_category, .panel_role = .viewport, .default_shortcut = "Delete", .destructive = true },
    .{ .id = SelectionCommand.duplicate.commandId(), .title = "Duplicate Selected Nodes", .description = "Duplicate selected nodes and their internal links", .category = node_editor_selection_category, .panel_role = .viewport, .default_shortcut = "Ctrl+D", .pinned = true },
    .{ .id = SelectionCommand.focus.commandId(), .title = "Focus Selection", .description = "Focus the active node selection", .category = node_editor_selection_category, .panel_role = .viewport, .default_shortcut = "F" },
};

pub const node_editor_commands = [_]Command{
    .{ .id = NodeEditorCommand.clear_selection.commandId(), .title = "Clear Node Selection", .description = "Clear the current node-editor selection", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Esc" },
    .{ .id = NodeEditorCommand.select_all.commandId(), .title = "Select All Nodes", .description = "Select every node in the active node editor", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Ctrl+A", .pinned = true },
    .{ .id = NodeEditorCommand.focus_selection.commandId(), .title = "Focus Node Selection", .description = "Focus the active node selection", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "F", .pinned = true },
    .{ .id = NodeEditorCommand.frame_all.commandId(), .title = "Frame Node Graph", .description = "Frame the full node graph in the editor viewport", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Home", .pinned = true },
    .{ .id = NodeEditorCommand.reconnect_to_previous.commandId(), .title = "Reconnect Link to Previous Node", .description = "Move the selected link endpoint to the previous compatible node", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.reconnect_to_next.commandId(), .title = "Reconnect Link to Next Node", .description = "Move the selected link endpoint to the next compatible node", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.align_left.commandId(), .title = "Align Nodes Left", .description = "Align selected nodes to the left edge", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.align_center_x.commandId(), .title = "Align Nodes Center X", .description = "Align selected nodes to their horizontal center", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.align_right.commandId(), .title = "Align Nodes Right", .description = "Align selected nodes to the right edge", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.align_top.commandId(), .title = "Align Nodes Top", .description = "Align selected nodes to the top edge", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.align_center_y.commandId(), .title = "Align Nodes Center Y", .description = "Align selected nodes to their vertical center", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.align_bottom.commandId(), .title = "Align Nodes Bottom", .description = "Align selected nodes to the bottom edge", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.distribute_horizontal.commandId(), .title = "Distribute Nodes Horizontally", .description = "Evenly distribute selected nodes along the X axis", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.distribute_vertical.commandId(), .title = "Distribute Nodes Vertically", .description = "Evenly distribute selected nodes along the Y axis", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.group_selected_nodes.commandId(), .title = "Group Selected Nodes", .description = "Create a visual group around the selected nodes", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Ctrl+G", .pinned = true },
    .{ .id = NodeEditorCommand.ungroup_selected.commandId(), .title = "Ungroup Selected Nodes", .description = "Remove the selected visual node group", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Ctrl+Shift+G" },
    .{ .id = NodeEditorCommand.select_group_contents.commandId(), .title = "Select Group Contents", .description = "Select all nodes contained by the active group", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.fit_group_to_selection.commandId(), .title = "Fit Group to Selection", .description = "Resize the selected group to wrap selected nodes", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.disconnect_selected_link.commandId(), .title = "Disconnect Selected Link", .description = "Remove the selected node link", .category = node_editor_command_category, .panel_role = .viewport, .destructive = true },
    .{ .id = NodeEditorCommand.disconnect_selected_inputs.commandId(), .title = "Disconnect Selected Inputs", .description = "Remove incoming links for selected nodes", .category = node_editor_command_category, .panel_role = .viewport, .destructive = true },
    .{ .id = NodeEditorCommand.disconnect_selected_outputs.commandId(), .title = "Disconnect Selected Outputs", .description = "Remove outgoing links for selected nodes", .category = node_editor_command_category, .panel_role = .viewport, .destructive = true },
    .{ .id = NodeEditorCommand.disconnect_selected_links.commandId(), .title = "Disconnect Selected Node Links", .description = "Remove all links attached to selected nodes", .category = node_editor_command_category, .panel_role = .viewport, .destructive = true },
    .{ .id = NodeEditorCommand.select_upstream_nodes.commandId(), .title = "Select Upstream Nodes", .description = "Select nodes feeding the active selection or link", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.select_downstream_nodes.commandId(), .title = "Select Downstream Nodes", .description = "Select nodes receiving data from the active selection or link", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.insert_image_input.commandId(), .title = "Insert Image Input Node", .description = "Insert an image-input node template", .category = node_editor_command_category, .panel_role = .viewport, .pinned = true },
    .{ .id = NodeEditorCommand.insert_processing_node.commandId(), .title = "Insert Processing Node", .description = "Insert a processing node template", .category = node_editor_command_category, .panel_role = .viewport, .pinned = true },
    .{ .id = NodeEditorCommand.insert_output_node.commandId(), .title = "Insert Output Node", .description = "Insert an output node template", .category = node_editor_command_category, .panel_role = .viewport, .pinned = true },
    .{ .id = NodeEditorCommand.insert_processing_chain.commandId(), .title = "Insert Processing Chain", .description = "Insert a caller-provided processing node chain", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.copy_selection.commandId(), .title = "Copy Node Selection", .description = "Copy selected nodes and internal links to the node-editor clipboard", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Ctrl+C", .pinned = true },
    .{ .id = NodeEditorCommand.paste_clipboard.commandId(), .title = "Paste Node Clipboard", .description = "Paste nodes from the node-editor clipboard", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Ctrl+V", .pinned = true },
    .{ .id = NodeEditorCommand.open_context_menu.commandId(), .title = "Open Node Context Menu", .description = "Open the node-editor context menu", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Shift+F10" },
    .{ .id = NodeEditorCommand.close_context_menu.commandId(), .title = "Close Node Context Menu", .description = "Close the node-editor context menu", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.disconnect_context_port_links.commandId(), .title = "Disconnect Context Port Links", .description = "Remove links attached to the port targeted by the context menu", .category = node_editor_command_category, .panel_role = .viewport, .destructive = true },
    .{ .id = NodeEditorCommand.select_context_port_peers.commandId(), .title = "Select Context Port Peers", .description = "Select nodes connected to the port targeted by the context menu", .category = node_editor_command_category, .panel_role = .viewport },
    .{ .id = NodeEditorCommand.auto_layout_layered.commandId(), .title = "Auto Layout Node Graph", .description = "Arrange nodes into deterministic dependency layers", .category = node_editor_command_category, .panel_role = .viewport, .default_shortcut = "Shift+Home", .pinned = true },
};

pub const node_editor_history_commands = [_]Command{
    .{ .id = HistoryCommand.undo.commandId(), .title = "Undo Node Edit", .description = "Undo the last node-editor mutation", .category = node_editor_history_category, .panel_role = .viewport, .default_shortcut = "Ctrl+Z", .pinned = true },
    .{ .id = HistoryCommand.redo.commandId(), .title = "Redo Node Edit", .description = "Redo the last undone node-editor mutation", .category = node_editor_history_category, .panel_role = .viewport, .default_shortcut = "Ctrl+Shift+Z", .pinned = true },
};

pub const node_editor_all_commands = node_editor_selection_commands ++ node_editor_commands ++ node_editor_history_commands;
pub const node_editor_selection_command_registry = CommandRegistry{ .commands = &node_editor_selection_commands };
pub const node_editor_command_registry = CommandRegistry{ .commands = &node_editor_commands };
pub const node_editor_history_command_registry = CommandRegistry{ .commands = &node_editor_history_commands };
pub const node_editor_all_command_registry = CommandRegistry{ .commands = &node_editor_all_commands };

pub const NodeEditorContextMenuOptions = struct {
    target: ?ContextTarget = null,
    include_history: bool = false,
    include_clipboard: bool = true,
    include_selection: bool = true,
    include_insert: bool = true,
    include_arrange: bool = true,
    include_group: bool = true,
    include_connection: bool = true,
    include_port_actions: bool = true,
};

pub const NodeEditorContextMenuSummary = struct {
    item_count: usize = 0,
    command_count: usize = 0,
    separator_count: usize = 0,
    selectable_count: usize = 0,
    disabled_count: usize = 0,

    pub fn empty(self: NodeEditorContextMenuSummary) bool {
        return self.item_count == 0;
    }
};

pub const NodeEditorContextMenuCapabilities = struct {
    target: ContextTarget = .canvas,
    can_copy: bool = false,
    can_paste: bool = false,
    has_nodes: bool = false,
    has_selection: bool = false,
    can_duplicate: bool = false,
    can_delete: bool = false,
    can_frame_all: bool = false,
    can_focus_selection: bool = false,
    can_insert_image_input: bool = false,
    can_insert_processing_node: bool = false,
    can_insert_output_node: bool = false,
    can_insert_processing_chain: bool = false,
    can_align_left: bool = false,
    can_align_center_x: bool = false,
    can_align_right: bool = false,
    can_align_top: bool = false,
    can_align_center_y: bool = false,
    can_align_bottom: bool = false,
    can_distribute_horizontal: bool = false,
    can_distribute_vertical: bool = false,
    can_group_selected_nodes: bool = false,
    can_select_group_contents: bool = false,
    can_fit_group_to_selection: bool = false,
    can_ungroup_selected: bool = false,
    can_disconnect_selected_link: bool = false,
    can_disconnect_selected_inputs: bool = false,
    can_disconnect_selected_outputs: bool = false,
    can_disconnect_selected_links: bool = false,
    can_disconnect_context_port_links: bool = false,
    can_select_context_port_peers: bool = false,
    can_select_upstream_nodes: bool = false,
    can_select_downstream_nodes: bool = false,
    can_reconnect_to_previous: bool = false,
    can_reconnect_to_next: bool = false,
    can_auto_layout_layered: bool = false,
};

pub fn nodeEditorCommandRegistry() CommandRegistry {
    return node_editor_command_registry;
}

pub fn nodeEditorSelectionCommandRegistry() CommandRegistry {
    return node_editor_selection_command_registry;
}

pub fn nodeEditorHistoryCommandRegistry() CommandRegistry {
    return node_editor_history_command_registry;
}

pub fn nodeEditorAllCommandRegistry() CommandRegistry {
    return node_editor_all_command_registry;
}

pub fn nodeEditorCommandRegistryForContext(context: *const CommandContext, out: *[node_editor_command_count]Command) CommandRegistry {
    out.* = node_editor_commands;
    for (out) |*command| {
        const node_command = command_dispatch.commandFromId(command.id) orelse continue;
        command.enabled = command_dispatch.canDispatch(context, node_command);
        command.checked = nodeEditorCommandChecked(context, node_command);
    }
    return .{ .commands = out };
}

pub fn nodeEditorSelectionCommandRegistryForContext(context: *const CommandContext, out: *[node_editor_selection_command_count]Command) CommandRegistry {
    out.* = node_editor_selection_commands;
    for (out) |*command| {
        const selection_command = command_dispatch.selectionCommandFromId(command.id) orelse continue;
        command.enabled = command_dispatch.canDispatchSelection(context, selection_command);
    }
    return .{ .commands = out };
}

pub fn nodeEditorHistoryCommandRegistryForContext(context: *const CommandContext, out: *[node_editor_history_command_count]Command) CommandRegistry {
    out.* = node_editor_history_commands;
    for (out) |*command| {
        const history_command = command_dispatch.historyCommandFromId(command.id) orelse continue;
        command.enabled = command_dispatch.canDispatchHistory(context, history_command);
    }
    return .{ .commands = out };
}

pub fn nodeEditorAllCommandRegistryForContext(context: *const CommandContext, out: *[node_editor_all_command_count]Command) CommandRegistry {
    for (node_editor_selection_commands, 0..) |command, index| {
        out[index] = command;
    }
    for (node_editor_commands, 0..) |command, index| {
        out[node_editor_selection_command_count + index] = command;
    }
    for (node_editor_history_commands, 0..) |command, index| {
        out[node_editor_selection_command_count + node_editor_command_count + index] = command;
    }
    for (out) |*command| {
        if (command_dispatch.selectionCommandFromId(command.id)) |selection_command| {
            command.enabled = command_dispatch.canDispatchSelection(context, selection_command);
        } else if (command_dispatch.commandFromId(command.id)) |node_command| {
            command.enabled = command_dispatch.canDispatch(context, node_command);
            command.checked = nodeEditorCommandChecked(context, node_command);
        } else if (command_dispatch.historyCommandFromId(command.id)) |history_command| {
            command.enabled = command_dispatch.canDispatchHistory(context, history_command);
        }
    }
    return .{ .commands = out };
}

pub fn nodeEditorContextMenuModel(context: *const CommandContext, options: NodeEditorContextMenuOptions, out: []MenuItem) MenuModel {
    var builder = MenuBuilder{ .context = context, .out = out };
    const target = options.target orelse context.state.context_menu.target;

    if (options.include_history) {
        builder.appendHistory(.undo);
        builder.appendHistory(.redo);
        builder.appendSeparator();
    }

    switch (target) {
        .canvas => {
            if (options.include_clipboard) {
                builder.appendCommand(.paste_clipboard);
                builder.appendCommand(.copy_selection);
                builder.appendSeparator();
            }
            if (options.include_selection) {
                builder.appendSelection(.duplicate);
                builder.appendSelection(.delete);
                builder.appendSeparator();
                builder.appendCommand(.select_all);
                builder.appendCommand(.clear_selection);
                builder.appendCommand(.focus_selection);
                builder.appendCommand(.frame_all);
                builder.appendCommand(.auto_layout_layered);
                builder.appendSeparator();
            }
            if (options.include_insert) {
                builder.appendCommand(.insert_image_input);
                builder.appendCommand(.insert_processing_node);
                builder.appendCommand(.insert_output_node);
                builder.appendCommand(.insert_processing_chain);
            }
        },
        .node => {
            if (options.include_clipboard) {
                builder.appendCommand(.copy_selection);
                builder.appendCommand(.paste_clipboard);
                builder.appendSeparator();
            }
            if (options.include_selection) {
                builder.appendSelection(.duplicate);
                builder.appendSelection(.delete);
                builder.appendSelection(.rename);
                builder.appendSeparator();
                builder.appendCommand(.clear_selection);
                builder.appendCommand(.focus_selection);
                builder.appendCommand(.frame_all);
                builder.appendCommand(.auto_layout_layered);
                builder.appendSeparator();
            }
            if (options.include_arrange) {
                builder.appendCommand(.align_left);
                builder.appendCommand(.align_center_x);
                builder.appendCommand(.align_right);
                builder.appendCommand(.align_top);
                builder.appendCommand(.align_center_y);
                builder.appendCommand(.align_bottom);
                builder.appendCommand(.distribute_horizontal);
                builder.appendCommand(.distribute_vertical);
                builder.appendSeparator();
            }
            if (options.include_group) {
                builder.appendCommand(.group_selected_nodes);
                builder.appendCommand(.select_group_contents);
                builder.appendCommand(.fit_group_to_selection);
                builder.appendCommand(.ungroup_selected);
                builder.appendSeparator();
            }
            if (options.include_connection) {
                builder.appendCommand(.disconnect_selected_inputs);
                builder.appendCommand(.disconnect_selected_outputs);
                builder.appendCommand(.disconnect_selected_links);
            }
        },
        .group => {
            if (options.include_group) {
                builder.appendCommand(.select_group_contents);
                builder.appendCommand(.fit_group_to_selection);
                builder.appendCommand(.ungroup_selected);
            }
        },
        .connection => {
            if (options.include_connection) {
                builder.appendSelection(.delete);
                builder.appendCommand(.reconnect_to_previous);
                builder.appendCommand(.reconnect_to_next);
                builder.appendCommand(.disconnect_selected_link);
                builder.appendSeparator();
                builder.appendCommand(.select_upstream_nodes);
                builder.appendCommand(.select_downstream_nodes);
            }
        },
        .input_port => {
            if (options.include_port_actions) {
                builder.appendCommand(.disconnect_context_port_links);
                builder.appendCommand(.select_context_port_peers);
                builder.appendSeparator();
            }
            if (options.include_connection) {
                builder.appendCommand(.disconnect_selected_inputs);
                builder.appendCommand(.select_upstream_nodes);
            }
        },
        .output_port => {
            if (options.include_port_actions) {
                builder.appendCommand(.disconnect_context_port_links);
                builder.appendCommand(.select_context_port_peers);
                builder.appendSeparator();
            }
            if (options.include_connection) {
                builder.appendCommand(.disconnect_selected_outputs);
                builder.appendCommand(.select_downstream_nodes);
            }
        },
    }

    builder.trimTrailingSeparator();
    return .{ .items = out[0..builder.count] };
}

pub fn nodeEditorContextMenuModelForCapabilities(capabilities: NodeEditorContextMenuCapabilities, options: NodeEditorContextMenuOptions, out: []MenuItem) MenuModel {
    var builder = CapabilityMenuBuilder{ .capabilities = capabilities, .out = out };
    const target = options.target orelse capabilities.target;
    if (options.include_history) {
        builder.appendHistory(.undo, false);
        builder.appendHistory(.redo, false);
        builder.appendSeparator();
    }
    switch (target) {
        .canvas => {
            if (options.include_clipboard) {
                builder.appendCommand(.paste_clipboard, capabilities.can_paste);
                builder.appendCommand(.copy_selection, capabilities.can_copy);
                builder.appendSeparator();
            }
            if (options.include_selection) {
                builder.appendSelection(.duplicate, capabilities.can_duplicate);
                builder.appendSelection(.delete, capabilities.can_delete);
                builder.appendSeparator();
                builder.appendCommand(.select_all, capabilities.has_nodes);
                builder.appendCommand(.clear_selection, capabilities.has_selection);
                builder.appendCommand(.focus_selection, capabilities.can_focus_selection);
                builder.appendCommand(.frame_all, capabilities.can_frame_all);
                builder.appendCommand(.auto_layout_layered, capabilities.can_auto_layout_layered);
                builder.appendSeparator();
            }
            if (options.include_insert) {
                builder.appendCommand(.insert_image_input, capabilities.can_insert_image_input);
                builder.appendCommand(.insert_processing_node, capabilities.can_insert_processing_node);
                builder.appendCommand(.insert_output_node, capabilities.can_insert_output_node);
                builder.appendCommand(.insert_processing_chain, capabilities.can_insert_processing_chain);
            }
        },
        .node => {
            if (options.include_clipboard) {
                builder.appendCommand(.copy_selection, capabilities.can_copy);
                builder.appendCommand(.paste_clipboard, capabilities.can_paste);
                builder.appendSeparator();
            }
            if (options.include_selection) {
                builder.appendSelection(.duplicate, capabilities.can_duplicate);
                builder.appendSelection(.delete, capabilities.can_delete);
                builder.appendSelection(.rename, capabilities.has_selection);
                builder.appendSeparator();
                builder.appendCommand(.clear_selection, capabilities.has_selection);
                builder.appendCommand(.focus_selection, capabilities.can_focus_selection);
                builder.appendCommand(.frame_all, capabilities.can_frame_all);
                builder.appendCommand(.auto_layout_layered, capabilities.can_auto_layout_layered);
                builder.appendSeparator();
            }
            if (options.include_arrange) {
                builder.appendCommand(.align_left, capabilities.can_align_left);
                builder.appendCommand(.align_center_x, capabilities.can_align_center_x);
                builder.appendCommand(.align_right, capabilities.can_align_right);
                builder.appendCommand(.align_top, capabilities.can_align_top);
                builder.appendCommand(.align_center_y, capabilities.can_align_center_y);
                builder.appendCommand(.align_bottom, capabilities.can_align_bottom);
                builder.appendCommand(.distribute_horizontal, capabilities.can_distribute_horizontal);
                builder.appendCommand(.distribute_vertical, capabilities.can_distribute_vertical);
                builder.appendSeparator();
            }
            if (options.include_group) {
                builder.appendCommand(.group_selected_nodes, capabilities.can_group_selected_nodes);
                builder.appendCommand(.select_group_contents, capabilities.can_select_group_contents);
                builder.appendCommand(.fit_group_to_selection, capabilities.can_fit_group_to_selection);
                builder.appendCommand(.ungroup_selected, capabilities.can_ungroup_selected);
                builder.appendSeparator();
            }
            if (options.include_connection) {
                builder.appendCommand(.disconnect_selected_inputs, capabilities.can_disconnect_selected_inputs);
                builder.appendCommand(.disconnect_selected_outputs, capabilities.can_disconnect_selected_outputs);
                builder.appendCommand(.disconnect_selected_links, capabilities.can_disconnect_selected_links);
            }
        },
        .group => {
            if (options.include_group) {
                builder.appendCommand(.select_group_contents, capabilities.can_select_group_contents);
                builder.appendCommand(.fit_group_to_selection, capabilities.can_fit_group_to_selection);
                builder.appendCommand(.ungroup_selected, capabilities.can_ungroup_selected);
            }
        },
        .connection => {
            if (options.include_connection) {
                builder.appendSelection(.delete, capabilities.can_delete);
                builder.appendCommand(.reconnect_to_previous, capabilities.can_reconnect_to_previous);
                builder.appendCommand(.reconnect_to_next, capabilities.can_reconnect_to_next);
                builder.appendCommand(.disconnect_selected_link, capabilities.can_disconnect_selected_link);
                builder.appendSeparator();
                builder.appendCommand(.select_upstream_nodes, capabilities.can_select_upstream_nodes);
                builder.appendCommand(.select_downstream_nodes, capabilities.can_select_downstream_nodes);
            }
        },
        .input_port => {
            if (options.include_port_actions) {
                builder.appendCommand(.disconnect_context_port_links, capabilities.can_disconnect_context_port_links);
                builder.appendCommand(.select_context_port_peers, capabilities.can_select_context_port_peers);
                builder.appendSeparator();
            }
            if (options.include_connection) {
                builder.appendCommand(.disconnect_selected_inputs, capabilities.can_disconnect_selected_inputs);
                builder.appendCommand(.select_upstream_nodes, capabilities.can_select_upstream_nodes);
            }
        },
        .output_port => {
            if (options.include_port_actions) {
                builder.appendCommand(.disconnect_context_port_links, capabilities.can_disconnect_context_port_links);
                builder.appendCommand(.select_context_port_peers, capabilities.can_select_context_port_peers);
                builder.appendSeparator();
            }
            if (options.include_connection) {
                builder.appendCommand(.disconnect_selected_outputs, capabilities.can_disconnect_selected_outputs);
                builder.appendCommand(.select_downstream_nodes, capabilities.can_select_downstream_nodes);
            }
        },
    }
    builder.trimTrailingSeparator();
    return .{ .items = out[0..builder.count] };
}

pub fn summarizeNodeEditorContextMenu(model: MenuModel, registry: CommandRegistry) NodeEditorContextMenuSummary {
    var summary = NodeEditorContextMenuSummary{ .item_count = model.items.len };
    for (model.items, 0..) |item, index| {
        if (item.kind == .separator) summary.separator_count += 1;
        if (item.command_id != null) summary.command_count += 1;
        const resolved = model.itemAt(index, registry) orelse continue;
        if (model.isSelectable(index, registry)) {
            summary.selectable_count += 1;
        } else if (resolved.kind != .separator) {
            summary.disabled_count += 1;
        }
    }
    return summary;
}

fn nodeEditorCommandChecked(context: *const CommandContext, command: NodeEditorCommand) bool {
    return switch (command) {
        .open_context_menu, .close_context_menu => context.state.context_menu.open,
        else => false,
    };
}

const MenuBuilder = struct {
    context: *const CommandContext,
    out: []MenuItem,
    count: usize = 0,

    fn appendCommand(self: *MenuBuilder, command: NodeEditorCommand) void {
        self.appendRaw(.{
            .command_id = command.commandId(),
            .enabled = command_dispatch.canDispatch(self.context, command),
        });
    }

    fn appendSelection(self: *MenuBuilder, command: SelectionCommand) void {
        self.appendRaw(.{
            .command_id = command.commandId(),
            .enabled = command_dispatch.canDispatchSelection(self.context, command),
        });
    }

    fn appendHistory(self: *MenuBuilder, command: HistoryCommand) void {
        self.appendRaw(.{
            .command_id = command.commandId(),
            .enabled = command_dispatch.canDispatchHistory(self.context, command),
        });
    }

    fn appendSeparator(self: *MenuBuilder) void {
        if (self.count == 0) return;
        if (self.out[self.count - 1].kind == .separator) return;
        self.appendRaw(MenuItem.separator());
    }

    fn appendRaw(self: *MenuBuilder, item: MenuItem) void {
        if (self.count >= self.out.len) return;
        self.out[self.count] = item;
        self.count += 1;
    }

    fn trimTrailingSeparator(self: *MenuBuilder) void {
        while (self.count > 0 and self.out[self.count - 1].kind == .separator) {
            self.count -= 1;
        }
    }
};

const CapabilityMenuBuilder = struct {
    capabilities: NodeEditorContextMenuCapabilities,
    out: []MenuItem,
    count: usize = 0,

    fn appendCommand(self: *CapabilityMenuBuilder, command: NodeEditorCommand, enabled: bool) void {
        _ = self.capabilities;
        self.appendRaw(.{ .command_id = command.commandId(), .enabled = enabled });
    }

    fn appendSelection(self: *CapabilityMenuBuilder, command: SelectionCommand, enabled: bool) void {
        self.appendRaw(.{ .command_id = command.commandId(), .enabled = enabled });
    }

    fn appendHistory(self: *CapabilityMenuBuilder, command: HistoryCommand, enabled: bool) void {
        self.appendRaw(.{ .command_id = command.commandId(), .enabled = enabled });
    }

    fn appendSeparator(self: *CapabilityMenuBuilder) void {
        if (self.count == 0) return;
        if (self.out[self.count - 1].kind == .separator) return;
        self.appendRaw(MenuItem.separator());
    }

    fn appendRaw(self: *CapabilityMenuBuilder, item: MenuItem) void {
        if (self.count >= self.out.len) return;
        self.out[self.count] = item;
        self.count += 1;
    }

    fn trimTrailingSeparator(self: *CapabilityMenuBuilder) void {
        while (self.count > 0 and self.out[self.count - 1].kind == .separator) {
            self.count -= 1;
        }
    }
};

fn menuContainsCommand(model: MenuModel, command: NodeEditorCommand) bool {
    const id = command.commandId();
    for (model.items) |item| {
        if (item.command_id != null and item.command_id.? == id) return true;
    }
    return false;
}

test "zui-nodes context menu capabilities build legacy-compatible menu without state type coupling" {
    var items: [node_editor_context_menu_capacity]MenuItem = undefined;
    const model = nodeEditorContextMenuModelForCapabilities(.{
        .target = .output_port,
        .can_disconnect_context_port_links = true,
        .can_select_context_port_peers = true,
        .can_disconnect_selected_outputs = true,
        .can_select_downstream_nodes = true,
    }, .{}, &items);
    const registry = nodeEditorAllCommandRegistry();
    const summary = summarizeNodeEditorContextMenu(model, registry);
    try std.testing.expectEqual(@as(usize, 5), summary.item_count);
    try std.testing.expectEqual(@as(usize, 4), summary.command_count);
    try std.testing.expectEqual(@as(usize, 1), summary.separator_count);
    try std.testing.expect(menuContainsCommand(model, .disconnect_context_port_links));
    try std.testing.expect(menuContainsCommand(model, .select_context_port_peers));
    try std.testing.expect(menuContainsCommand(model, .disconnect_selected_outputs));
    try std.testing.expect(menuContainsCommand(model, .select_downstream_nodes));
}

fn menuContainsSelectionCommand(model: MenuModel, command: SelectionCommand) bool {
    const id = command.commandId();
    for (model.items) |item| {
        if (item.command_id != null and item.command_id.? == id) return true;
    }
    return false;
}

test "zui-nodes command surface exposes stable node editor metadata" {
    try std.testing.expectEqual(node_editor_selection_command_count, node_editor_selection_commands.len);
    try std.testing.expectEqual(node_editor_command_count, node_editor_commands.len);
    try std.testing.expectEqual(node_editor_history_command_count, node_editor_history_commands.len);
    try std.testing.expectEqual(node_editor_all_command_count, node_editor_all_commands.len);

    const selection_registry = nodeEditorSelectionCommandRegistry();
    const duplicate = selection_registry.find(SelectionCommand.duplicate.commandId()) orelse return error.MissingDuplicateMetadata;
    try std.testing.expectEqualStrings("Duplicate Selected Nodes", duplicate.title);
    try std.testing.expectEqualStrings(node_editor_selection_category, duplicate.category);

    const registry = nodeEditorCommandRegistry();
    const select_all = registry.find(NodeEditorCommand.select_all.commandId()) orelse return error.MissingSelectAllMetadata;
    try std.testing.expectEqualStrings("Select All Nodes", select_all.title);
    try std.testing.expectEqualStrings(node_editor_command_category, select_all.category);
    try std.testing.expect(select_all.pinned);

    for (node_editor_selection_commands, 0..) |command, index| {
        try std.testing.expectEqual(commands.selection_command_id_base + @as(u32, @intCast(index)), command.id);
        try std.testing.expect(command_dispatch.selectionCommandFromId(command.id) != null);
    }
    for (node_editor_commands, 0..) |command, index| {
        try std.testing.expectEqual(commands.node_editor_command_id_base + @as(u32, @intCast(index)), command.id);
        try std.testing.expect(command_dispatch.commandFromId(command.id) != null);
    }
    for (node_editor_history_commands, 0..) |command, index| {
        try std.testing.expectEqual(commands.history_command_id_base + @as(u32, @intCast(index)), command.id);
        try std.testing.expect(command_dispatch.historyCommandFromId(command.id) != null);
    }
}

test "zui-nodes dynamic command registry mirrors dispatch availability" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [4]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 4;
    nodes[0] = .{ .id = 1, .title = "A", .pos = .{ 0, 0 } };
    nodes[1] = .{ .id = 2, .title = "B", .pos = .{ 100, 0 } };
    var node_len: usize = 2;
    var context = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len };
    var storage: [node_editor_command_count]Command = undefined;
    var selection_storage: [node_editor_selection_command_count]Command = undefined;

    var registry = nodeEditorCommandRegistryForContext(&context, &storage);
    var selection_registry = nodeEditorSelectionCommandRegistryForContext(&context, &selection_storage);
    try std.testing.expect(registry.isEnabled(NodeEditorCommand.select_all.commandId()));
    try std.testing.expect(!registry.isEnabled(NodeEditorCommand.clear_selection.commandId()));
    try std.testing.expect(!selection_registry.isEnabled(SelectionCommand.delete.commandId()));

    try std.testing.expect(command_dispatch.dispatchId(&context, NodeEditorCommand.select_all.commandId()));
    registry = nodeEditorCommandRegistryForContext(&context, &storage);
    selection_registry = nodeEditorSelectionCommandRegistryForContext(&context, &selection_storage);
    try std.testing.expect(registry.isEnabled(NodeEditorCommand.clear_selection.commandId()));
    try std.testing.expect(selection_registry.isEnabled(SelectionCommand.delete.commandId()));
    try std.testing.expect(selection_registry.isEnabled(SelectionCommand.duplicate.commandId()));
    try std.testing.expectEqual(@as(usize, 2), state.boundedSelectionLen());
}

test "zui-nodes context menu model resolves through command registry" {
    var selected: [8]u32 = .{0} ** 8;
    var state = node_editor.State{ .selected_node_ids = &selected };
    var nodes: [4]node_editor.Node = .{node_editor.Node{ .id = 0, .title = "", .pos = .{ 0, 0 } }} ** 4;
    nodes[0] = .{ .id = 1, .title = "A", .pos = .{ 0, 0 } };
    nodes[1] = .{ .id = 2, .title = "B", .pos = .{ 100, 0 } };
    var node_len: usize = 2;
    var context = CommandContext{ .state = &state, .nodes = &nodes, .node_len = &node_len };
    _ = state.openContextMenu(.canvas, .{ 12, 24 });

    var items: [node_editor_context_menu_capacity]MenuItem = undefined;
    const model = nodeEditorContextMenuModel(&context, .{ .include_history = true }, &items);
    var commands_out: [node_editor_all_command_count]Command = undefined;
    const registry = nodeEditorAllCommandRegistryForContext(&context, &commands_out);
    const summary = summarizeNodeEditorContextMenu(model, registry);

    try std.testing.expect(!summary.empty());
    try std.testing.expect(summary.command_count >= 6);
    try std.testing.expect(summary.separator_count >= 2);
    try std.testing.expect(summary.selectable_count >= 4);
    try std.testing.expect(summary.disabled_count >= 1);
    try std.testing.expect(menuContainsSelectionCommand(model, .duplicate));
    try std.testing.expect(menuContainsSelectionCommand(model, .delete));
    try std.testing.expect(menuContainsCommand(model, .select_all));
    try std.testing.expect(menuContainsCommand(model, .insert_processing_node));
    for (model.items, 0..) |item, index| {
        if (item.command_id != null and item.command_id.? == NodeEditorCommand.select_all.commandId()) {
            try std.testing.expectEqualStrings("Select All Nodes", model.itemAt(index, registry).?.title);
            break;
        }
    } else return error.MissingSelectAllMenuItem;
}
