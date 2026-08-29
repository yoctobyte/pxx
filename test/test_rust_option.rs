// Rust frontend: Option<T> as a monomorphized generic enum
// (feature-rust-corpus-chess stage 2 — the chess.rs wall).
//
// Each concrete Option<T> becomes its own auto-registered tagged-union
// UClass: __tag (i64) at 0, the payload as field "Some.0" past it, tags in
// Rust's declaration order (None = 0, Some = 1). `match` needs no special
// case — it resolves arm names against the scrutinee's own class, so the two
// synthesized variants behave exactly like a hand-written enum's.
//
// Covered here: annotated Some/None, payload-type inference for an
// unannotated `Some(e)`, two distinct instantiations live in one program
// (which is what makes the bare-variant table useless and the expected-type
// resolution necessary), is_some/is_none/unwrap, and both match arm forms
// (braced block and bare expression), Option in fn signatures -- params and
// RETURN values, on a free fn and on an impl method alike -- and a plain
// struct return, which the same wiring enables.

struct Board { ep: i64 }

// the engine's own shape: a fallible lookup returning Option
fn piece_at(sq: i64) -> Option<i64> {
    if sq < 0 { return None; }
    if sq > 63 { return None; }
    return Some(sq * 3);
}

// Option as a PARAMETER (record ABI, passed by address)
fn describe(o: Option<i64>) -> i64 {
    if o.is_none() { return -1; }
    return o.unwrap();
}

impl Board {
    fn ep_square(&self) -> Option<i64> {
        if self.ep < 0 { return None; }
        return Some(self.ep);
    }
}

// a plain record return -- same hidden-destination ABI, no longer refused
fn make_board(e: i64) -> Board {
    let b: Board = Board { ep: e };
    return b;
}

fn main() {
    let a: Option<i64> = Some(42);
    let b: Option<i64> = None;

    match a {
        Some(v) => { println!("a some {}", v); }
        None => { println!("a none"); }
    }
    match b {
        Some(v) => { println!("b some {}", v); }
        None => { println!("b none"); }
    }

    // bare (unbraced) arms — the spelling real Rust source uses
    let mut n: i64 = 0;
    match a {
        Some(v) => n = v * 2,
        None => n = -1,
    }
    println!("n {}", n);
    match b {
        Some(v) => n = v,
        None => n = -7,
    }
    println!("n {}", n);

    // accessors, no match
    if a.is_some() { println!("a is_some"); }
    if a.is_none() { println!("a is_none"); }
    if b.is_some() { println!("b is_some"); }
    if b.is_none() { println!("b is_none"); }
    println!("unwrap {}", a.unwrap());

    // a second instantiation in the same program: Option<u8> is a DIFFERENT
    // class with its own Some/None, so the literal must resolve against the
    // annotation rather than a global variant-name lookup.
    let c: Option<u8> = Some(200);
    match c {
        Some(v) => println!("c {}", v),
        None => println!("c none"),
    }

    // no annotation: the payload expression's own type picks the class
    let d = Some(9);
    println!("d {}", d.unwrap());

    // wildcard arm still works over a synthesized enum
    match b {
        Some(v) => println!("e {}", v),
        _ => println!("e wild"),
    }

    // Option through a signature: returned by a free fn, taken as a param
    let f = piece_at(5);
    match f {
        Some(v) => println!("f {}", v),
        None => println!("f none"),
    }
    let g = piece_at(-1);
    match g {
        Some(v) => println!("g {}", v),
        None => println!("g none"),
    }
    println!("describe {} {}", describe(f), describe(g));

    // ...and by a method, off a record returned by value
    let bd = make_board(40);
    let h = bd.ep_square();
    println!("h {}", h.unwrap());
    let bd2 = make_board(-1);
    let i = bd2.ep_square();
    if i.is_none() { println!("i none"); }
}
