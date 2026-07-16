// feature-zig-frontend, real-load bug-probe: a full-legality chess perft in
// Zig, mirroring the Rust corpus port. Exercises the freshly-added Zig
// capabilities under a realistic workload — []i64 slice params (movegen writes
// the move list through a slice), 5-parameter internal calls + recursion (r8
// register spill), array literals for the offset tables, and deep nested
// control flow. Signed-i64 mailbox; moves packed into one i64
// (from | to<<6 | flags<<12); castling bitmask + ep threaded by value.
// Node counts match the standard reference:
//   startpos perft(4) = 197281
//   Kiwipete perft(3) = 97862
const std = @import("std");

fn file_of(sq: i64) i64 { return sq - (sq / 8) * 8; }
fn rank_of(sq: i64) i64 { return sq / 8; }
fn mk(from: i64, to: i64, flags: i64) i64 { return from + to * 64 + flags * 4096; }

fn is_attacked(b: []i64, sq: i64, side: i64) i64 {
    const f = file_of(sq);
    const r = rank_of(sq);
    const pr = r - side;
    if (pr >= 0 and pr < 8) {
        if (f > 0) {
            if (b[pr * 8 + f - 1] == side) { return 1; }
        }
        if (f < 7) {
            if (b[pr * 8 + f + 1] == side) { return 1; }
        }
    }
    const ndf = [8]i64{ 1, 2, 2, 1, -1, -2, -2, -1 };
    const ndr = [8]i64{ 2, 1, -1, -2, -2, -1, 1, 2 };
    var i: i64 = 0;
    while (i < 8) : (i += 1) {
        const nf = f + ndf[i];
        const nr = r + ndr[i];
        if (nf >= 0 and nf < 8 and nr >= 0 and nr < 8) {
            if (b[nr * 8 + nf] == side * 2) { return 1; }
        }
    }
    const kdf = [8]i64{ 1, 1, 1, 0, 0, -1, -1, -1 };
    const kdr = [8]i64{ 1, 0, -1, 1, -1, 1, 0, -1 };
    i = 0;
    while (i < 8) : (i += 1) {
        const nf = f + kdf[i];
        const nr = r + kdr[i];
        if (nf >= 0 and nf < 8 and nr >= 0 and nr < 8) {
            if (b[nr * 8 + nf] == side * 6) { return 1; }
        }
    }
    const bdf = [4]i64{ 1, 1, -1, -1 };
    const bdr = [4]i64{ 1, -1, 1, -1 };
    i = 0;
    while (i < 4) : (i += 1) {
        var nf = f + bdf[i];
        var nr = r + bdr[i];
        while (nf >= 0 and nf < 8 and nr >= 0 and nr < 8) {
            const p = b[nr * 8 + nf];
            if (p != 0) {
                if (p == side * 3 or p == side * 5) { return 1; }
                nf = -100;
            } else {
                nf += bdf[i];
                nr += bdr[i];
            }
        }
    }
    const rdf = [4]i64{ 1, -1, 0, 0 };
    const rdr = [4]i64{ 0, 0, 1, -1 };
    i = 0;
    while (i < 4) : (i += 1) {
        var nf = f + rdf[i];
        var nr = r + rdr[i];
        while (nf >= 0 and nf < 8 and nr >= 0 and nr < 8) {
            const p = b[nr * 8 + nf];
            if (p != 0) {
                if (p == side * 4 or p == side * 5) { return 1; }
                nf = -100;
            } else {
                nf += rdf[i];
                nr += rdr[i];
            }
        }
    }
    return 0;
}

fn king_sq(b: []i64, side: i64) i64 {
    var s: i64 = 0;
    while (s < 64) : (s += 1) {
        if (b[s] == side * 6) { return s; }
    }
    return -1;
}

fn gen_moves(b: []i64, side: i64, ep: i64, castle: i64, ms: []i64) i64 {
    var n: i64 = 0;
    var from: i64 = 0;
    while (from < 64) : (from += 1) {
        const p = b[from] * side;
        if (p > 0) {
            const f = file_of(from);
            const r = rank_of(from);
            if (p == 1) {
                const r1 = r + side;
                const last = 7 * (1 + side) / 2;
                if (r1 >= 0 and r1 < 8) {
                    if (b[r1 * 8 + f] == 0) {
                        const to = r1 * 8 + f;
                        if (r1 == last) {
                            var pf: i64 = 4;
                            while (pf < 8) : (pf += 1) { ms[n] = mk(from, to, pf); n += 1; }
                        } else {
                            ms[n] = mk(from, to, 0); n += 1;
                            const start = (7 - 5 * side) / 2;
                            if (r == start) {
                                const r2 = r + side + side;
                                if (b[r2 * 8 + f] == 0) { ms[n] = mk(from, r2 * 8 + f, 1); n += 1; }
                            }
                        }
                    }
                    var dfi: i64 = 0;
                    while (dfi < 2) : (dfi += 1) {
                        const cf = f - 1 + dfi * 2;
                        if (cf >= 0 and cf < 8) {
                            const to = r1 * 8 + cf;
                            if (b[to] * side < 0) {
                                if (r1 == last) {
                                    var pf: i64 = 4;
                                    while (pf < 8) : (pf += 1) { ms[n] = mk(from, to, pf); n += 1; }
                                } else { ms[n] = mk(from, to, 0); n += 1; }
                            }
                            if (to == ep and ep >= 0) { ms[n] = mk(from, to, 3); n += 1; }
                        }
                    }
                }
            } else if (p == 2 or p == 6) {
                const df = [16]i64{ 1, 2, 2, 1, -1, -2, -2, -1, 1, 1, 1, 0, 0, -1, -1, -1 };
                const dr = [16]i64{ 2, 1, -1, -2, -2, -1, 1, 2, 1, 0, -1, 1, -1, 1, 0, -1 };
                const base = (p - 2) * 2;
                var i: i64 = 0;
                while (i < 8) : (i += 1) {
                    const nf = f + df[base + i];
                    const nr = r + dr[base + i];
                    if (nf >= 0 and nf < 8 and nr >= 0 and nr < 8) {
                        if (b[nr * 8 + nf] * side <= 0) { ms[n] = mk(from, nr * 8 + nf, 0); n += 1; }
                    }
                }
                if (p == 6) {
                    var wk: i64 = 1;
                    var wq: i64 = 2;
                    var home: i64 = 4;
                    if (side < 0) { wk = 4; wq = 8; home = 60; }
                    if (castle - (castle / (wk * 2)) * (wk * 2) >= wk) {
                        if (b[home + 1] == 0 and b[home + 2] == 0) {
                            if (is_attacked(b, home, 0 - side) == 0 and
                                is_attacked(b, home + 1, 0 - side) == 0 and
                                is_attacked(b, home + 2, 0 - side) == 0) {
                                ms[n] = mk(home, home + 2, 2); n += 1;
                            }
                        }
                    }
                    if (castle - (castle / (wq * 2)) * (wq * 2) >= wq) {
                        if (b[home - 1] == 0 and b[home - 2] == 0 and b[home - 3] == 0) {
                            if (is_attacked(b, home, 0 - side) == 0 and
                                is_attacked(b, home - 1, 0 - side) == 0 and
                                is_attacked(b, home - 2, 0 - side) == 0) {
                                ms[n] = mk(home, home - 2, 2); n += 1;
                            }
                        }
                    }
                }
            } else {
                const df = [8]i64{ 1, 1, -1, -1, 1, -1, 0, 0 };
                const dr = [8]i64{ 1, -1, 1, -1, 0, 0, 1, -1 };
                var d0: i64 = 0;
                var d1: i64 = 8;
                if (p == 3) { d1 = 4; }
                if (p == 4) { d0 = 4; }
                var d: i64 = d0;
                while (d < d1) : (d += 1) {
                    var nf = f + df[d];
                    var nr = r + dr[d];
                    while (nf >= 0 and nf < 8 and nr >= 0 and nr < 8) {
                        const t = b[nr * 8 + nf] * side;
                        if (t > 0) { nf = -100; } else {
                            ms[n] = mk(from, nr * 8 + nf, 0); n += 1;
                            if (t < 0) { nf = -100; } else { nf += df[d]; nr += dr[d]; }
                        }
                    }
                }
            }
        }
    }
    return n;
}

fn upd_castle(castle: i64, sq: i64) i64 {
    var c = castle;
    if (sq == 4)  { if (c - (c / 2) * 2 == 1) { c -= 1; } if (c - (c / 4) * 4 >= 2) { c -= 2; } }
    if (sq == 60) { if (c - (c / 8) * 8 >= 4) { c -= 4; } if (c - (c / 16) * 16 >= 8) { c -= 8; } }
    if (sq == 7)  { if (c - (c / 2) * 2 == 1) { c -= 1; } }
    if (sq == 0)  { if (c - (c / 4) * 4 >= 2) { c -= 2; } }
    if (sq == 63) { if (c - (c / 8) * 8 >= 4) { c -= 4; } }
    if (sq == 56) { if (c - (c / 16) * 16 >= 8) { c -= 8; } }
    return c;
}

fn perft(b: []i64, side: i64, ep: i64, castle: i64, depth: i64) i64 {
    if (depth == 0) { return 1; }
    var mv: [256]i64 = undefined;
    const ms = mv[0..256];
    const n = gen_moves(b, side, ep, castle, ms);
    var nodes: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        const m = ms[i];
        const from = m - (m / 64) * 64;
        const to = (m / 64) - (m / 4096) * 64;
        const flags = m / 4096;
        const moved = b[from];
        const captured = b[to];
        b[to] = moved;
        b[from] = 0;
        var ep_cap_sq: i64 = -1;
        var ep_cap_pc: i64 = 0;
        if (flags == 3) {
            ep_cap_sq = rank_of(from) * 8 + file_of(to);
            ep_cap_pc = b[ep_cap_sq];
            b[ep_cap_sq] = 0;
        }
        if (flags >= 4) { b[to] = side * (flags - 2); }
        var rook_from: i64 = -1;
        var rook_to: i64 = -1;
        if (flags == 2) {
            if (to > from) { rook_from = from + 3; rook_to = from + 1; }
            else { rook_from = from - 4; rook_to = from - 1; }
            b[rook_to] = b[rook_from];
            b[rook_from] = 0;
        }
        var nep: i64 = -1;
        if (flags == 1) { nep = (from + to) / 2; }
        var nc = upd_castle(castle, from);
        nc = upd_castle(nc, to);
        if (is_attacked(b, king_sq(b, side), 0 - side) == 0) {
            nodes += perft(b, 0 - side, nep, nc, depth - 1);
        }
        if (flags == 2) { b[rook_from] = b[rook_to]; b[rook_to] = 0; }
        if (flags == 3) { b[ep_cap_sq] = ep_cap_pc; }
        b[from] = moved;
        b[to] = captured;
    }
    return nodes;
}

pub fn main() void {
    var board: [64]i64 = undefined;
    var i: i64 = 0;
    while (i < 64) : (i += 1) { board[i] = 0; }
    const back = [8]i64{ 4, 2, 3, 5, 6, 3, 2, 4 };
    var f: i64 = 0;
    while (f < 8) : (f += 1) {
        board[f] = back[f];
        board[8 + f] = 1;
        board[48 + f] = -1;
        board[56 + f] = 0 - back[f];
    }
    const b = board[0..64];
    std.debug.print("perft4 {}\n", .{perft(b, 1, -1, 15, 4)});

    // Kiwipete
    var kb: [64]i64 = undefined;
    i = 0;
    while (i < 64) : (i += 1) { kb[i] = 0; }
    const k = kb[0..64];
    k[56] = -4; k[60] = -6; k[63] = -4;
    k[48] = -1; k[50] = -1; k[51] = -1; k[52] = -5; k[53] = -1; k[54] = -3;
    k[40] = -3; k[41] = -2; k[44] = -1; k[45] = -2; k[46] = -1;
    k[35] = 1; k[36] = 2;
    k[25] = -1; k[28] = 1;
    k[18] = 2; k[21] = 5; k[23] = -1;
    k[8] = 1; k[9] = 1; k[10] = 1; k[11] = 3; k[12] = 3; k[13] = 1; k[14] = 1; k[15] = 1;
    k[0] = 4; k[4] = 6; k[7] = 4;
    std.debug.print("kiwi3 {}\n", .{perft(k, 1, -1, 15, 3)});
}
