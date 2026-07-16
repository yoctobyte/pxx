// feature-zig-frontend: slice parameters `fn f(s: []T, ...)`. The frontend had
// slices only as locals / initializer-position slicing; passing a slice to a
// function is new. A `[]T` param is the 16-byte __ptr/__len record passed by
// address (IsRef), so `s[i]` read/write and `s.len` work through the pointer —
// mirroring the Rust frontend's `&[T]` params. Also exercises a 5th slice-
// carrying call arg alongside scalars (the r8 spill fixed this session).
const std = @import("std");

fn sum(s: []i64) i64 {
    var total: i64 = 0;
    var i: i64 = 0;
    while (i < s.len) : (i += 1) {
        total += s[i];
    }
    return total;
}

// two slice params + scalars: copy scaled src into dst, return element count.
fn scale_into(dst: []i64, src: []i64, factor: i64, base: i64, count: i64) i64 {
    var i: i64 = 0;
    while (i < count) : (i += 1) {
        dst[i] = src[i] * factor + base;
    }
    return count;
}

pub fn main() void {
    var a: [5]i64 = undefined;
    var i: i64 = 0;
    while (i < 5) : (i += 1) {
        a[i] = i + 1;
    }
    const sa = a[0..5];
    std.debug.print("sum {}\n", .{sum(sa)});

    var b: [5]i64 = undefined;
    const sb = b[0..5];
    const n = scale_into(sb, sa, 10, 3, 5);
    std.debug.print("scaled {} {} n {}\n", .{ sb[0], sb[4], n });
}
