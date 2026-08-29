---
prio: 35
track: R
resolved: PENDING-COMMIT
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


## RESOLVED (2026-08-29)

Both missing arms landed, and neither is a copy of the `let`-level one — the
`let` arm now calls the same function.

`RSliceHeaderStores(sliceSym, arrSym, loNode, hiNode)` is the single lowering:
`__ptr := &arr[lo]`, `__len := hi - lo`, with `loNode < 0` meaning 0 and
`hiNode < 0` meaning the array's declared length (`Syms[].ArrLen`), i.e. the
whole-array borrow. `RParseLet`'s borrowed-slice arm was rewritten to call it
and lost 20 lines; `RMaterializeSliceOf` wraps it for expression position,
allocating a `__sliceN` local and hoisting the two stores into `RPendingPreSeq`
the way the `?` desugar and the aggregate materializer already do.

**The disambiguation is why argument parsing had to become a function.** `&arr`
is spelled identically for a `&[T]` SLICE param (a two-word view) and a
`&[T; N]` ARRAY-REFERENCE param (a bare address); the operand alone cannot tell
them apart. `Procs[procIdx].Params[slot].IsArray` is the bit that separates
them, and it is reachable only where the callee is known. So the five copies of

```pascal
argNode := AllocNode(AN_ARG);
ASTLeft[argNode] := RParseExpr;
```

became five calls to one `RParseCallArg(procIdx, slot)` — which is worth more
than this bug: five hand-copied argument loops were themselves the double-case
smell, and any future argument-position rule now has one place to live. A range
borrow `&arr[lo..hi]` needs no disambiguation (a range index is never an array
ref) and is taken unconditionally. Anything that is not a borrow of a fixed
array rewinds the cursor and goes to `RParseExpr` exactly as before, so `&rec`
still reaches `RParseUnary`'s no-op, which is correct — records already travel
by address.

`test/test_rust_slice_borrow.rs` -> `test_rust_slice_borrow26`, oracle
hand-computed. Two lines carry the proof:

- `bump 101 132` — the second call mutates through a **range** borrow
  (`bump(&mut v[4..6], 1)` writes `v[5]`), so the view must alias the caller's
  storage rather than copy it. A lowering that built a correct-looking header
  over a temporary would pass every other line in the file and fail this one.
- `aref 9` — `&v` for a `&[T; N]` param stays a bare address. This is the half
  a naive "make `&arr` a slice" fix silently breaks.

The other seven lines cover the whole-array borrow, inline ranges, a slice
param in a non-zero slot, the pre-existing let-bound form (kept so a regression
in the path that already worked is visible), forwarding a slice param onward,
and a slice of records.

Self-host fixedpoint verified; forwardlint clean.
