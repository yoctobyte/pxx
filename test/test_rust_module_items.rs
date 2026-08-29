//! Rust module-level items -- the stage-0/stage-3 rung of
//! feature-rust-corpus-chess: what a real `.rs` file has ABOVE its first fn,
//! and what a unity-build concatenation of several modules therefore has a
//! lot of. Every module of the corpus engine used to die in its first four
//! lines on exactly this.
#![allow(dead_code)]

use crate::board::Board;
use std::cmp::max;
use crate::attacks::{knight, king};

mod board;
pub mod attacks;

// Type ALIASES now alias. They used to be dropped whole, so every use of the
// alias died on `unknown type` -- which a bitboard engine hits immediately,
// since `pub type Bitboard = u64;` names its one central type. Resolved in
// RTypeNameAt, the single canonical type-name reader, so nothing downstream
// needs to know aliases exist.
pub type Bitboard = u64;
type SqIdx = i64;
type Board64 = Bitboard;          // chained, and resolution is bounded

// Top-level const ARRAYS: the attack tables stage 3 is actually about. These
// used to be swallowed whole and every use errored. They become globals filled
// at startup -- a deviation from Rust's .rodata `const` that no compiling
// program can observe, since the values, their addresses and reads from any
// function are all the same.
const DELTAS: [i64; 4] = [1, -1, 8, -8];
const ZEROS: [u64; 8] = [0; 8];
pub const NAMES: [u8; 3] = [65, 66, 67];

pub const BOARD_SIZE: i64 = 64;
const FILES: i64 = 8;
pub const RANK_MASK: u64 = 255u64;

#[derive(Clone, Copy)]
pub struct Sq { pub idx: SqIdx }

// declared ABOVE the consts it reads, which is legal Rust and the reason the
// const registration has to be a prescan rather than part of the top-level walk
fn weighted() -> i64 {
    let mut s: i64 = 0;
    let mut i: i64 = 0;
    while i < 4 {
        s += DELTAS[i] * (i + 1);
        i += 1;
    }
    return s;
}

#[inline]
pub fn area() -> i64 {
    return BOARD_SIZE;
}

fn widen(b: Board64) -> Bitboard {
    return b | 1u64;
}

fn main() {
    // 1*1 + (-1)*2 + 8*3 + (-8)*4 = -9, computed by hand, not recorded
    println!("weighted {}", weighted());
    println!("names {} {} {}", NAMES[0], NAMES[1], NAMES[2]);
    println!("zeros {} {}", ZEROS[0], ZEROS[7]);
    println!("size {} files {} mask {}", BOARD_SIZE, FILES, RANK_MASK);
    println!("area {}", area());

    let b: Bitboard = 4;
    let s: SqIdx = 12;
    println!("alias {} {} {}", b, s, widen(b));

    let sq = Sq { idx: 7 };
    println!("sq {}", sq.idx);
}
