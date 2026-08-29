// Rust frontend: the chess engine's OWN idioms, written the way the real
// sources are, rather than the way the adapted branch works around them.
//
// feature-rust-corpus-chess's ladder is ordered by what the engine actually
// needs, and this file is the ladder's own acceptance shape: a Square tuple
// struct with associated fns and accessors, a Color enum flipped through a
// tail `match`, a Board holding a mailbox array and an `Option<Square>`
// en-passant slot, and a `&mut self` move-maker. Every construct here was
// refused by the frontend at the start of the 2026-08-29 Track R window.
//
// It is deliberately NOT a perft: the movegen corpora already carry that
// oracle. What this pins is that the SHAPES compile and behave -- attribute
// swallowing, `pub` everywhere, associated fns, by-value `self` accessors,
// a tail match returning an aggregate, a struct literal whose fields include
// a repeat array and a bare `None`, a method on a record-typed field, and a
// mutation through `&mut self` that the caller can see.

#[derive(Clone, Copy, PartialEq)]
pub struct Square(pub u8);

impl Square {
    pub fn new(index: u8) -> Square { Square(index) }
    pub fn file(self) -> i64 { self.0 % 8 }
    pub fn rank(self) -> i64 { self.0 / 8 }
}

#[derive(Clone, Copy, PartialEq)]
pub enum Color { White, Black }

impl Color {
    pub fn flip(self) -> Color {
        match self {
            Color::White => Color::Black,
            Color::Black => Color::White,
        }
    }
    pub fn code(self) -> i64 {
        match self {
            Color::White => 1,
            Color::Black => 2,
        }
    }
}

pub struct Board {
    pub squares: [u8; 64],
    pub side: Color,
    pub ep: Option<Square>,
    pub halfmove: i64,
}

impl Board {
    pub fn new() -> Board {
        Board { squares: [0; 64], side: Color::White, ep: None, halfmove: 0 }
    }

    pub fn piece_at(&self, sq: Square) -> Option<u8> {
        let v = self.squares[sq.0];
        if v == 0 { return None; }
        return Some(v);
    }

    pub fn make(&mut self, from: Square, to: Square) {
        self.squares[to.0] = self.squares[from.0];
        self.squares[from.0] = 0;
        self.side = self.side.flip();
        self.halfmove += 1;
    }

    pub fn set_ep(&mut self, sq: Square) {
        self.ep = Some(sq);
    }
}

fn main() {
    let mut b = Board::new();
    b.squares[8] = 1;

    let from = Square::new(8);
    let to = Square::new(16);
    println!("from f{} r{} to f{} r{}", from.file(), from.rank(), to.file(), to.rank());

    // the empty square before the move
    match b.piece_at(to) {
        Some(p) => println!("before {}", p),
        None => println!("before empty"),
    }

    b.make(from, to);

    // ...and the occupied one after, through &mut self having actually landed
    match b.piece_at(to) {
        Some(p) => println!("after {}", p),
        None => println!("after empty"),
    }
    match b.piece_at(from) {
        Some(p) => println!("origin {}", p),
        None => println!("origin empty"),
    }

    println!("side {} halfmove {}", b.side.code(), b.halfmove);

    // Option<Square> field: None from the literal, Some after the setter
    if b.ep.is_none() { println!("ep none"); }
    b.set_ep(Square::new(40));
    if let Some(s) = b.ep {
        println!("ep {} f{} r{}", s.0, s.file(), s.rank());
    }
}
