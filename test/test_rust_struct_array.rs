// feature-rust-corpus-chess enabler: fixed arrays of a struct/tuple-struct
// type with per-element field access (`arr[i].field` read and write, and
// tuple `arr[i].0`). This is what lets the adapted chess engine hold a move
// list as `[Move; 256]` — the pxx-friendly stand-in for the engine's
// ArrayVec<Move, 256> — using the real Move struct instead of a packed i64.
// Storage + indexing ride the shared array-of-record codegen (ElemRecName,
// resolved by ResolveNodeRec over AN_INDEX); pxx does not enforce Rust's
// definite-init, so the arrays are filled field-wise after an
// annotation-only `let`.

struct Move { from: i64, to: i64, flags: i64 }
struct Sq(i64);

fn main() -> i32 {
    let mut list: [Move; 8];
    let mut n = 0;
    // "generate" a few moves, one field-store at a time (the movegen shape).
    for i in 0..5 {
        list[n].from = i;
        list[n].to = i * 2;
        list[n].flags = i % 2;
        n += 1;
    }
    // read them back through indexed-field reads.
    let mut checksum = 0;
    for i in 0..n {
        checksum += list[i].from * 100 + list[i].to * 10 + list[i].flags;
    }
    // 5 moves: (0,0,0)(1,2,1)(2,4,0)(3,6,1)(4,8,0)
    // = 0 + 121 + 240 + 361 + 480 = 1202
    println!("checksum {}", checksum);

    // tuple-struct array with `.0` element field.
    let mut sqs: [Sq; 3];
    sqs[0].0 = 10;
    sqs[1].0 = 20;
    sqs[2].0 = sqs[0].0 + sqs[1].0;
    println!("sq {}", sqs[2].0);
    return 0;
}
