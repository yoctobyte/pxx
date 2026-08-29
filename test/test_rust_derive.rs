// `#[derive(...)]` and enum values in expression position.
//
// Measuring before building was worth more than the building here.
// `#[derive(Copy)]` needs nothing -- a whole-record assignment already copies.
// `#[derive(PartialEq)]` needs nothing -- the shared record comparison already
// answers field-wise, and a test written two rungs earlier already proved it.
// What was actually missing was older and dumber: an enum VARIANT could not
// appear in an expression AT ALL. `let c: Color = Color::White` worked and
// `c == Color::White` was a parse error, because a literal is always N stores
// into a named slot and an expression had no slot to name.
//
// The oracle is hand-computed. `knights`, `val` and `tag` are each
// independently checkable by reading the source.

#[derive(Clone, Copy, PartialEq)]
enum Piece { Pawn, Knight, King }

#[derive(Clone, Copy, PartialEq)]
enum Slot { Empty, Occ(i64) }

#[derive(Clone, Copy, PartialEq)]
struct Pos { f: i64, r: i64 }

fn val(p: Piece) -> i64 {
    if p == Piece::Pawn { return 1; }
    if p == Piece::Knight { return 3; }
    return 0;
}

fn tag(s: Slot) -> i64 {
    match s {
        Slot::Empty => 0,
        Slot::Occ(n) => n,
    }
}

fn flip(p: Piece) -> Piece {
    if p == Piece::Pawn { return Piece::Knight; }
    return Piece::Pawn;
}

fn main() {
    // a variant as a CALL ARGUMENT and inside a comparison
    println!("val {} {} {}", val(Piece::Pawn), val(Piece::Knight), val(Piece::King));

    // a TUPLE variant in expression position, payload and all
    println!("tag {} {}", tag(Slot::Empty), tag(Slot::Occ(7)));

    // a variant round-tripping through a fn that both takes and returns one
    println!("flip {} {}", val(flip(Piece::Pawn)), val(flip(Piece::Knight)));

    // derive(Clone) with no user `clone`: field-wise copy, which assignment
    // already is. derive(PartialEq): the shared record compare.
    let a: Pos = Pos { f: 1, r: 2 };
    let b: Pos = a.clone();
    let c: Pos = Pos { f: 9, r: 9 };
    println!("clone {} {} eq {} ne {}", b.f, b.r, a == b, a == c);

    // an ARRAY of enum values -- each element is its own materialization
    let arr: [Piece; 3] = [Piece::Pawn, Piece::Knight, Piece::King];
    println!("arr {} {} {}", val(arr[0]), val(arr[1]), val(arr[2]));

    // a variant inside a LOOP BODY. The condition is guarded against a
    // hoisted temporary (it would be evaluated once, outside the loop); the
    // body is not, and must not be.
    let mut i: i64 = 0;
    let mut n: i64 = 0;
    while i < 3 {
        if arr[i] == Piece::Knight { n = n + 1; }
        i = i + 1;
    }
    println!("knights {}", n);

    // an enum value built inside a nested call chain
    println!("nest {}", val(flip(flip(Piece::Pawn))));
}
