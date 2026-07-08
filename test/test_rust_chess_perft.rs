// feature-rust-corpus-chess, stage-1 milestone: a C-style port of the
// nextlevel engine's move-generation core in the pxx Rust subset —
// mailbox board as &[i64] slices (the record ABI passes them by
// address), no structs/Option/ArrayVec. No castling / en passant /
// promotion, which leaves perft exact through depth 3 from the start
// position (first EP/castle opportunities appear at ply >= 4):
// perft(1)=20  perft(2)=400  perft(3)=8902.
// Encoding: 0 empty; white P1 N2 B3 R4 Q5 K6; black negated. side=+1/-1.
// Moves encoded from*64+to. Slices written as &a[lo..hi] (mutability is
// not enforced; `&mut` slice creation is spelled without mut here).

fn file_of(sq: i64) -> i64 { return sq % 8; }
fn rank_of(sq: i64) -> i64 { return sq / 8; }

// 1 if a piece of `side` attacks sq, else 0.
fn is_attacked(b: &[i64], sq: i64, side: i64) -> i64 {
    let f = file_of(sq);
    let r = rank_of(sq);

    // pawns: a pawn of `side` on (f±1, r-side) attacks sq
    let pr = r - side;
    if pr >= 0 && pr < 8 {
        if f > 0 {
            if b[pr * 8 + f - 1] == side * 1 { return 1; }
        }
        if f < 7 {
            if b[pr * 8 + f + 1] == side * 1 { return 1; }
        }
    }

    // knights
    let ndf: [i64; 8] = [1, 2, 2, 1, -1, -2, -2, -1];
    let ndr: [i64; 8] = [2, 1, -1, -2, -2, -1, 1, 2];
    for i in 0..8 {
        let nf = f + ndf[i];
        let nr = r + ndr[i];
        if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            if b[nr * 8 + nf] == side * 2 { return 1; }
        }
    }

    // king adjacency
    let kdf: [i64; 8] = [1, 1, 1, 0, 0, -1, -1, -1];
    let kdr: [i64; 8] = [1, 0, -1, 1, -1, 1, 0, -1];
    for i in 0..8 {
        let nf = f + kdf[i];
        let nr = r + kdr[i];
        if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            if b[nr * 8 + nf] == side * 6 { return 1; }
        }
    }

    // diagonal sliders (bishop 3 / queen 5)
    let bdf: [i64; 4] = [1, 1, -1, -1];
    let bdr: [i64; 4] = [1, -1, 1, -1];
    for i in 0..4 {
        let mut nf = f + bdf[i];
        let mut nr = r + bdr[i];
        while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            let p = b[nr * 8 + nf];
            if p != 0 {
                if p == side * 3 || p == side * 5 { return 1; }
                break;
            }
            nf += bdf[i];
            nr += bdr[i];
        }
    }

    // straight sliders (rook 4 / queen 5)
    let rdf: [i64; 4] = [1, -1, 0, 0];
    let rdr: [i64; 4] = [0, 0, 1, -1];
    for i in 0..4 {
        let mut nf = f + rdf[i];
        let mut nr = r + rdr[i];
        while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            let p = b[nr * 8 + nf];
            if p != 0 {
                if p == side * 4 || p == side * 5 { return 1; }
                break;
            }
            nf += rdf[i];
            nr += rdr[i];
        }
    }

    return 0;
}

fn king_sq(b: &[i64], side: i64) -> i64 {
    for sq in 0..64 {
        if b[sq] == side * 6 { return sq; }
    }
    return -1;
}

// Pseudo-legal move generation into ms; returns the count.
fn gen_moves(b: &[i64], side: i64, ms: &[i64]) -> i64 {
    let mut n = 0;
    for from in 0..64 {
        let p = b[from] * side; // own pieces become positive kinds
        // no `continue`: the range-for desugar appends the increment at
        // body end, so continue would skip it (documented deviation)
        if p > 0 {
        let f = file_of(from);
        let r = rank_of(from);

        if p == 1 {
            // pawn: pushes (empty), captures (enemy piece)
            let r1 = r + side;
            if r1 >= 0 && r1 < 8 {
                if b[r1 * 8 + f] == 0 {
                    ms[n] = from * 64 + r1 * 8 + f;
                    n += 1;
                    let start = (7 - 5 * side) / 2; // side=1 -> 1, side=-1 -> 6
                    if r == start {
                        let r2 = r + side + side;
                        if b[r2 * 8 + f] == 0 {
                            ms[n] = from * 64 + r2 * 8 + f;
                            n += 1;
                        }
                    }
                }
                if f > 0 {
                    if b[r1 * 8 + f - 1] * side < 0 {
                        ms[n] = from * 64 + r1 * 8 + f - 1;
                        n += 1;
                    }
                }
                if f < 7 {
                    if b[r1 * 8 + f + 1] * side < 0 {
                        ms[n] = from * 64 + r1 * 8 + f + 1;
                        n += 1;
                    }
                }
            }
        } else if p == 2 || p == 6 {
            // knight / king: fixed offset sets
            let df: [i64; 16] = [1, 2, 2, 1, -1, -2, -2, -1, 1, 1, 1, 0, 0, -1, -1, -1];
            let dr: [i64; 16] = [2, 1, -1, -2, -2, -1, 1, 2, 1, 0, -1, 1, -1, 1, 0, -1];
            let base = (p - 2) * 2; // knight -> 0, king -> 8
            for i in 0..8 {
                let nf = f + df[base + i];
                let nr = r + dr[base + i];
                if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    if b[nr * 8 + nf] * side <= 0 {
                        ms[n] = from * 64 + nr * 8 + nf;
                        n += 1;
                    }
                }
            }
        } else {
            // sliders: bishop 3 (dirs 0..4), rook 4 (dirs 4..8), queen 5 (0..8)
            let df: [i64; 8] = [1, 1, -1, -1, 1, -1, 0, 0];
            let dr: [i64; 8] = [1, -1, 1, -1, 0, 0, 1, -1];
            let mut d0 = 0;
            let mut d1 = 8;
            if p == 3 { d1 = 4; }
            if p == 4 { d0 = 4; }
            for d in d0..d1 {
                let mut nf = f + df[d];
                let mut nr = r + dr[d];
                while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    let t = b[nr * 8 + nf] * side;
                    if t > 0 { break; }
                    ms[n] = from * 64 + nr * 8 + nf;
                    n += 1;
                    if t < 0 { break; }
                    nf += df[d];
                    nr += dr[d];
                }
            }
        }
        }
    }
    return n;
}

fn perft(b: &[i64], side: i64, depth: i64) -> i64 {
    if depth == 0 { return 1; }
    let mut mv: [i64; 256] = [0; 256];
    let ms = &mv[0..256];
    let n = gen_moves(b, side, ms);
    let mut nodes = 0;
    for i in 0..n {
        let m = ms[i];
        let from = m / 64;
        let to = m % 64;
        let captured = b[to];
        b[to] = b[from];
        b[from] = 0;
        if is_attacked(b, king_sq(b, side), 0 - side) == 0 {
            nodes += perft(b, 0 - side, depth - 1);
        }
        b[from] = b[to];
        b[to] = captured;
    }
    return nodes;
}

fn main() -> i32 {
    let mut board: [i64; 64] = [0; 64];
    let b = &board[0..64];
    // white back rank + pawns
    let back: [i64; 8] = [4, 2, 3, 5, 6, 3, 2, 4];
    for f in 0..8 {
        b[f] = back[f];
        b[8 + f] = 1;
        b[48 + f] = -1;
        b[56 + f] = 0 - back[f];
    }
    println!("perft1 {}", perft(b, 1, 1));
    println!("perft2 {}", perft(b, 1, 2));
    println!("perft3 {}", perft(b, 1, 3));
    return 0;
}
