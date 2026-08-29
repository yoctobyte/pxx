//! attacks.rs — a data module: const tables plus the fns that read them.
//! This is the shape stage 3 exists for; nothing here knows it will be
//! concatenated with anything.

pub type Bitboard = u64;

pub const KNIGHT_DF: [i64; 8] = [1, 1, -1, -1, 2, 2, -2, -2];
pub const KNIGHT_DR: [i64; 8] = [2, -2, 2, -2, 1, -1, 1, -1];

pub fn knight_from(sq: i64) -> Bitboard {
    let mut m: Bitboard = 0;
    let f: i64 = sq % 8;
    let r: i64 = sq / 8;
    let mut k: i64 = 0;
    while k < 8 {
        let nf: i64 = f + KNIGHT_DF[k];
        let nr: i64 = r + KNIGHT_DR[k];
        if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            m |= 1u64 << (nr * 8 + nf);
        }
        k += 1;
    }
    return m;
}

pub fn popcount(b: Bitboard) -> i64 {
    let mut n: i64 = 0;
    let mut i: i64 = 0;
    while i < 64 {
        if (b >> i) & 1u64 != 0 { n += 1; }
        i += 1;
    }
    return n;
}
