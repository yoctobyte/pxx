// Rust: FIXED-ARRAY return values (`fn f() -> [T; N]`), the attacks.rs rung of
// feature-rust-corpus-chess.
//
// The ABI underneath is Pascal's, unchanged: Procs[].RetType holds the ELEMENT
// kind, ProcRetFixedArrBytes carries the aggregate size the kind cannot show,
// and ABIRetViaHiddenDestProc joins the two so the caller allocates the
// scratch and the callee's epilogue copies into it. So what is pinned here is
// the Rust frontend REACHING for it -- every shape whose failure mode was a
// silent partial copy rather than a diagnostic.
//
// Also pins integer-literal SUFFIXES (`1u64`), which were lexed and discarded:
// `1u64 << 44` evaluated to 0 and `1u64 << 31` to 0xFFFFFFFF80000000, both
// without a word. A bitboard engine is made of that expression, so the knight
// table below is the real oracle for it -- hand-checked, not recorded from a
// run: knight(0) = {10, 17} = 132096, knight(27) = {10,12,17,21,33,37,42,44}
// = 22136263676928.

struct Sq { file: i64, rank: i64 }
struct Tab { seed: i64 }

fn knight(sq: i64) -> u64 {
    let df: [i64; 8] = [1, 1, -1, -1, 2, 2, -2, -2];
    let dr: [i64; 8] = [2, -2, 2, -2, 1, -1, 1, -1];
    let mut m: u64 = 0;
    let f: i64 = sq % 8;
    let r: i64 = sq / 8;
    let mut k: i64 = 0;
    while k < 8 {
        let nf: i64 = f + df[k];
        let nr: i64 = r + dr[k];
        if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            m |= 1u64 << (nr * 8 + nf);
        }
        k += 1;
    }
    return m;
}

// tail-position array return (no `return` keyword) -- the form attacks.rs uses
fn knight_table() -> [u64; 64] {
    let mut t: [u64; 64] = [0; 64];
    let mut i: i64 = 0;
    while i < 64 {
        t[i] = knight(i);
        i += 1;
    }
    t
}

// narrow element type: the copy is sized from the ELEMENT, not from a word
fn narrow() -> [u8; 4] {
    let mut b: [u8; 4] = [0; 4];
    b[0] = 200;
    b[1] = 7;
    b[2] = 255;
    b[3] = 1;
    return b;
}

// RECORD element: byte count comes from RecSize, not TypeSize
fn corners() -> [Sq; 2] {
    let mut c: [Sq; 2];
    c[0].file = 3;
    c[0].rank = 4;
    c[1].file = 7;
    c[1].rank = 7;
    return c;
}

impl Tab {
    // an array-returning METHOD, and an unannotated `let` at the call site
    // resolves it through the receiver's class
    fn rays(&self) -> [i64; 4] {
        let mut r: [i64; 4] = [0; 4];
        let mut i: i64 = 0;
        while i < 4 {
            r[i] = self.seed * (i + 1);
            i += 1;
        }
        r
    }
}

// `&[T; N]` -- a REFERENCE TO AN ARRAY, which Rust distinguishes from the
// `&[T]` slice: a slice is a two-word view, an array reference is the address
fn nonzero(t: &[u64; 64]) -> i64 {
    let mut n: i64 = 0;
    let mut i: i64 = 0;
    while i < 64 {
        if t[i] != 0 { n += 1; }
        i += 1;
    }
    return n;
}

fn main() {
    // unannotated `let` from a plain call: the callee's registered return
    // shape is the only thing that knows the length
    let kt = knight_table();
    println!("kt0 {}", kt[0]);
    println!("kt27 {}", kt[27]);
    println!("nonzero {}", nonzero(&kt));

    let nb: [u8; 4] = narrow();
    println!("nb {} {} {} {}", nb[0], nb[1], nb[2], nb[3]);

    let cs = corners();
    println!("cs {} {} {} {}", cs[0].file, cs[0].rank, cs[1].file, cs[1].rank);

    let tb = Tab { seed: 5 };
    let rs = tb.rays();
    println!("rs {} {} {} {}", rs[0], rs[1], rs[2], rs[3]);

    // whole-array copy from an lvalue reaches the same IR_COPY_REC arm
    let copy: [u8; 4] = nb;
    println!("copy {} {}", copy[0], copy[3]);

    // integer-literal suffixes, and the unsuffixed widening that keeps a
    // literal too big for i32 from truncating
    println!("sh {} {} {}", 1u64 << 31, 1u64 << 32, 1u64 << 44);
    let big: i64 = 4294967296;
    println!("big {}", big);
}
