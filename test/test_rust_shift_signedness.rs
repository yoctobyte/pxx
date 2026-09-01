//! Rust `>>` is ARITHMETIC on a signed operand and LOGICAL on an unsigned one,
//! and until 2026-09-01 no Rust test exercised `>>` at all. That gap is the
//! reason this file exists rather than one more row somewhere else.
//!
//! The IR's logical-shift-right operator was renamed from the Ord(tkIdent)
//! sentinel to tkShrLogical (314481dd7). The rename updated 25 sites across the
//! C, Pascal and Python frontends and all seven backends, and MISSED the three
//! in rparser.inc -- so every unsigned `>>` in a Rust program built a node no
//! backend handles and died on `Unsupported operator in IR codegen`, pointing
//! at whatever source line the node happened to carry.
//!
//! The rename's acceptance was byte-identity of emitted output on seven targets
//! at -O0..-O4. That is a strong check and it could not see this: a frontend
//! whose output is not in the corpus emits no bytes to compare. The gap was not
//! in the checking, it was in the population.
//!
//! Every number below is computed by hand, not recorded from a run. The rows
//! that matter are the UNSIGNED ones: if the operator regresses to arithmetic,
//! `u64` row 1 reads -4 instead of 9223372036854775804 and `u32` row 3 reads -4
//! instead of 2147483644. A signed-only test cannot fail that way.
//! bug-a-shr-reaches-the-ir-spelled-as-tkident

fn shr_var_u64(b: u64, n: i64) -> u64 { return b >> n; }
fn shr_var_i64(b: i64, n: i64) -> i64 { return b >> n; }

fn main() {
    // 0xFFFFFFFFFFFFFFF8 >> 1, zero shifted in => 0x7FFFFFFFFFFFFFFC
    let bu: u64 = 18446744073709551608;
    println!("u64 {} {}", bu >> 1, shr_var_u64(bu, 1));

    // -8 >> 1, sign shifted in => -4
    let bs: i64 = -8;
    println!("i64 {} {}", bs >> 1, shr_var_i64(bs, 1));

    // narrow unsigned: the zero must arrive at bit 31, not the sign
    // 0xFFFFFFF8 >> 1 => 0x7FFFFFFC
    let b32: u32 = 4294967288;
    let s32: i32 = -8;
    println!("32 {} {}", b32 >> 1, s32 >> 1);

    // u8 200 = 0xC8 >> 1 => 0x64
    let b8: u8 = 200;
    println!("u8 {}", b8 >> 1);

    // usize follows u64
    let bz: usize = 18446744073709551608;
    println!("usize {}", bz >> 1);

    // the compound forms take a SEPARATE path in rparser (two more sites), so
    // they are asserted separately rather than assumed to follow `>>`
    let mut cu: u64 = 18446744073709551608;
    cu >>= 1;
    let mut cs: i64 = -8;
    cs >>= 1;
    println!("shreq {} {}", cu, cs);

    // `<<` was never affected -- it is here as the control that says the test
    // is looking at the right operator
    let l: u64 = 8;
    println!("shl {}", l << 2);
}
