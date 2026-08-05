//! zui-nodes: node graph/editor extension package for Zui.
//!
//! Zui core intentionally stays focused on base UI primitives. This package
//! hosts node-graph/editor functionality built on top of those primitives.

pub const commands = @import("commands.zig");
pub const node_editor = @import("node_editor.zig");
pub const node_editor_adapters = @import("node_editor_adapters.zig");
pub const view = @import("view.zig");
pub const command_dispatch = @import("command_dispatch.zig");

pub const CommandId = commands.CommandId;
pub const SelectionCommand = commands.SelectionCommand;
pub const SelectionCommandResult = commands.SelectionCommandResult;
pub const SelectionCommandState = commands.SelectionCommandState;
pub const NodeEditorCommand = commands.NodeEditorCommand;
pub const node_editor_command_id_base = commands.node_editor_command_id_base;
pub const nodeEditorCommandId = commands.nodeEditorCommandId;
pub const NodeEditorCommandContext = command_dispatch.CommandContext;
pub const nodeEditorCommandFromId = command_dispatch.commandFromId;
pub const nodeEditorCanDispatch = command_dispatch.canDispatch;
pub const dispatchNodeEditorCommand = command_dispatch.dispatch;
pub const dispatchNodeEditorCommandId = command_dispatch.dispatchId;

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

pub const graphToScreen = node_editor.graphToScreen;
pub const screenToGraph = node_editor.screenToGraph;
pub const nodeGraphRect = node_editor.nodeGraphRect;
pub const defaultInsertPosition = node_editor.defaultInsertPosition;
pub const appendNodeEditor = node_editor.appendNodeEditor;
pub const appendNodeEditorConnectionOverlay = node_editor.appendNodeEditorConnectionOverlay;

pub fn adoptionNote() []const u8 {
    return "Use zui-nodes for node graph/editor functionality; Zui core keeps base UI primitives.";
}

test {
    @import("std").testing.refAllDecls(@This());
}
