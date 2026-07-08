// Tuple structs (chess-corpus rung): declaration, Name(args) constructor
// in let position, .N field access. ONE struct only: two field-bearing
// structs trip bug-uclass-field-window-stale-base (Track A, filed) —
// extend this test to two structs when that lands.
struct Pair(i64, i64);
fn main() -> i32 {
    let p = Pair(300, 44);
    println!("a {} b {}", p.0, p.1);
    return 0;
}
