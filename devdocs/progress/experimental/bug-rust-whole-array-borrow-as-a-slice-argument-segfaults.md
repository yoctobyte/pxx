---
prio: 35
track: R
---
# `f(&arr)` — borrowing a whole array as a `&[T]` argument — compiles and segfaults

Found on 2026-08-29 alongside
`bug-rust-slice-param-fn-erases-mains-record-array-element-type`, but a
different and independent defect.

## Repro

```rust
fn t(b: &[i64]) -> i64 { b[1] }
fn main() {
    let mut v: [i64; 4] = [0; 4];
    v[1] = 7;
    println!("{}", t(&v));        // ok: <bin>  ...  then SIGSEGV
}
```

`&mut v` behaves identically. Prio is above the sibling ticket's because this
one **compiles clean and then crashes** — there is no diagnostic at all, which
is the failure mode this repo treats as the expensive one.

## The three argument forms, measured

| form | result |
| --- | --- |
| `t(&v)` — whole-array borrow | compiles, **segfaults** |
| `t(&v[0..4])` — inline range borrow | `Rust: unexpected token near: t v >>>` |
| `let s = &v[0..4]; t(s)` | works, answers 7 |

Only the third is wired. `&v` is the form real Rust source is written in
(`&v[..]` and `&v` are the same thing to rustc, and the bare `&v` is what an
engine actually writes), so this is the shape a corpus port meets first.

## Cause, as far as measured

A `&[T]` param is the auto-registered two-word `__ptr`/`__len` slice view
(`RSliceClassForRec`, `compiler/rparser.inc`). `&v[lo..hi]` at `let` level has a
dedicated lowering that builds that pair (the "borrowed slice RHS" arm in
`RParseLet`). `&v` in ARGUMENT position has no such arm: the address of the
array is handed over where a slice header is expected, so the callee reads `v[0]`
and `v[1]` as `__ptr` and `__len` and dereferences 0.

## Fix shape (not attempted)

Two arms, both parser-only:
- `&arr` in argument position where the param is a slice: synthesize the same
  `__ptr` = `&arr[0]`, `__len` = the array's declared length pair the `let` arm
  already builds, into a hidden temp.
- `&arr[lo..hi]` in argument position: the same, with the bounds from the range.

Both want the `let`-level implementation factored out and called from the
argument path rather than copied — see
`devdocs/dev/normalise-dont-special-case.md`; this is exactly the double case
that note is about, and today only one arm exists.

Until then the workaround is the third row: bind the slice to a `let` first.
That is what `test/test_rust_chess_engine.rs` does (`let b = &board[0..64];`),
which is why the corpus is green.
