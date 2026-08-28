//! Allocation-free freehand stroke storage and geometry for cutting node links.
//!
//! The stroke stays in screen space for the lifetime of one pointer gesture.
//! This matches what the user drew and keeps hit tolerance independent of zoom.

const std = @import("std");

pub const max_points: usize = 64;
const max_cubic_depth: u4 = 10;

pub const Bounds = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const Stroke = struct {
    points: [max_points][2]f32 = .{.{ 0.0, 0.0 }} ** max_points,
    point_count: u8 = 0,
    active: bool = false,

    pub fn begin(self: *Stroke, point: [2]f32) bool {
        if (!pointFinite(point)) return false;
        self.points[0] = point;
        self.point_count = 1;
        self.active = true;
        return true;
    }

    pub fn append(self: *Stroke, point: [2]f32, sample_distance: f32) bool {
        if (!self.active or !pointFinite(point)) return false;
        var count = self.boundedPointCount();
        if (count == 0) return self.begin(point);
        const last = self.points[count - 1];
        if (pointsEqual(last, point)) return false;
        if (count == 1) {
            self.points[1] = point;
            self.point_count = 2;
            return true;
        }
        const spacing = if (std.math.isFinite(sample_distance)) @max(0.0, sample_distance) else 4.0;
        if (distanceSquared(last, point) < spacing * spacing) return false;
        if (count == self.points.len) {
            var read: usize = 2;
            var write: usize = 1;
            while (read < count) : (read += 2) {
                self.points[write] = self.points[read];
                write += 1;
            }
            count = write;
        }
        self.points[count] = point;
        self.point_count = @intCast(count + 1);
        return true;
    }

    pub fn cancel(self: *Stroke) bool {
        const changed = self.active or self.point_count != 0;
        self.active = false;
        self.point_count = 0;
        return changed;
    }

    /// Keep sampled graph locations aligned with content while the viewport
    /// auto-pans during an active screen-space gesture.
    pub fn translate(self: *Stroke, delta: [2]f32) void {
        for (self.points[0..self.boundedPointCount()]) |*point| {
            point[0] += delta[0];
            point[1] += delta[1];
        }
    }

    pub fn boundedPointCount(self: Stroke) usize {
        return @min(@as(usize, self.point_count), self.points.len);
    }

    pub fn slice(self: *const Stroke) []const [2]f32 {
        return self.points[0..self.boundedPointCount()];
    }

    pub fn length(self: Stroke) f32 {
        const count = self.boundedPointCount();
        if (count < 2) return 0.0;
        var total: f32 = 0.0;
        for (self.points[1..count], self.points[0 .. count - 1]) |point, previous| {
            total += @sqrt(distanceSquared(previous, point));
        }
        return total;
    }

    pub fn bounds(self: Stroke, padding_value: f32) ?Bounds {
        const count = self.boundedPointCount();
        if (count == 0) return null;
        var min_x = self.points[0][0];
        var max_x = min_x;
        var min_y = self.points[0][1];
        var max_y = min_y;
        for (self.points[1..count]) |point| {
            min_x = @min(min_x, point[0]);
            max_x = @max(max_x, point[0]);
            min_y = @min(min_y, point[1]);
            max_y = @max(max_y, point[1]);
        }
        const padding = if (std.math.isFinite(padding_value)) @max(0.0, padding_value) else 0.0;
        return .{
            .x = min_x - padding,
            .y = min_y - padding,
            .w = @max(0.001, max_x - min_x + padding * 2.0),
            .h = @max(0.001, max_y - min_y + padding * 2.0),
        };
    }
};

pub const PreparedStroke = struct {
    segments: [max_points - 1]Segment = undefined,
    segment_count: u8 = 0,
    bounds: ?Bounds = null,

    pub fn init(stroke: Stroke, tolerance_value: f32) PreparedStroke {
        const tolerance = if (std.math.isFinite(tolerance_value)) @max(0.0, tolerance_value) else 0.0;
        var prepared = PreparedStroke{ .bounds = stroke.bounds(tolerance) };
        const point_count = stroke.boundedPointCount();
        if (point_count < 2) return prepared;
        for (stroke.points[1..point_count], stroke.points[0 .. point_count - 1], 0..) |end, start, index| {
            prepared.segments[index] = .{
                .start = start,
                .end = end,
                .bounds = segmentBounds(start, end, tolerance),
            };
        }
        prepared.segment_count = @intCast(point_count - 1);
        return prepared;
    }

    pub fn slice(self: *const PreparedStroke) []const Segment {
        return self.segments[0..@min(@as(usize, self.segment_count), self.segments.len)];
    }
};

const Segment = struct {
    start: [2]f32,
    end: [2]f32,
    bounds: Bounds,
};

pub fn cubicIntersectsStroke(path: anytype, stroke: Stroke, tolerance_value: f32) bool {
    const tolerance = if (std.math.isFinite(tolerance_value)) @max(0.0, tolerance_value) else 0.0;
    const prepared = PreparedStroke.init(stroke, tolerance);
    return cubicIntersectsPreparedStroke(path, &prepared, tolerance);
}

pub fn cubicIntersectsPreparedStroke(path: anytype, stroke: *const PreparedStroke, tolerance: f32) bool {
    if (stroke.segment_count == 0) return false;
    const hit_tolerance = if (std.math.isFinite(tolerance)) @max(0.0, tolerance) else 0.0;
    if (stroke.bounds) |bounds| {
        if (!boundsOverlap(curveBounds(path.start, path.c0, path.c1, path.end, hit_tolerance), bounds)) return false;
    }
    for (stroke.slice()) |cut_segment| {
        if (cubicIntersectsSegment(path.start, path.c0, path.c1, path.end, cut_segment, hit_tolerance, 0)) return true;
    }
    return false;
}

fn cubicIntersectsSegment(a: [2]f32, c0: [2]f32, c1: [2]f32, b: [2]f32, cut: Segment, tolerance: f32, depth: u4) bool {
    if (!boundsOverlap(curveBounds(a, c0, c1, b, tolerance), cut.bounds)) return false;
    const baseline_length = @sqrt(distanceSquared(a, b));
    const flatness = @max(@sqrt(pointSegmentDistanceSquared(c0, a, b)), @sqrt(pointSegmentDistanceSquared(c1, a, b)));
    if (depth >= max_cubic_depth or (flatness <= @max(0.25, tolerance * 0.25) and baseline_length <= 24.0)) return segmentsWithinDistance(a, b, cut.start, cut.end, tolerance);

    const p01 = midpoint(a, c0);
    const p12 = midpoint(c0, c1);
    const p23 = midpoint(c1, b);
    const p012 = midpoint(p01, p12);
    const p123 = midpoint(p12, p23);
    const split = midpoint(p012, p123);
    return cubicIntersectsSegment(a, p01, p012, split, cut, tolerance, depth + 1) or
        cubicIntersectsSegment(split, p123, p23, b, cut, tolerance, depth + 1);
}

fn segmentBounds(a: [2]f32, b: [2]f32, padding: f32) Bounds {
    return .{
        .x = @min(a[0], b[0]) - padding,
        .y = @min(a[1], b[1]) - padding,
        .w = @abs(b[0] - a[0]) + padding * 2.0,
        .h = @abs(b[1] - a[1]) + padding * 2.0,
    };
}

fn curveBounds(a: [2]f32, c0: [2]f32, c1: [2]f32, b: [2]f32, padding: f32) Bounds {
    const min_x = @min(@min(a[0], b[0]), @min(c0[0], c1[0]));
    const max_x = @max(@max(a[0], b[0]), @max(c0[0], c1[0]));
    const min_y = @min(@min(a[1], b[1]), @min(c0[1], c1[1]));
    const max_y = @max(@max(a[1], b[1]), @max(c0[1], c1[1]));
    return .{ .x = min_x - padding, .y = min_y - padding, .w = max_x - min_x + padding * 2.0, .h = max_y - min_y + padding * 2.0 };
}

fn boundsOverlap(a: Bounds, b: Bounds) bool {
    return a.x <= b.x + b.w and a.x + a.w >= b.x and a.y <= b.y + b.h and a.y + a.h >= b.y;
}

pub fn segmentsWithinDistance(a: [2]f32, b: [2]f32, c: [2]f32, d: [2]f32, tolerance_value: f32) bool {
    if (!pointFinite(a) or !pointFinite(b) or !pointFinite(c) or !pointFinite(d)) return false;
    if (segmentsIntersect(a, b, c, d)) return true;
    const tolerance = if (std.math.isFinite(tolerance_value)) @max(0.0, tolerance_value) else 0.0;
    const tolerance_squared = tolerance * tolerance;
    return pointSegmentDistanceSquared(a, c, d) <= tolerance_squared or
        pointSegmentDistanceSquared(b, c, d) <= tolerance_squared or
        pointSegmentDistanceSquared(c, a, b) <= tolerance_squared or
        pointSegmentDistanceSquared(d, a, b) <= tolerance_squared;
}

fn segmentsIntersect(a: [2]f32, b: [2]f32, c: [2]f32, d: [2]f32) bool {
    const ab_c = cross(a, b, c);
    const ab_d = cross(a, b, d);
    const cd_a = cross(c, d, a);
    const cd_b = cross(c, d, b);
    return ((ab_c <= 0.0 and ab_d >= 0.0) or (ab_c >= 0.0 and ab_d <= 0.0)) and
        ((cd_a <= 0.0 and cd_b >= 0.0) or (cd_a >= 0.0 and cd_b <= 0.0)) and
        rangesOverlap(a[0], b[0], c[0], d[0]) and rangesOverlap(a[1], b[1], c[1], d[1]);
}

fn rangesOverlap(a: f32, b: f32, c: f32, d: f32) bool {
    return @max(@min(a, b), @min(c, d)) <= @min(@max(a, b), @max(c, d));
}

fn cross(a: [2]f32, b: [2]f32, point: [2]f32) f32 {
    return (b[0] - a[0]) * (point[1] - a[1]) - (b[1] - a[1]) * (point[0] - a[0]);
}

fn pointSegmentDistanceSquared(point: [2]f32, a: [2]f32, b: [2]f32) f32 {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const length_squared = dx * dx + dy * dy;
    const t = if (length_squared <= 0.000001) 0.0 else std.math.clamp(((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / length_squared, 0.0, 1.0);
    const offset_x = point[0] - (a[0] + dx * t);
    const offset_y = point[1] - (a[1] + dy * t);
    return offset_x * offset_x + offset_y * offset_y;
}

fn midpoint(a: [2]f32, b: [2]f32) [2]f32 {
    return .{ (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5 };
}

fn distanceSquared(a: [2]f32, b: [2]f32) f32 {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    return dx * dx + dy * dy;
}

fn pointsEqual(a: [2]f32, b: [2]f32) bool {
    return a[0] == b[0] and a[1] == b[1];
}

fn pointFinite(point: [2]f32) bool {
    return std.math.isFinite(point[0]) and std.math.isFinite(point[1]);
}

test "connection cut stroke samples without allocation and compacts deterministically" {
    var stroke = Stroke{};
    try std.testing.expect(stroke.begin(.{ 0, 0 }));
    for (1..129) |index| try std.testing.expect(stroke.append(.{ @floatFromInt(index), 0 }, 0));
    try std.testing.expect(stroke.boundedPointCount() <= max_points);
    try std.testing.expectEqual([2]f32{ 0, 0 }, stroke.points[0]);
    try std.testing.expectEqual([2]f32{ 128, 0 }, stroke.points[stroke.boundedPointCount() - 1]);
    try std.testing.expectApproxEqAbs(@as(f32, 128), stroke.length(), 0.001);
}

test "connection cut stroke rejects sub-threshold samples" {
    var stroke = Stroke{};
    _ = stroke.begin(.{ 10, 10 });
    try std.testing.expect(stroke.append(.{ 14, 10 }, 4));
    try std.testing.expectEqual(@as(usize, 2), stroke.boundedPointCount());
    try std.testing.expect(!stroke.append(.{ 16, 10 }, 4));
    try std.testing.expectEqual(@as(usize, 2), stroke.boundedPointCount());
    try std.testing.expect(stroke.append(.{ 18, 10 }, 4));
    try std.testing.expectEqual(@as(usize, 3), stroke.boundedPointCount());
}

test "connection cut stroke translates with viewport auto pan" {
    var stroke = Stroke{};
    _ = stroke.begin(.{ 10, 20 });
    _ = stroke.append(.{ 30, 50 }, 0);
    stroke.translate(.{ -4, 7 });
    try std.testing.expectEqual([2]f32{ 6, 27 }, stroke.points[0]);
    try std.testing.expectEqual([2]f32{ 26, 57 }, stroke.points[1]);
}

test "connection cut geometry detects cubic crossings and tolerance" {
    const Path = struct { start: [2]f32, c0: [2]f32, c1: [2]f32, end: [2]f32 };
    const path = Path{ .start = .{ 0, 0 }, .c0 = .{ 40, 0 }, .c1 = .{ 60, 100 }, .end = .{ 100, 100 } };
    var crossing = Stroke{};
    _ = crossing.begin(.{ 50, -20 });
    _ = crossing.append(.{ 50, 120 }, 0);
    try std.testing.expect(cubicIntersectsStroke(path, crossing, 0));
    const flat_path = Path{ .start = .{ 0, 0 }, .c0 = .{ 30, 0 }, .c1 = .{ 70, 0 }, .end = .{ 100, 0 } };
    var nearby = Stroke{};
    _ = nearby.begin(.{ 50, 5 });
    _ = nearby.append(.{ 50, 20 }, 0);
    try std.testing.expect(!cubicIntersectsStroke(flat_path, nearby, 2));
    try std.testing.expect(cubicIntersectsStroke(flat_path, nearby, 6));
}
