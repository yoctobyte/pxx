---
track: C
prio: 25
type: refactor
blocked-by: []
summary: "cparser's partial-index builder marks 'this add is raw bytes, do not scale' by RETAGGING its base ASTTk to tyInt64 — a type tag used as a flag. tyInt64 is also the honest element tag of a `long long` array, and that collision cost a real bug."
---

# The partial-index sentinel should not be a type tag

- **Track C** (C frontend).
- Filed 2026-08-20 out of
  [[bug-c-pointer-difference-on-a-long-long-element-type]], where the collision
  produced a silent wrong stride.

## What it is

`ParseCPostfixTail`'s partial-index arm (`m[1]` on `int m[3][4]`) builds a raw
byte add and marks the base so nothing scales it a second time:

```pascal
ASTTk[baseFld] := Ord(tyInt64);   { "raw 64-bit add, no pointer-stride scale" }
```

That is a **flag written into the type field**. tyInt64 is also the perfectly
honest element tag of `long long a[8]`, so a reader cannot tell "I am a
deliberately unscaled byte base" from "I am a signed 64-bit array".

## What it cost

`IRNodePointerBase` read the tag the sentinel way and bailed on tyInt64
outright. A signed 64-bit array was therefore never a pointer base: `a + 1`
stepped one byte, `q - p` answered 0, and `unsigned long long` — a different
tag — was correct. A sign bit decided a stride, silently.

The fix in place disambiguates by asking whether the node's DECLARATION explains
the tag (a fixed-extent, single-dimension array whose element type really is
tyInt64 carries it honestly). That is correct and it is a second reading of an
overloaded field, which is the thing worth removing.

## Sketch

Carry the "already byte-scaled" fact somewhere that means only that:

- an `ASTSLen`-style stamp, which the AN_BINOP arm of `IRPointerStride` already
  uses for exactly this family (`bug-c-a-decayed-array-row-steps-one-byte`), or
- a dedicated AST node kind for a decayed row, which would also give
  `CNodePointeeTk` something to key on instead of its walk-left-to-the-ident
  heuristic.

Then `IRNodePointerBase` loses its special case and `CNodePointeeTk` loses one
too. Two readers simplify, which is the measure worth using.

## Not urgent

The current disambiguation is tested from both sides — `carr2d_decay_stride.c`
pins the sentinel reading and the pointer-difference test pins the honest one —
so this is a clarity/robustness refactor, not an open defect.

## Gate

C tests green + self-host byte-identical; both tests above still pass, and the
tyInt64 special case in `IRNodePointerBase` is gone rather than moved.
