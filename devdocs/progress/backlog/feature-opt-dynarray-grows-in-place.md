---
prio: 45
track: A
---

# A growing dynamic array leaves its whole geometric series behind as garbage

- **Type:** feature (optimization / heap allocator) — Track A, tag O
- **Status:** backlog — opened 2026-08-21
- **Found by:** [[feature-dynamic-compiler-tables]], measuring RSS after converting
  seven table families from fixed BSS to dynamic arrays.

## The measurement

Converting ~100 of the compiler's fixed tables to dynamic arrays took its BSS
from 246.8 MB to 75.9 MB — and took its max RSS **up** ~10% (hello-world compile
24.2 -> 26.3 MB; self-compile 453 -> 497 MB). Wall time was unchanged.

## Why

`SetLength` on a dynamic array is allocate-copy-free. The freed block goes back
on the large-block free list, which is **first-fit on `size >= request`** — so it
can serve a SMALLER later request and never the NEXT DOUBLING of the same array,
which is by construction bigger. A table doubling 64 K -> 8 M therefore leaves
64 K + 128 K + ... + 4 M ~= one final-size worth of garbage that that table can
never reuse.

This is not a compiler-tables problem. **Every pxx program that grows a dynamic
array pays it**, and the append-in-a-loop shape is as common as programs get.

## The fix already exists, three arms away

`ir_codegen.inc`'s SetLength lowering (specialId 102) has TWO arms. The
AnsiString arm already does the right thing:

- resize IN PLACE when the handle is unique (`rc = 1`) and the request fits the
  block's allocator size word, and
- when it must allocate, take **geometric headroom off the LENGTH** (`add rcx,
  rcx`), deliberately not off the block size — the comment there records that
  headroom off the block size made a short string that had reused an oversized
  freed block double its block every grow, to OOM.

The scalar-array arm does neither: it allocates exactly `24 + n*elemSize` every
time and copies. Give it the same two properties and the garbage disappears —
and with headroom off the length, a caller that DOUBLES (which is what every
Ensure*Capacity in the compiler does) finds the next grow already fits, so the
copy disappears too.

This is `devdocs/dev/normalise-dont-special-case.md` exactly: one concept, two
arms, one of them better.

## Scope the fast path narrowly at first

In place only when ALL of: growing (`n >= oldLen`), unique (`rc = 1`), it fits
the block, and the element type is **unmanaged** (`ManagedElemKindLocked = 0`).
Managed elements make shrink-in-place a release problem and grow-in-place a
retain problem; the survivors keep their own references when nothing moves, but
that argument needs its own test, not an assumption. Zero the new tail, store
the new length, publish nothing (the slot already points at the block).

## Acceptance

- `hello` and self-compile RSS back to or below the pre-conversion numbers.
- A growth microbenchmark (append N elements one SetLength at a time) shows the
  copy gone.
- test_dynarray*, the managed-element dynarray tests, and the self-host
  fixedpoint green; cross targets unaffected (the arm is x86-64 codegen).
- Then, and only then, the remaining conversions in
  [[feature-dynamic-compiler-tables]] become close to free.
