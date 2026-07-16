// feature-zig-frontend: 5- and 6-parameter internal calls. The Zig frontend
// spilled the incoming arg registers with the same bespoke `case i of 0..3`
// the Rust frontend had — emitting no modrm byte for param index 4/5, so
// `mov [rbp+off], r8` degenerated into a bad instruction stream and SIGILL'd
// on the 5th param. Both frontends now share REmitParamRegSpill (REX.R for
// r8/r9); the register convention caps at 6 params. Recursion with 5 params
// checks the callee prologue reads r8 correctly across calls too.
const std = @import("std");

fn add5(a: i64, b: i64, c: i64, d: i64, e: i64) i64 {
    return a + b + c + d + e;
}

fn add6(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64) i64 {
    return a + b + c + d + e + f;
}

// 5-param recursion: sums e down to 0 while threading the other four through.
fn rec(a: i64, b: i64, c: i64, d: i64, e: i64) i64 {
    if (e == 0) {
        return a + b + c + d;
    }
    return rec(a, b, c, d, e - 1) + 1;
}

pub fn main() void {
    std.debug.print("a5 {} a6 {}\n", .{ add5(1, 2, 3, 4, 5), add6(1, 2, 3, 4, 5, 6) });
    std.debug.print("rec {}\n", .{rec(10, 20, 30, 40, 3)});
}
