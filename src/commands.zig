pub const CommandId = u32;

pub const SelectionCommand = enum(u8) {
    rename,
    delete,
    duplicate,
    focus,

    pub fn commandId(self: SelectionCommand) CommandId {
        return selectionCommandId(self);
    }
};

pub const selection_command_id_base: CommandId = 0x5345_0000;

pub fn selectionCommandId(command: SelectionCommand) CommandId {
    return selection_command_id_base + @intFromEnum(command);
}

pub const HistoryCommand = enum(u8) {
    undo,
    redo,

    pub fn commandId(self: HistoryCommand) CommandId {
        return historyCommandId(self);
    }
};

pub const history_command_id_base: CommandId = 0x4849_0000;

pub fn historyCommandId(command: HistoryCommand) CommandId {
    return history_command_id_base + @intFromEnum(command);
}

pub const NodeEditorCommand = enum(u8) {
    clear_selection,
    select_all,
    focus_selection,
    frame_all,
    reconnect_to_previous,
    reconnect_to_next,
    align_left,
    align_center_x,
    align_right,
    align_top,
    align_center_y,
    align_bottom,
    distribute_horizontal,
    distribute_vertical,
    group_selected_nodes,
    ungroup_selected,
    select_group_contents,
    fit_group_to_selection,
    disconnect_selected_link,
    disconnect_selected_inputs,
    disconnect_selected_outputs,
    disconnect_selected_links,
    select_upstream_nodes,
    select_downstream_nodes,
    insert_image_input,
    insert_processing_node,
    insert_output_node,
    insert_processing_chain,
    copy_selection,
    paste_clipboard,
    open_context_menu,
    close_context_menu,
    disconnect_context_port_links,
    select_context_port_peers,
    auto_layout_layered,
    toggle_selected_nodes_collapsed,
    collapse_selected_nodes,
    expand_selected_nodes,
    add_connection_waypoint,
    remove_connection_waypoint,
    clear_connection_waypoints,

    pub fn commandId(self: NodeEditorCommand) CommandId {
        return nodeEditorCommandId(self);
    }
};

pub const node_editor_command_id_base: CommandId = 0x4e45_0000;

pub fn nodeEditorCommandId(command: NodeEditorCommand) CommandId {
    return node_editor_command_id_base + @intFromEnum(command);
}

pub const SelectionCommandResult = struct {
    handled: bool = false,
    changed: bool = false,
};

pub const SelectionCommandState = struct {
    selected_id: ?u32 = null,
    last_renamed_id: ?u32 = null,
    last_deleted_id: ?u32 = null,
    last_duplicated_id: ?u32 = null,
    last_focused_id: ?u32 = null,
    duplicate_count: u32 = 0,

    pub fn canHandle(self: SelectionCommandState, command: SelectionCommand) bool {
        return switch (command) {
            .rename, .delete, .duplicate, .focus => self.selected_id != null,
        };
    }

    pub fn handle(self: *SelectionCommandState, command: SelectionCommand) SelectionCommandResult {
        const id = self.selected_id orelse return .{};
        switch (command) {
            .rename => self.last_renamed_id = id,
            .delete => {
                self.last_deleted_id = id;
                self.selected_id = null;
            },
            .duplicate => {
                self.last_duplicated_id = id;
                self.duplicate_count +%= 1;
            },
            .focus => self.last_focused_id = id,
        }
        return .{ .handled = true, .changed = command != .focus };
    }
};
