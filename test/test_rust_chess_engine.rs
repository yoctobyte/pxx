// feature-rust-corpus-chess, engine milestone: a faithful struct-based branch
// of the nextlevel engine, mirroring its real data model — a `Move` struct
// { from, to, flags } held in a `[Move; 256]` list (the pxx stand-in for
// ArrayVec<Move, 256>), rather than the packed-i64 encoding of the perft/search
// ports. Exercises the fixed-array-of-structs enabler (arr[i].field) under a
// full workload: legal movegen, make/unmake, material-eval negamax, and UCI
// best-move formatting via char casts. Documented deviations from the real
// source: signed-i64 mailbox (vs u8), Square as a plain i64 (vs Square(u8)),
// no Option/Result/String (best move printed with println! + `as char`).
//
// Verifies two things end to end:
//   perft(4) = 197281   (movegen correctness with the struct move list)
//   bestmove a1a8       (search picks the mate-in-1 rook lift and formats it)

struct Move { from: i64, to: i64, flags: i64 }

fn file_of(sq: i64) -> i64 { return sq % 8; }
fn rank_of(sq: i64) -> i64 { return sq / 8; }

fn is_attacked(b: &[i64], sq: i64, side: i64) -> i64 {
    let f = file_of(sq);
    let r = rank_of(sq);
    let pr = r - side;
    if pr >= 0 && pr < 8 {
        if f > 0 { if b[pr * 8 + f - 1] == side * 1 { return 1; } }
        if f < 7 { if b[pr * 8 + f + 1] == side * 1 { return 1; } }
    }
    let ndf: [i64; 8] = [1, 2, 2, 1, -1, -2, -2, -1];
    let ndr: [i64; 8] = [2, 1, -1, -2, -2, -1, 1, 2];
    for i in 0..8 {
        let nf = f + ndf[i]; let nr = r + ndr[i];
        if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            if b[nr * 8 + nf] == side * 2 { return 1; }
        }
    }
    let kdf: [i64; 8] = [1, 1, 1, 0, 0, -1, -1, -1];
    let kdr: [i64; 8] = [1, 0, -1, 1, -1, 1, 0, -1];
    for i in 0..8 {
        let nf = f + kdf[i]; let nr = r + kdr[i];
        if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            if b[nr * 8 + nf] == side * 6 { return 1; }
        }
    }
    let bdf: [i64; 4] = [1, 1, -1, -1];
    let bdr: [i64; 4] = [1, -1, 1, -1];
    for i in 0..4 {
        let mut nf = f + bdf[i]; let mut nr = r + bdr[i];
        while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            let p = b[nr * 8 + nf];
            if p != 0 {
                if p == side * 3 || p == side * 5 { return 1; }
                nf = -100;
            } else { nf += bdf[i]; nr += bdr[i]; }
        }
    }
    let rdf: [i64; 4] = [1, -1, 0, 0];
    let rdr: [i64; 4] = [0, 0, 1, -1];
    for i in 0..4 {
        let mut nf = f + rdf[i]; let mut nr = r + rdr[i];
        while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            let p = b[nr * 8 + nf];
            if p != 0 {
                if p == side * 4 || p == side * 5 { return 1; }
                nf = -100;
            } else { nf += rdf[i]; nr += rdr[i]; }
        }
    }
    return 0;
}

fn king_sq(b: &[i64], side: i64) -> i64 {
    for s in 0..64 { if b[s] == side * 6 { return s; } }
    return -1;
}

// Append a move to the struct list at index n; returns the new count.
fn add(ms: &[Move], n: i64, from: i64, to: i64, flags: i64) -> i64 {
    ms[n].from = from;
    ms[n].to = to;
    ms[n].flags = flags;
    return n + 1;
}

fn gen_moves(b: &[i64], side: i64, ep: i64, castle: i64, ms: &[Move]) -> i64 {
    let mut n = 0;
    for from in 0..64 {
        let p = b[from] * side;
        if p > 0 {
        let f = file_of(from);
        let r = rank_of(from);
        if p == 1 {
            let r1 = r + side;
            let last = 7 * (1 + side) / 2;
            if r1 >= 0 && r1 < 8 {
                if b[r1 * 8 + f] == 0 {
                    let to = r1 * 8 + f;
                    if r1 == last {
                        for pf in 4..8 { n = add(ms, n, from, to, pf); }
                    } else {
                        n = add(ms, n, from, to, 0);
                        let start = (7 - 5 * side) / 2;
                        if r == start {
                            let r2 = r + side + side;
                            if b[r2 * 8 + f] == 0 { n = add(ms, n, from, r2 * 8 + f, 1); }
                        }
                    }
                }
                let mut dfi = 0;
                while dfi < 2 {
                    let cf = f - 1 + dfi * 2;
                    if cf >= 0 && cf < 8 {
                        let to = r1 * 8 + cf;
                        if b[to] * side < 0 {
                            if r1 == last {
                                for pf in 4..8 { n = add(ms, n, from, to, pf); }
                            } else { n = add(ms, n, from, to, 0); }
                        }
                        if to == ep && ep >= 0 { n = add(ms, n, from, to, 3); }
                    }
                    dfi += 1;
                }
            }
        } else if p == 2 || p == 6 {
            let df: [i64; 16] = [1, 2, 2, 1, -1, -2, -2, -1, 1, 1, 1, 0, 0, -1, -1, -1];
            let dr: [i64; 16] = [2, 1, -1, -2, -2, -1, 1, 2, 1, 0, -1, 1, -1, 1, 0, -1];
            let base = (p - 2) * 2;
            for i in 0..8 {
                let nf = f + df[base + i]; let nr = r + dr[base + i];
                if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    if b[nr * 8 + nf] * side <= 0 { n = add(ms, n, from, nr * 8 + nf, 0); }
                }
            }
            if p == 6 {
                let mut wk = 1; let mut wq = 2; let mut home = 4;
                if side < 0 { wk = 4; wq = 8; home = 60; }
                if (castle % (wk * 2)) / wk == 1 {
                    if b[home + 1] == 0 && b[home + 2] == 0 {
                        if is_attacked(b, home, 0 - side) == 0 &&
                           is_attacked(b, home + 1, 0 - side) == 0 &&
                           is_attacked(b, home + 2, 0 - side) == 0 {
                            n = add(ms, n, home, home + 2, 2);
                        }
                    }
                }
                if (castle % (wq * 2)) / wq == 1 {
                    if b[home - 1] == 0 && b[home - 2] == 0 && b[home - 3] == 0 {
                        if is_attacked(b, home, 0 - side) == 0 &&
                           is_attacked(b, home - 1, 0 - side) == 0 &&
                           is_attacked(b, home - 2, 0 - side) == 0 {
                            n = add(ms, n, home, home - 2, 2);
                        }
                    }
                }
            }
        } else {
            let df: [i64; 8] = [1, 1, -1, -1, 1, -1, 0, 0];
            let dr: [i64; 8] = [1, -1, 1, -1, 0, 0, 1, -1];
            let mut d0 = 0; let mut d1 = 8;
            if p == 3 { d1 = 4; }
            if p == 4 { d0 = 4; }
            for d in d0..d1 {
                let mut nf = f + df[d]; let mut nr = r + dr[d];
                while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    let t = b[nr * 8 + nf] * side;
                    if t > 0 { nf = -100; }
                    else {
                        n = add(ms, n, from, nr * 8 + nf, 0);
                        if t < 0 { nf = -100; }
                        else { nf += df[d]; nr += dr[d]; }
                    }
                }
            }
        }
        }
    }
    return n;
}

fn upd_castle(castle: i64, sq: i64) -> i64 {
    let mut c = castle;
    if sq == 4  { if (c % 2) == 1 { c -= 1; } if (c % 4) / 2 == 1 { c -= 2; } }
    if sq == 60 { if (c % 8) / 4 == 1 { c -= 4; } if (c % 16) / 8 == 1 { c -= 8; } }
    if sq == 7  { if (c % 2) == 1 { c -= 1; } }
    if sq == 0  { if (c % 4) / 2 == 1 { c -= 2; } }
    if sq == 63 { if (c % 8) / 4 == 1 { c -= 4; } }
    if sq == 56 { if (c % 16) / 8 == 1 { c -= 8; } }
    return c;
}

// Play move fields on the board; returns the captured piece (for unmake).
// Special squares are handled by the caller via the flags it already holds.
fn perft(b: &[i64], side: i64, ep: i64, castle: i64, depth: i64) -> i64 {
    if depth == 0 { return 1; }
    let mut mv: [Move; 256];
    let ms = &mv[0..256];
    let n = gen_moves(b, side, ep, castle, ms);
    let mut nodes = 0;
    for i in 0..n {
        let from = ms[i].from;
        let to = ms[i].to;
        let flags = ms[i].flags;
        let moved = b[from];
        let captured = b[to];
        b[to] = moved;
        b[from] = 0;
        let mut ep_cap_sq = -1;
        let mut ep_cap_pc = 0;
        if flags == 3 {
            ep_cap_sq = rank_of(from) * 8 + file_of(to);
            ep_cap_pc = b[ep_cap_sq];
            b[ep_cap_sq] = 0;
        }
        if flags >= 4 { b[to] = side * (flags - 2); }
        let mut rook_from = -1;
        let mut rook_to = -1;
        if flags == 2 {
            if to > from { rook_from = from + 3; rook_to = from + 1; }
            else { rook_from = from - 4; rook_to = from - 1; }
            b[rook_to] = b[rook_from];
            b[rook_from] = 0;
        }
        let mut nep = -1;
        if flags == 1 { nep = (from + to) / 2; }
        let mut nc = upd_castle(castle, from);
        nc = upd_castle(nc, to);
        if is_attacked(b, king_sq(b, side), 0 - side) == 0 {
            nodes += perft(b, 0 - side, nep, nc, depth - 1);
        }
        if flags == 2 { b[rook_from] = b[rook_to]; b[rook_to] = 0; }
        if flags == 3 { b[ep_cap_sq] = ep_cap_pc; }
        b[from] = moved;
        b[to] = captured;
    }
    return nodes;
}

fn eval(b: &[i64]) -> i64 {
    let val: [i64; 7] = [0, 100, 320, 330, 500, 900, 0];
    let mut s = 0;
    for sq in 0..64 {
        let pc = b[sq];
        if pc > 0 { s += val[pc]; }
        else if pc < 0 { s -= val[0 - pc]; }
    }
    return s;
}

fn negamax(b: &[i64], side: i64, ep: i64, castle: i64, depth: i64, ply: i64) -> i64 {
    if depth == 0 { return eval(b) * side; }
    let mut mv: [Move; 256];
    let ms = &mv[0..256];
    let n = gen_moves(b, side, ep, castle, ms);
    let mut best = -2000000;
    let mut legal = 0;
    for i in 0..n {
        let from = ms[i].from;
        let to = ms[i].to;
        let flags = ms[i].flags;
        let moved = b[from];
        let captured = b[to];
        b[to] = moved;
        b[from] = 0;
        let mut ep_cap_sq = -1;
        let mut ep_cap_pc = 0;
        if flags == 3 {
            ep_cap_sq = rank_of(from) * 8 + file_of(to);
            ep_cap_pc = b[ep_cap_sq];
            b[ep_cap_sq] = 0;
        }
        if flags >= 4 { b[to] = side * (flags - 2); }
        let mut rook_from = -1;
        let mut rook_to = -1;
        if flags == 2 {
            if to > from { rook_from = from + 3; rook_to = from + 1; }
            else { rook_from = from - 4; rook_to = from - 1; }
            b[rook_to] = b[rook_from];
            b[rook_from] = 0;
        }
        let mut nep = -1;
        if flags == 1 { nep = (from + to) / 2; }
        let mut nc = upd_castle(castle, from);
        nc = upd_castle(nc, to);
        if is_attacked(b, king_sq(b, side), 0 - side) == 0 {
            legal += 1;
            let score = 0 - negamax(b, 0 - side, nep, nc, depth - 1, ply + 1);
            if score > best { best = score; }
        }
        if flags == 2 { b[rook_from] = b[rook_to]; b[rook_to] = 0; }
        if flags == 3 { b[ep_cap_sq] = ep_cap_pc; }
        b[from] = moved;
        b[to] = captured;
    }
    if legal == 0 {
        if is_attacked(b, king_sq(b, side), 0 - side) == 1 { return 0 - (1000000 - ply); }
        return 0;
    }
    return best;
}

// Print a square as two UCI chars (file letter + rank digit).
fn print_move(from: i64, to: i64) {
    let ff = (97 + file_of(from)) as u8 as char;
    let fr = (49 + rank_of(from)) as u8 as char;
    let tf = (97 + file_of(to)) as u8 as char;
    let tr = (49 + rank_of(to)) as u8 as char;
    println!("bestmove {}{}{}{}", ff, fr, tf, tr);
}

// Root search: pick the highest-scoring legal move and print it in UCI.
fn best_move(b: &[i64], side: i64, ep: i64, castle: i64, depth: i64) {
    let mut mv: [Move; 256];
    let ms = &mv[0..256];
    let n = gen_moves(b, side, ep, castle, ms);
    let mut best = -2000000;
    let mut bf = 0;
    let mut bt = 0;
    for i in 0..n {
        let from = ms[i].from;
        let to = ms[i].to;
        let flags = ms[i].flags;
        let moved = b[from];
        let captured = b[to];
        b[to] = moved;
        b[from] = 0;
        if flags >= 4 { b[to] = side * (flags - 2); }
        let mut rook_from = -1;
        let mut rook_to = -1;
        if flags == 2 {
            if to > from { rook_from = from + 3; rook_to = from + 1; }
            else { rook_from = from - 4; rook_to = from - 1; }
            b[rook_to] = b[rook_from];
            b[rook_from] = 0;
        }
        let mut nc = upd_castle(castle, from);
        nc = upd_castle(nc, to);
        if is_attacked(b, king_sq(b, side), 0 - side) == 0 {
            let score = 0 - negamax(b, 0 - side, -1, nc, depth - 1, 1);
            if score > best { best = score; bf = from; bt = to; }
        }
        if flags == 2 { b[rook_from] = b[rook_to]; b[rook_to] = 0; }
        b[from] = moved;
        b[to] = captured;
    }
    print_move(bf, bt);
}

fn main() -> i32 {
    // perft(4) from the start position, movegen driven by the Move struct list.
    let mut board: [i64; 64] = [0; 64];
    let b = &board[0..64];
    let back: [i64; 8] = [4, 2, 3, 5, 6, 3, 2, 4];
    for f in 0..8 {
        b[f] = back[f]; b[8 + f] = 1; b[48 + f] = -1; b[56 + f] = 0 - back[f];
    }
    println!("perft4 {}", perft(b, 1, -1, 15, 4));

    // Mate-in-1: white Ra1 + Kh1, black Kg8 boxed by f7/g7/h7 pawns.
    // The engine must choose 1.Ra8# -> UCI "a1a8".
    let mut mb: [i64; 64] = [0; 64];
    let m = &mb[0..64];
    m[62] = -6; m[53] = -1; m[54] = -1; m[55] = -1;
    m[7] = 6; m[0] = 4;
    best_move(m, 1, -1, 0, 2);
    return 0;
}
