// Rust `Result<T, E>` and the `?` try operator -- the rung after the unity
// build on feature-rust-corpus-chess's gap list.
//
// Result is monomorphized onto the same enum machinery Option uses: one
// auto-registered UClass per concrete (T, E), `__tag` at 0 and `Ok.0`/`Err.0`
// overlapping past it. That is what a tagged union IS, so match/return/field
// access all fall out with no Result-specific code anywhere downstream.
//
// `?` desugars to exactly what the reference says it means --
// `match e { Ok(v) => v, Err(e) => return Err(e) }` -- but two of those three
// pieces cannot live in an expression node: the operand must be materialized,
// and the Err arm RETURNS. So the statement half is hoisted and flushed by
// RParseStatement, and only `temp.Ok.0` is the expression's value.
//
// THE RECORD-PAYLOAD CASE IS THE POINT OF `place` AND `pick`. A monomorphized
// payload occupies its own full size, and for a record that is RecSize --
// TypeSize(tyRecord) answers 8, a pointer, and says so in its own comment.
// Option had this wrong since it was written and got away with it because
// Option<Square> is exactly 8 bytes. Option<Big> SEGFAULTED on master, and
// Result<Pos, i64> read `Pos { file: 4, rank: 2 }` back as `4 0`. Both are
// pinned here; neither failed loudly.

struct Pos { file: i64, rank: i64 }
struct Big { a: i64, b: i64, c: i64, d: i64 }

fn parse(n: i64) -> Result<i64, i64> {
    if n < 0 { return Err(7); }
    return Ok(n * 2);
}

fn chain(n: i64) -> Result<i64, i64> {
    let v = parse(n)?;
    return Ok(v + 1);
}

// two `?` in one expression: the second must not run once the first returns
fn twice(a: i64, b: i64) -> Result<i64, i64> {
    let s = parse(a)? + parse(b)?;
    return Ok(s);
}

// `?` under an implicit tail return
fn tail(n: i64) -> Result<i64, i64> {
    let v = parse(n)?;
    Ok(v * 10)
}

// Ok payload is a STRUCT larger than a word
fn place(n: i64) -> Result<Pos, i64> {
    if n < 0 { return Err(3); }
    let p = Pos { file: n % 8, rank: n / 8 };
    return Ok(p);
}

// the Option arm of the same sizing bug: Big is 32 bytes
fn pick(n: i64) -> Option<Big> {
    if n < 0 { return None; }
    let g = Big { a: n, b: n + 1, c: n + 2, d: n + 3 };
    return Some(g);
}

fn show(tag: i64, r: Result<i64, i64>) {
    match r {
        Ok(v) => println!("{} ok {}", tag, v),
        Err(e) => println!("{} err {}", tag, e),
    }
}

fn main() {
    show(1, chain(5));
    show(2, chain(-1));
    show(3, twice(3, 4));
    show(4, twice(3, -1));
    show(5, tail(6));
    show(6, tail(-2));

    let q: Result<Pos, i64> = place(20);
    match q {
        Ok(p) => println!("pos {} {}", p.file, p.rank),
        Err(e) => println!("pos err {}", e),
    }
    let z: Result<Pos, i64> = place(-1);
    match z {
        Ok(p) => println!("pos {} {}", p.file, p.rank),
        Err(e) => println!("pos err {}", e),
    }

    let x: Option<Big> = pick(10);
    match x {
        Some(g) => println!("big {} {} {} {}", g.a, g.b, g.c, g.d),
        None => println!("big none"),
    }
    let y: Option<Big> = pick(-1);
    if y.is_none() { println!("big none"); }
}
