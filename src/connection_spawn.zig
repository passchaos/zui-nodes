//! Type-aware matching for creating a node from a dangling connection.
//!
//! This module is deliberately model-only: hosts decide how to present their
//! template picker while zui-nodes owns deterministic compatibility ranking.

const std = @import("std");

pub fn compatibleTemplatePort(template: anytype, request: anytype) ?u8 {
    const PortType = @TypeOf(request.port_type);
    const port_count: u8 = switch (request.existing_end) {
        .from => @max(@as(u8, 1), template.input_count),
        .to => @max(@as(u8, 1), template.output_count),
    };
    const port_types = switch (request.existing_end) {
        .from => template.input_types,
        .to => template.output_types,
    };
    var best_index: ?u8 = null;
    var best_rank: u8 = std.math.maxInt(u8);
    var port_index: u8 = 0;
    while (port_index < port_count) : (port_index += 1) {
        const candidate_type: PortType = if (port_index < port_types.len) port_types[port_index] else .any;
        const output_type = if (request.existing_end == .from) request.port_type else candidate_type;
        const input_type = if (request.existing_end == .from) candidate_type else request.port_type;
        const rank = compatibilityRank(PortType, output_type, input_type) orelse continue;
        if (rank < best_rank) {
            best_rank = rank;
            best_index = port_index;
        }
    }
    return best_index;
}

fn compatibilityRank(comptime PortType: type, output_type: PortType, input_type: PortType) ?u8 {
    if (!PortType.compatible(output_type, input_type)) return null;
    if (output_type == input_type and output_type != .any) return 0;
    if (output_type != .any and input_type != .any) return 1;
    return 2;
}

test "connection spawn prefers exact ports before generic and converted ports" {
    const End = enum { from, to };
    const PortType = enum {
        any,
        float,
        mask,
        image,
        color,
        geometry,
        pub fn compatible(output: @This(), input: @This()) bool {
            return output == .any or input == .any or output == input or
                (output == .image and input == .color) or (output == .float and input == .mask);
        }
    };
    const Template = struct {
        input_count: u8 = 1,
        output_count: u8 = 1,
        input_types: []const PortType = &.{},
        output_types: []const PortType = &.{},
    };
    const Request = struct { existing_end: End, port_type: PortType };
    const sink = Template{ .input_count = 3, .input_types = &.{ .any, .color, .image } };
    try std.testing.expectEqual(@as(?u8, 2), compatibleTemplatePort(sink, Request{ .existing_end = .from, .port_type = .image }));
    const source = Template{ .output_count = 3, .output_types = &.{ .any, .float, .image } };
    try std.testing.expectEqual(@as(?u8, 1), compatibleTemplatePort(source, Request{ .existing_end = .to, .port_type = .mask }));
    try std.testing.expectEqual(@as(?u8, null), compatibleTemplatePort(Template{ .output_types = &.{.geometry} }, Request{ .existing_end = .to, .port_type = .image }));
}
