// feature-rust-corpus-chess, full-legality milestone. A pxx-friendly branch of
// the nextlevel engine's movegen: signed-i64 mailbox board (documented
// deviation from the engine's u8 encoding), moves packed into one i64
// (from | to<<6 | flags<<12) standing in for the engine's `Move` struct +
// ArrayVec<Move,256> (the ticket's sanctioned local-structure replacement).
// Adds every rule the depth-3 port skipped — en passant, castling,
// promotions — so perft matches the standard reference from the start
// position through depth 6:
//   perft(1)=20  perft(2)=400  perft(3)=8902  perft(4)=197281
//   perft(5)=4865609  perft(6)=119060324
// State threaded by value through the recursion: castling-rights bitmask
// (1=WK 2=WQ 4=BK 8=BQ) and the en-passant target square (-1 = none).
// Encoding: 0 empty; white P1 N2 B3 R4 Q5 K6, black negated; side = +1/-1.

fn file_of(sq: i64) -> i64 { return sq % 8; }
fn rank_of(sq: i64) -> i64 { return sq / 8; }

// flags: 0 normal, 1 double-push, 2 castle, 3 en-passant, 4..7 promo N/B/R/Q
fn mk(from: i64, to: i64, flags: i64) -> i64 { return from + to * 64 + flags * 4096; }

// 1 if a piece of `side` attacks sq, else 0. (ep/castling irrelevant here.)
fn is_attacked(b: &[i64], sq: i64, side: i64) -> i64 {
    let f = file_of(sq);
    let r = rank_of(sq);

    // pawns of `side` sit one rank "behind" (toward their origin) and attack forward
    let pr = r - side;
    if pr >= 0 && pr < 8 {
        if f > 0 {
            if b[pr * 8 + f - 1] == side * 1 { return 1; }
        }
        if f < 7 {
            if b[pr * 8 + f + 1] == side * 1 { return 1; }
        }
    }

    let ndf: [i64; 8] = [1, 2, 2, 1, -1, -2, -2, -1];
    let ndr: [i64; 8] = [2, 1, -1, -2, -2, -1, 1, 2];
    for i in 0..8 {
        let nf = f + ndf[i];
        let nr = r + ndr[i];
        if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            if b[nr * 8 + nf] == side * 2 { return 1; }
        }
    }

    let kdf: [i64; 8] = [1, 1, 1, 0, 0, -1, -1, -1];
    let kdr: [i64; 8] = [1, 0, -1, 1, -1, 1, 0, -1];
    for i in 0..8 {
        let nf = f + kdf[i];
        let nr = r + kdr[i];
        if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            if b[nr * 8 + nf] == side * 6 { return 1; }
        }
    }

    // diagonal sliders: bishop 3 / queen 5
    let bdf: [i64; 4] = [1, 1, -1, -1];
    let bdr: [i64; 4] = [1, -1, 1, -1];
    for i in 0..4 {
        let mut nf = f + bdf[i];
        let mut nr = r + bdr[i];
        while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            let p = b[nr * 8 + nf];
            if p != 0 {
                if p == side * 3 || p == side * 5 { return 1; }
                nf = -100;
            } else {
                nf += bdf[i];
                nr += bdr[i];
            }
        }
    }

    // orthogonal sliders: rook 4 / queen 5
    let rdf: [i64; 4] = [1, -1, 0, 0];
    let rdr: [i64; 4] = [0, 0, 1, -1];
    for i in 0..4 {
        let mut nf = f + rdf[i];
        let mut nr = r + rdr[i];
        while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            let p = b[nr * 8 + nf];
            if p != 0 {
                if p == side * 4 || p == side * 5 { return 1; }
                nf = -100;
            } else {
                nf += rdf[i];
                nr += rdr[i];
            }
        }
    }

    return 0;
}

fn king_sq(b: &[i64], side: i64) -> i64 {
    for s in 0..64 {
        if b[s] == side * 6 { return s; }
    }
    return -1;
}

// Generate pseudo-legal moves for `side`. Returns count; fills ms.
fn gen_moves(b: &[i64], side: i64, ep: i64, castle: i64, ms: &[i64]) -> i64 {
    let mut n = 0;
    for from in 0..64 {
        let p = b[from] * side; // own pieces -> positive kind
        if p > 0 {
        let f = file_of(from);
        let r = rank_of(from);

        if p == 1 {
            // pawn
            let r1 = r + side;
            let last = 7 * (1 + side) / 2; // side=1 -> 7, side=-1 -> 0  (promotion rank)
            if r1 >= 0 && r1 < 8 {
                // single push
                if b[r1 * 8 + f] == 0 {
                    let to = r1 * 8 + f;
                    if r1 == last {
                        for pf in 4..8 { ms[n] = mk(from, to, pf); n += 1; }
                    } else {
                        ms[n] = mk(from, to, 0); n += 1;
                        // double push
                        let start = (7 - 5 * side) / 2; // side=1 -> 1, side=-1 -> 6
                        if r == start {
                            let r2 = r + side + side;
                            if b[r2 * 8 + f] == 0 {
                                ms[n] = mk(from, r2 * 8 + f, 1); n += 1;
                            }
                        }
                    }
                }
                // captures (incl. promotion captures)
                let mut dfi = 0;
                while dfi < 2 {
                    let cf = f - 1 + dfi * 2; // f-1 then f+1
                    if cf >= 0 && cf < 8 {
                        let to = r1 * 8 + cf;
                        if b[to] * side < 0 {
                            if r1 == last {
                                for pf in 4..8 { ms[n] = mk(from, to, pf); n += 1; }
                            } else {
                                ms[n] = mk(from, to, 0); n += 1;
                            }
                        }
                        // en passant
                        if to == ep && ep >= 0 {
                            ms[n] = mk(from, to, 3); n += 1;
                        }
                    }
                    dfi += 1;
                }
            }
        } else if p == 2 || p == 6 {
            // knight / king single-step
            let df: [i64; 16] = [1, 2, 2, 1, -1, -2, -2, -1, 1, 1, 1, 0, 0, -1, -1, -1];
            let dr: [i64; 16] = [2, 1, -1, -2, -2, -1, 1, 2, 1, 0, -1, 1, -1, 1, 0, -1];
            let base = (p - 2) * 2; // knight -> 0, king -> 8
            for i in 0..8 {
                let nf = f + df[base + i];
                let nr = r + dr[base + i];
                if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    if b[nr * 8 + nf] * side <= 0 {
                        ms[n] = mk(from, nr * 8 + nf, 0); n += 1;
                    }
                }
            }
            if p == 6 {
                // castling: squares between must be empty; king path not attacked.
                // rights bits: white 1(K)/2(Q) on rank 0, black 4(K)/8(Q) on rank 7.
                let kbit = 1 + (1 - side) * 1; // side=1 -> 1, side=-1 -> ... computed below
                // compute per-side bits explicitly to avoid arithmetic ambiguity
                let mut wk = 1; let mut wq = 2; let mut home = 4;
                if side < 0 { wk = 4; wq = 8; home = 60; }
                // kingside
                if (castle % (wk * 2)) / wk == 1 {
                    if b[home + 1] == 0 && b[home + 2] == 0 {
                        if is_attacked(b, home, 0 - side) == 0 &&
                           is_attacked(b, home + 1, 0 - side) == 0 &&
                           is_attacked(b, home + 2, 0 - side) == 0 {
                            ms[n] = mk(home, home + 2, 2); n += 1;
                        }
                    }
                }
                // queenside
                if (castle % (wq * 2)) / wq == 1 {
                    if b[home - 1] == 0 && b[home - 2] == 0 && b[home - 3] == 0 {
                        if is_attacked(b, home, 0 - side) == 0 &&
                           is_attacked(b, home - 1, 0 - side) == 0 &&
                           is_attacked(b, home - 2, 0 - side) == 0 {
                            ms[n] = mk(home, home - 2, 2); n += 1;
                        }
                    }
                }
                let _ = kbit;
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

// castling-rights update: clear bits when king/rook squares are touched.
fn upd_castle(castle: i64, sq: i64) -> i64 {
    let mut c = castle;
    if sq == 4  { if (c % 2) == 1 { c -= 1; } if (c % 4) / 2 == 1 { c -= 2; } } // white king
    if sq == 60 { if (c % 8) / 4 == 1 { c -= 4; } if (c % 16) / 8 == 1 { c -= 8; } } // black king
    if sq == 7  { if (c % 2) == 1 { c -= 1; } }   // white kingside rook (h1)
    if sq == 0  { if (c % 4) / 2 == 1 { c -= 2; } } // white queenside rook (a1)
    if sq == 63 { if (c % 8) / 4 == 1 { c -= 4; } } // black kingside rook (h8)
    if sq == 56 { if (c % 16) / 8 == 1 { c -= 8; } } // black queenside rook (a8)
    return c;
}

fn perft(b: &[i64], side: i64, ep: i64, castle: i64, depth: i64) -> i64 {
    if depth == 0 { return 1; }
    let mut mv: [i64; 256] = [0; 256];
    let ms = &mv[0..256];
    let n = gen_moves(b, side, ep, castle, ms);
    let mut nodes = 0;
    for i in 0..n {
        let m = ms[i];
        let from = m % 64;
        let to = (m / 64) % 64;
        let flags = m / 4096;

        let moved = b[from];
        let captured = b[to];
        // make
        b[to] = moved;
        b[from] = 0;
        let mut ep_cap_sq = -1;
        let mut ep_cap_pc = 0;
        if flags == 3 {
            // en passant: captured pawn sits on the mover's own rank, `to` file
            ep_cap_sq = rank_of(from) * 8 + file_of(to);
            ep_cap_pc = b[ep_cap_sq];
            b[ep_cap_sq] = 0;
        }
        if flags >= 4 {
            // promotion: N2 B3 R4 Q5  == flags-2
            b[to] = side * (flags - 2);
        }
        let mut rook_from = -1;
        let mut rook_to = -1;
        if flags == 2 {
            // castle: move the rook too
            if to > from { rook_from = from + 3; rook_to = from + 1; } // kingside
            else { rook_from = from - 4; rook_to = from - 1; }        // queenside
            b[rook_to] = b[rook_from];
            b[rook_from] = 0;
        }

        // new ep target: only after a double push
        let mut nep = -1;
        if flags == 1 { nep = (from + to) / 2; }
        // update castling rights
        let mut nc = upd_castle(castle, from);
        nc = upd_castle(nc, to);

        if is_attacked(b, king_sq(b, side), 0 - side) == 0 {
            nodes += perft(b, 0 - side, nep, nc, depth - 1);
        }

        // unmake
        if flags == 2 {
            b[rook_from] = b[rook_to];
            b[rook_to] = 0;
        }
        if flags == 3 {
            b[ep_cap_sq] = ep_cap_pc;
        }
        b[from] = moved;
        b[to] = captured;
    }
    return nodes;
}

fn main() -> i32 {
    let mut board: [i64; 64] = [0; 64];
    let b = &board[0..64];
    let back: [i64; 8] = [4, 2, 3, 5, 6, 3, 2, 4];
    for f in 0..8 {
        b[f] = back[f];
        b[8 + f] = 1;
        b[48 + f] = -1;
        b[56 + f] = 0 - back[f];
    }
    // start position, full castling rights, no ep
    println!("perft1 {}", perft(b, 1, -1, 15, 1));
    println!("perft2 {}", perft(b, 1, -1, 15, 2));
    println!("perft3 {}", perft(b, 1, -1, 15, 3));
    println!("perft4 {}", perft(b, 1, -1, 15, 4));
    println!("perft5 {}", perft(b, 1, -1, 15, 5));

    // Promotion-heavy CPW position 5 to exercise promotions/underpromotions,
    // which never occur this shallow from the start position:
    //   n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - -
    //   perft(1)=24  perft(2)=496  perft(3)=9483
    // (black to move; white pawns on the 7th and black pawns on the 2nd both
    // promote next move.)
    let mut pb: [i64; 64] = [0; 64];
    let p = &pb[0..64];
    p[56] = -2; p[58] = -2;                       // n1n..... (rank 8)
    p[48] = 1; p[49] = 1; p[50] = 1; p[51] = -6;  // PPPk.... (rank 7)
    p[12] = 6; p[13] = -1; p[14] = -1; p[15] = -1; // ....Kppp (rank 2)
    p[5] = 2; p[7] = 2;                            // .....N.N (rank 1)
    println!("promo1 {}", perft(p, -1, -1, 0, 1));
    println!("promo2 {}", perft(p, -1, -1, 0, 2));
    println!("promo3 {}", perft(p, -1, -1, 0, 3));
    return 0;
}
