// Associated fns (no self) + Self resolution (chess-corpus rung):
// Type::fn(args) and Self::fn(args) call paths, mixed with &self methods.
struct Counter { n: i64 }

impl Counter {
    fn scale() -> i64 {
        return 7;
    }
    fn combine(a: i64, b: i64) -> i64 {
        return a * Self::scale() + b;
    }
    fn value(&self) -> i64 {
        return self.n * Counter::scale();
    }
}

fn main() -> i32 {
    let c = Counter { n: 6 };
    println!("v {} comb {}", c.value(), Counter::combine(10, 5));
    return 0;
}
