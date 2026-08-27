//! Shared effective geometry for node rendering, indexing, layout, and hit tests.

const std = @import("std");

pub fn effectiveSize(node: anytype) @TypeOf(node.size) {
    var size = node.size;
    size.w = @max(1.0, size.w);
    size.h = @max(1.0, size.h);
    if (comptime @hasField(@TypeOf(node), "collapsed")) {
        if (node.collapsed) {
            const collapsed_height = if (comptime @hasField(@TypeOf(node), "collapsed_height")) node.collapsed_height else 32.0;
            const safe_collapsed_height = if (std.math.isFinite(collapsed_height)) @max(1.0, collapsed_height) else 32.0;
            size.h = @min(size.h, safe_collapsed_height);
        }
    }
    return size;
}

const TestSize = struct { w: f32, h: f32 };
const TestNode = struct { size: TestSize, collapsed: bool = false, collapsed_height: f32 = 32.0 };
const LegacyNode = struct { size: TestSize };

test "effective size preserves expanded and legacy nodes" {
    try std.testing.expectEqual(TestSize{ .w = 120, .h = 80 }, effectiveSize(TestNode{ .size = .{ .w = 120, .h = 80 } }));
    try std.testing.expectEqual(TestSize{ .w = 120, .h = 80 }, effectiveSize(LegacyNode{ .size = .{ .w = 120, .h = 80 } }));
}

test "effective size clamps collapsed height without losing width" {
    try std.testing.expectEqual(TestSize{ .w = 120, .h = 28 }, effectiveSize(TestNode{ .size = .{ .w = 120, .h = 80 }, .collapsed = true, .collapsed_height = 28 }));
    try std.testing.expectEqual(TestSize{ .w = 120, .h = 20 }, effectiveSize(TestNode{ .size = .{ .w = 120, .h = 20 }, .collapsed = true, .collapsed_height = 32 }));
    try std.testing.expectEqual(TestSize{ .w = 120, .h = 32 }, effectiveSize(TestNode{ .size = .{ .w = 120, .h = 80 }, .collapsed = true, .collapsed_height = std.math.nan(f32) }));
}
