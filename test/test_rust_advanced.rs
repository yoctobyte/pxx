// feature-rust-frontend "ports-back" pass (2026-07-09, Track R):
// println!/print! (Zig's format splitter ported: #9+#12 subset), [T; N]
// fixed arrays (repeat + list literals, indexing, .len()), borrowed
// slices &a[lo..hi] (#8 minimal: ptr+len UClass, s[i] rw, s.len()), and
// for-in integer ranges (../..=). All parse-time desugar onto existing
// IR; no shared-internals changes.
struct Point { x: i64, y: i64 }

enum Shape {
    Circle(i64),
    Rect { w: i64, h: i64 },
    Dot,
}

fn area(r: i64) -> i64 {
    return 3 * r * r;
}

fn main() -> i32 {
    let mut total = 0;
    for i in 0..5 {
        total = total + i;
    }
    for j in 1..=3 {
        total = total + j * 100;
    }
    println!("total {}", total);

    let mut a: [i64; 4] = [1; 4];
    for k in 0..a.len() {
        a[k] = k * k;
    }
    let s = &a[1..3];
    println!("a3 {} s0 {} s1 {} slen {}", a[3], s[0], s[1], s.len());

    let p = Point { x: 3, y: 4 };
    println!("p {} {}", p.x, p.y);

    let sh = Shape::Circle(5);
    match sh {
        Circle(r) => { println!("circle {}", area(r)); },
        Rect { w, h } => { println!("rect {}", w * h); },
        _ => { println!("dot"); },
    }
    return 0;
}
