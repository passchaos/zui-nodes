//! zui-nodes: node graph/editor extension package for Zui.
//!
//! Zui core intentionally stays focused on base UI primitives. This package
//! hosts node-graph/editor functionality built on top of those primitives.

const std = @import("std");
const zui = @import("zui");

pub const extension_id = "zui-nodes";
pub const extension_command_surface_command_id: zui.CommandId = 0x5A4E_0001;

pub const extension_capabilities = [_]zui.ExtensionCapability{
    .{ .area = .node_graph, .name = "node graph editor" },
    .{ .area = .node_graph, .name = "node graph command surface" },
    .{ .area = .node_graph, .name = "node graph document persistence" },
};

pub const extension_contributions = [_]zui.ExtensionContribution{
    .{ .kind = .widget, .id = extension_id ++ ".node-editor", .title = "Node Editor", .payload = .{ .widget = .{ .widget_id = "node-editor", .view_adapter = "zui-nodes.nodeEditorView" } } },
    .{ .kind = .command, .id = extension_id ++ ".command-surface", .title = "Node Editor Commands", .payload = .{ .command = .{ .command_id = extension_command_surface_command_id, .registry_id = "node-editor", .category = "node graph" } } },
    .{ .kind = .keymap, .id = extension_id ++ ".keymap", .title = "Node Editor Keymap", .payload = .{ .keymap = .{ .binding_count = node_editor_all_command_count, .profile = "node-editor", .bindings = &.{.{ .key = "n", .modifiers = "super", .command_id = extension_command_surface_command_id }} } } },
    .{ .kind = .menu, .id = extension_id ++ ".context-menu", .title = "Node Editor Context Menu", .payload = .{ .menu = .{ .menu_id = "node-editor.context", .location = "canvas" } } },
    .{ .kind = .workspace_panel, .id = extension_id ++ ".workspace-panel", .title = "Node Editor Workspace Panel", .payload = .{ .workspace_panel = .{ .panel_id = "node-editor", .role = "editor", .default_area = "center" } } },
    .{ .kind = .devtools_panel, .id = extension_id ++ ".devtools", .title = "Node Editor Devtools", .payload = .{ .devtools_panel = .{ .panel_id = "node-editor", .scope = "node graph" } } },
    .{ .kind = .demo_scene, .id = extension_id ++ ".demo.basic", .title = "Node Editor Demo", .payload = .{ .demo_scene = .{ .scene_id = "nodes-basic", .headless_scene = "zui-nodes" } } },
    .{ .kind = .asset_loader, .id = extension_id ++ ".document-snapshot", .title = "Node Graph Document Snapshot", .payload = .{ .asset_loader = .{ .loader_id = "node-document", .format = "zui-nodes.snapshot" } } },
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
pub const migration_manifest_mod = @import("migration_manifest.zig");
pub const devtools = @import("devtools.zig");
pub const document_snapshot = @import("document_snapshot.zig");
pub const graph_validation = @import("graph_validation.zig");
pub const graph_layout = @import("graph_layout.zig");
pub const graph_topology = @import("graph_topology.zig");
pub const node_viewport = @import("node_viewport.zig");

pub const MigrationStatus = migration_manifest_mod.MigrationStatus;
pub const MigrationArea = migration_manifest_mod.MigrationArea;
pub const MigrationItem = migration_manifest_mod.MigrationItem;
pub const MigrationSummary = migration_manifest_mod.MigrationSummary;
pub const migration_manifest = migration_manifest_mod.migration_manifest;
pub const summarizeMigration = migration_manifest_mod.summarize;
pub const migrationHasItem = migration_manifest_mod.hasItem;
pub const DevtoolsSummary = devtools.Summary;
pub const DevtoolsSummaryOptions = devtools.SummaryOptions;
pub const DevtoolsPanelOptions = devtools.PanelOptions;
pub const summarizeDevtools = devtools.summarize;
pub const devtoolsPanel = devtools.panel;
pub const DocumentSnapshot = document_snapshot.DocumentSnapshot;
pub const DocumentSnapshotVersion = document_snapshot.DocumentSnapshotVersion;
pub const DocumentSnapshotCaptureOptions = document_snapshot.CaptureOptions;
pub const DocumentSnapshotApplyOptions = document_snapshot.ApplyOptions;
pub const DocumentSnapshotApplyResult = document_snapshot.ApplyResult;
pub const DocumentSnapshotValidationReport = document_snapshot.ValidationReport;
pub const DocumentSnapshotSummary = document_snapshot.Summary;
pub const captureDocumentSnapshot = document_snapshot.captureDocumentSnapshot;
pub const applyDocumentSnapshot = document_snapshot.applyDocumentSnapshot;
pub const summarizeDocumentSnapshot = document_snapshot.summarizeDocumentSnapshot;
pub const summarizeDocumentSnapshotWithPolicy = document_snapshot.summarizeDocumentSnapshotWithPolicy;
pub const validateDocumentSnapshot = document_snapshot.validateDocumentSnapshot;
pub const validateDocumentSnapshotWithPolicy = document_snapshot.validateDocumentSnapshotWithPolicy;
pub const writeDocumentSnapshotJson = document_snapshot.writeDocumentSnapshotJson;
pub const parseDocumentSnapshotJson = document_snapshot.parseDocumentSnapshotJson;

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
pub const nodeEditorCanRecordHistory = command_dispatch.canRecordHistory;
pub const nodeEditorCanRecordSelectionCommand = command_dispatch.canRecordSelectionCommand;
pub const nodeEditorCanRecordCommand = command_dispatch.canRecordNodeEditorCommand;
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
pub const BoxSelectScope = node_editor.BoxSelectScope;
pub const NodeNavigationDirection = node_editor.NodeNavigationDirection;
pub const SpatialNavigationOptions = node_editor.SpatialNavigationOptions;
pub const NodeCollapseOptions = node_editor.NodeCollapseOptions;
pub const NodeResizeOptions = node_editor.NodeResizeOptions;
pub const NodeResizeEdges = node_editor.NodeResizeEdges;
pub const NodeResizeHit = node_editor.NodeResizeHit;
pub const State = node_editor.State;
pub const Node = node_editor.Node;
pub const NodeTemplate = node_editor.NodeTemplate;
pub const ChainTemplate = node_editor.ChainTemplate;
pub const TemplatePaletteKind = node_editor.TemplatePaletteKind;
pub const TemplatePaletteItem = node_editor.TemplatePaletteItem;
pub const TemplatePaletteState = node_editor.TemplatePaletteState;
pub const Group = node_editor.Group;
pub const Connection = node_editor.Connection;
pub const ConnectionWaypointHit = node_editor.ConnectionWaypointHit;
pub const ConnectionRerouteOptions = node_editor.ConnectionRerouteOptions;
pub const ConnectionCutOptions = node_editor.ConnectionCutOptions;
pub const ConnectionCutStroke = node_editor.ConnectionCutStroke;
pub const ConnectionCutBounds = node_editor.ConnectionCutBounds;
pub const ConnectionCutResult = node_editor.ConnectionCutResult;
pub const max_connection_waypoints = node_editor.max_connection_waypoints;
pub const connection_path_command_capacity = node_editor.connection_path_command_capacity;
pub const max_connection_cut_points = node_editor.max_connection_cut_points;
pub const ConnectionPolicy = node_editor.ConnectionPolicy;
pub const ConnectionValidation = node_editor.ConnectionValidation;
pub const ConnectionValidationOptions = node_editor.ConnectionValidationOptions;
pub const GraphValidationReport = node_editor.GraphValidationReport;
pub const ConnectedSelectionResult = node_editor.ConnectedSelectionResult;
pub const DetailLevel = node_editor.DetailLevel;
pub const SemanticZoomMode = node_editor.SemanticZoomMode;
pub const SemanticZoomOptions = node_editor.SemanticZoomOptions;
pub const semanticDetailLevel = node_editor.semanticDetailLevel;
pub const DragAutoPanOptions = node_editor.DragAutoPanOptions;
pub const DragSnapOptions = node_editor.DragSnapOptions;
pub const AlignmentSnapOptions = node_editor.AlignmentSnapOptions;
pub const DistributionSnapOptions = node_editor.DistributionSnapOptions;
pub const SpacingGuide = node_editor.SpacingGuide;
pub const ConnectionEnd = node_editor.ConnectionEnd;
pub const ConnectionPath = node_editor.ConnectionPath;
pub const ConnectionPathCache = node_editor.ConnectionPathCache;
pub const ConnectionPathCacheSummary = node_editor.ConnectionPathCacheSummary;
pub const ConnectionPathCacheCapacity = node_editor.ConnectionPathCacheCapacity;
pub const ConnectionDrawWorkspace = node_editor.ConnectionDrawWorkspace;
pub const ConnectionDrawSummary = node_editor.ConnectionDrawSummary;
pub const ConnectionDrawStorage = node_editor.ConnectionDrawStorage;
pub const StaticConnectionDrawWorkspace = node_editor.StaticConnectionDrawWorkspace;
pub const PortType = node_editor.PortType;
pub const HistorySnapshot = node_editor.HistorySnapshot;
pub const History = node_editor.History;
pub const HistoryWorkspace = node_editor.HistoryWorkspace;
pub const HistoryStorage = node_editor.HistoryStorage;
pub const StaticHistoryWorkspace = node_editor.StaticHistoryWorkspace;
pub const HistorySummary = node_editor.HistorySummary;
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
pub const nodeEffectiveSize = node_editor.nodeEffectiveSize;
pub const inputPortGraphPositionAt = node_editor.inputPortGraphPositionAt;
pub const outputPortGraphPositionAt = node_editor.outputPortGraphPositionAt;
pub const connectionSegmentPath = node_editor.connectionSegmentPath;
pub const connectionSegmentAtPoint = node_editor.connectionSegmentAtPoint;
pub const connectionWaypointPosition = node_editor.connectionWaypointPosition;
pub const connectionWaypointAtPoint = node_editor.connectionWaypointAtPoint;
pub const connectionWaypointAtEditorPoint = node_editor.connectionWaypointAtEditorPoint;
pub const connectionCutStrokeBounds = node_editor.connectionCutStrokeBounds;
pub const connectionIntersectsCutStroke = node_editor.connectionIntersectsCutStroke;
pub const countConnectionsIntersectingCutStroke = node_editor.countConnectionsIntersectingCutStroke;
pub const countConnectionsIntersectingCutStrokeIndexed = node_editor.countConnectionsIntersectingCutStrokeIndexed;
pub const resizeNodeRect = node_editor.resizeNodeRect;
pub const nodeResizeAtPoint = node_editor.nodeResizeAtPoint;
pub const nodeResizeCursor = node_editor.nodeResizeCursor;
pub const graphBounds = node_editor.graphBounds;
pub const graphBoundsWithConnections = node_editor.graphBoundsWithConnections;
pub const connectionGraphBounds = node_editor.connectionGraphBounds;
pub const validateConnection = node_editor.validateConnection;
pub const connectionAllowed = node_editor.connectionAllowed;
pub const validateGraph = node_editor.validateGraph;
pub const GraphTopologyDirection = graph_topology.Direction;
pub const GraphTopologyWorkspace = graph_topology.Workspace;
pub const StaticGraphTopologyWorkspace = graph_topology.StaticWorkspace;
pub const GraphTopologyBuildResult = graph_topology.BuildResult;
pub const GraphTopologyTraversalResult = graph_topology.TraversalResult;
pub const GraphTopologySummary = graph_topology.Summary;
pub const GraphTopologyIndex = graph_topology.Index;
pub const NodeViewportWorkspace = node_editor.ViewportWorkspace;
pub const NodeViewportStorage = node_editor.ViewportStorage;
pub const StaticNodeViewportWorkspace = node_editor.StaticViewportWorkspace;
pub const NodeViewportPrepareResult = node_editor.ViewportPrepareResult;
pub const NodeViewportSummary = node_editor.ViewportSummary;
pub const NodeViewportIndex = node_editor.ViewportIndex;
pub const LayeredLayoutDirection = graph_layout.LayeredLayoutDirection;
pub const LayeredLayoutOptions = graph_layout.LayeredLayoutOptions;
pub const LayeredLayoutResult = graph_layout.LayeredLayoutResult;
pub const LayeredLayoutWorkspace = graph_layout.LayeredLayoutWorkspace;
pub const StaticLayeredLayoutWorkspace = graph_layout.StaticLayeredLayoutWorkspace;
pub const canLayoutLayered = graph_layout.canLayoutLayered;
pub const layoutLayered = graph_layout.layoutLayered;
pub const defaultInsertPosition = node_editor.defaultInsertPosition;
pub const appendNodeEditor = node_editor.appendNodeEditor;
pub const connectionPathForPoints = node_editor.connectionPathForPoints;
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
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.keymap));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.menu));
    try std.testing.expectEqual(@as(usize, 0), registry.countContributions(.panel));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.workspace_panel));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.devtools_panel));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.demo_scene));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.widget));
    try std.testing.expectEqual(@as(usize, 1), registry.countContributions(.asset_loader));
    try std.testing.expect(registry.contributes(extension_id, .widget, extension_id ++ ".node-editor"));
    try std.testing.expect(registry.contributes(extension_id, .command, extension_id ++ ".command-surface"));
    try std.testing.expect(registry.contributes(extension_id, .keymap, extension_id ++ ".keymap"));
    try std.testing.expect(registry.contributes(extension_id, .menu, extension_id ++ ".context-menu"));
    try std.testing.expect(registry.contributes(extension_id, .workspace_panel, extension_id ++ ".workspace-panel"));
    try std.testing.expect(registry.contributes(extension_id, .devtools_panel, extension_id ++ ".devtools"));
    try std.testing.expect(registry.contributes(extension_id, .demo_scene, extension_id ++ ".demo.basic"));
    try std.testing.expect(registry.contributes(extension_id, .asset_loader, extension_id ++ ".document-snapshot"));

    const node_editor_contribution = registry.findContribution(.widget, extension_id ++ ".node-editor") orelse return error.MissingNodeEditorContribution;
    try std.testing.expectEqualStrings("Node Editor", node_editor_contribution.contribution.title);
    try std.testing.expectEqual(zui.ExtensionContributionKind.widget, node_editor_contribution.contribution.payload.contributionKind().?);
    const command_surface_contribution = registry.findContribution(.command, extension_id ++ ".command-surface") orelse return error.MissingNodeCommandSurfaceContribution;
    try std.testing.expectEqual(@as(?zui.CommandId, extension_command_surface_command_id), command_surface_contribution.contribution.payload.command.command_id);
    const workspace_panel = registry.findContribution(.workspace_panel, extension_id ++ ".workspace-panel") orelse return error.MissingNodeWorkspacePanelContribution;
    try std.testing.expectEqualStrings("center", workspace_panel.contribution.payload.workspace_panel.default_area);
    try std.testing.expectEqual(zui.ExtensionBoundaryDecision.extension_package, zui.defaultExtensionBoundary(.node_graph));
}

test "zui-nodes migration manifest documents node editor ownership" {
    const summary = summarizeMigration(&migration_manifest);
    try std.testing.expect(summary.native_count > summary.bridge_count);
    try std.testing.expect(migrationHasItem(&migration_manifest, "node editor model", .native));
    try std.testing.expect(migrationHasItem(&migration_manifest, "node graph devtools", .native));
}
