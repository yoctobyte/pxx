// Rust: `if` as an EXPRESSION -- `let x = if c { a } else { b };` and the tail
// form `fn pick(n) -> i64 { if n > 0 { 1 } else { -1 } }`. Both are how real
// Rust spells a two-way choice; the delta tables in the chess engine's
// attacks.rs are written with them, which is what put this on the ladder.
//
// Lowers to the shared AN_TERNARY -- the same node the C frontend builds for
// `c ? a : b` -- so only the SELECTED arm is evaluated and nothing new reaches
// the IR. `guard` below is the pin for that: the unselected arm divides by
// zero, so if both arms ran the program would fault rather than print.
//
// The tail form is decided by a token scan (RIfIsTailValue) rather than by a
// speculative parse, and `side_effect` is the guard on the other side: an
// if-STATEMENT that merely happens to be last in its body must still be a
// statement. Its blocks end in `;`, which is Rust's own discriminator.

fn pick(n: i64) -> i64 {
    if n > 0 { 1 } else { -1 }
}

fn sign(n: i64) -> i64 {
    return if n > 0 { 1 } else if n < 0 { -1 } else { 0 };
}

// u64 arms must keep their width: RWiden alone would collapse a matching pair
// to i32, which is the integer-literal-suffix bug wearing a different hat
fn mask(hi: bool) -> u64 {
    let m: u64 = if hi { 1u64 << 63 } else { 1u64 };
    return m;
}

fn guard(d: i64) -> i64 {
    let c: i64 = if d == 0 { 7 } else { 100 / d };
    return c;
}

fn twice(n: i64) -> i64 {
    return n * 2;
}

fn side_effect(n: i64) {
    if n > 0 { println!("pos"); } else { println!("neg"); }
}

fn main() {
    println!("pick {} {}", pick(5), pick(-5));
    println!("sign {} {} {}", sign(9), sign(-3), sign(0));
    println!("mask {} {}", mask(true), mask(false));
    println!("guard {} {}", guard(0), guard(4));

    // the knight-delta shape the engine actually uses
    let mut k: i64 = 0;
    let mut acc: i64 = 0;
    while k < 8 {
        let df: i64 = if k < 4 { 1 } else { 2 };
        let dr: i64 = if k % 2 == 0 { 0 - df } else { df };
        acc += dr * (k + 1);
        k += 1;
    }
    println!("acc {}", acc);

    // in an argument position, and nested
    let a: i64 = 5;
    println!("arg {}", twice(if a > 3 { a } else { 0 - a }));
    println!("nest {}", if a > 0 { if a > 4 { 100 } else { 50 } } else { 0 });

    side_effect(1);
    side_effect(-1);
}
