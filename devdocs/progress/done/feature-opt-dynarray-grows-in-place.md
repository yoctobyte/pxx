---
prio: 40
track: A
---

# A growing dynamic array leaves its whole geometric series behind as garbage

- **Type:** feature (optimization / heap allocator) — Track A, tag O
- **Status:** done
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

---

## 2026-09-02 (frankH) — done, both emit sites, and the managed-element scope was widened deliberately

Landed as `cd27d80f7` (symbol-target arm) and `d6ba3927c` (the nested/field
site, `IR_SETLEN_DYN`). Both halves of the fix, because neither works alone:
grow in place when the block is non-nil, UNIQUE, the request grows and it fits
the size word at `[data-32]`; and when it must allocate, take
`max(needed, 2*oldBytes + 24)` so the next grows fit. Headroom off the LENGTH,
never off `[data-32]`, for exactly the reason the ansistring arm's comment
records.

### The measurement, unconfounded

40000 one-element grows x 20 rounds, same host, interleaved, same printed
result: **44.3 s / 3.1 GB max RSS -> 0.02 s / 392 KB.** Reallocation counts
(real data-pointer moves) across 4095 one-element grows: **4095 -> 11**, which
is log2 and is the shape the ticket predicted. Compiler self-compile max RSS
572.5 -> 569.4 MB; `hello` 13172 -> 12752 KB. **Wall time on the self-compile is
NOT claimed** — the baseline binary predates a rebase that brought in
`b8ee49996`, so that half of the A/B is confounded and only the RSS direction
is safe to read.

### There were TWO emit sites and the ticket named one

`ir_codegen.inc:10863` (`IR_SETLEN_DYN`) is the nested/field site; the arm the
ticket's "specialId 102 has TWO arms" paragraph describes is a *different*
lowering ~700 lines earlier, and it is the one a plain `SetLength(a, n)` on a
variable reaches. Fixing only the named one would have left every
`SetLength(rec.arr, n)` and `SetLength(grid[i], n)` on the slow path — and a
two-dimensional table grown a row at a time is precisely the compiler-tables
shape. Both are done. Each has its own positive control in the test, because
the first row could not reach the second site.

### Managed elements are IN, and that is a measured decision, not an oversight

The ticket scoped the fast path to `ManagedElemKindLocked = 0`. That predicate
would also have been the wrong instrument: it answers "no element walk is
emitted HERE", and it returns 0 for kinds 4 and 6 under `--threadsafe` as a
deliberate deadlock REFUSAL, not because the elements are unmanaged.

The scope was widened to every element kind instead, on an argument the ticket
asked to be tested rather than assumed: on the slow path each SURVIVING element
is retained and then the whole old block is released, so a survivor nets exactly
zero — which is what doing nothing at all also produces. Only a SHRINK drops
elements, and a shrink still allocates. Tested rather than asserted: array of
AnsiString, array of record-with-a-string-field, and `array of array of Integer`
all grow through the fast path and are checked for value survival and for an
empty/zeroed new tail, under the normal allocator and under
`-dPXX_HEAP_DEBUG`.

### Zeroing the tail is load-bearing, and not for tidiness

`PXXAlloc`'s zero-init contract covers the bytes it was ASKED for. The large
first-fit path hands back an oversized block **without rewriting its size word**
and clears only `size` bytes — so the capacity this fast path grows into is
exactly the span nothing zeroed. The `rep stosb` over the new tail is what makes
that safe, and it is also why the `-dPXX_HEAP_DEBUG` row is wired.

### Acceptance, row by row

- growth microbenchmark shows the copy gone — **yes**, 4095 moves -> 11.
- `test_dynarray*` and the managed-element dynarray tests green, self-host
  fixedpoint green — **yes**, `converged after 2 round(s)`, `5c743f5e918d`.
- cross targets unaffected — **yes**, `ir_codegen.inc` is x86-64 only; the
  386/aarch64/arm32/xtensa/riscv32/wasm32 emitters are separate files and route
  SetLength through `PXXDynSetLen`.
- "`hello` and self-compile RSS back to or below the pre-conversion numbers" —
  **cannot be checked from here and does not belong to this ticket**: those
  conversions were reverted, so there is no converted tree to re-measure. It is
  [[feature-dynamic-compiler-tables]]'s row now, and it is the reason that
  ticket said to do this one first.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
