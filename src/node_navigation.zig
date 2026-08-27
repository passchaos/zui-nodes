//! Deterministic geometry scoring for node-editor spatial navigation.

const std = @import("std");

pub const Direction = enum(u8) {
    left,
    right,
    up,
    down,
};

/// Navigation is opt-in so host applications retain ownership of arrow keys.
/// Indexed editors inspect only visible nodes by default.
pub const Options = struct {
    enabled: bool = false,
    visible_only: bool = true,
    ensure_visible: bool = true,
    viewport_padding: f32 = 16.0,
};

pub const Score = struct {
    overlap_penalty: u1,
    primary: f32,
    cross: f32,
    distance_squared: f32,
    area: f32,
};

pub fn score(current: anytype, candidate: @TypeOf(current), direction: Direction) ?Score {
    if (!rectValid(current) or !rectValid(candidate)) return null;
    const primary = switch (direction) {
        .left => if (candidate.x + candidate.w <= current.x) current.x - (candidate.x + candidate.w) else return null,
        .right => if (candidate.x >= current.x + current.w) candidate.x - (current.x + current.w) else return null,
        .up => if (candidate.y + candidate.h <= current.y) current.y - (candidate.y + candidate.h) else return null,
        .down => if (candidate.y >= current.y + current.h) candidate.y - (current.y + current.h) else return null,
    };
    const horizontal = direction == .left or direction == .right;
    const current_cross_start = if (horizontal) current.y else current.x;
    const current_cross_end = current_cross_start + if (horizontal) current.h else current.w;
    const candidate_cross_start = if (horizontal) candidate.y else candidate.x;
    const candidate_cross_end = candidate_cross_start + if (horizontal) candidate.h else candidate.w;
    const cross = if (candidate_cross_end < current_cross_start)
        current_cross_start - candidate_cross_end
    else if (candidate_cross_start > current_cross_end)
        candidate_cross_start - current_cross_end
    else
        0;
    return .{
        .overlap_penalty = @intFromBool(cross > 0),
        .primary = primary,
        .cross = cross,
        .distance_squared = primary * primary + cross * cross,
        .area = candidate.w * candidate.h,
    };
}

pub fn lessThan(lhs: Score, rhs: Score) bool {
    if (lhs.overlap_penalty != rhs.overlap_penalty) return lhs.overlap_penalty < rhs.overlap_penalty;
    if (lhs.primary != rhs.primary) return lhs.primary < rhs.primary;
    if (lhs.cross != rhs.cross) return lhs.cross < rhs.cross;
    if (lhs.distance_squared != rhs.distance_squared) return lhs.distance_squared < rhs.distance_squared;
    return lhs.area < rhs.area;
}

pub fn rectValid(rect: anytype) bool {
    return rectFinite(rect) and rect.w > 0 and rect.h > 0;
}

fn rectFinite(rect: anytype) bool {
    return std.math.isFinite(rect.x) and std.math.isFinite(rect.y) and std.math.isFinite(rect.w) and std.math.isFinite(rect.h);
}

const TestRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

test "spatial navigation requires a candidate beyond the current edge" {
    const current = TestRect{ .x = 0, .y = 0, .w = 40, .h = 40 };
    try std.testing.expect(score(current, .{ .x = 30, .y = 0, .w = 40, .h = 40 }, .right) == null);
    try std.testing.expect(score(current, .{ .x = 40, .y = 0, .w = 40, .h = 40 }, .right) != null);
    try std.testing.expect(score(current, .{ .x = -40, .y = 0, .w = 40, .h = 40 }, .left) != null);
}

test "spatial navigation prefers axis overlap before diagonal proximity" {
    const current = TestRect{ .x = 0, .y = 0, .w = 40, .h = 40 };
    const aligned = score(current, .{ .x = 120, .y = 10, .w = 40, .h = 20 }, .right).?;
    const diagonal = score(current, .{ .x = 45, .y = 60, .w = 20, .h = 20 }, .right).?;
    try std.testing.expect(lessThan(aligned, diagonal));
}

test "spatial navigation rejects non-finite and empty geometry" {
    const current = TestRect{ .x = 0, .y = 0, .w = 40, .h = 40 };
    try std.testing.expect(score(current, .{ .x = std.math.nan(f32), .y = 0, .w = 20, .h = 20 }, .right) == null);
    try std.testing.expect(score(current, .{ .x = 80, .y = 0, .w = 0, .h = 20 }, .right) == null);
}
