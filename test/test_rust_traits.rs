// `impl Trait for Type`, and `impl fmt::Display` rerouted to a String method.
//
// THE TRAIT-IMPL PATH HAD NEVER RUN. Both the prescan and the body parser
// tested `GetTokenStr(j+1) = 'for'` against a token the lexer classifies as
// tkFor, whose name slice is empty -- so the comparison was against '' and
// could never be true. Every `impl Trait for Type` in the world was read as
// `impl <Trait>` and died with "impl for unknown type". Dead code that looked
// live, and only trying to EXTEND it found that out.
//
// Display is rerouted rather than dispatched, which is what the corpus ticket
// predicted would be cheaper: `fn fmt(&self, f: &mut Formatter) -> Result` is
// registered as `fn fmt(&self) -> String`, `write!` appends to it, and `{}`
// on the type calls it. No Formatter, no trait objects, no vtable.
//
// Oracle hand-computed.

use std::fmt;

trait Area {
    fn area(&self) -> i64;
}

struct Sq { s: i64 }
struct Rect { w: i64, h: i64 }

impl Area for Sq {
    fn area(&self) -> i64 { return self.s * self.s; }
}

impl Area for Rect {
    fn area(&self) -> i64 { return self.w * self.h; }
}

struct Move { from: i64, to: i64 }

// ONE write!, as a tail expression with no semicolon
impl fmt::Display for Move {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}-{}", self.from, self.to)
    }
}

struct Tag { n: i64, label: String }

// SEVERAL write!s with `?`, then the `Ok(())` every real impl ends with.
// They must accumulate, not overwrite.
impl fmt::Display for Tag {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "[")?;
        write!(f, "{}={}", self.label, self.n)?;
        write!(f, "]")?;
        Ok(())
    }
}

fn main() {
    let q: Sq = Sq { s: 4 };
    let r: Rect = Rect { w: 3, h: 5 };
    println!("area {} {}", q.area(), r.area());

    let m: Move = Move { from: 12, to: 28 };
    println!("mv {}", m);

    // ToString is Rust's blanket impl over Display, so it is the same text
    println!("ts {}", m.to_string());

    // and the value path agrees with the write path
    println!("via {}", format!("<{}>", m));

    let t: Tag = Tag { n: 7, label: String::from("w") };
    println!("tag {}", t);

    // Display and Debug are different traits: `{:?}` still renders field-wise
    println!("dbg {:?}", m);
}
