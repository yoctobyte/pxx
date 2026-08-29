// bug-a-allocarray-leaves-recname-stale-on-a-recycled-symbol-slot
//
// AllocArray/AllocDynArray write ElemRecName and never RecName, and symbol
// slots are RECYCLED when a proc body restores SymCount. So an array symbol
// that lands on a slot last used by a by-value record PARAM (AllocVar and
// AllocParam are the only allocators that write RecName) inherits that
// param's record id in a field that is meaningless for an array.
//
// Rust reads it in RIsSliceSym, which is guarded by `TypeKind = tyRecord`
// and nothing else -- and an array-of-record symbol HAS tyRecord, because
// that field holds the ELEMENT kind. So the stale id made `cells` look like
// a &[T] slice header and `cells[0].id` took the slice path:
//
//     error: unexpected token  near: cells >>> id
//
// The shape is load-bearing and was found by sweeping it: `sum` needs TWO
// params and `cells` must be main's FIRST local, or the recycled slot does
// not line up and nothing happens. Same alignment as the C _Generic probe in
// test_c_recname_recycled_slot.c, which is the SILENT face of this one bug --
// that one compiles and prints the wrong answer, this one refuses to parse.

struct Cell { id: i64 }

fn sum(s: &[i64], k: i64) -> i64 {
    let mut t: i64 = k;
    let mut i: i64 = 0;
    while i < s.len() { t += s[i]; i += 1; }
    t
}

fn main() -> i32 {
    let mut cells: [Cell; 4];
    cells[0].id = 5;
    cells[1].id = 6;
    let raw: [i64; 3] = [1, 2, 3];
    // 100 + 1+2+3 = 106, and 5 + 6 = 11.
    println!("{} {}", sum(&raw, 100), cells[0].id + cells[1].id);
    0
}
