//! board.rs — a type module. Reaches into `attacks` by fully-qualified
//! `crate::` path, which is what a submodule must write in real Rust and what
//! a concatenation does NOT fix on its own.

use crate::attacks::knight_from;

pub struct Board {
    pub side: i64,
    pub occupied: u64,
}

impl Board {
    pub fn new() -> Board {
        return Board { side: 1, occupied: 0 };
    }

    pub fn put(&mut self, sq: i64) {
        self.occupied |= 1u64 << sq;
    }

    // one arm through the `use` import, one fully qualified: both spellings
    // have to end up meaning the same flat name
    pub fn mobility(&self, sq: i64) -> i64 {
        return crate::attacks::popcount(knight_from(sq));
    }

    pub fn flip(&mut self) {
        self.side = if self.side == 1 { 2 } else { 1 };
    }
}
