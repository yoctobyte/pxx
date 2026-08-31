---
track: A
prio: 70
type: bug
status: done
found: 2026-08-31
found-by: frankA
owner: frankA
blocked-by: []
resolved-commit: f3ef2ef1d
summary: "FIXED. `p^[i]` where p points at a named DYNAMIC array used a 4-BYTE STRIDE whatever the element type: a Double slot read back 0.00 (the store wrote the low half), two Int64 writes packed into one slot as (20 shl 32) or 10 = 85899345930, a pointer-to-dyn-array PARAMETER SEGFAULTED, and an AnsiString element was refused as \"cannot assign ShortString to Char\". SILENT for the numeric cases -- compiles clean, exits 0, wrong values -- and confirmed against FPC 3.2.2 on byte-identical source. ROOT CAUSE: this is the DYNAMIC sibling of bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds; BOTH arms that fix landed in guarded on `not ArrTypeIsDyn`, and two more helpers had the same split. Biggest blast radius was `parallel for`: EVERY captured dynamic array goes through this, so a captured `array of Double` written in a parallel body silently produced all zeros. Fix is two files, four one-shape-per-site changes, all removing a fixed-vs-dynamic distinction rather than adding a case."
---

# `p^[i]` over a pointer to a dynamic array indexes with a 4-byte stride

Found while building a race-free replacement for
`test/test_setlen_in_parallel_for_body.pas` (see
[[bug-a-a-parallel-for-body-shares-one-captured-string-across-all-workers]]) —
the disjoint-slot loop that replacement needs would not compile, and the reason
was not in `parallel for` at all.

## The measurement

Plain single-threaded Pascal. No threads, no `--threadsafe`:

```pascal
type TD = array of Double; TPD = ^TD;
var d: TD; ptr: TPD; i: Integer;
begin
  SetLength(d, 4); ptr := @d;
  for i := 0 to 3 do ptr^[i] := (i+1)*1.5;   { -> 0.00 0.00 0.00 0.00 }
  for i := 0 to 3 do d[i]    := (i+1)*1.5;   { -> 1.50 3.00 4.50 6.00 }
```

| shape | pre-fix | FPC 3.2.2 |
| --- | --- | --- |
| pointer to **fixed** `array[0..3] of Double` | `1.50 3.00 4.50 6.00` | same |
| pointer to **dynamic** `array of Double` | **`0.00 0.00 0.00 0.00`** | `1.50 3.00 4.50 6.00` |
| pointer to dynamic `array of Int64` | **`85899345930 171798691870 0 0`** | `10 20 30 40` |
| dynamic pointee as a **parameter** | **SIGSEGV** | fine |
| dynamic `array of AnsiString` | **refused**, "cannot assign ShortString to Char" | fine |

FPC rejects the bare `p^[i]` spelling ("Illegal qualifier"), so the differential
was run on the parenthesised `(p^)[i]` form, byte-identical source, both
compilers: pxx `0.00 0.00 0.00 0.00` vs FPC `1.50 3.00 4.50 6.00`.

**Two numeric predictions confirmed the diagnosis before any code was read.**
`85899345930` is exactly `(20 shl 32) or 10` — two 4-byte writes into one 8-byte
slot. `1.5` is `$3FF8000000000000`, whose low 32 bits are `0` — which is why
every Double slot read back `0.00` rather than garbage.

## Root cause: a fixed/dynamic split, in four places

`bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds`
fixed this family for pointers to **fixed** arrays. Every site it touched
excluded the dynamic half, so the dynamic half kept the old behaviour — and the
comment above one of them states the symptom exactly: *"Without it the alias
recorded a tyInteger pointee and every variable of it inherited a 4-byte
stride."*

1. `pasparser_decl.inc`, the inline `^TArr` arm — `if (ptrArrAi >= 0) and (not
   ArrTypeIsDyn[ptrArrAi])`.
2. `pasparser_decl.inc`, the `PArr = ^TArr` alias arm — the same condition.
   Together these are why `Syms[pd].PtrElemTk` read `1` (tyInteger) where the
   fixed sibling read `19` (tyDouble), measured with `PXXDBG=a.symptr`.
3. `symtab.inc`, `SetPtrElemArrayInfo` — `if ArrTypeIsDyn[...] then Exit`, with
   the dyn-depth arm living in `AllocVar` **alone**. That is the segfault: a
   pointer-to-dyn-array PARAMETER recorded no depth at all, so `p^[i]` took a
   different and wholly wrong path. Moved into the one procedure all four
   allocators already call.
4. `symtab.inc`, `DynArrayNodeDepth` — the parser-side twin of IR's
   `NodeDynDepth`, missing the `AN_DEREF` arm its twin has. That made
   `IsNodeArray` answer FALSE for `p^` over an `array of AnsiString`, so the
   selector chain took the managed-STRING arm and refused the assignment.

All four changes DELETE a distinction. Nothing was special-cased.

## Blast radius: every captured dynamic array in a `parallel for`

A `parallel for` body is lifted into a worker that receives each captured local
as `cap: ^T` and rewrites `a` to `a^`, so **every captured dynamic array in
every parallel loop is this exact shape**. Measured, `parallel(pdChunked, n 1)`,
writing `a[i] := (i+1)*1.5` into a captured local:

| element type | pre-fix | post-fix |
| --- | --- | --- |
| `array of Integer` | `10 20 30 40` | `10 20 30 40` |
| `array of Int64` | `85899345930 171798691870 0 0` | `10 20 30 40` |
| `array of Double` | `0.00 0.00 0.00 0.00` | `1.50 3.00 4.50 6.00` |
| same as a **global** (not captured) | correct | correct |
| captured **fixed** `array[0..3] of Double` | correct | correct |

`array of Integer` was right **by coincidence** — the wrong stride happened to
equal `SizeOf(Integer)`. That is why this survived: the element type every test
reaches for first is the one type it cannot fail on.

## An intermediate state worth recording

After fixes 1–3 but before 4, `p^[i]` and `(p^)[i]` **disagreed on the same
line** — bare wrong, parenthesised right — because the metadata was correct by
then and only the AN_INDEX node's own static type was not, so `store_mem`
carried `tk=1` while `dynunique`/`index` both carried `size=8 tk=19`. Before any
fix, both spellings were wrong. Recorded because a half-applied fix here
produces a divergence between two spellings of one access, which reads like a
parser bug and is not.

A fifth change was written and then **removed**: an arm in
`pasparser_lval.inc`'s selector chain. Ablation showed it dead — fix 4 wins
earlier in the chain — and a dead arm carrying a confident comment about a bug
it does not fix is worse than no arm.

## Test

`test/test_pointer_to_dynamic_array_indexing.pas`, 30 checks, wired into
`test-core` beside its fixed-array sibling. Every row compares the pointer
spelling against the direct `a[i]` spelling, because the broken rows exited 0.

**Positive control, run not assumed:** on the pre-fix compiler
(`fb68a748bcee3da3`) the file is REFUSED at the AnsiString row; with those rows
removed so it gets far enough to run, it prints **11 FAIL rows** — carrying the
`85899345930` signature — and then exits **139** on the parameter row. With the fix all 30 pass.

**A sha correction, because this file cited one that cannot be reproduced.** An
earlier draft named `e6bd287595d1c5c2` as the post-fix compiler. The compiler
built from the landed sources is **`abea85c67b094be9`**, and that is
reproducible: reseeded from `pinned` it converges in 2 rounds and reseeded from
itself in 1, to that same sha both times — so the fixedpoint is NOT
seed-dependent and the earlier value came from a working tree I can no longer
account for. The behavioural claims above were each measured directly against a
binary and are unaffected; only the identifier was wrong. Recorded rather than
quietly edited, because an unreproducible sha beside a correct result is exactly
the kind of citation that gets trusted later.
