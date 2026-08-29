// Rust strings: `String`, `&str`, `format!`, and the methods real source
// reaches for. Both types map to pxx's managed AnsiString -- see
// devdocs/dev/rust-semantics-divergences.md for why one representation is
// enough (the difference is only observable through aliasing that rustc's
// borrow checker refuses to compile).
//
// The oracle below is hand-computed, not recorded from a run. Two of the
// three bugs this window produced a PLAUSIBLE wrong value rather than a
// crash, and a recorded expectation would have locked either of them in.
//
// `square_name` is the corpus shape this rung exists for: the chess engine
// formats UCI moves, and until now it did that by printing bytes one at a
// time because it had no string to build.

struct Move { from: i64, to: i64 }

fn square_name(sq: i64) -> String {
    let mut s: String = String::new();
    s.push(((97 + (sq % 8)) as u8) as char);
    s.push(((49 + (sq / 8)) as u8) as char);
    return s;
}

impl Move {
    fn uci(&self) -> String {
        return square_name(self.from) + &square_name(self.to);
    }
}

fn shout(who: &str) -> String {
    return format!("hello, {}!", who);
}

fn main() {
    let e: String = String::new();
    println!("empty [{}] len {} isempty {}", e, e.len(), e.is_empty());

    let a: String = String::from("abc");
    let b: String = String::from("de");
    let cat: String = a.clone() + &b;
    println!("cat {} len {} isempty {}", cat, cat.len(), cat.is_empty());

    println!("eq {} ne {} lit {}", a == "abc", a != "abc", "abc".len());

    // push_str/push are the same append on one representation; both are
    // ()-valued in Rust, so they only ever appear in statement position.
    let mut acc: String = String::new();
    acc.push_str("uci");
    acc.push(':');
    acc.push_str(" go");
    println!("acc [{}] len {}", acc, acc.len());

    println!("sq {} {} {}", square_name(0), square_name(63), square_name(27));

    let m: Move = Move { from: 12, to: 28 };
    println!("uci {}", m.uci());

    println!("{}", shout("world"));

    // every argument kind format! converts: string, int, negative int, bool,
    // char. A char literal is a tkInteger carrying `char` in the suffix
    // channel -- without that it renders as its code point.
    println!("fmt {}", format!("i={} n={} b={} s={} c={}", 42, -7, true, "mid", 'x'));

    // the two degenerate formats: no placeholders and no text at all
    println!("degen [{}] [{}]", format!(""), format!("just text"));

    let n: i64 = 1234;
    println!("chain {} {}", format!("ab{}", 7).len(), n.to_string());

    let big: String = format!("{}{}{}{}", square_name(0), "-", square_name(63), 99);
    println!("big {} len {}", big, big.len());
}
