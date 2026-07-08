// feature-zig-frontend "theoretic completion" pass (2026-07-08):
// everything reachable by pure parse-time desugaring onto the existing IR —
// switch (if-chain), defer/errdefer (fn-level replay at exits), optionals
// ?T (tag+payload UClass: null / assign / if-capture / orelse / .?),
// error unions !T (errno-style global slot, caller-clears: return error.X /
// try / catch / catch |e|), and minimal slices (ptr+len UClass, a[lo..hi],
// s[i] read/write, s.len). Zero shared-internals changes.
const std = @import("std");

const MyErr = error{ Overflow, Underflow };

fn checked_add(a: i64, b: i64) !i64 {
    if (a > 1000) {
        return error.Overflow;
    }
    if (a < -1000) {
        return error.Underflow;
    }
    return a + b;
}

fn twice_checked(a: i64) !i64 {
    var x = try checked_add(a, 1);
    var y = try checked_add(x, 1);
    return y;
}

fn risky(n: i64) !i64 {
    errdefer std.debug.print("cleanup\n", .{});
    defer std.debug.print("always\n", .{});
    if (n > 10) {
        return error.TooBig;
    }
    return n * 2;
}

fn classify(n: i64) i64 {
    switch (n) {
        0 => return 100,
        1, 2 => { return 200; },
        else => return 300,
    }
    return -1;
}

fn sum_slice_demo() i64 {
    var a: [6]i64 = undefined;
    for (0..6) |i| {
        a[i] = i * 10;
    }
    var s = a[1..4];
    var total: i64 = 0;
    for (0..s.len) |j| {
        total += s[j];
    }
    s[0] = 999;
    return total * 1000 + a[1];
}

pub fn main() void {
    std.debug.print("c0 {} c1 {} c2 {} c9 {}\n", .{ classify(0), classify(1), classify(2), classify(9) });

    var ok = checked_add(1, 2) catch -1;
    var bad = checked_add(2000, 2) catch -1;
    std.debug.print("ok {} bad {}\n", .{ ok, bad });

    var t1 = twice_checked(5) catch -2;
    var t2 = twice_checked(1001) catch -2;
    std.debug.print("t1 {} t2 {}\n", .{ t1, t2 });

    checked_add(-5000, 1) catch |e| {
        if (e == error.Underflow) {
            std.debug.print("underflow caught {}\n", .{e});
        }
    };

    var r1 = risky(5) catch -1;
    std.debug.print("r1 {}\n", .{r1});
    var r2 = risky(50) catch -1;
    std.debug.print("r2 {}\n", .{r2});

    var opt: ?i64 = null;
    if (opt) |v| {
        std.debug.print("unexpected {}\n", .{v});
    } else {
        std.debug.print("none\n", .{});
    }
    opt = 42;
    if (opt) |v| {
        std.debug.print("some {}\n", .{v});
    }
    std.debug.print("orelse {} unwrap {}\n", .{ opt orelse 7, opt.? });
    opt = null;
    std.debug.print("orelse2 {}\n", .{opt orelse 7});

    std.debug.print("slices {}\n", .{sum_slice_demo()});

    defer std.debug.print("main done\n", .{});
    std.debug.print("end\n", .{});
}
