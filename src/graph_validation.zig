//! Structural graph validation for zui-nodes.
//!
//! This module intentionally avoids importing `node_editor.zig`: it works on
//! node/connection records with the standard zui-nodes fields and can therefore
//! stay as a small policy layer below the editor state machine.

const std = @import("std");

pub const MaxTraversalNodes: usize = 512;

pub const ConnectionPolicy = struct {
    require_existing_nodes: bool = true,
    allow_self_links: bool = false,
    allow_duplicate_links: bool = false,
    allow_multiple_links_to_input: bool = true,
    enforce_port_ranges: bool = true,
    enforce_port_types: bool = true,
    allow_cycles: bool = true,

    pub const default = ConnectionPolicy{};
    pub const permissive = ConnectionPolicy{
        .require_existing_nodes = false,
        .allow_self_links = true,
        .allow_duplicate_links = true,
        .allow_multiple_links_to_input = true,
        .enforce_port_ranges = false,
        .enforce_port_types = false,
        .allow_cycles = true,
    };
    pub const strict_dataflow = ConnectionPolicy{
        .require_existing_nodes = true,
        .allow_self_links = false,
        .allow_duplicate_links = false,
        .allow_multiple_links_to_input = false,
        .enforce_port_ranges = true,
        .allow_cycles = false,
    };
};

pub const ConnectionKey = struct {
    from_id: u32,
    to_id: u32,
    from_port: u8 = 0,
    to_port: u8 = 0,

    pub fn from(connection: anytype) ConnectionKey {
        return .{
            .from_id = connection.from_id,
            .to_id = connection.to_id,
            .from_port = connection.from_port,
            .to_port = connection.to_port,
        };
    }

    pub fn eql(self: ConnectionKey, other: ConnectionKey) bool {
        return self.from_id == other.from_id and
            self.to_id == other.to_id and
            self.from_port == other.from_port and
            self.to_port == other.to_port;
    }
};

pub const ConnectionValidationOptions = struct {
    ignore_connection: ?ConnectionKey = null,
    nodes_are_authoritative: bool = true,
};

pub const ConnectionValidation = struct {
    from_node_present: bool = true,
    to_node_present: bool = true,
    from_port_present: bool = true,
    to_port_present: bool = true,
    port_types_compatible: bool = true,
    self_link: bool = false,
    duplicate_link: bool = false,
    input_already_linked: bool = false,
    creates_cycle: bool = false,
    cycle_check_truncated: bool = false,

    pub fn validFor(self: ConnectionValidation, policy: ConnectionPolicy) bool {
        if (policy.require_existing_nodes and (!self.from_node_present or !self.to_node_present)) return false;
        if (!policy.allow_self_links and self.self_link) return false;
        if (!policy.allow_duplicate_links and self.duplicate_link) return false;
        if (!policy.allow_multiple_links_to_input and self.input_already_linked) return false;
        if (policy.enforce_port_ranges and (!self.from_port_present or !self.to_port_present)) return false;
        if (policy.enforce_port_types and !self.port_types_compatible) return false;
        if (!policy.allow_cycles and (self.creates_cycle or self.cycle_check_truncated)) return false;
        return true;
    }

    pub fn firstIssue(self: ConnectionValidation, policy: ConnectionPolicy) []const u8 {
        if (policy.require_existing_nodes and !self.from_node_present) return "source node missing";
        if (policy.require_existing_nodes and !self.to_node_present) return "target node missing";
        if (!policy.allow_self_links and self.self_link) return "self link disabled";
        if (!policy.allow_duplicate_links and self.duplicate_link) return "duplicate link";
        if (!policy.allow_multiple_links_to_input and self.input_already_linked) return "input already linked";
        if (policy.enforce_port_ranges and !self.from_port_present) return "source port missing";
        if (policy.enforce_port_ranges and !self.to_port_present) return "target port missing";
        if (policy.enforce_port_types and !self.port_types_compatible) return "port type mismatch";
        if (!policy.allow_cycles and self.creates_cycle) return "cycle";
        if (!policy.allow_cycles and self.cycle_check_truncated) return "cycle check truncated";
        return "ok";
    }
};

pub const GraphValidationReport = struct {
    node_count: usize = 0,
    connection_count: usize = 0,
    duplicate_node_id_count: usize = 0,
    duplicate_connection_count: usize = 0,
    orphan_connection_count: usize = 0,
    self_link_count: usize = 0,
    input_fan_in_count: usize = 0,
    invalid_port_count: usize = 0,
    incompatible_port_type_count: usize = 0,
    cycle_count: usize = 0,
    cycle_check_truncated_count: usize = 0,

    pub fn valid(self: GraphValidationReport) bool {
        return self.validFor(.default);
    }

    pub fn validFor(self: GraphValidationReport, policy: ConnectionPolicy) bool {
        if (self.duplicate_node_id_count != 0) return false;
        if (policy.require_existing_nodes and self.orphan_connection_count != 0) return false;
        if (!policy.allow_self_links and self.self_link_count != 0) return false;
        if (!policy.allow_duplicate_links and self.duplicate_connection_count != 0) return false;
        if (!policy.allow_multiple_links_to_input and self.input_fan_in_count != 0) return false;
        if (policy.enforce_port_ranges and self.invalid_port_count != 0) return false;
        if (policy.enforce_port_types and self.incompatible_port_type_count != 0) return false;
        if (!policy.allow_cycles and (self.cycle_count != 0 or self.cycle_check_truncated_count != 0)) return false;
        return true;
    }

    pub fn issueCountFor(self: GraphValidationReport, policy: ConnectionPolicy) usize {
        var count = self.duplicate_node_id_count;
        if (policy.require_existing_nodes) count += self.orphan_connection_count;
        if (!policy.allow_self_links) count += self.self_link_count;
        if (!policy.allow_duplicate_links) count += self.duplicate_connection_count;
        if (!policy.allow_multiple_links_to_input) count += self.input_fan_in_count;
        if (policy.enforce_port_ranges) count += self.invalid_port_count;
        if (policy.enforce_port_types) count += self.incompatible_port_type_count;
        if (!policy.allow_cycles) count += self.cycle_count + self.cycle_check_truncated_count;
        return count;
    }
};

pub fn validateConnection(
    nodes: anytype,
    connections: anytype,
    candidate: anytype,
    policy: ConnectionPolicy,
    options: ConnectionValidationOptions,
) ConnectionValidation {
    const key = ConnectionKey.from(candidate);
    const from_index = if (options.nodes_are_authoritative) nodeIndexById(nodes, key.from_id) else null;
    const to_index = if (options.nodes_are_authoritative) nodeIndexById(nodes, key.to_id) else null;
    var out = ConnectionValidation{
        .from_node_present = !options.nodes_are_authoritative or from_index != null,
        .to_node_present = !options.nodes_are_authoritative or to_index != null,
        .self_link = key.from_id == key.to_id,
    };

    if (from_index) |index| {
        out.from_port_present = key.from_port < outputPortCount(nodes[index]);
    }
    if (to_index) |index| {
        out.to_port_present = key.to_port < inputPortCount(nodes[index]);
    }
    if (from_index != null and to_index != null and out.from_port_present and out.to_port_present) {
        out.port_types_compatible = portTypesCompatible(nodes[from_index.?], nodes[to_index.?], key);
    }

    for (connections) |connection| {
        const existing = ConnectionKey.from(connection);
        if (options.ignore_connection) |ignore| {
            if (existing.eql(ignore)) continue;
        }
        if (existing.eql(key)) {
            out.duplicate_link = true;
            break;
        }
    }
    if (!policy.allow_multiple_links_to_input) {
        for (connections) |connection| {
            const existing = ConnectionKey.from(connection);
            if (options.ignore_connection) |ignore| {
                if (existing.eql(ignore)) continue;
            }
            if (existing.to_id == key.to_id and existing.to_port == key.to_port) {
                out.input_already_linked = true;
                break;
            }
        }
    }

    if (!policy.allow_cycles and out.from_node_present and out.to_node_present) {
        const path = pathExists(connections, key.to_id, key.from_id, options.ignore_connection);
        out.creates_cycle = path.found;
        out.cycle_check_truncated = path.truncated;
    }
    return out;
}

pub fn connectionAllowed(
    nodes: anytype,
    connections: anytype,
    candidate: anytype,
    policy: ConnectionPolicy,
    options: ConnectionValidationOptions,
) bool {
    return validateConnection(nodes, connections, candidate, policy, options).validFor(policy);
}

pub fn validateGraph(nodes: anytype, connections: anytype, policy: ConnectionPolicy) GraphValidationReport {
    var report = GraphValidationReport{
        .node_count = nodes.len,
        .connection_count = connections.len,
    };

    for (nodes, 0..) |node, index| {
        var later = index + 1;
        while (later < nodes.len) : (later += 1) {
            if (nodes[later].id == node.id) report.duplicate_node_id_count += 1;
        }
    }

    for (connections, 0..) |connection, index| {
        const key = ConnectionKey.from(connection);
        const from_index = nodeIndexById(nodes, key.from_id);
        const to_index = nodeIndexById(nodes, key.to_id);
        if (from_index == null or to_index == null) {
            report.orphan_connection_count += 1;
        } else {
            if (key.from_port >= outputPortCount(nodes[from_index.?]) or key.to_port >= inputPortCount(nodes[to_index.?])) {
                report.invalid_port_count += 1;
            } else if (!portTypesCompatible(nodes[from_index.?], nodes[to_index.?], key)) {
                report.incompatible_port_type_count += 1;
            }
        }
        if (key.from_id == key.to_id) report.self_link_count += 1;
        if (!policy.allow_multiple_links_to_input) {
            var later_input = index + 1;
            while (later_input < connections.len) : (later_input += 1) {
                const other = ConnectionKey.from(connections[later_input]);
                if (other.to_id == key.to_id and other.to_port == key.to_port) report.input_fan_in_count += 1;
            }
        }

        var later = index + 1;
        while (later < connections.len) : (later += 1) {
            if (ConnectionKey.from(connections[later]).eql(key)) report.duplicate_connection_count += 1;
        }

        if (!policy.allow_cycles and from_index != null and to_index != null) {
            const cycle = pathExists(connections, key.to_id, key.from_id, key);
            if (cycle.found) report.cycle_count += 1;
            if (cycle.truncated) report.cycle_check_truncated_count += 1;
        }
    }

    return report;
}

const PathResult = struct {
    found: bool = false,
    truncated: bool = false,
};

fn pathExists(connections: anytype, start_id: u32, target_id: u32, ignore_connection: ?ConnectionKey) PathResult {
    if (start_id == target_id) return .{ .found = true };
    var visited: [MaxTraversalNodes]u32 = undefined;
    var visited_len: usize = 0;
    var stack: [MaxTraversalNodes]u32 = undefined;
    var stack_len: usize = 1;
    stack[0] = start_id;

    while (stack_len > 0) {
        stack_len -= 1;
        const current = stack[stack_len];
        if (current == target_id) return .{ .found = true };
        if (idInList(visited[0..visited_len], current)) continue;
        if (visited_len >= visited.len) return .{ .truncated = true };
        visited[visited_len] = current;
        visited_len += 1;

        for (connections) |connection| {
            const key = ConnectionKey.from(connection);
            if (ignore_connection) |ignore| {
                if (key.eql(ignore)) continue;
            }
            if (key.from_id != current) continue;
            if (key.to_id == target_id) return .{ .found = true };
            if (idInList(visited[0..visited_len], key.to_id)) continue;
            if (stack_len >= stack.len) return .{ .truncated = true };
            stack[stack_len] = key.to_id;
            stack_len += 1;
        }
    }
    return .{};
}

fn nodeIndexById(nodes: anytype, id: u32) ?usize {
    for (nodes, 0..) |node, index| {
        if (node.id == id) return index;
    }
    return null;
}

fn inputPortCount(node: anytype) u16 {
    return @max(@as(u16, 1), @as(u16, node.input_count));
}

fn outputPortCount(node: anytype) u16 {
    return @max(@as(u16, 1), @as(u16, node.output_count));
}

fn portTypesCompatible(from_node: anytype, to_node: anytype, key: ConnectionKey) bool {
    const FromNode = @TypeOf(from_node);
    const ToNode = @TypeOf(to_node);
    if (!@hasField(FromNode, "output_types") or !@hasField(ToNode, "input_types")) return true;
    if (key.from_port >= from_node.output_types.len or key.to_port >= to_node.input_types.len) return true;
    return from_node.output_types[key.from_port].compatible(to_node.input_types[key.to_port]);
}

fn idInList(ids: []const u32, id: u32) bool {
    for (ids) |value| {
        if (value == id) return true;
    }
    return false;
}

const TestNode = struct {
    id: u32,
    input_count: u8 = 1,
    output_count: u8 = 1,
    input_types: []const TestPortType = &.{},
    output_types: []const TestPortType = &.{},
};

const TestConnection = struct {
    from_id: u32,
    to_id: u32,
    from_port: u8 = 0,
    to_port: u8 = 0,
};

const TestPortType = enum {
    any,
    value,
    image,

    fn compatible(output_type: TestPortType, input_type: TestPortType) bool {
        return output_type == .any or input_type == .any or output_type == input_type;
    }
};

test "graph validation reports duplicate orphan invalid port and cycle structure" {
    const nodes = [_]TestNode{
        .{ .id = 1 },
        .{ .id = 2, .input_count = 1, .output_count = 1 },
        .{ .id = 3 },
    };
    const connections = [_]TestConnection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3, .from_port = 3 },
        .{ .from_id = 3, .to_id = 1 },
        .{ .from_id = 4, .to_id = 1 },
    };
    const report = validateGraph(&nodes, &connections, .strict_dataflow);
    try std.testing.expectEqual(@as(usize, 5), report.connection_count);
    try std.testing.expectEqual(@as(usize, 1), report.duplicate_connection_count);
    try std.testing.expectEqual(@as(usize, 2), report.input_fan_in_count);
    try std.testing.expectEqual(@as(usize, 1), report.orphan_connection_count);
    try std.testing.expectEqual(@as(usize, 1), report.invalid_port_count);
    try std.testing.expect(report.cycle_count > 0);
    try std.testing.expect(!report.validFor(.strict_dataflow));
}

test "graph validation can reject a candidate that would create a cycle" {
    const nodes = [_]TestNode{
        .{ .id = 1 },
        .{ .id = 2 },
        .{ .id = 3 },
    };
    const connections = [_]TestConnection{
        .{ .from_id = 1, .to_id = 2 },
        .{ .from_id = 2, .to_id = 3 },
    };
    const candidate = TestConnection{ .from_id = 3, .to_id = 1 };
    const validation = validateConnection(&nodes, &connections, candidate, .strict_dataflow, .{});
    try std.testing.expect(validation.creates_cycle);
    try std.testing.expect(!validation.validFor(.strict_dataflow));
    try std.testing.expect(validation.validFor(.default));
}

test "graph validation reports port type mismatch when node schema exposes types" {
    const nodes = [_]TestNode{
        .{ .id = 1, .output_types = &.{.image} },
        .{ .id = 2, .input_types = &.{.value} },
    };
    const connection = TestConnection{ .from_id = 1, .to_id = 2 };
    const empty_connections: [0]TestConnection = .{};
    const connections = [_]TestConnection{connection};
    const validation = validateConnection(&nodes, &empty_connections, connection, .default, .{});
    try std.testing.expect(!validation.port_types_compatible);
    try std.testing.expectEqualStrings("port type mismatch", validation.firstIssue(.default));
    const report = validateGraph(&nodes, &connections, .default);
    try std.testing.expectEqual(@as(usize, 1), report.incompatible_port_type_count);
    try std.testing.expect(!report.valid());
}

test "strict dataflow validation rejects multiple incoming links to one input port" {
    const nodes = [_]TestNode{
        .{ .id = 1 },
        .{ .id = 2 },
        .{ .id = 3 },
    };
    const connections = [_]TestConnection{
        .{ .from_id = 1, .to_id = 3 },
    };
    const candidate = TestConnection{ .from_id = 2, .to_id = 3 };
    const validation = validateConnection(&nodes, &connections, candidate, .strict_dataflow, .{});
    try std.testing.expect(validation.input_already_linked);
    try std.testing.expectEqualStrings("input already linked", validation.firstIssue(.strict_dataflow));
    try std.testing.expect(!validation.validFor(.strict_dataflow));
    try std.testing.expect(validation.validFor(.default));
}
