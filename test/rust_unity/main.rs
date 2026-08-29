//! main.rs — the crate root. It is the file that DECLARES the modules, which
//! is what tells the frontend which `Ident ::` prefixes are module qualifiers
//! and must be stripped, and which (Board::new, Color::White) are type paths
//! and must survive.
#![allow(dead_code)]

mod attacks;
mod board;
mod movegen;

use crate::board::Board;
use crate::movegen::mobility_table;

fn main() {
    let mut b = board::Board::new();
    b.put(0);
    b.put(9);
    b.put(63);
    println!("side {} occupied {}", b.side, movegen::total(&b));

    b.flip();
    println!("flipped {}", b.side);

    // a1 has 2 knight moves, b2 has 4, h8 has 2
    println!("mob {} {} {}", b.mobility(0), b.mobility(9), b.mobility(63));

    let t = crate::movegen::mobility_table();
    println!("tbl {} {} {} {}", t[0], t[1], t[2], t[7]);

    println!("kf0 {}", attacks::knight_from(0));
}
