// Tuple structs (chess-corpus rung): declaration, Name(args) constructor
// in let position, .N field access. Two field-bearing structs with the SMALLER
// one declared FIRST exercises bug-uclass-field-window-stale-base (fixed): the
// second struct's field window must re-base to the tail, not overlap the first.
struct Square(u8);
struct Pair(i64, i64);
fn main() -> i32 {
    let s = Square(7);
    let p = Pair(300, 44);
    println!("a {} b {} s {}", p.0, p.1, s.0);
    return 0;
}
