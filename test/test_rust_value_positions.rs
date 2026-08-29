// Rust frontend: the two places a value can appear that the skeleton did not
// model -- a whole struct/enum value RETURNED, and an implicit TAIL return.
//
// Both come from the same limitation: no AST node carries a whole aggregate
// through an expression, so an aggregate value is always N stores into a
// named slot. Once a record-returning fn has a Result slot to name (which
// landed with Option<T>), `return Square(i);` is the same lowering `let s =
// Square(i);` already used -- so the two spellings now share ONE
// implementation (RPeekAggregateCi + RParseAggregateInto) instead of the
// three near-copies `let` carried.
//
// The tail return is what real source actually writes: `fn file(self) -> u8
// { self.0 % 8 }`. It applies to a fn BODY and deliberately not to any inner
// block -- an inner block's trailing expression is a block VALUE, and
// treating one as a return would turn `if c { f() }` into an early exit. The
// `pick` case below is the assertion for that: its `if/else` arms each hold a
// call, and the function must run past them to its own tail.

struct Square(u8);
struct Point { x: i64, y: i64 }
enum Shape { Circle(i64), Rect { w: i64, h: i64 }, Nothing }

impl Square {
    fn file(self) -> i64 { self.0 % 8 }
    fn rank(self) -> i64 { self.0 / 8 }
}

// aggregate literals in return position, every shape
fn mksq(i: i64) -> Square { return Square(i); }
fn mkpt(a: i64, b: i64) -> Point { return Point { x: a, y: b }; }
fn mkshape(r: i64) -> Shape {
    if r > 0 { return Circle(r); }
    if r < 0 { return Rect { w: 0 - r, h: 2 }; }
    return Nothing;
}
fn maybe(x: i64) -> Option<i64> {
    if x < 0 { return None; }
    return Some(x * 10);
}

// implicit tail returns
fn double(x: i64) -> i64 { x * 2 }

// the anti-case: the if/else arms are STATEMENTS, and the fn's own tail is
// the expression after them. A tail rule that applied to any block would
// return from inside the if and never reach `c + 1`.
fn pick(c: i64) -> i64 {
    if c > 0 {
        println!("pos");
    } else {
        println!("neg");
    }
    c + 1
}

fn main() {
    let s = mksq(19);
    println!("sq {} file {} rank {}", s.0, s.file(), s.rank());

    let p = mkpt(3, 4);
    println!("pt {} {}", p.x, p.y);

    match mkshape(5) {
        Circle(r) => println!("circle {}", r),
        Rect { w, h } => println!("rect {} {}", w, h),
        Nothing => println!("nothing"),
    }
    match mkshape(-6) {
        Circle(r) => println!("circle {}", r),
        Rect { w, h } => println!("rect {} {}", w, h),
        Nothing => println!("nothing"),
    }
    match mkshape(0) {
        Circle(r) => println!("circle {}", r),
        Rect { w, h } => println!("rect {} {}", w, h),
        Nothing => println!("nothing"),
    }

    // (Option accessors still want a plain variable, not a call result --
    //  `maybe(4).unwrap_or(-1)` is a narrowing recorded in the ticket.)
    let m1 = maybe(4);
    let m2 = maybe(-4);
    println!("opt {} {}", m1.unwrap_or(-1), m2.unwrap_or(-1));
    println!("double {}", double(21));
    // hoisted: println! evaluates each argument as it reaches that segment,
    // so a call with output of its own would interleave with the format text
    // (a deviation from Rust, which evaluates all arguments first). Nothing
    // here is testing that, so keep it out of the expected output.
    let a = pick(3);
    let b = pick(-3);
    println!("pick {} {}", a, b);
}
