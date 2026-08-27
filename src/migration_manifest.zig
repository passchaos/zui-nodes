//! Migration coverage manifest for moving node graph/editor out of Zui core.
//!
//! zui-nodes owns the node editor model, command surface, view adapter and
//! command-target integration.  This manifest makes the split auditable from
//! zui-demos and keeps any remaining bridge/compatibility areas explicit.

const std = @import("std");

pub const MigrationStatus = enum(u8) {
    native,
    bridge,

    pub fn label(self: MigrationStatus) []const u8 {
        return switch (self) {
            .native => "native",
            .bridge => "bridge",
        };
    }
};

pub const MigrationArea = enum(u8) {
    model,
    view,
    commands,
    routing,
    adapters,
    persistence,
    diagnostics,
};

pub const MigrationItem = struct {
    name: []const u8,
    area: MigrationArea,
    status: MigrationStatus,
    note: []const u8 = "",
};

pub const migration_manifest = [_]MigrationItem{
    .{ .name = "node editor model", .area = .model, .status = .native, .note = "nodes, ports, connections, groups, cached topology traversal for large graphs" },
    .{ .name = "node editor history", .area = .model, .status = .native, .note = "capacity-safe undo/redo snapshots with scalable external storage" },
    .{ .name = "node editor view", .area = .view, .status = .native, .note = "ElementNode/view adapter lives in zui-nodes" },
    .{ .name = "node editor command dispatch", .area = .commands, .status = .native, .note = "mutation/selection/history commands" },
    .{ .name = "node editor command surface", .area = .commands, .status = .native, .note = "registries, context menu model" },
    .{ .name = "node editor command targets", .area = .routing, .status = .native, .note = "CommandRouter handlers" },
    .{ .name = "node editor adapters", .area = .adapters, .status = .native, .note = "copy/convert from compatible node payloads" },
    .{ .name = "node graph document persistence", .area = .persistence, .status = .native, .note = "JSON snapshot capture/restore owned by zui-nodes" },
    .{ .name = "zui core compatibility imports", .area = .adapters, .status = .bridge, .note = "temporary compatibility for downstream migration" },
    .{ .name = "node graph devtools", .area = .diagnostics, .status = .native, .note = "extension-owned summary and panel" },
};

pub const MigrationSummary = struct {
    total_count: usize = 0,
    native_count: usize = 0,
    bridge_count: usize = 0,

    pub fn complete(self: MigrationSummary) bool {
        return self.total_count > 0 and self.bridge_count == 0;
    }

    pub fn nativeRatio(self: MigrationSummary) f32 {
        if (self.total_count == 0) return 0;
        return @as(f32, @floatFromInt(self.native_count)) / @as(f32, @floatFromInt(self.total_count));
    }
};

pub fn summarize(items: []const MigrationItem) MigrationSummary {
    var out = MigrationSummary{ .total_count = items.len };
    for (items) |item| {
        switch (item.status) {
            .native => out.native_count += 1,
            .bridge => out.bridge_count += 1,
        }
    }
    return out;
}

pub fn hasItem(items: []const MigrationItem, name: []const u8, status: MigrationStatus) bool {
    for (items) |item| {
        if (item.status == status and std.mem.eql(u8, item.name, name)) return true;
    }
    return false;
}

test "zui-nodes migration manifest tracks native and bridge coverage" {
    const summary = summarize(&migration_manifest);
    try std.testing.expect(summary.native_count > summary.bridge_count);
    try std.testing.expect(!summary.complete());
    try std.testing.expect(summary.nativeRatio() > 0.6);
    try std.testing.expect(hasItem(&migration_manifest, "node editor command dispatch", .native));
    try std.testing.expect(hasItem(&migration_manifest, "node graph document persistence", .native));
    try std.testing.expect(hasItem(&migration_manifest, "node graph devtools", .native));
    try std.testing.expect(hasItem(&migration_manifest, "zui core compatibility imports", .bridge));
}
