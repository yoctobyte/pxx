---
prio: 30
track: R
---
# A fn with a slice param and >=2 params erases `main`'s record-array element type

Found on 2026-08-29 while probing the `[Name { .. }; N]` rung (rung 16 of the
Track R ladder). **Pre-existing** — it has nothing to do with that rung: the
narrowest repro declares its array with no initializer at all, a path that rung
did not touch.

## Repro

```rust
struct Move { from: i64, to: i64 }
fn t(b: &[i64], i: i64) { }              // never called; the BODY is irrelevant
fn main() {
    let mut a: [Move; 4];
    a[0].to = 7;                          // Rust: unexpected token  near: a >>> to
    println!("{}", a[0].to);
}
```

Delete `fn t`, or drop it to a single parameter, and it compiles and prints 7.

## What is actually broken

The parse error comes from `RParsePrimary`'s `arr[i].field` arm, whose guard is
`Syms[symIdx].ElemType = tyRecord` (`compiler/rparser.inc`, the "plain
fixed-array indexing" block). So `a` was allocated as an array whose ELEMENT
TYPE is not a record — `RTypeKindFromName('Move')` did not answer `tyRecord` at
`AllocArray` time in `main`, even though `FindUClass('Move')` plainly still
works right next to it.

Note the failure MODE changes with the element type, and the second one is the
dangerous half:

| element type of the array in `main` | symptom |
| --- | --- |
| a struct (`[Move; 4]`) | parse error on `.field` — loud, harmless |
| the same struct when the slice param is `&[Move]` | **compiles, then segfaults** |

## The probe matrix (all measured, not reasoned)

Program shape is fixed: `struct Move`, the listed declaration, then
`fn main() { let mut a: [Move; 4]; a[0].to = 7; println!("{}", a[0].to); }`.

| declaration inserted before `main` | result |
| --- | --- |
| *nothing* | 7 |
| `struct Other { x: i64 }` | 7 |
| `fn t(x: i64) -> i64 { x }` | 7 |
| `fn t(b: &i64) -> i64 { 1 }` | 7 |
| `fn t(b: &[i64]) { }` | 7 |
| `fn t(b: &[i64]) -> i64 { b[0] }` | 7 |
| `fn t(b: &[i64], i: i64) { }` | **broken** |
| `fn t(i: i64, b: &[i64]) { }` | **broken** |
| `fn t(b: &[i64], c: &[i64]) { }` | **broken** |
| `fn t(b: &[i64], i: i64, j: i64) { }` | **broken** |
| `fn t(i: i64, j: i64) { }` | 7 |
| `fn t(b: &[Move], i: i64) { }` | **segfault** (compiles clean) |

So the trigger is exactly: **a fn whose parameter list contains at least one
`&[T]` slice AND has arity >= 2.** One slice alone is fine; two scalars are
fine; the body is irrelevant (an empty body triggers it).

Two further facts that a root-cause has to explain, and both cut against the
obvious "the slice UClass shifts an index" story:

- **It is specific to `main`.** The identical array in an ordinary fn is fine:
  `fn u() -> i64 { let mut a: [Move; 4]; a[0].to = 7; a[0].to }` compiles and
  answers 7 with `fn t(b: &[i64], i: i64) { }` present.
- **The slice fn must precede `main` in TOKEN order.** Move `fn t` below `main`
  and it compiles. That is surprising, because `RRegisterFnSignatures` prescans
  every top-level fn — and therefore calls `RSliceClassForRec` — before any body
  is parsed, so the slice UClass exists in both orderings.

`Move` itself is undamaged: `let m: Move = Move { from: 1, to: 2 };` still works
in the same `main` that cannot type `a[0].to`.

## Knock-on

`let m: Move = a[2];` under the same conditions fails with
`Rust: struct assignment from a non-literal expression is not supported by the
skeleton yet` — that is this bug, not a missing feature: without the slice fn,
the same line compiles. Do not file it separately.

## Why the corpus engine does not hit it

`test/test_rust_chess_engine.rs` has three slice-param fns with arity >= 2
(`is_attacked`, `king_sq`, `gen_moves`) declared before `main`, and it is green
— because `main`'s only arrays are `[i64; 64]` boards. Scalar element types are
unaffected. The engine's move list is a `MoveList` STRUCT local, not a record
array in `main`. The bug is one `let mut a: [Move; 4];` in `main` away at all
times.

## Next step

Measure, do not reason: dump `Syms[]` for `a` (ElemType / ElemRecName) in the
broken and working orderings rather than continuing to guess at the mechanism.
The probe matrix above is the artifact worth keeping; the mechanism is still
unknown and none of the plausible stories survives both bullet points.
