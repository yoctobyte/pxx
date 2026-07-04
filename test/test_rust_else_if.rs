// Regression: bug-selfhost-multifn-ifelse-miscompile.
// A 3-function Rust program where one function is an if/else-if/else chain with
// a return per branch, plus another declared function, plus a call site — the
// exact shape that self-hosted pascal26 once miscompiled (rparser lowered the
// `else if` to a dead IR_UNSUPPORTED node, which a PXX-built compiler emitted as
// a spurious "return n" block at the else-label; FPC-built emitted nothing).
// classify(1) must return 20; the whole program must exit 20.
// Fixed by rparser.inc `elseNode := RParseIf()` (parens force the recursive
// call, not the own-name Result pseudo-var). The --strict-ir guard is the
// general safety net that would have caught the dead IR_UNSUPPORTED at compile
// time. Runs identically FPC-built and self-hosted (byte-identical fixedpoint).
fn f1(a: i32) -> i32 {
    return a;
}
fn classify(n: i32) -> i32 {
    if n == 0 {
        return 10;
    } else if n == 1 {
        return 20;
    } else {
        return 30;
    }
}
fn main() -> i32 {
    let mut total = 0;
    total = total + classify(1);
    return total;
}
