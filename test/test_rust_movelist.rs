// Rust frontend: an ArrayVec-shaped fixed-capacity vector of structs.
//
// The rung this exercises is `[Name { .. }; N]` -- a repeat-array literal whose
// element is a STRUCT literal, both as a `let` initializer and as a struct
// field initializer. Everything else here (array-of-struct fields, `&mut self`
// stores through `self.data[self.len]`, whole-record copies between slots)
// already worked; the missing piece was the one form that makes `MoveList::new`
// expressible as valid Rust instead of an uninitialised `let mut`.

struct Move {
    from: i64,
    to: i64,
    flags: i64,
}

struct MoveList {
    data: [Move; 16],
    len: i64,
}

impl MoveList {
    fn new() -> MoveList {
        MoveList {
            data: [Move { from: -1, to: -1, flags: 0 }; 16],
            len: 0,
        }
    }

    fn push(&mut self, f: i64, t: i64, fl: i64) {
        self.data[self.len].from = f;
        self.data[self.len].to = t;
        self.data[self.len].flags = fl;
        self.len += 1;
    }

    fn get(&self, i: i64) -> Move {
        self.data[i]
    }

    fn len(&self) -> i64 {
        self.len
    }

    fn clear(&mut self) {
        self.len = 0;
    }

    // Sum of every to-square, to prove iteration over the live prefix only.
    fn sum_to(&self) -> i64 {
        let mut s: i64 = 0;
        let mut i: i64 = 0;
        while i < self.len {
            s += self.data[i].to;
            i += 1;
        }
        s
    }

    // Swap two slots -- two whole-record copies through a temporary, which is
    // the shape a move-ordering pass needs.
    fn swap(&mut self, i: i64, j: i64) {
        let t: Move = self.data[i];
        self.data[i] = self.data[j];
        self.data[j] = t;
    }
}

fn fill(ml: &mut MoveList, base: i64, n: i64) {
    let mut i: i64 = 0;
    while i < n {
        ml.push(base + i, base + i * 2, i);
        i += 1;
    }
}

fn main() {
    // let-level repeat, annotated.
    let a: [Move; 4] = [Move { from: 7, to: 8, flags: 1 }; 4];
    println!("a {} {} {} {}", a[0].from, a[3].to, a[2].flags, a[1].from);

    // let-level repeat, length inferred from the repeat count.
    let b = [Move { from: 2, to: 3, flags: 0 }; 3];
    println!("b {} {}", b[0].from, b[2].to);

    // field-level repeat, through the constructor.
    let mut ml: MoveList = MoveList::new();
    println!("fresh {} {} {}", ml.len(), ml.data[0].from, ml.data[15].to);

    ml.push(12, 28, 0);
    ml.push(6, 21, 4);
    let m: Move = ml.get(1);
    println!("push {} {} {} {}", ml.len(), ml.data[0].from, m.from, m.flags);

    ml.swap(0, 1);
    let s0: Move = ml.get(0);
    let s1: Move = ml.get(1);
    println!("swap {} {}", s0.from, s1.from);

    ml.clear();
    fill(&mut ml, 10, 5);
    let f0: Move = ml.get(0);
    let f4: Move = ml.get(4);
    println!("fill {} {} {} {}", ml.len(), f0.to, f4.to, ml.sum_to());

    // The tail beyond len is still the constructor's fill value, untouched.
    println!("tail {} {}", ml.data[5].from, ml.data[15].flags);

    // A second list is independent of the first.
    let mut m2: MoveList = MoveList::new();
    m2.push(1, 2, 3);
    let g1: Move = ml.get(0);
    let g2: Move = m2.get(0);
    println!("two {} {} {} {}", ml.len(), m2.len(), g1.from, g2.from);
}
