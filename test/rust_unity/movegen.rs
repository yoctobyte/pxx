//! movegen.rs — reaches into BOTH other modules, and returns an array.

use crate::attacks::knight_from;
use crate::attacks::popcount;
use crate::board::Board;

pub fn mobility_table() -> [i64; 8] {
    let mut t: [i64; 8] = [0; 8];
    let mut i: i64 = 0;
    while i < 8 {
        t[i] = crate::attacks::popcount(knight_from(i * 9));
        i += 1;
    }
    return t;
}

pub fn total(b: &Board) -> i64 {
    return popcount(b.occupied);
}
