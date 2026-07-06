// Zig frontend skeleton test (feature-zig-frontend, esoteric probe):
// fns + params + calls, var/const with and without inference, if/else if/else,
// while with continue-expression, range for (exclusive hi), break/continue,
// compound assignment, and/or, std.debug.print with {} placeholders.
const std = @import("std");

fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn classify(n: i64) i64 {
    if (n < 0) {
        return 1;
    } else if (n == 0) {
        return 2;
    } else if (n < 100) {
        return 3;
    } else {
        return 4;
    }
}

fn fib(n: i64) i64 {
    if (n < 2) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

pub fn main() void {
    // inference: const from expression; explicit annotation; undefined
    const x = add(2, 3);
    var acc: i64 = 0;
    var scratch: i64 = undefined;
    scratch = x * 10;
    std.debug.print("add gives {}\n", .{x});
    std.debug.print("scratch {}\n", .{scratch});

    // range for, exclusive upper bound: 0+1+2+3+4 = 10
    for (0..5) |i| {
        acc += i;
    }
    std.debug.print("for-sum {}\n", .{acc});

    // while with continue-expression
    var j: i64 = 0;
    var evens: i64 = 0;
    while (j < 10) : (j += 2) {
        evens += 1;
    }
    std.debug.print("evens {}\n", .{evens});

    // break/continue in a plain while
    var k: i64 = 0;
    var odd_sum: i64 = 0;
    while (true) {
        k += 1;
        if (k >= 10) {
            break;
        }
        if (k - (k / 2) * 2 == 0) {
            continue;
        }
        odd_sum += k;
    }
    std.debug.print("odd-sum {}\n", .{odd_sum});

    // else-if ladder + and/or in one condition
    const cls = classify(42);
    if (cls == 3 and (x == 5 or false)) {
        std.debug.print("classify ok\n", .{});
    } else {
        std.debug.print("classify BROKEN\n", .{});
    }

    // recursion through the shared call path
    std.debug.print("fib(10) is {}\n", .{fib(10)});

    // two placeholders in one format string
    std.debug.print("pair {} and {}\n", .{ add(1, 1), add(2, 2) });
}
