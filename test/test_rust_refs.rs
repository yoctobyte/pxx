// Rust frontend: `&` / `&mut` parameters actually ALIAS the caller.
//
// The frontend used to drop the `&` on a parameter ("records pass by address
// via the record ABI anyway"), which threw away the one bit that decides
// aliasing. ir.inc gives a record parameter that is by-ref only for ABI
// efficiency a private temp copy -- correct for a by-value `p: Board`, wrong
// for a reference -- so `self.side = v` in a method wrote into a temp and the
// caller saw nothing, silently. `&mut self` was not even accepted.
//
// So this file asserts the DISTINCTION, in both directions:
//   `&mut B` / `&mut self` mutate the caller's record;
//   `&B` / `&self` read the caller's record (no stale copy);
//   a by-value `B` / `self` mutates only its own copy, which is what a move
//   means -- and that half is the one a blanket "always alias" fix breaks.
// Compound assignment on a field target (`b.side += v`) rides along: it is
// how real code spells the mutation this test is about.

struct B {
    side: i64,
    sq: [i64; 4],
}

fn bump(b: &mut B, v: i64) {
    b.side += v;
    b.sq[0] = v * 2;
    b.sq[1] += 3;
}

fn peek(b: &B) -> i64 {
    return b.side;
}

fn byval(b: B) -> i64 {
    b.side = 999;
    return b.side;
}

impl B {
    fn setside(&mut self, v: i64) { self.side = v; }
    fn addside(&mut self, v: i64) { self.side += v; }
    fn getside(&self) -> i64 { return self.side; }
    fn ownside(self) -> i64 { self.side = 555; return self.side; }
}

fn main() {
    let mut b: B;
    b.side = 1;
    b.sq[0] = 0;
    b.sq[1] = 10;

    // &mut through a free fn
    bump(b, 4);
    println!("bump {} {} {}", b.side, b.sq[0], b.sq[1]);

    // & reads the caller's record, not a snapshot
    println!("peek {}", peek(b));

    // &mut self / &self
    b.setside(11);
    b.addside(7);
    println!("meth {} {}", b.side, b.getside());

    // by value: the callee mutates its own copy only
    println!("byval {} caller {}", byval(b), b.side);
    println!("own {} caller {}", b.ownside(), b.side);
}
