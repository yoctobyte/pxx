// feature-rust-corpus-chess, search milestone (stage-6 gate: "search finds a
// mate"). Reuses the full-legality movegen from the perft port and adds a
// material-eval negamax with mate scoring, then verifies the engine finds a
// forced mate-in-1 and a forced mate-in-2 by score. This exercises the
// engine's *decision* logic (recursion returning a best value, alpha-style
// max, mate detection), not just move enumeration.
//
// Same pxx-friendly representation as the perft port: signed-i64 mailbox,
// moves packed into one i64 (from | to<<6 | flags<<12), castling/ep threaded
// by value.  MATE = 1000000; a returned score >= MATE - 100 means a forced
// mate was found within the search horizon.

fn file_of(sq: i64) -> i64 { return sq % 8; }
fn rank_of(sq: i64) -> i64 { return sq / 8; }
fn mk(from: i64, to: i64, flags: i64) -> i64 { return from + to * 64 + flags * 4096; }

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

fn gen_moves(b: &[i64], side: i64, ep: i64, castle: i64, ms: &[i64]) -> i64 {
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
                        for pf in 4..8 { ms[n] = mk(from, to, pf); n += 1; }
                    } else {
                        ms[n] = mk(from, to, 0); n += 1;
                        let start = (7 - 5 * side) / 2;
                        if r == start {
                            let r2 = r + side + side;
                            if b[r2 * 8 + f] == 0 { ms[n] = mk(from, r2 * 8 + f, 1); n += 1; }
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
                                for pf in 4..8 { ms[n] = mk(from, to, pf); n += 1; }
                            } else { ms[n] = mk(from, to, 0); n += 1; }
                        }
                        if to == ep && ep >= 0 { ms[n] = mk(from, to, 3); n += 1; }
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
                    if b[nr * 8 + nf] * side <= 0 { ms[n] = mk(from, nr * 8 + nf, 0); n += 1; }
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
                            ms[n] = mk(home, home + 2, 2); n += 1;
                        }
                    }
                }
                if (castle % (wq * 2)) / wq == 1 {
                    if b[home - 1] == 0 && b[home - 2] == 0 && b[home - 3] == 0 {
                        if is_attacked(b, home, 0 - side) == 0 &&
                           is_attacked(b, home - 1, 0 - side) == 0 &&
                           is_attacked(b, home - 2, 0 - side) == 0 {
                            ms[n] = mk(home, home - 2, 2); n += 1;
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
                        ms[n] = mk(from, nr * 8 + nf, 0); n += 1;
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

// Static material eval from White's perspective (centipawns).
fn eval(b: &[i64]) -> i64 {
    let val: [i64; 7] = [0, 100, 320, 330, 500, 900, 0]; // index by |piece| kind
    let mut s = 0;
    for sq in 0..64 {
        let pc = b[sq];
        if pc > 0 { s += val[pc]; }
        else if pc < 0 { s -= val[0 - pc]; }
    }
    return s;
}

// Negamax with mate scoring. Returns the best achievable score for `side`
// (side-relative: positive = good for side to move). `ply` grows with depth
// from the root so nearer mates score higher.
fn negamax(b: &[i64], side: i64, ep: i64, castle: i64, depth: i64, ply: i64) -> i64 {
    if depth == 0 { return eval(b) * side; }
    let mut mv: [i64; 256] = [0; 256];
    let ms = &mv[0..256];
    let n = gen_moves(b, side, ep, castle, ms);
    let mut best = -2000000;
    let mut legal = 0;
    for i in 0..n {
        let m = ms[i];
        let from = m % 64;
        let to = (m / 64) % 64;
        let flags = m / 4096;
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
        // no legal move: checkmate (in check) or stalemate (not in check)
        if is_attacked(b, king_sq(b, side), 0 - side) == 1 {
            return 0 - (1000000 - ply);
        }
        return 0;
    }
    return best;
}

// 1 if score reaches the mate band, else 0 (the frontend has no if-expression).
fn is_mate(score: i64) -> i64 {
    if score >= 999000 { return 1; }
    return 0;
}

fn main() -> i32 {
    // Mate in 1: black Kg8 boxed by its own f7/g7/h7 pawns, white Ra1 + Kh1.
    // 6k1/5ppp/8/8/8/8/8/R6K w - -  ->  1.Ra8#.
    let mut b1: [i64; 64] = [0; 64];
    let p1 = &b1[0..64];
    p1[62] = -6;                            // black king g8
    p1[53] = -1; p1[54] = -1; p1[55] = -1;  // black pawns f7 g7 h7
    p1[7] = 6;                              // white king h1
    p1[0] = 4;                              // white rook a1
    // depth 2 = our move + confirm the opponent has no reply: mate is found.
    let s1 = negamax(p1, 1, -1, 0, 2, 0);
    println!("mate1 {} score {}", is_mate(s1), s1);
    // depth 1 only looks one ply, so the mate is NOT yet visible — proves the
    // mate detection is real search depth, not a static-eval artifact.
    let s1shallow = negamax(p1, 1, -1, 0, 1, 0);
    println!("shallow {} score {}", is_mate(s1shallow), s1shallow);

    // Mate in 2 (3 plies): black Kh8, white Kf5, Ra7. The rook cannot mate
    // immediately (1.Ra8+ Kh7 escapes — Kf5 is too far to cover h7), so white
    // must first play the QUIET move 1.Kg6!, which covers g7/h7 and confines
    // the black king to g8; then 2.Ra8# mates. Because the first move is not a
    // check, this is a genuine two-mover, not a disguised mate-in-1. Detecting
    // a mate-in-N needs search depth 2N here: the delivered-mate node must
    // still generate moves (depth >= 1) to notice the side to move has none.
    // So depth 4 finds this mate; depth 3 does not.
    let mut b2: [i64; 64] = [0; 64];
    let p2 = &b2[0..64];
    p2[63] = -6;   // black king h8
    p2[37] = 6;    // white king f5
    p2[48] = 4;    // white rook a7
    let s2deep = negamax(p2, 1, -1, 0, 4, 0);
    let s2shallow = negamax(p2, 1, -1, 0, 3, 0);
    println!("mate2 {} score {}", is_mate(s2deep), s2deep);
    println!("mate2shallow {} score {}", is_mate(s2shallow), s2shallow);

    // Start-position sanity: symmetric material, so depth-1 best score ~ 0,
    // proving eval + negamax wiring on a normal (non-mate) node.
    let mut sb: [i64; 64] = [0; 64];
    let sp = &sb[0..64];
    let back: [i64; 8] = [4, 2, 3, 5, 6, 3, 2, 4];
    for f in 0..8 {
        sp[f] = back[f]; sp[8 + f] = 1; sp[48 + f] = -1; sp[56 + f] = 0 - back[f];
    }
    println!("starteval {}", negamax(sp, 1, -1, 15, 1, 0));
    return 0;
}
