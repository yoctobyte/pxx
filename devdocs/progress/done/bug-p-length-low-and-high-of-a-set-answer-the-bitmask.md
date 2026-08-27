---
track: P
prio: 45
type: bug
summary: "`Length([1,2])` answered 6 — the SET BITMASK, read as a string handle — and `Low([1,2])`/`High([1,2])` were refused outright. `[e1,..,en]` as the operand of Low/High/Length is an open-array CONSTRUCTOR in FPC and the answer is a compile-time count. `Length(<a set variable>)` had the same silent bitmask answer and is now refused, as FPC refuses it."
status: done
---

# `Length` of a bracket constructor answers the set bitmask

- **Type:** bug (silent wrong answer) — **Track P**
- **Found:** 2026-08-27, from `tools/fpc_diff_probe.sh`'s
  `param-openarray-empty` row, which had been tagged `known` with **no ticket
  behind it** — the tag the probe's own header calls a lie with a cost.

## Measured

```pascal
writeln(Length([1]));        { pxx 2    fpc 2 }
writeln(Length([1,2]));      { pxx 6    fpc 2 }
writeln(Length([1,2,3]));    { pxx 14   fpc 3 }
writeln(Length([5,9]));      { pxx 544  fpc 2 }
writeln(Length(['a','b']));  { pxx 0    fpc 2 }
writeln(Low([1,2]));         { pxx: error: Low: expected array variable or ordinal type }
writeln(High([1,2]));        { pxx: error: High: expected array variable or ordinal type }
```

2, 6, 14, 544 are `1 shl 1`, `(1 shl 1) or (1 shl 2)`, `2 or 4 or 8`,
`(1 shl 5) or (1 shl 9)`. pxx read the brackets as a **set**, and `Length` then
read the 32-byte bitset as a string handle and returned the low word of the
bitmask. `['a','b']` sets bits 97 and 98, past that word, hence 0.

The Length rows are the expensive half: a small set produces a small plausible
number, which is how `Length([1])` = 2 sat there looking correct.

The same silent bitmask came back from a set VARIABLE:

```pascal
var s: set of Byte; begin s := [1,2]; writeln(Length(s)); end.   { pxx 6, fpc: Type mismatch }
```

## Outcome — 2026-08-27

`[e1, ..., en]` as the operand of `Low`/`High`/`Length` is an open-array
CONSTRUCTOR, not a set — FPC's reading — and the answer is a compile-time COUNT
whatever the elements are: `Length` = n, `Low` = 0, `High` = n - 1. Measured
across `[]`, char elements, string elements, nested constructors and
non-constant elements; the count is the whole rule, so it folds to a literal and
nothing in the brackets is evaluated. That is what FPC does too.

`TryFoldBracketCtorLen` + `FoldBracketCtorBound`, called from all three arms
right after their `(`. One helper rather than three copies of a comma count:
these three arms already differ in a dozen ways and this is the one thing they
agree on.

`Length(<a set>)` is now **refused** rather than given a meaning. FPC has no
`Length(set)`, so any answer invented here would be pxx-only, and a caller
almost certainly means the element COUNT — which is not what any spelling of
this used to return.

### The exclusion that check needed

An ARRAY operand had to be excluded, and it is the whole subtlety: an array
symbol's `TypeKind` is its **element's**, so `ds: array of TDays` with
`TDays = set of TDay` reads as `tySet` on both the symbol and the node.
`Length(ds)` there is the array's length and is entirely legal.
`test_dynarray_insert_delete` has four of them, and they are what caught the
first version of the check — the quick gate went RED on it, which is the gate
working.

### Measured, after

`test/test_open_array_constructor_bounds.pas` (+ `.expected`) — 10 rows byte
identical to `fpc -O1 -Mobjfpc` 3.2.2, including the `[]` edge (`0 | -1 | 0`),
non-constant elements, nested constructors, the open-array PARAMETER form that
always worked, a real set still behaving like a set, and an array OF sets
keeping its length. `test/test_length_of_a_set_fail.pas` asserts both set rows
refused and no binary. Both wired into `test-core`.

`tools/fpc_diff_probe.sh`'s `param-openarray-empty` is **untagged**: `0|0|1` on
both compilers. It still shows as a divergence against the DEFAULT oracle until
the next `chore(stable): pin`, because that oracle is
`stable_linux_amd64/default/pinned` and the pin is from 2026-07-27; run with
`PXX_STABLE=./compiler/pascal26` to see it clean. Noted in the probe file beside
the row so it is not mistaken for a regression. Full run against master:
**0 new divergences**, 11 known/filed, 1 by design.

### What is deliberately NOT closed

`Low`/`High` of a set VARIABLE answer 0 and -1 where FPC answers the element
type's bounds — split out as
[[bug-p-low-and-high-of-a-set-do-not-answer-the-element-bounds]] because it
needs storage the compiler does not keep: `set of 1..10` drops its bounds at
declaration, so a partial fix would answer two shapes right and the third — the
one whose bounds are written down in the source — plausibly wrong.

### Gate

`make compiler/pascal26` byte-identical (695fc8658e1e) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7 ·
`fpc_diff_probe.sh` 0 new against master.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
