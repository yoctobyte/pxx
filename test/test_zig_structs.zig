// feature-zig-frontend sub-ticket 2 (zig-structs-and-pointers):
// struct decl + field read/write + struct literal, *T pointers (&x, p.*,
// pointer params, annotated + inferred pointer vars), [N]T fixed arrays
// (undefined init, index read/write, .len) — all lowering onto the
// existing shared AST/IR (tyRecord/AN_FIELD, tyPointer/AN_ADDR/AN_DEREF,
// AllocArray/AN_INDEX); zero new compiler internals.
const std = @import("std");

const Point = struct {
    x: i64,
    y: i64,
};

fn dist2(ax: i64, ay: i64, bx: i64, by: i64) i64 {
    var dx: i64 = ax - bx;
    var dy: i64 = ay - by;
    return dx * dx + dy * dy;
}

fn bump(p: *i64, by: i64) void {
    p.* = p.* + by;
}

pub fn main() void {
    // struct: undefined init + field writes + field reads as call args
    var pt: Point = undefined;
    pt.x = 3;
    pt.y = 4;
    std.debug.print("dist2 {}\n", .{dist2(pt.x, pt.y, 0, 0)});

    // struct literal init; field exprs on both sides of an assignment
    var q = Point{ .x = pt.x + 7, .y = 2 };
    q.y = q.y * (q.x - 8);
    std.debug.print("q {} {}\n", .{ q.x, q.y });

    // fixed array: write via loop, read+accumulate, .len (also as a bound)
    var a: [5]i64 = undefined;
    for (0..5) |i| {
        a[i] = i * i;
    }
    var sum: i64 = 0;
    for (0..a.len) |j| {
        sum += a[j];
    }
    std.debug.print("squares sum {} len {}\n", .{ sum, a.len });

    // pointers: annotated var, deref read/write, & as call arg
    var v: i64 = 10;
    var p: *i64 = &v;
    p.* = p.* + 30;
    bump(&v, 2);
    std.debug.print("v {}\n", .{v});

    // pointer type inferred from &x
    const r = &sum;
    r.* = r.* + 1;
    std.debug.print("sum {}\n", .{sum});
}
