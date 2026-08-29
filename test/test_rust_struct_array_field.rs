// Rust frontend: fixed-array STRUCT FIELDS (`squares: [i64; 64]`).
//
// The next rung on feature-rust-corpus-chess after Option: chess.rs's Board
// is a mailbox array held in a struct, and the frontend refused the syntax
// outright ("expected field type"). The shared UClass machinery has always
// modelled an array field -- UFldIsArray/UFldArrLen is what Pascal's
// `arr: array[0..N-1] of T` and C's `int a[N];` both land on -- so this is
// frontend wiring, not a new capability.
//
// Covered: scalar element types (i64 and a narrow u8), a RECORD element type
// with `field[i].member` access, reads and writes, several array fields in
// one struct laid out around a scalar, and the array reaching a fn by the
// record ABI.

struct Piece { kind: i64, color: i64 }

struct Board {
    squares: [i64; 64],
    side: i64,
    flags: [u8; 8],
    pieces: [Piece; 4],
}

fn checksum(b: Board) -> i64 {
    let mut s: i64 = 0;
    let mut i: i64 = 0;
    while i < 64 {
        s += b.squares[i];
        i += 1;
    }
    return s;
}

fn main() {
    let mut b: Board;
    b.side = 1;

    let mut i: i64 = 0;
    while i < 64 {
        b.squares[i] = i * i;
        i += 1;
    }
    i = 0;
    while i < 8 {
        b.flags[i] = i + 200;
        i += 1;
    }

    // a record element, read and written through the array field
    b.pieces[0].kind = 5;
    b.pieces[0].color = 1;
    b.pieces[3].kind = 9;
    b.pieces[3].color = b.pieces[0].color + 1;

    println!("sq {} {} {}", b.squares[0], b.squares[7], b.squares[63]);
    println!("flags {} {}", b.flags[0], b.flags[7]);
    println!("side {}", b.side);
    println!("pieces {} {} {} {}", b.pieces[0].kind, b.pieces[0].color, b.pieces[3].kind, b.pieces[3].color);
    println!("checksum {}", checksum(b));
}
