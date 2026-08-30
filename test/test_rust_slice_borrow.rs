// Rust frontend: borrowing an array as a `&[T]` slice in ARGUMENT position.
//
// `&arr` and `&arr[lo..hi]` used to have a lowering only at `let` level. In an
// argument they fell through to the no-op `&` in RParseUnary, so the ARRAY's
// address was handed to a callee expecting a two-word __ptr/__len header: the
// callee read arr[0] and arr[1] as the pointer and the length and dereferenced
// whatever that was. It compiled clean and segfaulted
// (bug-rust-whole-array-borrow-as-a-slice-argument-segfaults).
//
// Both forms now go through the one RSliceHeaderStores, and the disambiguation
// that argument position needs -- `&arr` is spelled the same for a `&[T]` slice
// and a `&[T; N]` array reference -- is resolved against the callee's own
// parameter, which is the only place that bit exists.

struct Cell {
    id: i64,
    w: i64,
}

fn sum(s: &[i64]) -> i64 {
    let mut t: i64 = 0;
    let mut i: i64 = 0;
    while i < s.len() {
        t += s[i];
        i += 1;
    }
    t
}

fn first(s: &[i64]) -> i64 {
    s[0]
}

fn size(s: &[i64]) -> i64 {
    s.len()
}

// A slice param that is not in slot 0, to pin that the parameter slot is
// counted correctly rather than assumed to be the first argument.
fn at(k: i64, s: &[i64]) -> i64 {
    s[k]
}

// Mutation through the borrowed view must reach the caller's array.
fn bump(s: &mut [i64], k: i64) {
    s[k] = s[k] + 100;
}

// An array REFERENCE, not a slice: `&[T; N]` is a bare address, and `&v` at the
// call site must NOT be turned into a header here.
fn aref(a: &[i64; 4]) -> i64 {
    a[2]
}

fn recsum(s: &[Cell]) -> i64 {
    let mut t: i64 = 0;
    let mut i: i64 = 0;
    while i < s.len() {
        t += s[i].w;
        i += 1;
    }
    t
}

// A slice received as a param and forwarded onward unchanged -- the path that
// already worked, kept here so a regression in it is visible.
fn forward(s: &[i64]) -> i64 {
    sum(s)
}

fn main() {
    let mut v: [i64; 6] = [0; 6];
    v[0] = 1;
    v[1] = 2;
    v[2] = 4;
    v[3] = 8;
    v[4] = 16;
    v[5] = 32;

    // whole-array borrow
    println!("whole {} {} {}", sum(&v), first(&v), size(&v));

    // range borrow, inline at the call
    println!("range {} {} {}", sum(&v[0..3]), sum(&v[3..6]), size(&v[2..5]));

    // the slot is counted, not assumed
    println!("slot {} {}", at(4, &v), at(0, &v));

    // the let-bound form, unchanged
    let s = &v[1..4];
    println!("bound {} {}", sum(s), forward(s));

    // mutation through &mut, whole array and a range
    bump(&mut v, 0);
    bump(&mut v[4..6], 1);
    println!("bump {} {}", v[0], v[5]);

    // `&[T; N]` stays an array reference
    let mut w: [i64; 4] = [0; 4];
    w[2] = 9;
    println!("aref {}", aref(&w));

    // a slice of records
    let mut cs: [Cell; 3] = [Cell { id: 0, w: 0 }; 3];
    cs[0].w = 5;
    cs[1].w = 6;
    cs[2].w = 7;
    println!("rec {} {}", recsum(&cs), recsum(&cs[1..3]));
}
