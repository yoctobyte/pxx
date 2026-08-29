// Rust spells its booleans `true` / `false`; the shared writer spells a
// tyBoolean in Pascal's `TRUE` / `FALSE`. Both spellings are correct for their
// own language, so the Rust frontend splits a bool argument into a branch
// between two literal writes rather than teaching the writer a second dialect.
//
// The cases here are the ones that lowering can get wrong: a bool as the LAST
// placeholder (the trailing text is empty, and the newline must survive), two
// adjacent bools with no text between them, a bool that is not the only
// argument, and a bool inside `print!` where there is no newline to hide a
// dropped segment.

struct Sq { v: i64 }

impl Sq {
    fn big(&self) -> bool { self.v > 10 }
}

fn is_even(n: i64) -> bool { n % 2 == 0 }

fn main() {
    let t: bool = true;
    let f: bool = false;

    println!("pair {} {}", t, f);
    println!("{}", is_even(4));
    println!("{}", is_even(7));
    println!("lead {} mid {} tail", is_even(3), 7);
    println!("{}{}", t, f);
    println!("end {}", t);
    println!("{} start", f);

    let s = Sq { v: 12 };
    let small = Sq { v: 2 };
    println!("m {} {}", s.big(), small.big());
    println!("cmp {} {}", s.v > 100, s.v == 12);
    println!("not {}", !t);

    print!("p {} ", f);
    println!("q {}", t);

    println!("plain {} unchanged", 42);
}
