//! zui-nodes: node graph/editor extension package for Zui.
//!
//! Zui core intentionally stays focused on base UI primitives. This package
//! hosts node-graph/editor functionality built on top of those primitives.

const std = @import("std");
const zui = @import("zui");

pub const extension_id = "zui-nodes";

pub const extension_capabilities = [_]zui.ExtensionCapability{
    .{ .area = .node_graph, .name = "node graph editor" },
    .{ .area = .node_graph, .name = "node graph command surface" },
};

pub const extension_contributions = [_]zui.ExtensionContribution{
    .{ .kind = .widget, .id = extension_id ++ ".node-editor", .title = "Node Editor" },
    .{ .kind = .command, .id = extension_id ++ ".command-surface", .title = "Node Editor Commands" },
    .{ .kind = .panel, .id = extension_id ++ ".context-menu", .title = "Node Editor Context Menu" },
};

pub const extension_descriptor = zui.ExtensionDescriptor{
    .id = extension_id,
    .name = "Zui Nodes",
    .version = "0.0.1",
    .capabilities = &extension_capabilities,
    .contributions = &extension_contributions,
};

pub fn extensionDescriptor() zui.ExtensionDescriptor {
    return extension_descriptor;
}

pub const commands = @import("commands.zig");
pub const node_editor = @import("node_editor.zig");
pub const node_editor_adapters = @import("node_editor_adapters.zig");
pub const view = @import("view.zig");
pub const command_dispatch = @import("command_dispatch.zig");
pub const command_surface = @import("command_surface.zig");
pub const command_targets = @import("command_targets.zig");

pub const CommandId = commands.CommandId;
pub const SelectionCommand = commands.SelectionCommand;
pub const SelectionCommandResult = commands.SelectionCommandResult;
pub const SelectionCommandState = commands.SelectionCommandState;
pub const HistoryCommand = commands.HistoryCommand;
pub const history_command_id_base = commands.history_command_id_base;
pub const historyCommandId = commands.historyCommandId;
pub const NodeEditorCommand = commands.NodeEditorCommand;
pub const node_editor_command_id_base = commands.node_editor_command_id_base;
pub const nodeEditorCommandId = commands.nodeEditorCommandId;
pub const NodeEditorCommandContext = command_dispatch.CommandContext;
pub const nodeEditorCommandFromId = command_dispatch.commandFromId;
pub const nodeEditorCanDispatch = command_dispatch.canDispatch;
pub const dispatchNodeEditorCommand = command_dispatch.dispatch;
pub const dispatchNodeEditorCommandId = command_dispatch.dispatchId;
pub const nodeEditorSelectionCommandFromId = command_dispatch.selectionCommandFromId;
pub const nodeEditorCanDispatchSelection = command_dispatch.canDispatchSelection;
pub const dispatchNodeEditorSelectionCommand = command_dispatch.dispatchSelection;
pub const dispatchNodeEditorSelectionCommandId = command_dispatch.dispatchSelectionId;
pub const nodeEditorHistoryCommandFromId = command_dispatch.historyCommandFromId;
pub const nodeEditorCanDispatchHistory = command_dispatch.canDispatchHistory;
pub const dispatchNodeEditorHistoryCommand = command_dispatch.dispatchHistory;
pub const dispatchNodeEditorHistoryCommandId = command_dispatch.dispatchHistoryId;
pub const node_editor_command_category = command_surface.node_editor_command_category;
pub const node_editor_selection_category = command_surface.node_editor_selection_category;
pub const node_editor_history_category = command_surface.node_editor_history_category;
pub const node_editor_selection_command_count = command_surface.node_editor_selection_command_count;
pub const node_editor_command_count = command_surface.node_editor_command_count;
pub const node_editor_history_command_count = command_surface.node_editor_history_command_count;
pub const node_editor_all_command_count = command_surface.node_editor_all_command_count;
pub const node_editor_context_menu_capacity = command_surface.node_editor_context_menu_capacity;
pub const node_editor_selection_commands = command_surface.node_editor_selection_commands;
pub const node_editor_commands = command_surface.node_editor_commands;
pub const node_editor_history_commands = command_surface.node_editor_history_commands;
pub const node_editor_all_commands = command_surface.node_editor_all_commands;
pub const NodeEditorContextMenuOptions = command_surface.NodeEditorContextMenuOptions;
pub const NodeEditorContextMenuSummary = command_surface.NodeEditorContextMenuSummary;
pub const NodeEditorContextMenuCapabilities = command_surface.NodeEditorContextMenuCapabilities;
pub const nodeEditorSelectionCommandRegistry = command_surface.nodeEditorSelectionCommandRegistry;
pub const nodeEditorCommandRegistry = command_surface.nodeEditorCommandRegistry;
pub const nodeEditorHistoryCommandRegistry = command_surface.nodeEditorHistoryCommandRegistry;
pub const nodeEditorAllCommandRegistry = command_surface.nodeEditorAllCommandRegistry;
pub const nodeEditorSelectionCommandRegistryForContext = command_surface.nodeEditorSelectionCommandRegistryForContext;
pub const nodeEditorCommandRegistryForContext = command_surface.nodeEditorCommandRegistryForContext;
pub const nodeEditorHistoryCommandRegistryForContext = command_surface.nodeEditorHistoryCommandRegistryForContext;
pub const nodeEditorAllCommandRegistryForContext = command_surface.nodeEditorAllCommandRegistryForContext;
pub const nodeEditorContextMenuModel = command_surface.nodeEditorContextMenuModel;
pub const nodeEditorContextMenuModelForCapabilities = command_surface.nodeEditorContextMenuModelForCapabilities;
pub const summarizeNodeEditorContextMenu = command_surface.summarizeNodeEditorContextMenu;
pub const nodeEditorRoutedCommandPredicate = command_targets.nodeEditorRoutedCommandPredicate;
pub const nodeEditorRoutedCommandHandler = command_targets.nodeEditorRoutedCommandHandler;
pub const nodeEditorRoutedCommandDisabledReason = command_targets.nodeEditorRoutedCommandDisabledReason;
pub const nodeEditorRoutedCommandTargetHandler = command_targets.nodeEditorRoutedCommandTargetHandler;
pub const nodeEditorSelectionCommandTargetHandler = command_targets.nodeEditorSelectionCommandTargetHandler;
pub const nodeEditorCommandTargetHandler = command_targets.nodeEditorCommandTargetHandler;
pub const nodeEditorHistoryCommandTargetHandler = command_targets.nodeEditorHistoryCommandTargetHandler;
pub const nodeEditorSelectionCommandTargetHandlers = command_targets.nodeEditorSelectionCommandTargetHandlers;
pub const nodeEditorCommandTargetHandlers = command_targets.nodeEditorCommandTargetHandlers;
pub const nodeEditorHistoryCommandTargetHandlers = command_targets.nodeEditorHistoryCommandTargetHandlers;
pub const nodeEditorAllCommandTargetHandlers = command_targets.nodeEditorAllCommandTargetHandlers;
pub const nodeEditorCanDispatchRoutedCommand = command_targets.canDispatchRoutedCommand;
pub const dispatchNodeEditorRoutedCommand = command_targets.dispatchRoutedCommand;

pub const GroupResizeEdges = node_editor.GroupResizeEdges;
pub const ContextTarget = node_editor.ContextTarget;
pub const ContextMenuState = node_editor.ContextMenuState;
pub const Clipboard = node_editor.Clipboard;
pub const InspectorSnapshot = node_editor.InspectorSnapshot;
pub const InspectorDraft = node_editor.InspectorDraft;
pub const MinimapSnapshot = node_editor.MinimapSnapshot;
pub const BoxSelectMode = node_editor.BoxSelectMode;
pub const State = node_editor.State;
pub const Node = node_editor.Node;
pub const NodeTemplate = node_editor.NodeTemplate;
pub const ChainTemplate = node_editor.ChainTemplate;
pub const TemplatePaletteKind = node_editor.TemplatePaletteKind;
pub const TemplatePaletteItem = node_editor.TemplatePaletteItem;
pub const TemplatePaletteState = node_editor.TemplatePaletteState;
pub const Group = node_editor.Group;
pub const Connection = node_editor.Connection;
pub const ConnectionEnd = node_editor.ConnectionEnd;
pub const PortType = node_editor.PortType;
pub const HistorySnapshot = node_editor.HistorySnapshot;
pub const History = node_editor.History;
pub const Options = node_editor.Options;
pub const NodeEditorViewOptions = view.NodeEditorViewOptions;
pub const nodeEditorView = view.nodeEditorView;

pub const nodeFrom = node_editor_adapters.nodeFrom;
pub const connectionFrom = node_editor_adapters.connectionFrom;
pub const groupFrom = node_editor_adapters.groupFrom;
pub const templateFrom = node_editor_adapters.templateFrom;
pub const portTypeFrom = node_editor_adapters.portTypeFrom;
pub const copyNodesFrom = node_editor_adapters.copyNodesFrom;
pub const copyConnectionsFrom = node_editor_adapters.copyConnectionsFrom;
pub const copyGroupsFrom = node_editor_adapters.copyGroupsFrom;

pub const graphToScreen = node_editor.graphToScreen;
pub const screenToGraph = node_editor.screenToGraph;
pub const nodeGraphRect = node_editor.nodeGraphRect;
pub const defaultInsertPosition = node_editor.defaultInsertPosition;
pub const appendNodeEditor = node_editor.appendNodeEditor;
pub const appendNodeEditorConnectionOverlay = node_editor.appendNodeEditorConnectionOverlay;
pub const nodeRectFromState = node_editor.nodeRectFromState;
pub const inputPortPositionAt = node_editor.inputPortPositionAt;
pub const outputPortPositionAt = node_editor.outputPortPositionAt;
pub const minimapSnapshot = node_editor.minimapSnapshot;
pub const handleNodeEditorEvent = node_editor.handleEditorEvent;

pub fn adoptionNote() []const u8 {
    return "Use zui-nodes for node graph/editor functionality; Zui core keeps base UI primitives.";
}

test {
    std.testing.refAllDecls(@This());
}

test "zui-nodes extension descriptor registers node graph capabilities" {
    const descriptor_value = extensionDescriptor();
    try std.testing.expectEqualStrings(extension_id, descriptor_value.id);
    const registry = zui.ExtensionRegistry{ .extensions = &.{descriptor_value} };

    try registry.validate();
    try std.testing.expect(registry.contains(extension_id));
    try std.testing.expectEqual(@as(usize, 1), registry.countByArea(.node_graph));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.command));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.panel));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.widget));
    try std.testing.expect(registry.contributes(extension_id, .widget, extension_id ++ ".node-editor"));
    try std.testing.expect(registry.contributes(extension_id, .command, extension_id ++ ".command-surface"));

    const node_editor_contribution = registry.findContribution(.widget, extension_id ++ ".node-editor") orelse return error.MissingNodeEditorContribution;
    try std.testing.expectEqualStrings("Node Editor", node_editor_contribution.contribution.title);
    try std.testing.expectEqual(zui.ExtensionBoundaryDecision.extension_package, zui.defaultExtensionBoundary(.node_graph));
}
